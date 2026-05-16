#include "macro.h"
#include "editor.h"
#include "i18n.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

/* ------------------------------------------------------------------ */
/* SCI constants                                                       */
/* ------------------------------------------------------------------ */
#define SCI_STARTRECORD  3001
#define SCI_STOPRECORD   3002

/* Messages whose lParam is a NUL-terminated string pointer */
static const unsigned int k_string_msgs[] = {
    2003, /* SCI_INSERTTEXT  */
    2170, /* SCI_REPLACESEL  */
    2181, /* SCI_SETTEXT     */
    2001, /* SCI_ADDTEXT     */
    2282, /* SCI_APPENDTEXT  */
};
#define K_NSTR (sizeof(k_string_msgs) / sizeof(k_string_msgs[0]))

static gboolean lp_is_string(unsigned int msg)
{
    for (size_t i = 0; i < K_NSTR; i++)
        if (k_string_msgs[i] == msg) return TRUE;
    return FALSE;
}

/* ------------------------------------------------------------------ */
/* Storage                                                             */
/* ------------------------------------------------------------------ */
typedef struct {
    unsigned int msg;
    uptr_t       wp;
    sptr_t       lp;      /* integer value, or 0 when text != NULL */
    char        *text;    /* heap copy when lParam was a string */
} MacroStep;

#define MAX_STEPS 65536

static MacroStep  s_steps[MAX_STEPS];
static int        s_count      = 0;
static gboolean   s_recording  = FALSE;

/* ------------------------------------------------------------------ */
/* API                                                                 */
/* ------------------------------------------------------------------ */

static sptr_t sci_msg(GtkWidget *sci, unsigned int m, uptr_t w, sptr_t l)
{
    return scintilla_send_message(SCINTILLA(sci), m, w, l);
}

void macro_start_recording(GtkWidget *sci)
{
    /* Clear previous macro */
    for (int i = 0; i < s_count; i++)
        g_free(s_steps[i].text);
    s_count     = 0;
    s_recording = TRUE;
    sci_msg(sci, SCI_STARTRECORD, 0, 0);
}

void macro_stop_recording(GtkWidget *sci)
{
    s_recording = FALSE;
    sci_msg(sci, SCI_STOPRECORD, 0, 0);
}

void macro_on_record(unsigned int msg, uptr_t wp, sptr_t lp)
{
    if (!s_recording || s_count >= MAX_STEPS) return;
    MacroStep *step = &s_steps[s_count++];
    step->msg  = msg;
    step->wp   = wp;
    step->text = NULL;
    if (lp_is_string(msg) && lp != 0) {
        step->text = g_strdup((const char *)lp);
        step->lp   = 0;
    } else {
        step->lp = lp;
    }
}

void macro_playback(GtkWidget *sci)
{
    if (s_recording || s_count == 0) return;
    sci_msg(sci, SCI_BEGINUNDOACTION, 0, 0);
    for (int i = 0; i < s_count; i++) {
        MacroStep *step = &s_steps[i];
        sptr_t lp = step->text ? (sptr_t)step->text : step->lp;
        sci_msg(sci, step->msg, step->wp, lp);
    }
    sci_msg(sci, SCI_ENDUNDOACTION, 0, 0);
}

