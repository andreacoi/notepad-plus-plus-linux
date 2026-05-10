#include "pluginsadmin.h"
#include "plugin.h"
#include <string.h>
#include <stdlib.h>

/* ------------------------------------------------------------------ */
/* Plugin entry (from manifest or installed)                           */
/* ------------------------------------------------------------------ */
typedef struct {
    char *name;
    char *version;
    char *description;
    char *install_path;  /* NULL = not installed */
    gboolean installed;
} PlugEntry;

static GPtrArray *s_entries = NULL;

static char *plugins_dir(void)
{
    return g_build_filename(g_get_home_dir(), ".config", "notetux", "plugins", NULL);
}

/* ------------------------------------------------------------------ */
/* Scan installed plugins                                              */
/* ------------------------------------------------------------------ */
static void scan_installed(void)
{
    char *dir = plugins_dir();
    GDir *d = g_dir_open(dir, 0, NULL);
    if (d) {
        const char *name;
        while ((name = g_dir_read_name(d))) {
            char *so = g_build_filename(dir, name, NULL);
            char *so_file = g_build_filename(so, NULL);
            gchar *so_path = g_strdup_printf("%s/%s.so", so, name);
            if (g_file_test(so_path, G_FILE_TEST_EXISTS)) {
                PlugEntry *pe = g_new0(PlugEntry, 1);
                pe->name         = g_strdup(name);
                pe->version      = g_strdup("(installed)");
                pe->description  = g_strdup("Installed locally");
                pe->install_path = g_strdup(so_path);
                pe->installed    = TRUE;
                g_ptr_array_add(s_entries, pe);
            }
            g_free(so_path);
            g_free(so_file);
            g_free(so);
        }
        g_dir_close(d);
    }
    g_free(dir);
}

static void free_entry(gpointer p)
{
    PlugEntry *pe = p;
    g_free(pe->name);
    g_free(pe->version);
    g_free(pe->description);
    g_free(pe->install_path);
    g_free(pe);
}

/* ------------------------------------------------------------------ */
/* List model columns                                                  */
/* ------------------------------------------------------------------ */
enum { COL_IDX=0, COL_NAME, COL_VER, COL_DESC, COL_STATUS, N_COLS };

static void populate_store(GtkListStore *ls)
{
    gtk_list_store_clear(ls);
    for (guint i = 0; i < s_entries->len; i++) {
        PlugEntry *pe = s_entries->pdata[i];
        GtkTreeIter it;
        gtk_list_store_append(ls, &it);
        gtk_list_store_set(ls, &it,
            COL_IDX,    (int)i,
            COL_NAME,   pe->name,
            COL_VER,    pe->version,
            COL_DESC,   pe->description,
            COL_STATUS, pe->installed ? "Installed" : "Available",
            -1);
    }
}

/* ------------------------------------------------------------------ */
/* Install (copy .so from file chooser)                               */
/* ------------------------------------------------------------------ */
static void on_install(GtkButton *b, gpointer ud)
{
    (void)b;
    GtkWindow *parent = GTK_WINDOW(ud);
    GtkWidget *dlg = gtk_file_chooser_dialog_new("Select Plugin (.so)",
        parent, GTK_FILE_CHOOSER_ACTION_OPEN,
        "_Cancel", GTK_RESPONSE_CANCEL,
        "_Install", GTK_RESPONSE_ACCEPT, NULL);
    GtkFileFilter *ff = gtk_file_filter_new();
    gtk_file_filter_set_name(ff, "Shared Libraries (*.so)");
    gtk_file_filter_add_pattern(ff, "*.so");
    gtk_file_chooser_add_filter(GTK_FILE_CHOOSER(dlg), ff);

    if (gtk_dialog_run(GTK_DIALOG(dlg)) == GTK_RESPONSE_ACCEPT) {
        char *src = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dlg));
        char *base = g_path_get_basename(src);
        /* Remove .so extension for dir name */
        char *name = g_strdup(base);
        char *dot  = strrchr(name, '.');
        if (dot) *dot = '\0';

        char *dest_dir = g_build_filename(g_get_home_dir(), ".config", "notetux",
                                          "plugins", name, NULL);
        g_mkdir_with_parents(dest_dir, 0755);
        char *dest = g_build_filename(dest_dir, base, NULL);

        GFile *src_f  = g_file_new_for_path(src);
        GFile *dest_f = g_file_new_for_path(dest);
        GError *err = NULL;
        g_file_copy(src_f, dest_f, G_FILE_COPY_OVERWRITE, NULL, NULL, NULL, &err);
        g_object_unref(src_f);
        g_object_unref(dest_f);

        GtkWidget *msg = gtk_message_dialog_new(parent, GTK_DIALOG_MODAL,
            err ? GTK_MESSAGE_ERROR : GTK_MESSAGE_INFO,
            GTK_BUTTONS_OK,
            err ? "Install failed: %s" : "Plugin installed.\nRestart Notetux++ to load it.",
            err ? err->message : "");
        gtk_dialog_run(GTK_DIALOG(msg));
        gtk_widget_destroy(msg);
        if (err) g_error_free(err);
        g_free(dest); g_free(dest_dir); g_free(name); g_free(base); g_free(src);
    }
    gtk_widget_destroy(dlg);
}

/* ------------------------------------------------------------------ */
/* Uninstall selected plugin                                           */
/* ------------------------------------------------------------------ */
typedef struct { GtkTreeView *tv; GtkListStore *ls; GtkWindow *parent; } AdminData;

