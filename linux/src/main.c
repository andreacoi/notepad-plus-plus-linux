#include <gtk/gtk.h>
#include "sci_c.h"
#include "editor.h"
#include "statusbar.h"
#include "findreplace.h"
#include "toolbar.h"
#include "styleeditor.h"
#include "lexer.h"
#include "i18n.h"

/* ------------------------------------------------------------------ */
/* Menu callbacks                                                      */
/* ------------------------------------------------------------------ */

/* File */
static void cb_new(GtkMenuItem *i, gpointer d)    { (void)i;(void)d; editor_new_doc(); }
static void cb_open(GtkMenuItem *i, gpointer d)   { (void)i;(void)d; editor_open_dialog(); }
static void cb_save(GtkMenuItem *i, gpointer d)   { (void)i;(void)d; editor_save(); }
static void cb_save_as(GtkMenuItem *i, gpointer d){ (void)i;(void)d; editor_save_as_dialog(); }
static void cb_close(GtkMenuItem *i, gpointer d)  { (void)i;(void)d; editor_close_page(-1); }

static void cb_quit(GtkMenuItem *i, gpointer app)
{
    (void)i;
    editor_close_all_quit(G_APPLICATION(app));
}

/* Edit */
static void cb_undo(GtkMenuItem *i, gpointer d)    { (void)i;(void)d; editor_undo(); }
static void cb_redo(GtkMenuItem *i, gpointer d)    { (void)i;(void)d; editor_redo(); }
static void cb_cut(GtkMenuItem *i, gpointer d)     { (void)i;(void)d; editor_cut(); }
static void cb_copy(GtkMenuItem *i, gpointer d)    { (void)i;(void)d; editor_copy(); }
static void cb_paste(GtkMenuItem *i, gpointer d)   { (void)i;(void)d; editor_paste(); }
static void cb_selall(GtkMenuItem *i, gpointer d)  { (void)i;(void)d; editor_select_all(); }

/* Search */
static GtkWidget *s_main_window = NULL;

static void cb_find(GtkMenuItem *i, gpointer d)
{
    (void)i;(void)d;
    findreplace_set_sci(editor_current_doc()->sci);
    findreplace_show(s_main_window, NULL, FALSE);
}

static void cb_replace(GtkMenuItem *i, gpointer d)
{
    (void)i;(void)d;
    findreplace_set_sci(editor_current_doc()->sci);
    findreplace_show(s_main_window, NULL, TRUE);
}

static void cb_goto(GtkMenuItem *i, gpointer d)   { (void)i;(void)d; editor_goto_line_dialog(); }

/* Settings */
static void cb_style_editor(GtkMenuItem *i, gpointer d)
{
    (void)i; (void)d;
    styleeditor_show(s_main_window, editor_reapply_styles);
}

/* Edge column state — declared early so line-op callbacks can read it */
static gboolean s_edge_enabled = FALSE;
static int      s_edge_column  = 80;

/* ------------------------------------------------------------------ */
/* Show/hide symbols                                                  */
/* ------------------------------------------------------------------ */

static gboolean s_show_whitespace = FALSE;
static gboolean s_show_eol_marks  = FALSE;
static gboolean s_show_linenums   = TRUE;
static gboolean s_show_fold       = TRUE;
static gboolean s_show_bookmarks  = FALSE;

/* Apply current symbol visibility state to a single Scintilla widget. */
static void apply_view_symbols(GtkWidget *sci)
{
    if (!sci) return;
    scintilla_send_message(SCINTILLA(sci), SCI_SETVIEWWS,
        s_show_whitespace ? SC_WS_VISIBLEALWAYS : SC_WS_INVISIBLE, 0);
    scintilla_send_message(SCINTILLA(sci), SCI_SETVIEWEOL,
        s_show_eol_marks, 0);
    scintilla_send_message(SCINTILLA(sci), SCI_SETMARGINWIDTHN,
        0, s_show_linenums ? 44 : 0);
    scintilla_send_message(SCINTILLA(sci), SCI_SETMARGINWIDTHN,
        2, s_show_fold ? 14 : 0);
    scintilla_send_message(SCINTILLA(sci), SCI_SETMARGINWIDTHN,
        1, s_show_bookmarks ? 16 : 0);
}

/* Apply to every open tab. */
static void apply_view_symbols_all(void)
{
    int n = editor_page_count();
    for (int i = 0; i < n; i++) {
        NppDoc *doc = editor_doc_at(i);
        if (doc) apply_view_symbols(doc->sci);
    }
}

static void cb_toggle_whitespace(GtkCheckMenuItem *item, gpointer d)
{
    (void)d;
    s_show_whitespace = gtk_check_menu_item_get_active(item);
    apply_view_symbols_all();
}

static void cb_toggle_eol_marks(GtkCheckMenuItem *item, gpointer d)
{
    (void)d;
    s_show_eol_marks = gtk_check_menu_item_get_active(item);
    apply_view_symbols_all();
}

static void cb_toggle_linenums(GtkCheckMenuItem *item, gpointer d)
{
    (void)d;
    s_show_linenums = gtk_check_menu_item_get_active(item);
    apply_view_symbols_all();
}

static void cb_toggle_fold(GtkCheckMenuItem *item, gpointer d)
{
    (void)d;
    s_show_fold = gtk_check_menu_item_get_active(item);
    apply_view_symbols_all();
}

static void cb_toggle_bookmarks(GtkCheckMenuItem *item, gpointer d)
{
    (void)d;
    s_show_bookmarks = gtk_check_menu_item_get_active(item);
    apply_view_symbols_all();
}

/* ------------------------------------------------------------------ */
/* Line operations                                                    */
/* ------------------------------------------------------------------ */

static void cb_line_duplicate(GtkMenuItem *i, gpointer d)
{
    (void)i; (void)d;
    editor_send(SCI_LINEDUPLICATE, 0, 0);
}

static void cb_line_delete(GtkMenuItem *i, gpointer d)
{
    (void)i; (void)d;
    editor_send(SCI_LINEDELETE, 0, 0);
}

static void cb_line_move_up(GtkMenuItem *i, gpointer d)
{
    (void)i; (void)d;
    editor_send(SCI_MOVESELECTEDLINESUP, 0, 0);
}

static void cb_line_move_down(GtkMenuItem *i, gpointer d)
{
    (void)i; (void)d;
    editor_send(SCI_MOVESELECTEDLINESDOWN, 0, 0);
}

