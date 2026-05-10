#include "run.h"
#include <string.h>
#include <stdlib.h>

/* ------------------------------------------------------------------ */
/* Named commands persistence                                          */
/* ------------------------------------------------------------------ */

#define MAX_CMDS 64

typedef struct {
    char *name;
    char *cmd;
} SavedCmd;

static SavedCmd s_cmds[MAX_CMDS];
static int      s_cmd_count = 0;

static char *cmds_path(void)
{
    return g_build_filename(g_get_home_dir(), ".config", "notetux",
                            "commands.xml", NULL);
}

static void cmds_save(void)
{
    GString *out = g_string_new("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                                "<NotepadPlus>\n    <Commands>\n");
    for (int i = 0; i < s_cmd_count; i++) {
        gchar *en = g_markup_escape_text(s_cmds[i].name, -1);
        gchar *ec = g_markup_escape_text(s_cmds[i].cmd,  -1);
        g_string_append_printf(out,
            "        <Command name=\"%s\" cmd=\"%s\"/>\n", en, ec);
        g_free(en); g_free(ec);
    }
    g_string_append(out, "    </Commands>\n</NotepadPlus>\n");
    char *path = cmds_path();
    g_file_set_contents(path, out->str, (gssize)out->len, NULL);
    g_free(path);
    g_string_free(out, TRUE);
}

static void cmd_parse_start(GMarkupParseContext *ctx, const char *el,
                             const char **attrs, const char **vals,
                             gpointer ud, GError **err)
{
    (void)ctx; (void)ud; (void)err;
    if (g_strcmp0(el, "Command") != 0 || s_cmd_count >= MAX_CMDS) return;
    const char *name = NULL, *cmd = NULL;
    for (int i = 0; attrs[i]; i++) {
        if (g_strcmp0(attrs[i], "name") == 0) name = vals[i];
        else if (g_strcmp0(attrs[i], "cmd")  == 0) cmd  = vals[i];
    }
    if (name && cmd) {
        s_cmds[s_cmd_count].name = g_strdup(name);
        s_cmds[s_cmd_count].cmd  = g_strdup(cmd);
        s_cmd_count++;
    }
}

static GMarkupParser s_parser = { cmd_parse_start, NULL, NULL, NULL, NULL };

static void cmds_load(void)
{
    char *path = cmds_path();
    char *buf  = NULL;
    gsize len  = 0;
    if (!g_file_get_contents(path, &buf, &len, NULL)) { g_free(path); return; }
    g_free(path);
    GMarkupParseContext *ctx = g_markup_parse_context_new(&s_parser, 0, NULL, NULL);
    g_markup_parse_context_parse(ctx, buf, (gssize)len, NULL);
    g_markup_parse_context_free(ctx);
    g_free(buf);
}

static void ensure_cmds_loaded(void)
{
    static gboolean loaded = FALSE;
    if (!loaded) { loaded = TRUE; cmds_load(); }
}

/* ------------------------------------------------------------------ */
/* %TOKEN% substitution                                                */
/* ------------------------------------------------------------------ */

static char *subst(const char *tmpl, const char *filepath)
{
    if (!filepath)
        return g_strdup(tmpl);

    char *dir  = g_path_get_dirname(filepath);
    char *base = g_path_get_basename(filepath);

    /* Split name and extension */
    char *dot  = strrchr(base, '.');
    char *name = dot ? g_strndup(base, (gsize)(dot - base)) : g_strdup(base);
    char *ext  = dot ? g_strdup(dot + 1) : g_strdup("");

    GString *out = g_string_new(NULL);
    for (const char *p = tmpl; *p; ) {
        if (strncmp(p, "%FILE%", 6) == 0) {
            g_string_append(out, filepath); p += 6;
        } else if (strncmp(p, "%DIR%",  5) == 0) {
            g_string_append(out, dir);      p += 5;
        } else if (strncmp(p, "%NAME%", 6) == 0) {
            g_string_append(out, name);     p += 6;
        } else if (strncmp(p, "%EXT%",  5) == 0) {
            g_string_append(out, ext);      p += 5;
        } else {
            g_string_append_c(out, *p++);
        }
    }
    g_free(dir); g_free(base); g_free(name); g_free(ext);
    return g_string_free(out, FALSE);
}

static void run_command(GtkWindow *parent, const char *cmd_str,
                         const char *filepath)
{
    char *expanded = subst(cmd_str, filepath);
    char *shell_argv[] = { "sh", "-c", expanded, NULL };
    GError *err = NULL;
    if (!g_spawn_async(filepath ? g_path_get_dirname(filepath) : NULL,
                       shell_argv, NULL,
                       G_SPAWN_SEARCH_PATH, NULL, NULL, NULL, &err)) {
        GtkWidget *d = gtk_message_dialog_new(parent, GTK_DIALOG_MODAL,
            GTK_MESSAGE_ERROR, GTK_BUTTONS_OK,
            "Could not run command:\n%s", err ? err->message : cmd_str);
        gtk_dialog_run(GTK_DIALOG(d));
        gtk_widget_destroy(d);
        if (err) g_error_free(err);
    }
    g_free(expanded);
}

/* ------------------------------------------------------------------ */
/* Run dialog                                                          */
/* ------------------------------------------------------------------ */

typedef struct {
    GtkWidget  *combo;
    GtkWindow  *parent;
    const char *filepath;
} RunDlgData;

static void on_run_save(GtkButton *b, gpointer ud)
{
    (void)b;
    RunDlgData *d = ud;
    const char *cmd = gtk_entry_get_text(GTK_ENTRY(gtk_bin_get_child(GTK_BIN(d->combo))));
    if (!cmd || !*cmd) return;
    ensure_cmds_loaded();

    /* Simple name dialog */
    GtkWidget *nd = gtk_dialog_new_with_buttons("Save Command As…", d->parent,
        GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT,
        "_Cancel", GTK_RESPONSE_CANCEL, "_Save", GTK_RESPONSE_OK, NULL);
    gtk_dialog_set_default_response(GTK_DIALOG(nd), GTK_RESPONSE_OK);
    GtkWidget *nb = gtk_dialog_get_content_area(GTK_DIALOG(nd));
    GtkWidget *hb = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    gtk_container_set_border_width(GTK_CONTAINER(hb), 8);
    gtk_box_pack_start(GTK_BOX(hb), gtk_label_new("Name:"), FALSE, FALSE, 0);
    GtkWidget *ne = gtk_entry_new();
    gtk_entry_set_activates_default(GTK_ENTRY(ne), TRUE);
    gtk_entry_set_width_chars(GTK_ENTRY(ne), 28);
    gtk_box_pack_start(GTK_BOX(hb), ne, TRUE, TRUE, 0);
    gtk_box_pack_start(GTK_BOX(nb), hb, FALSE, FALSE, 0);
    gtk_widget_show_all(nd);
    if (gtk_dialog_run(GTK_DIALOG(nd)) == GTK_RESPONSE_OK && s_cmd_count < MAX_CMDS) {
        const char *name = gtk_entry_get_text(GTK_ENTRY(ne));
        if (name && *name) {
            s_cmds[s_cmd_count].name = g_strdup(name);
            s_cmds[s_cmd_count].cmd  = g_strdup(cmd);
            s_cmd_count++;
            cmds_save();
            gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(d->combo), cmd);
        }
    }
    gtk_widget_destroy(nd);
}