void macro_playback_n(GtkWidget *sci, GtkWindow *parent)
{
    if (s_recording || s_count == 0) return;

    GtkWidget *dlg = gtk_dialog_new_with_buttons(
        T("dlg.MultiMacro.title", "Run Macro Multiple Times"),
        parent,
        GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT,
        TM("dlg.MultiMacro.2", "_Cancel"), GTK_RESPONSE_CANCEL,
        TM("dlg.MultiMacro.1", "_Run"),    GTK_RESPONSE_OK,
        NULL);
    gtk_dialog_set_default_response(GTK_DIALOG(dlg), GTK_RESPONSE_OK);

    GtkWidget *content = gtk_dialog_get_content_area(GTK_DIALOG(dlg));
    GtkWidget *hbox    = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    gtk_container_set_border_width(GTK_CONTAINER(hbox), 12);
    GtkWidget *label   = gtk_label_new(T("dlg.MultiMacro.8005", "Number of times:"));
    GtkWidget *spin    = gtk_spin_button_new_with_range(1, 10000, 1);
    gtk_spin_button_set_value(GTK_SPIN_BUTTON(spin), 1);
    gtk_entry_set_activates_default(GTK_ENTRY(spin), TRUE);
    gtk_box_pack_start(GTK_BOX(hbox), label, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hbox), spin,  FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(content), hbox, FALSE, FALSE, 0);
    gtk_widget_show_all(dlg);

    if (gtk_dialog_run(GTK_DIALOG(dlg)) == GTK_RESPONSE_OK) {
        int n = (int)gtk_spin_button_get_value(GTK_SPIN_BUTTON(spin));
        gtk_widget_destroy(dlg);
        sci_msg(sci, SCI_BEGINUNDOACTION, 0, 0);
        for (int t = 0; t < n; t++) {
            for (int i = 0; i < s_count; i++) {
                MacroStep *step = &s_steps[i];
                sptr_t lp = step->text ? (sptr_t)step->text : step->lp;
                sci_msg(sci, step->msg, step->wp, lp);
            }
        }
        sci_msg(sci, SCI_ENDUNDOACTION, 0, 0);
    } else {
        gtk_widget_destroy(dlg);
    }
}

gboolean macro_is_recording(void) { return s_recording; }
gboolean macro_has_macro(void)    { return s_count > 0; }

/* ================================================================== */
/* Named macro management (item 66)                                    */
/* ================================================================== */

typedef struct {
    char *name;
    int   step_count;
    MacroStep steps[MAX_STEPS];
} NamedMacro;

#define MAX_NAMED 64
static NamedMacro s_named[MAX_NAMED];
static int        s_named_count = 0;

static char *macros_path(void)
{
    return g_build_filename(g_get_home_dir(), ".config", "notetux",
                            "macros.xml", NULL);
}