static void cb_join_lines(GtkMenuItem *i, gpointer d)
{
    (void)i; (void)d;
    NppDoc *doc = editor_current_doc();
    if (!doc) return;

    sptr_t sel_start = scintilla_send_message(SCINTILLA(doc->sci), SCI_GETSELECTIONSTART, 0, 0);
    sptr_t sel_end   = scintilla_send_message(SCINTILLA(doc->sci), SCI_GETSELECTIONEND,   0, 0);

    sptr_t rstart, rend;
    if (sel_start == sel_end) {
        int line  = (int)scintilla_send_message(SCINTILLA(doc->sci), SCI_LINEFROMPOSITION, sel_start, 0);
        int total = (int)scintilla_send_message(SCINTILLA(doc->sci), SCI_GETLINECOUNT, 0, 0);
        if (line + 1 >= total) return;
        rstart = scintilla_send_message(SCINTILLA(doc->sci), SCI_POSITIONFROMLINE, line, 0);
        rend   = scintilla_send_message(SCINTILLA(doc->sci), SCI_GETLINEENDPOSITION, line + 1, 0);
    } else {
        int ls = (int)scintilla_send_message(SCINTILLA(doc->sci), SCI_LINEFROMPOSITION, sel_start, 0);
        int le = (int)scintilla_send_message(SCINTILLA(doc->sci), SCI_LINEFROMPOSITION, sel_end,   0);
        rstart = scintilla_send_message(SCINTILLA(doc->sci), SCI_POSITIONFROMLINE, ls, 0);
        rend   = scintilla_send_message(SCINTILLA(doc->sci), SCI_GETLINEENDPOSITION, le, 0);
    }

    sptr_t len = rend - rstart;
    if (len <= 0) return;

    char *buf = g_malloc(len + 2);
    Sci_TextRangeFull tr = { { rstart, rend }, buf };
    scintilla_send_message(SCINTILLA(doc->sci), SCI_GETTEXTRANGEFULL, 0, (sptr_t)&tr);

    GString *out = g_string_sized_new(len);
    for (char *p = buf; *p; ) {
        if (*p == '\r' || *p == '\n') {
            while (out->len && out->str[out->len - 1] == ' ')
                g_string_truncate(out, out->len - 1);
            if (*p == '\r' && *(p + 1) == '\n') p++;
            p++;
            while (*p == ' ' || *p == '\t') p++;
            if (*p) g_string_append_c(out, ' ');
        } else {
            g_string_append_c(out, *p++);
        }
    }
    g_free(buf);

    scintilla_send_message(SCINTILLA(doc->sci), SCI_SETTARGETRANGE, (uptr_t)rstart, (sptr_t)rend);
    scintilla_send_message(SCINTILLA(doc->sci), SCI_REPLACETARGET, (uptr_t)out->len, (sptr_t)out->str);
    g_string_free(out, TRUE);
}

static void cb_split_lines(GtkMenuItem *i, gpointer d)
{
    (void)i; (void)d;
    NppDoc *doc = editor_current_doc();
    if (!doc) return;

    int col = s_edge_column > 0 ? s_edge_column : 80;
    int eol_mode = (int)scintilla_send_message(SCINTILLA(doc->sci), SCI_GETEOLMODE, 0, 0);
    const char *eol = eol_mode == SC_EOL_CRLF ? "\r\n" : eol_mode == SC_EOL_CR ? "\r" : "\n";

    sptr_t sel_start = scintilla_send_message(SCINTILLA(doc->sci), SCI_GETSELECTIONSTART, 0, 0);
    sptr_t sel_end   = scintilla_send_message(SCINTILLA(doc->sci), SCI_GETSELECTIONEND,   0, 0);

    sptr_t rstart, rend;
    if (sel_start == sel_end) {
        int line = (int)scintilla_send_message(SCINTILLA(doc->sci), SCI_LINEFROMPOSITION, sel_start, 0);
        rstart = scintilla_send_message(SCINTILLA(doc->sci), SCI_POSITIONFROMLINE, line, 0);
        rend   = scintilla_send_message(SCINTILLA(doc->sci), SCI_GETLINEENDPOSITION, line, 0);
    } else {
        int ls = (int)scintilla_send_message(SCINTILLA(doc->sci), SCI_LINEFROMPOSITION, sel_start, 0);
        int le = (int)scintilla_send_message(SCINTILLA(doc->sci), SCI_LINEFROMPOSITION, sel_end,   0);
        rstart = scintilla_send_message(SCINTILLA(doc->sci), SCI_POSITIONFROMLINE, ls, 0);
        rend   = scintilla_send_message(SCINTILLA(doc->sci), SCI_GETLINEENDPOSITION, le, 0);
    }

    sptr_t len = rend - rstart;
    if (len <= 0) return;

    char *buf = g_malloc(len + 2);
    Sci_TextRangeFull tr = { { rstart, rend }, buf };
    scintilla_send_message(SCINTILLA(doc->sci), SCI_GETTEXTRANGEFULL, 0, (sptr_t)&tr);

    size_t eol_len = strlen(eol);
    GString *out = g_string_sized_new(len + 16);
    char *p = buf;
    while (*p) {
        char *nl = strpbrk(p, "\r\n");
        size_t line_len = nl ? (size_t)(nl - p) : strlen(p);
        size_t pos = 0;
        while (pos + (size_t)col < line_len) {
            int brk = -1;
            for (int j = col; j >= 0; j--) {
                if (p[pos + j] == ' ') { brk = j; break; }
            }
            if (brk < 0) brk = col;
            g_string_append_len(out, p + pos, brk);
            g_string_append_len(out, eol, eol_len);
            pos += brk;
            if (p[pos] == ' ') pos++;
        }
        g_string_append_len(out, p + pos, line_len - pos);
        if (nl) {
            if (*nl == '\r' && *(nl + 1) == '\n') nl++;
            p = nl + 1;
            g_string_append_len(out, eol, eol_len);
        } else {
            break;
        }
    }
    g_free(buf);

    scintilla_send_message(SCINTILLA(doc->sci), SCI_SETTARGETRANGE, (uptr_t)rstart, (sptr_t)rend);
    scintilla_send_message(SCINTILLA(doc->sci), SCI_REPLACETARGET, (uptr_t)out->len, (sptr_t)out->str);
    g_string_free(out, TRUE);
}

static void cb_line_insert_above(GtkMenuItem *i, gpointer d)
{
    (void)i; (void)d;
    editor_send(SCI_HOME,    0, 0);
    editor_send(SCI_NEWLINE, 0, 0);
    editor_send(SCI_LINEUP,  0, 0);
}

static void cb_line_insert_below(GtkMenuItem *i, gpointer d)
{
    (void)i; (void)d;
    editor_send(SCI_LINEEND, 0, 0);
    editor_send(SCI_NEWLINE, 0, 0);
}

/* ------------------------------------------------------------------ */
/* Trim whitespace                                                    */
/* ------------------------------------------------------------------ */

typedef enum { TRIM_TRAILING, TRIM_LEADING, TRIM_BOTH } TrimMode;