void run_dialog(GtkWindow *parent, const char *filepath)
{
    ensure_cmds_loaded();
    GtkWidget *dlg = gtk_dialog_new_with_buttons("Run…", parent,
        GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT,
        "_Cancel",  GTK_RESPONSE_CANCEL,
        "_Run",     GTK_RESPONSE_OK, NULL);
    gtk_dialog_set_default_response(GTK_DIALOG(dlg), GTK_RESPONSE_OK);
    gtk_window_set_default_size(GTK_WINDOW(dlg), 520, -1);

    GtkWidget *box = gtk_dialog_get_content_area(GTK_DIALOG(dlg));
    GtkWidget *grid = gtk_grid_new();
    gtk_grid_set_column_spacing(GTK_GRID(grid), 8);
    gtk_grid_set_row_spacing(GTK_GRID(grid), 4);
    gtk_container_set_border_width(GTK_CONTAINER(grid), 8);
    gtk_box_pack_start(GTK_BOX(box), grid, TRUE, TRUE, 0);

    gtk_grid_attach(GTK_GRID(grid), gtk_label_new("Command:"), 0, 0, 1, 1);
    GtkWidget *combo = gtk_combo_box_text_new_with_entry();
    for (int i = 0; i < s_cmd_count; i++)
        gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(combo), s_cmds[i].cmd);
    gtk_widget_set_hexpand(combo, TRUE);
    gtk_grid_attach(GTK_GRID(grid), combo, 1, 0, 1, 1);

    GtkWidget *hint = gtk_label_new(
        "<small>Tokens: %FILE% %DIR% %NAME% %EXT%</small>");
    gtk_label_set_use_markup(GTK_LABEL(hint), TRUE);
    gtk_widget_set_halign(hint, GTK_ALIGN_START);
    gtk_grid_attach(GTK_GRID(grid), hint, 0, 1, 2, 1);

    GtkWidget *save_btn = gtk_button_new_with_label("Save…");
    gtk_grid_attach(GTK_GRID(grid), save_btn, 1, 2, 1, 1);
    gtk_widget_set_halign(save_btn, GTK_ALIGN_END);

    RunDlgData rd = { combo, parent, filepath };
    g_signal_connect(save_btn, "clicked", G_CALLBACK(on_run_save), &rd);

    gtk_widget_show_all(dlg);
    if (gtk_dialog_run(GTK_DIALOG(dlg)) == GTK_RESPONSE_OK) {
        const char *cmd = gtk_entry_get_text(
            GTK_ENTRY(gtk_bin_get_child(GTK_BIN(combo))));
        if (cmd && *cmd) {
            gtk_widget_destroy(dlg);
            run_command(parent, cmd, filepath);
            return;
        }
    }
    gtk_widget_destroy(dlg);
}

