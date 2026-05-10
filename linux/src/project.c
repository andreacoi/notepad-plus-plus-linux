#include "project.h"
#include "editor.h"
#include <string.h>
#include <stdlib.h>

/* ------------------------------------------------------------------ */
/* Tree model columns                                                  */
/* ------------------------------------------------------------------ */
enum {
    COL_ICON = 0,   /* const char*  icon name  */
    COL_NAME,       /* const char*  display label */
    COL_PATH,       /* const char*  full path (NULL for folders) */
    COL_IS_FOLDER,  /* gboolean */
    N_COLS
};

/* ------------------------------------------------------------------ */
/* Module state                                                        */
/* ------------------------------------------------------------------ */
static GtkWidget    *s_panel      = NULL;
static GtkWidget    *s_treeview   = NULL;
static GtkTreeStore *s_store      = NULL;
static GtkWidget    *s_window     = NULL;
static char         *s_proj_path  = NULL;   /* NULL = no project open */

/* ------------------------------------------------------------------ */
/* Helpers                                                             */
/* ------------------------------------------------------------------ */
static void msg_dialog(const char *msg)
{
    GtkWidget *d = gtk_message_dialog_new(GTK_WINDOW(s_window),
        GTK_DIALOG_MODAL, GTK_MESSAGE_INFO, GTK_BUTTONS_OK, "%s", msg);
    gtk_dialog_run(GTK_DIALOG(d));
    gtk_widget_destroy(d);
}

static char *config_path(const char *name)
{
    return g_build_filename(g_get_home_dir(), ".config", "notetux", name, NULL);
}

/* ------------------------------------------------------------------ */
/* XML save                                                            */
/* ------------------------------------------------------------------ */
static void write_node(GString *out, GtkTreeStore *store,
                       GtkTreeIter *iter, int depth)
{
    do {
        gboolean is_folder;
        char *name, *path;
        gtk_tree_model_get(GTK_TREE_MODEL(store), iter,
            COL_NAME, &name, COL_PATH, &path,
            COL_IS_FOLDER, &is_folder, -1);
        for (int i = 0; i < depth; i++) g_string_append(out, "    ");
        if (is_folder) {
            gchar *esc = g_markup_escape_text(name, -1);
            g_string_append_printf(out, "<Folder name=\"%s\">\n", esc);
            g_free(esc);
            GtkTreeIter child;
            if (gtk_tree_model_iter_children(GTK_TREE_MODEL(store), &child, iter))
                write_node(out, store, &child, depth + 1);
            for (int i = 0; i < depth; i++) g_string_append(out, "    ");
            g_string_append(out, "</Folder>\n");
        } else if (path) {
            gchar *esc = g_markup_escape_text(path, -1);
            g_string_append_printf(out, "<File name=\"%s\"/>\n", esc);
            g_free(esc);
        }
        g_free(name);
        g_free(path);
    } while (gtk_tree_model_iter_next(GTK_TREE_MODEL(store), iter));
}

static void do_save(const char *path)
{
    GString *out = g_string_new("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                                "<NotepadPlus>\n"
                                "    <Project name=\"Project\">\n");
    GtkTreeIter root;
    if (gtk_tree_model_get_iter_first(GTK_TREE_MODEL(s_store), &root))
        write_node(out, s_store, &root, 2);
    g_string_append(out, "    </Project>\n</NotepadPlus>\n");
    GError *err = NULL;
    if (!g_file_set_contents(path, out->str, (gssize)out->len, &err)) {
        msg_dialog(err ? err->message : "Save failed");
        if (err) g_error_free(err);
    }
    g_string_free(out, TRUE);
}

/* ------------------------------------------------------------------ */
/* XML load                                                            */
/* ------------------------------------------------------------------ */
typedef struct {
    GtkTreeStore *store;
    GtkTreeIter   parent_stack[32];
    int           depth;
} ParseCtx;

static void on_start(GMarkupParseContext *ctx, const char *element,
                     const char **attrs, const char **vals,
                     gpointer user_data, GError **err)
{
    (void)ctx; (void)err;
    ParseCtx *pc = user_data;
    const char *name = NULL;
    for (int i = 0; attrs[i]; i++)
        if (g_strcmp0(attrs[i], "name") == 0) { name = vals[i]; break; }
    if (!name) return;

    if (g_strcmp0(element, "Folder") == 0) {
        GtkTreeIter iter;
        GtkTreeIter *par = pc->depth > 0 ? &pc->parent_stack[pc->depth - 1] : NULL;
        gtk_tree_store_append(pc->store, &iter, par);
        gtk_tree_store_set(pc->store, &iter,
            COL_ICON, "folder", COL_NAME, name,
            COL_PATH, NULL, COL_IS_FOLDER, TRUE, -1);
        if (pc->depth < 31)
            pc->parent_stack[pc->depth++] = iter;
    } else if (g_strcmp0(element, "File") == 0) {
        GtkTreeIter iter;
        GtkTreeIter *par = pc->depth > 0 ? &pc->parent_stack[pc->depth - 1] : NULL;
        gtk_tree_store_append(pc->store, &iter, par);
        const char *base = g_path_get_basename(name);
        gtk_tree_store_set(pc->store, &iter,
            COL_ICON, "text-x-generic", COL_NAME, base,
            COL_PATH, name, COL_IS_FOLDER, FALSE, -1);
    }
}