static void do_trim(TrimMode mode)
{
    NppDoc *doc = editor_current_doc();
    if (!doc) return;

    sptr_t sel_start = scintilla_send_message(SCINTILLA(doc->sci), SCI_GETSELECTIONSTART, 0, 0);
    sptr_t sel_end   = scintilla_send_message(SCINTILLA(doc->sci), SCI_GETSELECTIONEND,   0, 0);

    sptr_t rstart, rend;
    if (sel_start == sel_end) {
        rstart = 0;
        rend   = scintilla_send_message(SCINTILLA(doc->sci), SCI_GETLENGTH, 0, 0);
    } else {
        int ls = (int)scintilla_send_message(SCINTILLA(doc->sci), SCI_LINEFROMPOSITION, sel_start, 0);
        int le = (int)scintilla_send_message(SCINTILLA(doc->sci), SCI_LINEFROMPOSITION, sel_end,   0);
        rstart = scintilla_send_message(SCINTILLA(doc->sci), SCI_POSITIONFROMLINE, ls, 0);
        rend   = scintilla_send_message(SCINTILLA(doc->sci), SCI_GETLINEENDPOSITION, le, 0);
    }

    sptr_t len = rend - rstart;
    if (len <= 0) return;

    char *buf = g_malloc(len + 2);
    Sci_TextRangeFull tr = { { rstart, rend }, buf };
    scintilla_send_message(SCINTILLA(doc->sci), SCI_GETTEXTRANGEFULL, 0, (sptr_t)&tr);

    GString *out = g_string_sized_new(len);
    char *p = buf;
    while (*p) {
        char *nl = strpbrk(p, "\r\n");
        size_t line_len = nl ? (size_t)(nl - p) : strlen(p);

        size_t ts = 0, te = line_len;
        if (mode == TRIM_LEADING || mode == TRIM_BOTH)
            while (ts < te && (p[ts] == ' ' || p[ts] == '\t')) ts++;
        if (mode == TRIM_TRAILING || mode == TRIM_BOTH)
            while (te > ts && (p[te - 1] == ' ' || p[te - 1] == '\t')) te--;

        g_string_append_len(out, p + ts, te - ts);

        if (nl) {
            if (*nl == '\r' && *(nl + 1) == '\n') { g_string_append_len(out, "\r\n", 2); p = nl + 2; }
            else                                   { g_string_append_c(out, *nl);         p = nl + 1; }
        } else {
            break;
        }
    }
    g_free(buf);

    scintilla_send_message(SCINTILLA(doc->sci), SCI_SETTARGETRANGE, (uptr_t)rstart, (sptr_t)rend);
    scintilla_send_message(SCINTILLA(doc->sci), SCI_REPLACETARGET, (uptr_t)out->len, (sptr_t)out->str);
    g_string_free(out, TRUE);
}

static void cb_trim_trailing(GtkMenuItem *i, gpointer d) { (void)i; (void)d; do_trim(TRIM_TRAILING); }
static void cb_trim_leading (GtkMenuItem *i, gpointer d) { (void)i; (void)d; do_trim(TRIM_LEADING);  }
static void cb_trim_both    (GtkMenuItem *i, gpointer d) { (void)i; (void)d; do_trim(TRIM_BOTH);     }

/* ------------------------------------------------------------------ */
/* Insert date/time                                                   */
/* ------------------------------------------------------------------ */

static void insert_datetime(const char *fmt)
{
    NppDoc *doc = editor_current_doc();
    if (!doc) return;
    GDateTime *dt = g_date_time_new_now_local();
    gchar *str = g_date_time_format(dt, fmt);
    g_date_time_unref(dt);
    if (str) {
        scintilla_send_message(SCINTILLA(doc->sci), SCI_REPLACESEL, 0, (sptr_t)str);
        g_free(str);
    }
}

static void cb_insert_date_short(GtkMenuItem *i, gpointer d)
{
    (void)i; (void)d;
    insert_datetime("%H:%M:%S %m/%d/%Y");
}

static void cb_insert_date_long(GtkMenuItem *i, gpointer d)
{
    (void)i; (void)d;
    insert_datetime("%A, %B %d, %Y %H:%M:%S");
}

/* ------------------------------------------------------------------ */
/* Hash tools                                                         */
/* ------------------------------------------------------------------ */

static void cb_hash_generator(GtkMenuItem *item, gpointer d)
{
    (void)item; (void)d;
    NppDoc *doc = editor_current_doc();
    if (!doc) return;

    sptr_t sel_start = scintilla_send_message(SCINTILLA(doc->sci), SCI_GETSELECTIONSTART, 0, 0);
    sptr_t sel_end   = scintilla_send_message(SCINTILLA(doc->sci), SCI_GETSELECTIONEND,   0, 0);
    gboolean has_sel = sel_start != sel_end;

    sptr_t rstart = has_sel ? sel_start : 0;
    sptr_t rend   = has_sel ? sel_end
                            : scintilla_send_message(SCINTILLA(doc->sci), SCI_GETLENGTH, 0, 0);
    sptr_t len = rend - rstart;
    if (len <= 0) return;

    char *buf = g_malloc(len + 1);
    Sci_TextRangeFull tr = { { rstart, rend }, buf };
    scintilla_send_message(SCINTILLA(doc->sci), SCI_GETTEXTRANGEFULL, 0, (sptr_t)&tr);

    static const struct { GChecksumType type; const char *name; } algos[] = {
        { G_CHECKSUM_MD5,    "MD5"     },
        { G_CHECKSUM_SHA1,   "SHA-1"   },
        { G_CHECKSUM_SHA256, "SHA-256" },
        { G_CHECKSUM_SHA512, "SHA-512" },
    };

    GtkWidget *dlg = gtk_dialog_new_with_buttons(
        TM("dlg.hash.title", "Hash Generator"),
        GTK_WINDOW(s_main_window),
        GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT,
        TM("dlg.Find.2", "_Close"), GTK_RESPONSE_CLOSE,
        NULL);

    GtkWidget *grid = gtk_grid_new();
    gtk_grid_set_row_spacing(GTK_GRID(grid), 6);
    gtk_grid_set_column_spacing(GTK_GRID(grid), 8);
    gtk_widget_set_margin_start(grid, 12);
    gtk_widget_set_margin_end(grid, 12);
    gtk_widget_set_margin_top(grid, 8);
    gtk_widget_set_margin_bottom(grid, 8);

    /* Source info label */
    char info[64];
    snprintf(info, sizeof(info),
             has_sel ? "Selection (%ld bytes)" : "Document (%ld bytes)", (long)len);
    GtkWidget *info_lbl = gtk_label_new(info);
    gtk_widget_set_halign(info_lbl, GTK_ALIGN_START);
    gtk_grid_attach(GTK_GRID(grid), info_lbl, 0, 0, 2, 1);

    for (int i = 0; i < 4; i++) {
        gchar *hash = g_compute_checksum_for_data(algos[i].type,
                                                  (const guchar *)buf, (gsize)len);
        GtkWidget *lbl = gtk_label_new(algos[i].name);
        gtk_widget_set_halign(lbl, GTK_ALIGN_START);

        GtkWidget *entry = gtk_entry_new();
        gtk_entry_set_text(GTK_ENTRY(entry), hash);
        gtk_editable_set_editable(GTK_EDITABLE(entry), FALSE);
        gtk_entry_set_width_chars(GTK_ENTRY(entry), 64);

        gtk_grid_attach(GTK_GRID(grid), lbl,   0, i + 1, 1, 1);
        gtk_grid_attach(GTK_GRID(grid), entry, 1, i + 1, 1, 1);
        g_free(hash);
    }
    g_free(buf);

    GtkWidget *ca = gtk_dialog_get_content_area(GTK_DIALOG(dlg));
    gtk_box_pack_start(GTK_BOX(ca), grid, FALSE, FALSE, 0);
    gtk_widget_show_all(dlg);
    gtk_dialog_run(GTK_DIALOG(dlg));
    gtk_widget_destroy(dlg);
}