static void named_macros_save(void)
{
    GString *out = g_string_new("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                                "<NotepadPlus>\n    <Macros>\n");
    for (int i = 0; i < s_named_count; i++) {
        NamedMacro *nm = &s_named[i];
        gchar *esc = g_markup_escape_text(nm->name, -1);
        g_string_append_printf(out, "        <Macro name=\"%s\">\n", esc);
        g_free(esc);
        for (int j = 0; j < nm->step_count; j++) {
            MacroStep *st = &nm->steps[j];
            if (st->text) {
                gchar *te = g_markup_escape_text(st->text, -1);
                g_string_append_printf(out,
                    "            <Action msg=\"%u\" wParam=\"%lu\" lParam=\"0\" sParam=\"%s\"/>\n",
                    st->msg, (unsigned long)st->wp, te);
                g_free(te);
            } else {
                g_string_append_printf(out,
                    "            <Action msg=\"%u\" wParam=\"%lu\" lParam=\"%ld\" sParam=\"\"/>\n",
                    st->msg, (unsigned long)st->wp, (long)st->lp);
            }
        }
        g_string_append(out, "        </Macro>\n");
    }
    g_string_append(out, "    </Macros>\n</NotepadPlus>\n");
    char *path = macros_path();
    g_file_set_contents(path, out->str, (gssize)out->len, NULL);
    g_free(path);
    g_string_free(out, TRUE);
}

/* Simple SAX parser for saved macros */
typedef struct { NamedMacro *cur; } MacroParseCtx;

static void mp_start(GMarkupParseContext *c, const char *el,
                     const char **attrs, const char **vals,
                     gpointer ud, GError **err)
{
    (void)c; (void)err;
    MacroParseCtx *pc = ud;
    if (g_strcmp0(el, "Macro") == 0) {
        if (s_named_count >= MAX_NAMED) return;
        const char *name = NULL;
        for (int i = 0; attrs[i]; i++)
            if (g_strcmp0(attrs[i], "name") == 0) { name = vals[i]; break; }
        if (!name) return;
        pc->cur = &s_named[s_named_count++];
        pc->cur->name       = g_strdup(name);
        pc->cur->step_count = 0;
    } else if (g_strcmp0(el, "Action") == 0 && pc->cur) {
        if (pc->cur->step_count >= MAX_STEPS) return;
        unsigned int msg = 0; unsigned long wp = 0; long lp = 0;
        const char *sp = NULL;
        for (int i = 0; attrs[i]; i++) {
            if (g_strcmp0(attrs[i], "msg")    == 0) msg = (unsigned int)atoi(vals[i]);
            else if (g_strcmp0(attrs[i], "wParam") == 0) wp  = strtoul(vals[i], NULL, 10);
            else if (g_strcmp0(attrs[i], "lParam") == 0) lp  = strtol (vals[i], NULL, 10);
            else if (g_strcmp0(attrs[i], "sParam") == 0) sp  = vals[i];
        }
        MacroStep *st = &pc->cur->steps[pc->cur->step_count++];
        st->msg  = msg;
        st->wp   = (uptr_t)wp;
        st->text = (sp && *sp) ? g_strdup(sp) : NULL;
        st->lp   = st->text ? 0 : (sptr_t)lp;
    }
}

static void mp_end(GMarkupParseContext *c, const char *el, gpointer ud, GError **err)
{
    (void)c; (void)err;
    MacroParseCtx *pc = ud;
    if (g_strcmp0(el, "Macro") == 0) pc->cur = NULL;
}

static GMarkupParser s_mp = { mp_start, mp_end, NULL, NULL, NULL };

static void named_macros_load(void)
{
    char *path = macros_path();
    char *buf  = NULL;
    gsize len  = 0;
    if (!g_file_get_contents(path, &buf, &len, NULL)) { g_free(path); return; }
    g_free(path);
    MacroParseCtx pc = { NULL };
    GMarkupParseContext *ctx = g_markup_parse_context_new(&s_mp, 0, &pc, NULL);
    g_markup_parse_context_parse(ctx, buf, (gssize)len, NULL);
    g_markup_parse_context_free(ctx);
    g_free(buf);
}

/* Ensure macros are loaded from disk once */
static void ensure_loaded(void)
{
    static gboolean loaded = FALSE;
    if (!loaded) { loaded = TRUE; named_macros_load(); }
}

/* ------------------------------------------------------------------ */
/* Save dialog                                                         */
/* ------------------------------------------------------------------ */

void macro_save_as_dialog(GtkWidget *sci, GtkWindow *parent)
{
    (void)sci;
    if (s_count == 0) {
        GtkWidget *d = gtk_message_dialog_new(parent, GTK_DIALOG_MODAL,
            GTK_MESSAGE_INFO, GTK_BUTTONS_OK,
            "No macro is currently recorded.");
        gtk_dialog_run(GTK_DIALOG(d));
        gtk_widget_destroy(d);
        return;
    }
    ensure_loaded();
    GtkWidget *dlg = gtk_dialog_new_with_buttons("Save Macro As…", parent,
        GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT,
        "_Cancel", GTK_RESPONSE_CANCEL, "_Save", GTK_RESPONSE_OK, NULL);
    gtk_dialog_set_default_response(GTK_DIALOG(dlg), GTK_RESPONSE_OK);
    GtkWidget *box = gtk_dialog_get_content_area(GTK_DIALOG(dlg));
    GtkWidget *grid = gtk_grid_new();
    gtk_grid_set_column_spacing(GTK_GRID(grid), 8);
    gtk_grid_set_row_spacing(GTK_GRID(grid), 4);
    gtk_container_set_border_width(GTK_CONTAINER(grid), 8);
    gtk_box_pack_start(GTK_BOX(box), grid, FALSE, FALSE, 0);

    GtkWidget *name_lbl = gtk_label_new("Name:");
    gtk_widget_set_halign(name_lbl, GTK_ALIGN_END);
    GtkWidget *name_ent = gtk_entry_new();
    gtk_entry_set_activates_default(GTK_ENTRY(name_ent), TRUE);
    gtk_entry_set_width_chars(GTK_ENTRY(name_ent), 30);
    gtk_grid_attach(GTK_GRID(grid), name_lbl, 0, 0, 1, 1);
    gtk_grid_attach(GTK_GRID(grid), name_ent, 1, 0, 1, 1);

    gtk_widget_show_all(dlg);
    if (gtk_dialog_run(GTK_DIALOG(dlg)) == GTK_RESPONSE_OK) {
        const char *name = gtk_entry_get_text(GTK_ENTRY(name_ent));
        if (name && *name && s_named_count < MAX_NAMED) {
            NamedMacro *nm = &s_named[s_named_count++];
            nm->name       = g_strdup(name);
            nm->step_count = s_count;
            for (int i = 0; i < s_count; i++) {
                nm->steps[i] = s_steps[i];
                if (s_steps[i].text)
                    nm->steps[i].text = g_strdup(s_steps[i].text);
            }
            named_macros_save();
        }
    }
    gtk_widget_destroy(dlg);
}

/* ------------------------------------------------------------------ */
/* Manage dialog                                                       */
/* ------------------------------------------------------------------ */

typedef struct { GtkTreeView *tv; GtkListStore *ls; } DelData;

static void on_delete_macro(GtkButton *b, gpointer ud)
{
    (void)b;
    DelData *d = ud;
    GtkTreeSelection *sel = gtk_tree_view_get_selection(d->tv);
    GtkTreeIter it;
    GtkTreeModel *m;
    if (!gtk_tree_selection_get_selected(sel, &m, &it)) return;
    int idx;
    gtk_tree_model_get(m, &it, 0, &idx, -1);
    if (idx < 0 || idx >= s_named_count) return;
    g_free(s_named[idx].name);
    for (int j = 0; j < s_named[idx].step_count; j++)
        g_free(s_named[idx].steps[j].text);
    for (int j = idx; j < s_named_count - 1; j++)
        s_named[j] = s_named[j + 1];
    s_named_count--;
    named_macros_save();
    gtk_list_store_remove(d->ls, &it);
}

void macro_manage_dialog(GtkWidget *sci, GtkWindow *parent)
{
    (void)sci;
    ensure_loaded();
    GtkWidget *dlg = gtk_dialog_new_with_buttons(T("dlg.MultiMacro.title", "Modify / Delete Macros"), parent,
        GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT,
        T("dlg.Find.2", "_Close"), GTK_RESPONSE_CLOSE, NULL);
    gtk_window_set_default_size(GTK_WINDOW(dlg), 380, 280);
    GtkWidget *box = gtk_dialog_get_content_area(GTK_DIALOG(dlg));

    GtkListStore *ls = gtk_list_store_new(2, G_TYPE_INT, G_TYPE_STRING);
    for (int i = 0; i < s_named_count; i++) {
        GtkTreeIter it;
        gtk_list_store_append(ls, &it);
        gtk_list_store_set(ls, &it, 0, i, 1, s_named[i].name, -1);
    }
    GtkWidget *tv = gtk_tree_view_new_with_model(GTK_TREE_MODEL(ls));
    g_object_unref(ls);
    gtk_tree_view_set_headers_visible(GTK_TREE_VIEW(tv), FALSE);
    GtkCellRenderer *r = gtk_cell_renderer_text_new();
    gtk_tree_view_append_column(GTK_TREE_VIEW(tv),
        gtk_tree_view_column_new_with_attributes("Name", r, "text", 1, NULL));

    GtkWidget *scroll = gtk_scrolled_window_new(NULL, NULL);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll),
        GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
    gtk_container_add(GTK_CONTAINER(scroll), tv);
    gtk_box_pack_start(GTK_BOX(box), scroll, TRUE, TRUE, 0);

    GtkWidget *btn_bar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
    gtk_container_set_border_width(GTK_CONTAINER(btn_bar), 4);
    GtkWidget *del_btn = gtk_button_new_with_label(T("dlg.ShortcutMapper.2603", "Delete"));
    gtk_box_pack_end(GTK_BOX(btn_bar), del_btn, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(box), btn_bar, FALSE, FALSE, 0);

    DelData *dd = g_new(DelData, 1);
    dd->tv = GTK_TREE_VIEW(tv);
    dd->ls = GTK_LIST_STORE(gtk_tree_view_get_model(GTK_TREE_VIEW(tv)));
    g_signal_connect_data(del_btn, "clicked", G_CALLBACK(on_delete_macro),
                          dd, (GClosureNotify)g_free, 0);

    gtk_widget_show_all(dlg);
    gtk_dialog_run(GTK_DIALOG(dlg));
    gtk_widget_destroy(dlg);
}