static void on_uninstall(GtkButton *b, gpointer ud)
{
    (void)b;
    AdminData *ad = ud;
    GtkTreeSelection *sel = gtk_tree_view_get_selection(ad->tv);
    GtkTreeIter it;
    GtkTreeModel *m;
    if (!gtk_tree_selection_get_selected(sel, &m, &it)) return;
    int idx;
    gtk_tree_model_get(m, &it, 0, &idx, -1);
    if (idx < 0 || idx >= (int)s_entries->len) return;
    PlugEntry *pe = s_entries->pdata[idx];
    if (!pe->installed || !pe->install_path) return;

    GFile *f = g_file_new_for_path(pe->install_path);
    GError *err = NULL;
    /* Remove the whole plugin directory */
    char *dir = g_path_get_dirname(pe->install_path);
    GFile *df = g_file_new_for_path(dir);
    g_file_delete(f, NULL, &err);
    if (!err) {
        g_file_delete(df, NULL, &err);
    }
    g_object_unref(f);
    g_object_unref(df);
    g_free(dir);

    GtkWidget *msg = gtk_message_dialog_new(ad->parent, GTK_DIALOG_MODAL,
        err ? GTK_MESSAGE_ERROR : GTK_MESSAGE_INFO, GTK_BUTTONS_OK,
        err ? "Uninstall failed: %s" : "Plugin removed.\nRestart Notetux++ to apply.",
        err ? err->message : "");
    gtk_dialog_run(GTK_DIALOG(msg));
    gtk_widget_destroy(msg);
    if (err) { g_error_free(err); return; }

    pe->installed = FALSE;
    gtk_list_store_set(ad->ls, &it, COL_STATUS, "Available", -1);
}

/* ------------------------------------------------------------------ */
/* Public dialog                                                       */
/* ------------------------------------------------------------------ */

void pluginsadmin_show(GtkWindow *parent)
{
    if (!s_entries) {
        s_entries = g_ptr_array_new_with_free_func(free_entry);
        scan_installed();
    }

    GtkWidget *dlg = gtk_dialog_new_with_buttons("Plugins Admin", parent,
        GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT,
        "_Close", GTK_RESPONSE_CLOSE, NULL);
    gtk_window_set_default_size(GTK_WINDOW(dlg), 600, 400);
    GtkWidget *box = gtk_dialog_get_content_area(GTK_DIALOG(dlg));

    /* Refresh */
    g_ptr_array_set_size(s_entries, 0);
    scan_installed();

    GtkListStore *ls = gtk_list_store_new(N_COLS, G_TYPE_INT,
        G_TYPE_STRING, G_TYPE_STRING, G_TYPE_STRING, G_TYPE_STRING);
    populate_store(ls);

    GtkWidget *tv = gtk_tree_view_new_with_model(GTK_TREE_MODEL(ls));
    g_object_unref(ls);
    gtk_tree_view_set_headers_visible(GTK_TREE_VIEW(tv), TRUE);
    GtkCellRenderer *r = gtk_cell_renderer_text_new();
    const char *cols[] = { "Name", "Version", "Description", "Status" };
    int col_ids[]      = { COL_NAME, COL_VER, COL_DESC, COL_STATUS };
    for (int i = 0; i < 4; i++) {
        GtkTreeViewColumn *c = gtk_tree_view_column_new_with_attributes(
            cols[i], r, "text", col_ids[i], NULL);
        if (i == 2) gtk_tree_view_column_set_expand(c, TRUE);
        gtk_tree_view_append_column(GTK_TREE_VIEW(tv), c);
    }

    GtkWidget *scroll = gtk_scrolled_window_new(NULL, NULL);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll),
        GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
    gtk_container_add(GTK_CONTAINER(scroll), tv);
    gtk_box_pack_start(GTK_BOX(box), scroll, TRUE, TRUE, 0);

    GtkWidget *btn_bar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
    gtk_container_set_border_width(GTK_CONTAINER(btn_bar), 4);

    GtkWidget *inst_btn   = gtk_button_new_with_label("Install from file…");
    GtkWidget *uninst_btn = gtk_button_new_with_label("Uninstall");
    gtk_box_pack_start(GTK_BOX(btn_bar), inst_btn,   FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(btn_bar), uninst_btn, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(box), btn_bar, FALSE, FALSE, 0);

    g_signal_connect(inst_btn, "clicked", G_CALLBACK(on_install), parent);

    AdminData *ad = g_new(AdminData, 1);
    ad->tv     = GTK_TREE_VIEW(tv);
    ad->ls     = GTK_LIST_STORE(gtk_tree_view_get_model(GTK_TREE_VIEW(tv)));
    ad->parent = parent;
    g_signal_connect_data(uninst_btn, "clicked", G_CALLBACK(on_uninstall),
                          ad, (GClosureNotify)g_free, 0);

    if (s_entries->len == 0) {
        GtkWidget *lbl = gtk_label_new(
            "No plugins installed.\n"
            "Use \"Install from file…\" to add a plugin (.so),\n"
            "or place it manually in ~/.config/notetux/plugins/<Name>/<Name>.so");
        gtk_label_set_justify(GTK_LABEL(lbl), GTK_JUSTIFY_CENTER);
        gtk_box_pack_start(GTK_BOX(box), lbl, FALSE, FALSE, 8);
    }

    gtk_widget_show_all(dlg);
    gtk_dialog_run(GTK_DIALOG(dlg));
    gtk_widget_destroy(dlg);
}