/* Edge column                                                        */
/* ------------------------------------------------------------------ */

static void apply_edge(GtkWidget *sci)
{
    if (!sci) return;
    scintilla_send_message(SCINTILLA(sci), SCI_SETEDGEMODE,
        s_edge_enabled ? SC_EDGE_LINE : SC_EDGE_NONE, 0);
    scintilla_send_message(SCINTILLA(sci), SCI_SETEDGECOLUMN,
        (uptr_t)s_edge_column, 0);
}

static void apply_edge_all(void)
{
    int n = editor_page_count();
    for (int i = 0; i < n; i++) {
        NppDoc *doc = editor_doc_at(i);
        if (doc) apply_edge(doc->sci);
    }
}

static void cb_toggle_edge(GtkCheckMenuItem *item, gpointer d)
{
    (void)d;
    s_edge_enabled = gtk_check_menu_item_get_active(item);
    apply_edge_all();
}

static void cb_set_edge_column(GtkMenuItem *item, gpointer d)
{
    (void)item; (void)d;
    GtkWidget *dlg = gtk_dialog_new_with_buttons(
        TM("dlg.edgecol.title", "Set Edge Column"),
        GTK_WINDOW(s_main_window),
        GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT,
        TM("dlg.Find.2", "_Close"),  GTK_RESPONSE_CANCEL,
        TM("cmd.41006",  "_OK"),     GTK_RESPONSE_ACCEPT,
        NULL);

    GtkWidget *spin = gtk_spin_button_new_with_range(1, 512, 1);
    gtk_spin_button_set_value(GTK_SPIN_BUTTON(spin), s_edge_column);

    GtkWidget *lbl = gtk_label_new(TM("dlg.edgecol.label", "Column:"));
    GtkWidget *hbox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    gtk_widget_set_margin_start(hbox, 12);
    gtk_widget_set_margin_end(hbox, 12);
    gtk_widget_set_margin_top(hbox, 8);
    gtk_widget_set_margin_bottom(hbox, 8);
    gtk_box_pack_start(GTK_BOX(hbox), lbl,  FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hbox), spin, FALSE, FALSE, 0);

    GtkWidget *ca = gtk_dialog_get_content_area(GTK_DIALOG(dlg));
    gtk_box_pack_start(GTK_BOX(ca), hbox, FALSE, FALSE, 0);
    gtk_widget_show_all(dlg);

    if (gtk_dialog_run(GTK_DIALOG(dlg)) == GTK_RESPONSE_ACCEPT) {
        s_edge_column = (int)gtk_spin_button_get_value(GTK_SPIN_BUTTON(spin));
        if (s_edge_enabled) apply_edge_all();
    }
    gtk_widget_destroy(dlg);
}

/* ------------------------------------------------------------------ */
/* EOL menu                                                           */
/* ------------------------------------------------------------------ */

/* Indexed by SC_EOL_CRLF=0, SC_EOL_CR=1, SC_EOL_LF=2 */
static GtkWidget *s_eol_items[3];

static void cb_eol_toggled(GtkCheckMenuItem *item, gpointer data)
{
    if (!gtk_check_menu_item_get_active(item)) return;
    int mode = GPOINTER_TO_INT(data);
    NppDoc *doc = editor_current_doc();
    if (!doc) return;
    scintilla_send_message(SCINTILLA(doc->sci), SCI_SETEOLMODE, (uptr_t)mode, 0);
    scintilla_send_message(SCINTILLA(doc->sci), SCI_CONVERTEOLS, (uptr_t)mode, 0);
    statusbar_update_from_sci(doc->sci);
}

static void eol_menu_sync(int mode)
{
    if (mode < 0 || mode > 2) mode = SC_EOL_LF;
    GtkCheckMenuItem *item = GTK_CHECK_MENU_ITEM(s_eol_items[mode]);
    if (!item) return;
    g_signal_handlers_block_by_func(item, G_CALLBACK(cb_eol_toggled),
                                    GINT_TO_POINTER(mode));
    gtk_check_menu_item_set_active(item, TRUE);
    g_signal_handlers_unblock_by_func(item, G_CALLBACK(cb_eol_toggled),
                                      GINT_TO_POINTER(mode));
}

/* ------------------------------------------------------------------ */
/* Language menu                                                       */
/* ------------------------------------------------------------------ */

/* Maps lang key → GtkRadioMenuItem* for checkmark syncing. */
static GHashTable *s_lang_item_map = NULL;