/* ------------------------------------------------------------------ */
/* Trim trailing whitespace + save                                     */
/* ------------------------------------------------------------------ */

void macro_trim_and_save(GtkWidget *sci)
{
    /* Trim trailing whitespace on every line */
    Sci_Position n = (Sci_Position)scintilla_send_message(SCINTILLA(sci),
        SCI_GETLINECOUNT, 0, 0);
    scintilla_send_message(SCINTILLA(sci), SCI_BEGINUNDOACTION, 0, 0);
    for (Sci_Position line = 0; line < n; line++) {
        Sci_Position start = (Sci_Position)scintilla_send_message(
            SCINTILLA(sci), SCI_POSITIONFROMLINE, (uptr_t)line, 0);
        Sci_Position end   = (Sci_Position)scintilla_send_message(
            SCINTILLA(sci), SCI_GETLINEENDPOSITION, (uptr_t)line, 0);
        /* Walk backwards over spaces and tabs */
        Sci_Position trim = end;
        while (trim > start) {
            int ch = (int)scintilla_send_message(SCINTILLA(sci),
                SCI_GETCHARAT, (uptr_t)(trim - 1), 0);
            if (ch != ' ' && ch != '\t') break;
            trim--;
        }
        if (trim < end) {
            scintilla_send_message(SCINTILLA(sci), SCI_SETTARGETSTART,
                (uptr_t)trim, 0);
            scintilla_send_message(SCINTILLA(sci), SCI_SETTARGETEND,
                (uptr_t)end, 0);
            scintilla_send_message(SCINTILLA(sci), SCI_REPLACETARGET, 0,
                (sptr_t)"");
        }
    }
    scintilla_send_message(SCINTILLA(sci), SCI_ENDUNDOACTION, 0, 0);
}

