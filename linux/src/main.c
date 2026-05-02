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
    }

    /* ---- Language ---- */
    build_language_menu(bar);

    /* ---- Settings ---- */
    GtkWidget *settings = submenu(bar, TM("menu.settings", "Se_ttings"));
    APPEND(settings, menu_item(TM("cmd.46001", "_Style Configurator…"),
                               G_CALLBACK(cb_style_editor), NULL, accel, 0, 0));

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