/* Display names for menu labels (lang key → human label). */
typedef struct { const char *lang; const char *label; } LangLabel;
static const LangLabel kLangLabels[] = {
    /* C-family */
    {"c",           "C"},
    {"cpp",         "C++"},
    {"objc",        "Objective-C"},
    {"cs",          "C#"},
    {"java",        "Java"},
    {"javascript",  "JavaScript"},
    {"typescript",  "TypeScript"},
    {"swift",       "Swift"},
    {"rc",          "Resource file"},
    {"actionscript","ActionScript"},
    {"go",          "Go"},
    /* Web */
    {"html",        "HTML"},
    {"asp",         "ASP"},
    {"xml",         "XML"},
    {"css",         "CSS"},
    {"json",        "JSON"},
    {"php",         "PHP"},
    /* Scripting */
    {"python",      "Python"},
    {"ruby",        "Ruby"},
    {"perl",        "Perl"},
    {"lua",         "Lua"},
    {"bash",        "Shell"},
    {"powershell",  "PowerShell"},
    {"batch",       "Batch"},
    {"tcl",         "TCL"},
    {"r",           "R"},
    {"raku",        "Raku"},
    {"coffeescript","CoffeeScript"},
    /* Systems */
    {"rust",        "Rust"},
    {"d",           "D"},
    /* Markup / Config */
    {"markdown",    "Markdown"},
    {"latex",       "LaTeX"},
    {"tex",         "TeX"},
    {"yaml",        "YAML"},
    {"toml",        "TOML"},
    {"ini",         "INI"},
    {"props",       "Properties"},
    {"makefile",    "Makefile"},
    {"cmake",       "CMake"},
    {"diff",        "Diff"},
    {"registry",    "Registry"},
    {"nsis",        "NSIS"},
    {"inno",        "Inno Setup"},
    /* Database */
    {"sql",         "SQL"},
    {"mssql",       "MS-SQL"},
    /* Scientific */
    {"fortran",     "Fortran (free)"},
    {"fortran77",   "Fortran (fixed)"},
    {"pascal",      "Pascal"},
    {"haskell",     "Haskell"},
    {"caml",        "CAML"},
    {"lisp",        "Lisp"},
    {"scheme",      "Scheme"},
    {"erlang",      "Erlang"},
    {"nim",         "Nim"},
    {"gdscript",    "GDScript"},
    {"sas",         "SAS"},
    /* Hardware */
    {"vhdl",        "VHDL"},
    {"verilog",     "Verilog"},
    {"asm",         "Assembly"},
    /* Other */
    {"ada",         "Ada"},
    {"cobol",       "COBOL"},
    {"vb",          "Visual Basic"},
    {"autoit",      "AutoIt"},
    {"postscript",  "PostScript"},
    {"matlab",      "MATLAB"},
    {"smalltalk",   "Smalltalk"},
    {"forth",       "Forth"},
    {"oscript",     "OScript"},
    {"avs",         "AVS"},
    {"hollywood",   "Hollywood"},
    {"purebasic",   "PureBasic"},
    {"freebasic",   "FreeBasic"},
    {"blitzbasic",  "BlitzBasic"},
    {"kix",         "KiXtart"},
    {"visualprolog","Visual Prolog"},
    {"baanc",       "BaanC"},
    {"nncrontab",   "NNCronTab"},
    {"csound",      "CSound"},
    {"escript",     "EScript"},
    {"spice",       "Spice"},
    {NULL, NULL}
};

static const char *lang_label(const char *lang)
{
    for (const LangLabel *l = kLangLabels; l->lang; l++)
        if (strcmp(l->lang, lang) == 0) return l->label;
    return lang;
}

static void cb_lang_toggled(GtkCheckMenuItem *item, gpointer data)
{
    if (!gtk_check_menu_item_get_active(item)) return;
    const char *lang = (const char *)data;   /* "" = Normal Text */
    NppDoc *doc = editor_current_doc();
    if (!doc) return;
    lexer_apply(doc->sci, lang[0] ? lang : NULL);
    statusbar_set_language(lang[0] ? lang : NULL);
}

/* Update the checked radio item to match the current tab's language. */
static void lang_menu_sync(const char *lang)
{
    if (!s_lang_item_map) return;
    const char *key = (lang && lang[0]) ? lang : "";
    GtkCheckMenuItem *item = GTK_CHECK_MENU_ITEM(
        g_hash_table_lookup(s_lang_item_map, key));
    if (!item)   /* unknown language: fall back to Normal Text */
        item = GTK_CHECK_MENU_ITEM(g_hash_table_lookup(s_lang_item_map, ""));
    if (!item) return;
    g_signal_handlers_block_by_func(item, G_CALLBACK(cb_lang_toggled), (gpointer)key);
    gtk_check_menu_item_set_active(item, TRUE);
    g_signal_handlers_unblock_by_func(item, G_CALLBACK(cb_lang_toggled), (gpointer)key);
}

/* Add one radio item to a menu, register it in the map, advance the group. */
static void add_lang_item(GtkWidget *menu, GSList **group,
                          const char *lang_key, const char *label)
{
    GtkWidget *item = gtk_radio_menu_item_new_with_label(*group, label);
    *group = gtk_radio_menu_item_get_group(GTK_RADIO_MENU_ITEM(item));
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), item);
    g_signal_connect(item, "toggled", G_CALLBACK(cb_lang_toggled), (gpointer)lang_key);
    g_hash_table_insert(s_lang_item_map, (gpointer)lang_key, item);
}

/* Add a labelled submenu of language items to the Language menu. */
static void add_lang_group(GtkWidget *lang_menu, GSList **group,
                           const char *group_label,
                           const char * const *langs, int n)
{
    GtkWidget *sub_item = gtk_menu_item_new_with_label(group_label);
    GtkWidget *sub_menu = gtk_menu_new();
    gtk_menu_item_set_submenu(GTK_MENU_ITEM(sub_item), sub_menu);
    gtk_menu_shell_append(GTK_MENU_SHELL(lang_menu), sub_item);
    for (int i = 0; i < n; i++)
        add_lang_item(sub_menu, group, langs[i], lang_label(langs[i]));
}

static GtkWidget *build_language_menu(GtkWidget *bar)
{
    s_lang_item_map = g_hash_table_new(g_str_hash, g_str_equal);
    GSList *group = NULL;

    GtkWidget *top_item = gtk_menu_item_new_with_mnemonic(T("menu.language", "_Language"));
    GtkWidget *menu = gtk_menu_new();
    gtk_menu_item_set_submenu(GTK_MENU_ITEM(top_item), menu);
    gtk_menu_shell_append(GTK_MENU_SHELL(bar), top_item);

    /* Normal Text at the top */
    add_lang_item(menu, &group, "", "Normal Text");
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), gtk_separator_menu_item_new());

    /* Language groups */
    static const char * const c_family[] = {
        "c","cpp","objc","cs","java","javascript","typescript",
        "swift","rc","actionscript","go"
    };
    static const char * const web[] = { "html","asp","xml","css","json","php" };
    static const char * const scripting[] = {
        "python","ruby","perl","lua","bash","powershell",
        "batch","tcl","r","raku","coffeescript"
    };
    static const char * const systems[] = { "rust","d" };
    static const char * const markup[] = {
        "markdown","latex","tex","yaml","toml","ini","props",
        "makefile","cmake","diff","registry","nsis","inno"
    };
    static const char * const database[] = { "sql","mssql" };
    static const char * const scientific[] = {
        "fortran","fortran77","pascal","haskell","caml","lisp",
        "scheme","erlang","nim","gdscript","sas"
    };
    static const char * const hardware[] = { "vhdl","verilog","asm" };
    static const char * const other[] = {
        "ada","cobol","vb","autoit","postscript","matlab","smalltalk",
        "forth","oscript","avs","hollywood","purebasic","freebasic",
        "blitzbasic","kix","visualprolog","baanc","nncrontab",
        "csound","escript","spice"
    };