/* ------------------------------------------------------------------ */
/* Populate saved-macro menu items                                     */
/* ------------------------------------------------------------------ */

typedef struct { int idx; } PlayData;

static void on_play_saved(GtkMenuItem *mi, gpointer ud)
{
    (void)mi;
    PlayData *pd = ud;
    NppDoc *doc = editor_current_doc();
    if (!doc || pd->idx < 0 || pd->idx >= s_named_count) return;
    NamedMacro *nm = &s_named[pd->idx];
    scintilla_send_message(SCINTILLA(doc->sci), SCI_BEGINUNDOACTION, 0, 0);
    for (int i = 0; i < nm->step_count; i++) {
        MacroStep *st = &nm->steps[i];
        sptr_t lp = st->text ? (sptr_t)st->text : st->lp;
        scintilla_send_message(SCINTILLA(doc->sci), st->msg, st->wp, lp);
    }
    scintilla_send_message(SCINTILLA(doc->sci), SCI_ENDUNDOACTION, 0, 0);
}

void macro_populate_saved_menu(GtkWidget *menu, GtkWidget *sci)
{
    (void)sci; /* sci is always resolved at playback time via editor_current_doc() */
    ensure_loaded();
    if (s_named_count == 0) return;
    GtkWidget *sep = gtk_separator_menu_item_new();
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), sep);
    gtk_widget_show(sep);
    for (int i = 0; i < s_named_count; i++) {
        GtkWidget *mi = gtk_menu_item_new_with_label(s_named[i].name);
        PlayData *pd  = g_new(PlayData, 1);
        pd->idx = i;
        g_signal_connect_data(mi, "activate", G_CALLBACK(on_play_saved), pd,
                              (GClosureNotify)g_free, 0);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), mi);
        gtk_widget_show(mi);
    }
}