/* ------------------------------------------------------------------ */
/* Manage saved commands                                               */
/* ------------------------------------------------------------------ */

typedef struct { GtkTreeView *tv; GtkListStore *ls; } ManageData;

static void on_delete_cmd(GtkButton *b, gpointer ud)
{
    (void)b;
    ManageData *d = ud;
    GtkTreeSelection *sel = gtk_tree_view_get_selection(d->tv);
    GtkTreeIter it;
    GtkTreeModel *m;
    if (!gtk_tree_selection_get_selected(sel, &m, &it)) return;
    int idx;
    gtk_tree_model_get(m, &it, 0, &idx, -1);
    if (idx < 0 || idx >= s_cmd_count) return;
    g_free(s_cmds[idx].name);
    g_free(s_cmds[idx].cmd);
    for (int j = idx; j < s_cmd_count - 1; j++)
        s_cmds[j] = s_cmds[j + 1];
    s_cmd_count--;
    cmds_save();
    gtk_list_store_remove(d->ls, &it);
}

void run_manage_dialog(GtkWindow *parent, const char *filepath)
{
    (void)filepath;
    ensure_cmds_loaded();
    GtkWidget *dlg = gtk_dialog_new_with_buttons("Modify / Delete Commands", parent,
        GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT,
        "_Close", GTK_RESPONSE_CLOSE, NULL);
    gtk_window_set_default_size(GTK_WINDOW(dlg), 460, 300);
    GtkWidget *box = gtk_dialog_get_content_area(GTK_DIALOG(dlg));

    /* Two columns: name and command */
    GtkListStore *ls = gtk_list_store_new(3, G_TYPE_INT,
                                          G_TYPE_STRING, G_TYPE_STRING);
    for (int i = 0; i < s_cmd_count; i++) {
        GtkTreeIter it;
        gtk_list_store_append(ls, &it);
        gtk_list_store_set(ls, &it, 0, i,
            1, s_cmds[i].name, 2, s_cmds[i].cmd, -1);
    }
    GtkWidget *tv = gtk_tree_view_new_with_model(GTK_TREE_MODEL(ls));
    g_object_unref(ls);
    GtkCellRenderer *r = gtk_cell_renderer_text_new();
    gtk_tree_view_append_column(GTK_TREE_VIEW(tv),
        gtk_tree_view_column_new_with_attributes("Name", r, "text", 1, NULL));
    gtk_tree_view_append_column(GTK_TREE_VIEW(tv),
        gtk_tree_view_column_new_with_attributes("Command", r, "text", 2, NULL));

    GtkWidget *scroll = gtk_scrolled_window_new(NULL, NULL);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll),
        GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
    gtk_container_add(GTK_CONTAINER(scroll), tv);
    gtk_box_pack_start(GTK_BOX(box), scroll, TRUE, TRUE, 0);

    GtkWidget *btn_bar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
    gtk_container_set_border_width(GTK_CONTAINER(btn_bar), 4);
    GtkWidget *del_btn = gtk_button_new_with_label("Delete");
    gtk_box_pack_end(GTK_BOX(btn_bar), del_btn, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(box), btn_bar, FALSE, FALSE, 0);

    ManageData *md = g_new(ManageData, 1);
    md->tv = GTK_TREE_VIEW(tv);
    md->ls = GTK_LIST_STORE(gtk_tree_view_get_model(GTK_TREE_VIEW(tv)));
    g_signal_connect_data(del_btn, "clicked", G_CALLBACK(on_delete_cmd),
                          md, (GClosureNotify)g_free, 0);

    gtk_widget_show_all(dlg);
    gtk_dialog_run(GTK_DIALOG(dlg));
    gtk_widget_destroy(dlg);
}