#define NELEM(a) (int)(sizeof(a)/sizeof(a[0]))
    add_lang_group(menu, &group, "C, C++, C#, Java",  c_family,  NELEM(c_family));
    add_lang_group(menu, &group, "Web",                web,       NELEM(web));
    add_lang_group(menu, &group, "Scripting",          scripting, NELEM(scripting));
    add_lang_group(menu, &group, "Systems",            systems,   NELEM(systems));
    add_lang_group(menu, &group, "Markup / Config",    markup,    NELEM(markup));
    add_lang_group(menu, &group, "Database",           database,  NELEM(database));
    add_lang_group(menu, &group, "Scientific",         scientific,NELEM(scientific));
    add_lang_group(menu, &group, "Hardware",           hardware,  NELEM(hardware));
    add_lang_group(menu, &group, "Other",              other,     NELEM(other));
#undef NELEM

    return menu;
}

/* ------------------------------------------------------------------ */
/* Menu builder helpers                                               */
/* ------------------------------------------------------------------ */

static GtkWidget *menu_item(const char *label, GCallback cb, gpointer data,
                             GtkAccelGroup *accel, guint key, GdkModifierType mod)
{
    GtkWidget *item = gtk_menu_item_new_with_mnemonic(label);
    if (cb)
        g_signal_connect(item, "activate", cb, data);
    if (key && accel)
        gtk_widget_add_accelerator(item, "activate", accel, key, mod,
                                   GTK_ACCEL_VISIBLE);
    return item;
}

static GtkWidget *sep_item(void)
{
    return gtk_separator_menu_item_new();
}

static GtkWidget *submenu(GtkWidget *bar, const char *label)
{
    GtkWidget *item = gtk_menu_item_new_with_mnemonic(label);
    GtkWidget *menu = gtk_menu_new();
    gtk_menu_item_set_submenu(GTK_MENU_ITEM(item), menu);
    gtk_menu_shell_append(GTK_MENU_SHELL(bar), item);
    return menu;
}

#define APPEND(menu, item) gtk_menu_shell_append(GTK_MENU_SHELL(menu), item)