static void on_end(GMarkupParseContext *ctx, const char *element,
                   gpointer user_data, GError **err)
{
    (void)ctx; (void)err;
    ParseCtx *pc = user_data;
    if (g_strcmp0(element, "Folder") == 0 && pc->depth > 0)
        pc->depth--;
}

static GMarkupParser s_parser = { on_start, on_end, NULL, NULL, NULL };

static gboolean do_load(const char *path)
{
    char *contents = NULL;
    gsize len = 0;
    if (!g_file_get_contents(path, &contents, &len, NULL)) return FALSE;
    gtk_tree_store_clear(s_store);
    ParseCtx pc = { s_store, {}, 0 };
    GMarkupParseContext *ctx = g_markup_parse_context_new(&s_parser, 0, &pc, NULL);
    GError *err = NULL;
    g_markup_parse_context_parse(ctx, contents, (gssize)len, &err);
    g_markup_parse_context_free(ctx);
    g_free(contents);
    if (err) { g_error_free(err); return FALSE; }
    /* Expand all */
    gtk_tree_view_expand_all(GTK_TREE_VIEW(s_treeview));
    return TRUE;
}

/* ------------------------------------------------------------------ */
/* Row activated → open file                                          */
/* ------------------------------------------------------------------ */
static void on_row_activated(GtkTreeView *tv, GtkTreePath *tp,
                              GtkTreeViewColumn *col, gpointer d)
{
    (void)col; (void)d;
    GtkTreeIter iter;
    if (!gtk_tree_model_get_iter(GTK_TREE_MODEL(s_store), &iter, tp)) return;
    gboolean is_folder;
    char *path;
    gtk_tree_model_get(GTK_TREE_MODEL(s_store), &iter,
        COL_PATH, &path, COL_IS_FOLDER, &is_folder, -1);
    if (!is_folder && path)
        editor_open_path(path);
    g_free(path);
    (void)tv;
}

/* ------------------------------------------------------------------ */
/* Toolbar actions                                                     */
/* ------------------------------------------------------------------ */
static void on_add_file(GtkButton *b, gpointer d)
{
    (void)b; (void)d;
    GtkWidget *dlg = gtk_file_chooser_dialog_new("Add File(s) to Project",
        GTK_WINDOW(s_window), GTK_FILE_CHOOSER_ACTION_OPEN,
        "_Cancel", GTK_RESPONSE_CANCEL,
        "_Add",    GTK_RESPONSE_ACCEPT, NULL);
    gtk_file_chooser_set_select_multiple(GTK_FILE_CHOOSER(dlg), TRUE);
    if (gtk_dialog_run(GTK_DIALOG(dlg)) == GTK_RESPONSE_ACCEPT) {
        GSList *files = gtk_file_chooser_get_filenames(GTK_FILE_CHOOSER(dlg));
        /* Find selected parent folder (if any) */
        GtkTreeIter parent_iter, *par = NULL;
        GtkTreeSelection *sel = gtk_tree_view_get_selection(GTK_TREE_VIEW(s_treeview));
        if (gtk_tree_selection_get_selected(sel, NULL, &parent_iter)) {
            gboolean is_folder;
            gtk_tree_model_get(GTK_TREE_MODEL(s_store), &parent_iter,
                COL_IS_FOLDER, &is_folder, -1);
            if (is_folder) par = &parent_iter;
        }
        for (GSList *f = files; f; f = f->next) {
            const char *fp = (const char *)f->data;
            GtkTreeIter it;
            gtk_tree_store_append(s_store, &it, par);
            const char *base = g_path_get_basename(fp);
            gtk_tree_store_set(s_store, &it,
                COL_ICON, "text-x-generic", COL_NAME, base,
                COL_PATH, fp, COL_IS_FOLDER, FALSE, -1);
        }
        g_slist_free_full(files, g_free);
    }
    gtk_widget_destroy(dlg);
}