static GtkWidget *build_menubar(GtkWindow *window, GApplication *app)
{
    GtkAccelGroup *accel = gtk_accel_group_new();
    gtk_window_add_accel_group(window, accel);

    GtkWidget *bar = gtk_menu_bar_new();

    /* ---- File ---- */
    GtkWidget *file = submenu(bar, TM("menu.file", "_File"));
    APPEND(file, menu_item(TM("cmd.41001", "_New"),        G_CALLBACK(cb_new),    NULL, accel, GDK_KEY_n, GDK_CONTROL_MASK));
    APPEND(file, menu_item(TM("cmd.41002", "_Open…"),      G_CALLBACK(cb_open),   NULL, accel, GDK_KEY_o, GDK_CONTROL_MASK));
    APPEND(file, sep_item());
    APPEND(file, menu_item(TM("cmd.41006", "_Save"),       G_CALLBACK(cb_save),   NULL, accel, GDK_KEY_s, GDK_CONTROL_MASK));
    APPEND(file, menu_item(TM("cmd.41008", "Save _As…"),   G_CALLBACK(cb_save_as),NULL, accel, GDK_KEY_s, GDK_CONTROL_MASK | GDK_SHIFT_MASK));
    APPEND(file, sep_item());
    APPEND(file, menu_item(TM("cmd.41003", "_Close"),      G_CALLBACK(cb_close),  NULL, accel, GDK_KEY_w, GDK_CONTROL_MASK));
    APPEND(file, sep_item());
    APPEND(file, menu_item(TM("cmd.41011", "_Quit"),       G_CALLBACK(cb_quit),   app,  accel, GDK_KEY_q, GDK_CONTROL_MASK));

    /* ---- Edit ---- */
    GtkWidget *edit = submenu(bar, TM("menu.edit", "_Edit"));
    APPEND(edit, menu_item(TM("cmd.42003", "_Undo"),       G_CALLBACK(cb_undo),   NULL, accel, GDK_KEY_z, GDK_CONTROL_MASK));
    APPEND(edit, menu_item(TM("cmd.42004", "_Redo"),       G_CALLBACK(cb_redo),   NULL, accel, GDK_KEY_z, GDK_CONTROL_MASK | GDK_SHIFT_MASK));
    APPEND(edit, sep_item());
    APPEND(edit, menu_item(TM("cmd.42001", "Cu_t"),        G_CALLBACK(cb_cut),    NULL, accel, GDK_KEY_x, GDK_CONTROL_MASK));
    APPEND(edit, menu_item(TM("cmd.42002", "_Copy"),       G_CALLBACK(cb_copy),   NULL, accel, GDK_KEY_c, GDK_CONTROL_MASK));
    APPEND(edit, menu_item(TM("cmd.42005", "_Paste"),      G_CALLBACK(cb_paste),  NULL, accel, GDK_KEY_v, GDK_CONTROL_MASK));
    APPEND(edit, sep_item());
    APPEND(edit, menu_item(TM("cmd.42007", "Select _All"), G_CALLBACK(cb_selall), NULL, accel, GDK_KEY_a, GDK_CONTROL_MASK));
    APPEND(edit, sep_item());

    /* EOL Conversion submenu */
    {
        GtkWidget *eol_sub_item = gtk_menu_item_new_with_mnemonic(TM("menu.eolformat", "EOL Con_version"));
        GtkWidget *eol_menu = gtk_menu_new();
        gtk_menu_item_set_submenu(GTK_MENU_ITEM(eol_sub_item), eol_menu);

        GSList *eol_group = NULL;
        s_eol_items[SC_EOL_CRLF] = gtk_radio_menu_item_new_with_mnemonic(eol_group,
            TM("menu.windows", "_Windows (CR+LF)"));
        eol_group = gtk_radio_menu_item_get_group(GTK_RADIO_MENU_ITEM(s_eol_items[SC_EOL_CRLF]));
        s_eol_items[SC_EOL_LF] = gtk_radio_menu_item_new_with_mnemonic(eol_group,
            TM("menu.unix", "_Unix (LF)"));
        eol_group = gtk_radio_menu_item_get_group(GTK_RADIO_MENU_ITEM(s_eol_items[SC_EOL_LF]));
        s_eol_items[SC_EOL_CR] = gtk_radio_menu_item_new_with_mnemonic(eol_group,
            TM("menu.oldmac", "Old _Mac (CR)"));

        g_signal_connect(s_eol_items[SC_EOL_CRLF], "toggled",
                         G_CALLBACK(cb_eol_toggled), GINT_TO_POINTER(SC_EOL_CRLF));
        g_signal_connect(s_eol_items[SC_EOL_LF], "toggled",
                         G_CALLBACK(cb_eol_toggled), GINT_TO_POINTER(SC_EOL_LF));
        g_signal_connect(s_eol_items[SC_EOL_CR], "toggled",
                         G_CALLBACK(cb_eol_toggled), GINT_TO_POINTER(SC_EOL_CR));

        APPEND(eol_menu, s_eol_items[SC_EOL_CRLF]);
        APPEND(eol_menu, s_eol_items[SC_EOL_LF]);
        APPEND(eol_menu, s_eol_items[SC_EOL_CR]);
        APPEND(edit, eol_sub_item);
    }

    /* Insert Date/Time submenu */
    {
        GtkWidget *dt_item = gtk_menu_item_new_with_mnemonic(TM("menu.datetime", "Insert _Date/Time"));
        GtkWidget *dt_menu = gtk_menu_new();
        gtk_menu_item_set_submenu(GTK_MENU_ITEM(dt_item), dt_menu);
        APPEND(dt_menu, menu_item(TM("menu.datetime.short", "_Short (HH:MM:SS MM/DD/YYYY)"),
                                  G_CALLBACK(cb_insert_date_short), NULL, NULL, 0, 0));
        APPEND(dt_menu, menu_item(TM("menu.datetime.long",  "_Long (Weekday, Month DD, YYYY HH:MM:SS)"),
                                  G_CALLBACK(cb_insert_date_long),  NULL, NULL, 0, 0));
        APPEND(edit, dt_item);
    }

    /* Line operations submenu */
    {
        GtkWidget *line_item = gtk_menu_item_new_with_mnemonic(TM("menu.line", "_Line Operations"));
        GtkWidget *line_menu = gtk_menu_new();
        gtk_menu_item_set_submenu(GTK_MENU_ITEM(line_item), line_menu);
        APPEND(line_menu, menu_item(TM("menu.line.duplicate", "_Duplicate Line"),
                                    G_CALLBACK(cb_line_duplicate), NULL, accel,
                                    GDK_KEY_d, GDK_CONTROL_MASK));
        APPEND(line_menu, menu_item(TM("menu.line.delete", "D_elete Line"),
                                    G_CALLBACK(cb_line_delete), NULL, accel,
                                    GDK_KEY_l, GDK_CONTROL_MASK | GDK_SHIFT_MASK));
        APPEND(line_menu, sep_item());
        APPEND(line_menu, menu_item(TM("menu.line.moveup", "Move Line _Up"),
                                    G_CALLBACK(cb_line_move_up), NULL, accel,
                                    GDK_KEY_Up, GDK_CONTROL_MASK | GDK_SHIFT_MASK));
        APPEND(line_menu, menu_item(TM("menu.line.movedown", "Move Line _Down"),
                                    G_CALLBACK(cb_line_move_down), NULL, accel,
                                    GDK_KEY_Down, GDK_CONTROL_MASK | GDK_SHIFT_MASK));
        APPEND(line_menu, sep_item());
        APPEND(line_menu, menu_item(TM("menu.line.join",  "_Join Lines"),
                                    G_CALLBACK(cb_join_lines),  NULL, NULL, 0, 0));
        APPEND(line_menu, menu_item(TM("menu.line.split", "S_plit Lines"),
                                    G_CALLBACK(cb_split_lines), NULL, NULL, 0, 0));
        APPEND(line_menu, sep_item());
        APPEND(line_menu, menu_item(TM("menu.line.insabove", "Insert Blank Line A_bove"),
                                    G_CALLBACK(cb_line_insert_above), NULL, accel,
                                    GDK_KEY_Return, GDK_CONTROL_MASK | GDK_MOD1_MASK));
        APPEND(line_menu, menu_item(TM("menu.line.insbelow", "Insert Blank Line Belo_w"),
                                    G_CALLBACK(cb_line_insert_below), NULL, accel,
                                    GDK_KEY_Return, GDK_CONTROL_MASK | GDK_SHIFT_MASK));
        APPEND(edit, line_item);
    }

    /* Blank Operations submenu */
    {
        GtkWidget *blank_item = gtk_menu_item_new_with_mnemonic(TM("menu.blank", "_Blank Operations"));
        GtkWidget *blank_menu = gtk_menu_new();
        gtk_menu_item_set_submenu(GTK_MENU_ITEM(blank_item), blank_menu);
        APPEND(blank_menu, menu_item(TM("menu.blank.trimtrail", "Trim _Trailing Whitespace"),
                                     G_CALLBACK(cb_trim_trailing), NULL, NULL, 0, 0));
        APPEND(blank_menu, menu_item(TM("menu.blank.trimlead",  "Trim _Leading Whitespace"),
                                     G_CALLBACK(cb_trim_leading),  NULL, NULL, 0, 0));
        APPEND(blank_menu, menu_item(TM("menu.blank.trimboth",  "Trim _Both"),
                                     G_CALLBACK(cb_trim_both),     NULL, NULL, 0, 0));
        APPEND(edit, blank_item);
    }

    /* ---- Search ---- */
    GtkWidget *search = submenu(bar, TM("menu.search", "_Search"));
    APPEND(search, menu_item(TM("cmd.43001", "_Find…"),       G_CALLBACK(cb_find),    NULL, accel, GDK_KEY_f, GDK_CONTROL_MASK));
    APPEND(search, menu_item(TM("cmd.43003", "_Replace…"),    G_CALLBACK(cb_replace), NULL, accel, GDK_KEY_h, GDK_CONTROL_MASK));
    APPEND(search, sep_item());
    APPEND(search, menu_item(TM("cmd.43004", "_Go To Line…"), G_CALLBACK(cb_goto),    NULL, accel, GDK_KEY_g, GDK_CONTROL_MASK));

    /* ---- View ---- */
    {
        GtkWidget *view = submenu(bar, TM("menu.view", "_View"));

        GtkWidget *ws = gtk_check_menu_item_new_with_mnemonic(
            TM("menu.view.whitespace", "Show _Whitespace"));
        gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(ws), s_show_whitespace);
        g_signal_connect(ws, "toggled", G_CALLBACK(cb_toggle_whitespace), NULL);
        APPEND(view, ws);

        GtkWidget *eolm = gtk_check_menu_item_new_with_mnemonic(
            TM("menu.view.eol", "Show _EOL Markers"));
        gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(eolm), s_show_eol_marks);
        g_signal_connect(eolm, "toggled", G_CALLBACK(cb_toggle_eol_marks), NULL);
        APPEND(view, eolm);

        APPEND(view, sep_item());

        GtkWidget *ln = gtk_check_menu_item_new_with_mnemonic(
            TM("menu.view.linenums", "Show _Line Numbers"));
        gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(ln), s_show_linenums);
        g_signal_connect(ln, "toggled", G_CALLBACK(cb_toggle_linenums), NULL);
        APPEND(view, ln);

        GtkWidget *fm = gtk_check_menu_item_new_with_mnemonic(
            TM("menu.view.fold", "Show _Fold Margin"));
        gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(fm), s_show_fold);
        g_signal_connect(fm, "toggled", G_CALLBACK(cb_toggle_fold), NULL);
        APPEND(view, fm);

        GtkWidget *bm = gtk_check_menu_item_new_with_mnemonic(
            TM("menu.view.bookmarks", "Show _Bookmarks Margin"));
        gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(bm), s_show_bookmarks);
        g_signal_connect(bm, "toggled", G_CALLBACK(cb_toggle_bookmarks), NULL);
        APPEND(view, bm);

        APPEND(view, sep_item());

        GtkWidget *edge = gtk_check_menu_item_new_with_mnemonic(
            TM("menu.view.edge", "Show _Edge Column"));
        gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(edge), s_edge_enabled);
        g_signal_connect(edge, "toggled", G_CALLBACK(cb_toggle_edge), NULL);
        APPEND(view, edge);

        APPEND(view, menu_item(TM("menu.view.setedge", "Set Edge Column…"),
                               G_CALLBACK(cb_set_edge_column), NULL, NULL, 0, 0));
    }

    /* ---- Language ---- */
    build_language_menu(bar);

    /* ---- Settings ---- */
    GtkWidget *settings = submenu(bar, TM("menu.settings", "Se_ttings"));
    APPEND(settings, menu_item(TM("cmd.46001", "_Style Configurator…"),
                               G_CALLBACK(cb_style_editor), NULL, accel, 0, 0));

    /* ---- Tools ---- */
    GtkWidget *tools = submenu(bar, TM("menu.tools", "_Tools"));
    APPEND(tools, menu_item(TM("menu.tools.hash", "_Hash Generator…"),
                            G_CALLBACK(cb_hash_generator), NULL, accel, 0, 0));

    return bar;
}

/* ------------------------------------------------------------------ */
/* Tab switch                                                         */
/* ------------------------------------------------------------------ */

static void on_switch_page(GtkNotebook *nb, GtkWidget *page,
                           guint n, gpointer d)
{
    (void)nb; (void)page; (void)n; (void)d;
    NppDoc *doc = editor_current_doc();
    if (!doc) return;
    statusbar_update_from_sci(doc->sci);
    const char *lang = (const char *)g_object_get_data(G_OBJECT(doc->sci), "npp-lang");
    lang_menu_sync(lang);
    int eol = (int)scintilla_send_message(SCINTILLA(doc->sci), SCI_GETEOLMODE, 0, 0);
    eol_menu_sync(eol);
    apply_view_symbols(doc->sci);
    apply_edge(doc->sci);
}

/* ------------------------------------------------------------------ */
/* Insert key — toggle overtype mode                                  */
/* ------------------------------------------------------------------ */

static gboolean on_key_press(GtkWidget *w, GdkEventKey *ev, gpointer d)
{
    (void)w; (void)d;
    if (ev->keyval != GDK_KEY_Insert) return FALSE;
    NppDoc *doc = editor_current_doc();
    if (!doc) return FALSE;
    gboolean ovr = (gboolean)scintilla_send_message(
        SCINTILLA(doc->sci), SCI_GETOVERTYPE, 0, 0);
    scintilla_send_message(SCINTILLA(doc->sci), SCI_SETOVERTYPE, !ovr, 0);
    statusbar_set_overtype(!ovr);
    return TRUE;  /* consumed — prevents Scintilla from double-toggling */
}

/* ------------------------------------------------------------------ */
/* Delete-event (window X button)                                     */
/* ------------------------------------------------------------------ */

static gboolean on_delete_event(GtkWidget *w, GdkEvent *e, gpointer app)
{
    (void)w; (void)e;
    editor_close_all_quit(G_APPLICATION(app));
    return TRUE; /* prevent default destroy; quit handles it */
}

/* ------------------------------------------------------------------ */
/* Application activate                                               */
/* ------------------------------------------------------------------ */

static void on_activate(GtkApplication *app, gpointer data)
{
    (void)data;

    i18n_init();

    GtkWidget *window = gtk_application_window_new(app);
    s_main_window = window;
    gtk_window_set_title(GTK_WINDOW(window), "Notepad++ Linux");
    gtk_window_set_default_size(GTK_WINDOW(window), 1024, 700);
    g_signal_connect(window, "delete-event",   G_CALLBACK(on_delete_event), app);
    g_signal_connect(window, "key-press-event", G_CALLBACK(on_key_press),   NULL);

    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_container_add(GTK_CONTAINER(window), vbox);

    /* Menu bar */
    GtkWidget *menubar = build_menubar(GTK_WINDOW(window), G_APPLICATION(app));
    gtk_box_pack_start(GTK_BOX(vbox), menubar, FALSE, FALSE, 0);

    /* Toolbar */
    GtkWidget *toolbar = toolbar_init(window);
    gtk_box_pack_start(GTK_BOX(vbox), toolbar, FALSE, FALSE, 0);

    /* Editor (notebook) */
    GtkWidget *notebook = editor_init(window);
    g_signal_connect(notebook, "switch-page", G_CALLBACK(on_switch_page), NULL);
    gtk_box_pack_start(GTK_BOX(vbox), notebook, TRUE, TRUE, 0);

    /* Status bar */
    GtkWidget *statusbar = statusbar_init();
    gtk_box_pack_start(GTK_BOX(vbox), statusbar, FALSE, FALSE, 0);

    /* Open files passed on the command line */
    const gchar **args = g_application_get_dbus_object_path(G_APPLICATION(app))
        ? NULL : NULL;
    (void)args; /* CLI args handled below in main() via editor_open_path */

    gtk_widget_show_all(window);
    NppDoc *initial = editor_current_doc();
    statusbar_update_from_sci(initial->sci);
    lang_menu_sync((const char *)g_object_get_data(G_OBJECT(initial->sci), "npp-lang"));
    eol_menu_sync((int)scintilla_send_message(SCINTILLA(initial->sci), SCI_GETEOLMODE, 0, 0));
    apply_view_symbols(initial->sci);
    apply_edge(initial->sci);
}

/* ------------------------------------------------------------------ */
/* main                                                               */
/* ------------------------------------------------------------------ */

int main(int argc, char **argv)
{
    GtkApplication *app = gtk_application_new("org.notepadplusplus.linux",
                                              G_APPLICATION_DEFAULT_FLAGS);
    g_signal_connect(app, "activate", G_CALLBACK(on_activate), NULL);

    /* Register app, open window */
    int status = g_application_run(G_APPLICATION(app), 1, argv);

    /* Open any files passed as arguments after the window is up */
    if (status == 0 && argc > 1) {
        for (int i = 1; i < argc; i++)
            editor_open_path(argv[i]);
    }

    g_object_unref(app);
    scintilla_release_resources();
    return status;
}