static void on_add_folder(GtkButton *b, gpointer d)
{
    (void)b; (void)d;
    GtkWidget *dlg = gtk_dialog_new_with_buttons("Add Folder",
        GTK_WINDOW(s_window), GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT,
        "_Cancel", GTK_RESPONSE_CANCEL, "_Add", GTK_RESPONSE_OK, NULL);
    gtk_dialog_set_default_response(GTK_DIALOG(dlg), GTK_RESPONSE_OK);
    GtkWidget *box  = gtk_dialog_get_content_area(GTK_DIALOG(dlg));
    GtkWidget *hbox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    gtk_container_set_border_width(GTK_CONTAINER(hbox), 8);
    gtk_box_pack_start(GTK_BOX(hbox), gtk_label_new("Folder name:"), FALSE, FALSE, 0);
    GtkWidget *entry = gtk_entry_new();
    gtk_entry_set_activates_default(GTK_ENTRY(entry), TRUE);
    gtk_box_pack_start(GTK_BOX(hbox), entry, TRUE, TRUE, 0);
    gtk_box_pack_start(GTK_BOX(box), hbox, FALSE, FALSE, 0);
    gtk_widget_show_all(dlg);

    if (gtk_dialog_run(GTK_DIALOG(dlg)) == GTK_RESPONSE_OK) {
        const char *name = gtk_entry_get_text(GTK_ENTRY(entry));
        if (name && *name) {
            GtkTreeIter it, parent_iter, *par = NULL;
            GtkTreeSelection *sel = gtk_tree_view_get_selection(GTK_TREE_VIEW(s_treeview));
            if (gtk_tree_selection_get_selected(sel, NULL, &parent_iter)) {
                gboolean is_folder;
                gtk_tree_model_get(GTK_TREE_MODEL(s_store), &parent_iter,
                    COL_IS_FOLDER, &is_folder, -1);
                if (is_folder) par = &parent_iter;
            }
            gtk_tree_store_append(s_store, &it, par);
            gtk_tree_store_set(s_store, &it,
                COL_ICON, "folder", COL_NAME, name,
                COL_PATH, NULL, COL_IS_FOLDER, TRUE, -1);
        }
    }
    gtk_widget_destroy(dlg);
}

static void on_remove_node(GtkButton *b, gpointer d)
{
    (void)b; (void)d;
    GtkTreeSelection *sel = gtk_tree_view_get_selection(GTK_TREE_VIEW(s_treeview));
    GtkTreeIter iter;
    if (gtk_tree_selection_get_selected(sel, NULL, &iter))
        gtk_tree_store_remove(s_store, &iter);
}

/* ------------------------------------------------------------------ */
/* Public API                                                          */
/* ------------------------------------------------------------------ */

GtkWidget *project_init(GtkWidget *window)
{
    s_window = window;

    s_store = gtk_tree_store_new(N_COLS,
        G_TYPE_STRING,   /* icon name */
        G_TYPE_STRING,   /* display name */
        G_TYPE_STRING,   /* file path */
        G_TYPE_BOOLEAN); /* is folder */

    s_treeview = gtk_tree_view_new_with_model(GTK_TREE_MODEL(s_store));
    gtk_tree_view_set_headers_visible(GTK_TREE_VIEW(s_treeview), FALSE);
    gtk_tree_view_set_enable_tree_lines(GTK_TREE_VIEW(s_treeview), TRUE);

    GtkCellRenderer *icon_r = gtk_cell_renderer_pixbuf_new();
    GtkCellRenderer *name_r = gtk_cell_renderer_text_new();
    GtkTreeViewColumn *col  = gtk_tree_view_column_new();
    gtk_tree_view_column_pack_start(col, icon_r, FALSE);
    gtk_tree_view_column_add_attribute(col, icon_r, "icon-name", COL_ICON);
    gtk_tree_view_column_pack_start(col, name_r, TRUE);
    gtk_tree_view_column_add_attribute(col, name_r, "text", COL_NAME);
    gtk_tree_view_append_column(GTK_TREE_VIEW(s_treeview), col);

    g_signal_connect(s_treeview, "row-activated", G_CALLBACK(on_row_activated), NULL);

    /* Toolbar */
    GtkWidget *tb = gtk_toolbar_new();
    gtk_toolbar_set_style(GTK_TOOLBAR(tb), GTK_TOOLBAR_ICONS);
    gtk_toolbar_set_icon_size(GTK_TOOLBAR(tb), GTK_ICON_SIZE_SMALL_TOOLBAR);

    struct { const char *icon; const char *tip; GCallback cb; } btns[] = {
        { "document-new",        "New Project",    G_CALLBACK(project_new)   },
        { "document-open",       "Open Project…",  G_CALLBACK(project_open)  },
        { "document-save",       "Save Project",   G_CALLBACK(project_save)  },
        { "list-add",            "Add File",        G_CALLBACK(on_add_file)   },
        { "folder-new",          "Add Folder",      G_CALLBACK(on_add_folder) },
        { "list-remove",         "Remove Item",     G_CALLBACK(on_remove_node)},
    };
    for (size_t i = 0; i < sizeof(btns)/sizeof(btns[0]); i++) {
        GtkToolItem *ti = gtk_tool_button_new(
            gtk_image_new_from_icon_name(btns[i].icon, GTK_ICON_SIZE_SMALL_TOOLBAR),
            NULL);
        gtk_tool_item_set_tooltip_text(ti, btns[i].tip);
        g_signal_connect(ti, "clicked", btns[i].cb, NULL);
        gtk_toolbar_insert(GTK_TOOLBAR(tb), ti, -1);
    }

    GtkWidget *scroll = gtk_scrolled_window_new(NULL, NULL);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll),
        GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
    gtk_container_add(GTK_CONTAINER(scroll), s_treeview);

    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);

    /* Header bar */
    GtkWidget *hdr    = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
    GtkWidget *title  = gtk_label_new("Project Manager");
    gtk_widget_set_halign(title, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(hdr), title, TRUE, TRUE, 4);
    GtkWidget *close_btn = gtk_button_new_from_icon_name("window-close-symbolic",
                                                          GTK_ICON_SIZE_MENU);
    gtk_button_set_relief(GTK_BUTTON(close_btn), GTK_RELIEF_NONE);
    g_signal_connect_swapped(close_btn, "clicked",
                             G_CALLBACK(project_set_visible), GINT_TO_POINTER(FALSE));
    gtk_box_pack_end(GTK_BOX(hdr), close_btn, FALSE, FALSE, 0);

    gtk_box_pack_start(GTK_BOX(box), hdr,    FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(box), tb,     FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(box), scroll, TRUE,  TRUE,  0);

    s_panel = box;
    gtk_widget_set_size_request(s_panel, 180, -1);
    return s_panel;
}

void project_set_visible(gboolean v)
{
    if (!s_panel) return;
    if (v) gtk_widget_show(s_panel);
    else    gtk_widget_hide(s_panel);
}

gboolean project_is_visible(void)
{
    return s_panel && gtk_widget_get_visible(s_panel);
}

void project_new(void)
{
    gtk_tree_store_clear(s_store);
    g_free(s_proj_path);
    s_proj_path = NULL;
    project_set_visible(TRUE);
    project_save(); /* prompt for a name right away */
}

void project_open(const char *path)
{
    if (!path) {
        GtkWidget *dlg = gtk_file_chooser_dialog_new("Open Project",
            GTK_WINDOW(s_window), GTK_FILE_CHOOSER_ACTION_OPEN,
            "_Cancel", GTK_RESPONSE_CANCEL,
            "_Open",   GTK_RESPONSE_ACCEPT, NULL);
        GtkFileFilter *ff = gtk_file_filter_new();
        gtk_file_filter_set_name(ff, "Notepad++ Projects (*.nppproject)");
        gtk_file_filter_add_pattern(ff, "*.nppproject");
        gtk_file_chooser_add_filter(GTK_FILE_CHOOSER(dlg), ff);
        if (gtk_dialog_run(GTK_DIALOG(dlg)) == GTK_RESPONSE_ACCEPT) {
            char *fn = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dlg));
            gtk_widget_destroy(dlg);
            g_free(s_proj_path);
            s_proj_path = fn;
            do_load(fn);
            project_set_visible(TRUE);
        } else {
            gtk_widget_destroy(dlg);
        }
        return;
    }
    g_free(s_proj_path);
    s_proj_path = g_strdup(path);
    do_load(path);
    project_set_visible(TRUE);
}

void project_save(void)
{
    if (!s_proj_path) {
        GtkWidget *dlg = gtk_file_chooser_dialog_new("Save Project As…",
            GTK_WINDOW(s_window), GTK_FILE_CHOOSER_ACTION_SAVE,
            "_Cancel", GTK_RESPONSE_CANCEL,
            "_Save",   GTK_RESPONSE_ACCEPT, NULL);
        gtk_file_chooser_set_do_overwrite_confirmation(GTK_FILE_CHOOSER(dlg), TRUE);
        gtk_file_chooser_set_current_name(GTK_FILE_CHOOSER(dlg), "project.nppproject");
        GtkFileFilter *ff = gtk_file_filter_new();
        gtk_file_filter_set_name(ff, "Notepad++ Projects (*.nppproject)");
        gtk_file_filter_add_pattern(ff, "*.nppproject");
        gtk_file_chooser_add_filter(GTK_FILE_CHOOSER(dlg), ff);
        if (gtk_dialog_run(GTK_DIALOG(dlg)) == GTK_RESPONSE_ACCEPT) {
            s_proj_path = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dlg));
        }
        gtk_widget_destroy(dlg);
    }
    if (s_proj_path)
        do_save(s_proj_path);
}

void project_close(void)
{
    gtk_tree_store_clear(s_store);
    g_free(s_proj_path);
    s_proj_path = NULL;
    project_set_visible(FALSE);
}
