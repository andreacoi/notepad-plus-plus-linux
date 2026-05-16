/* toolbar.c — GTK3 toolbar for the Linux port.
 * Ports the toolbar structure from MainWindowController.mm (toolbarDescriptors).
 * Uses the same Fluent PNG icons (light/dark) as the macOS version.
 */
#include "toolbar.h"
#include "editor.h"
#include "findreplace.h"
#include "macro.h"
#include "doclist.h"
#include "docmap.h"
#include "workspace.h"
#include "funclist.h"
#include "sci_c.h"
#include <string.h>
#include <stdio.h>

/* ------------------------------------------------------------------ */
/* SCI view-toggle constants                                           */
/* ------------------------------------------------------------------ */
#define SCI_ZOOMIN              2333
#define SCI_ZOOMOUT             2334
/* SCI_SETWRAPMODE / SCI_GETWRAPMODE / SC_WRAP_* defined in sci_c.h */
/* SCI_SETVIEWWS / SCI_GETVIEWWS defined in sci_c.h */
#define SCI_SETINDENTATIONGUIDES 2132
#define SCI_GETINDENTATIONGUIDES 2133
/* SC_WS_INVISIBLE / SC_WS_VISIBLEALWAYS defined in sci_c.h */
#define SC_IV_NONE              0
#define SC_IV_LOOKBOTH          3

/* ------------------------------------------------------------------ */
/* Icon size (same visual size as macOS 28pt button / 26pt icon)      */
/* ------------------------------------------------------------------ */
#define ICON_PX 24

#ifndef RESOURCES_DIR
#define RESOURCES_DIR "../../resources"
#endif

/* ------------------------------------------------------------------ */
/* Module state                                                        */
/* ------------------------------------------------------------------ */
static GtkWidget *s_window           = NULL;
static GtkWidget *s_btn_undo         = NULL;
static GtkWidget *s_btn_redo         = NULL;
static GtkWidget *s_btn_save         = NULL;
static GtkWidget *s_tgl_wrap         = NULL;
static GtkWidget *s_tgl_allchars     = NULL;
static GtkWidget *s_tgl_indent       = NULL;
static GtkWidget *s_btn_startrecord  = NULL;
static GtkWidget *s_btn_stoprecord   = NULL;
static GtkWidget *s_btn_play         = NULL;
static GtkWidget *s_btn_playn        = NULL;
static GtkWidget *s_btn_saverecord   = NULL;
/* Panel toggle buttons */
static GtkWidget *s_tgl_doclist      = NULL;
static GtkWidget *s_tgl_docmap       = NULL;
static GtkWidget *s_tgl_workspace    = NULL;
static GtkWidget *s_tgl_funclist     = NULL;
static GtkWidget *s_tgl_monitoring   = NULL;

/* ------------------------------------------------------------------ */
/* Dark mode detection (mirrors NppThemeManager logic)                */
/* ------------------------------------------------------------------ */
static gboolean is_dark_mode(void)
{
    GtkSettings *s = gtk_settings_get_default();
    gboolean dark = FALSE;
    g_object_get(s, "gtk-application-prefer-dark-theme", &dark, NULL);
    if (!dark) {
        gchar *name = NULL;
        g_object_get(s, "gtk-theme-name", &name, NULL);
        if (name) {
            gchar *lower = g_ascii_strdown(name, -1);
            dark = (strstr(lower, "dark") != NULL);
            g_free(lower);
            g_free(name);
        }
    }
    return dark;
}

/* ------------------------------------------------------------------ */
/* Icon loading — same PNG set as macOS, scaled to ICON_PX            */
/* ------------------------------------------------------------------ */
static GtkWidget *load_icon(const char *name)
{
    char path[512];
    gboolean dark = is_dark_mode();

    if (dark)
        snprintf(path, sizeof(path),
                 RESOURCES_DIR "/icons/dark/toolbar/%s_off.png", name);
    else
        snprintf(path, sizeof(path),
                 RESOURCES_DIR "/icons/light/toolbar/filled/%s_off.png", name);

    GError *err = NULL;
    GdkPixbuf *pb = gdk_pixbuf_new_from_file_at_scale(path, ICON_PX, ICON_PX, TRUE, &err);
    if (!pb) {
        if (err) g_error_free(err);
        /* Fallback: try standard/ (16×16 classic icons) */
        snprintf(path, sizeof(path),
                 RESOURCES_DIR "/icons/standard/toolbar/%s.png", name);
        err = NULL;
        pb = gdk_pixbuf_new_from_file_at_scale(path, ICON_PX, ICON_PX, TRUE, &err);
        if (!pb) {
            if (err) g_error_free(err);
            return gtk_image_new_from_icon_name("image-missing",
                                                GTK_ICON_SIZE_SMALL_TOOLBAR);
        }
    }
    GtkWidget *img = gtk_image_new_from_pixbuf(pb);
    g_object_unref(pb);
    return img;
}

/* Convenience: GtkToolButton with icon + tooltip */
static GtkToolItem *make_btn(const char *icon_name, const char *tooltip,
                             GCallback cb, gpointer data)
{
    GtkToolItem *item = gtk_tool_button_new(load_icon(icon_name), NULL);
    gtk_tool_item_set_tooltip_text(item, tooltip);
    if (cb)
        g_signal_connect(item, "clicked", cb, data);
    return item;
}

/* Convenience: GtkToggleToolButton */
static GtkToolItem *make_toggle(const char *icon_name, const char *tooltip,
                                GCallback cb, gpointer data)
{
    GtkToolItem *item = gtk_toggle_tool_button_new();
    gtk_tool_button_set_icon_widget(GTK_TOOL_BUTTON(item), load_icon(icon_name));
    gtk_tool_item_set_tooltip_text(item, tooltip);
    if (cb)
        g_signal_connect(item, "toggled", cb, data);
    return item;
}

static GtkToolItem *make_sep(void)
{
    return gtk_separator_tool_item_new();
}

/* Placeholder: shows the icon but stays insensitive until the feature is wired. */
static GtkToolItem *make_placeholder(const char *icon_name, const char *tooltip)
{
    GtkToolItem *item = make_btn(icon_name, tooltip, NULL, NULL);
    gtk_widget_set_sensitive(GTK_WIDGET(item), FALSE);
    return item;
}

/* ------------------------------------------------------------------ */
/* Button callbacks — mirror macOS toolbar actions                    */
/* ------------------------------------------------------------------ */

static void on_new    (GtkToolItem *i, gpointer d) { (void)i;(void)d; editor_new_doc(); }
static void on_open   (GtkToolItem *i, gpointer d) { (void)i;(void)d; editor_open_dialog(); }
static void on_save   (GtkToolItem *i, gpointer d) { (void)i;(void)d; editor_save(); }

static void on_save_all(GtkToolItem *i, gpointer d)
{
    (void)i; (void)d;
    int n = editor_page_count();
    for (int p = 0; p < n; p++) {
        NppDoc *doc = editor_doc_at(p);
        if (doc && doc->modified)
            editor_save_at(p);
    }
}

static void on_close(GtkToolItem *i, gpointer d)    { (void)i;(void)d; editor_close_page(-1); }

static void on_close_all(GtkToolItem *i, gpointer d)
{
    (void)i; (void)d;
    /* Close tabs from right to left so indices stay valid */
    while (editor_page_count() > 1)
        if (!editor_close_page(editor_page_count() - 1)) break;
    /* last tab: close to an empty new doc */
    editor_close_page(0);
}

static void on_cut  (GtkToolItem *i, gpointer d) { (void)i;(void)d; editor_cut(); }
static void on_copy (GtkToolItem *i, gpointer d) { (void)i;(void)d; editor_copy(); }
static void on_paste(GtkToolItem *i, gpointer d) { (void)i;(void)d; editor_paste(); }
static void on_undo (GtkToolItem *i, gpointer d) { (void)i;(void)d; editor_undo(); }
static void on_redo (GtkToolItem *i, gpointer d) { (void)i;(void)d; editor_redo(); }

static void on_find(GtkToolItem *i, gpointer d)
{
    (void)i;
    NppDoc *doc = editor_current_doc();
    if (doc) findreplace_set_sci(doc->sci);
    findreplace_show((GtkWidget *)d, NULL, FALSE);
}

static void on_replace(GtkToolItem *i, gpointer d)
{
    (void)i;
    NppDoc *doc = editor_current_doc();
    if (doc) findreplace_set_sci(doc->sci);
    findreplace_show((GtkWidget *)d, NULL, TRUE);
}

static void on_zoom_in (GtkToolItem *i, gpointer d)
{
    (void)i;(void)d;
    editor_send(SCI_ZOOMIN, 0, 0);
}

static void on_zoom_out(GtkToolItem *i, gpointer d)
{
    (void)i;(void)d;
    editor_send(SCI_ZOOMOUT, 0, 0);
}

static void on_wrap(GtkToolItem *item, gpointer d)
{
    (void)d;
    gboolean on = gtk_toggle_tool_button_get_active(GTK_TOGGLE_TOOL_BUTTON(item));
    editor_send(SCI_SETWRAPMODE, on ? SC_WRAP_WORD : SC_WRAP_NONE, 0);
}

static void on_allchars(GtkToolItem *item, gpointer d)
{
    (void)d;
    gboolean on = gtk_toggle_tool_button_get_active(GTK_TOGGLE_TOOL_BUTTON(item));
    editor_send(SCI_SETVIEWWS, on ? SC_WS_VISIBLEALWAYS : SC_WS_INVISIBLE, 0);
}

static void on_indent(GtkToolItem *item, gpointer d)
{
    (void)d;
    gboolean on = gtk_toggle_tool_button_get_active(GTK_TOGGLE_TOOL_BUTTON(item));
    editor_send(SCI_SETINDENTATIONGUIDES, on ? SC_IV_LOOKBOTH : SC_IV_NONE, 0);
}

static void on_print(GtkToolItem *i, gpointer d)
{
    (void)i; (void)d;
    main_do_print();
}

static void on_saverecord(GtkToolItem *i, gpointer d)
{
    (void)i; (void)d;
    NppDoc *doc = editor_current_doc();
    if (doc) macro_save_as_dialog(doc->sci, GTK_WINDOW(s_window));
}

/* ---- Panel toggles ---- */
static void on_tgl_doclist(GtkToolItem *item, gpointer d)
{
    (void)d;
    gboolean on = gtk_toggle_tool_button_get_active(GTK_TOGGLE_TOOL_BUTTON(item));
    doclist_set_visible(on);
}

static void on_tgl_docmap(GtkToolItem *item, gpointer d)
{
    (void)d;
    gboolean on = gtk_toggle_tool_button_get_active(GTK_TOGGLE_TOOL_BUTTON(item));
    docmap_set_visible(on);
    if (on) {
        NppDoc *doc = editor_current_doc();
        if (doc) docmap_update(doc->sci);
    }
}

static void on_tgl_workspace(GtkToolItem *item, gpointer d)
{
    (void)d;
    gboolean on = gtk_toggle_tool_button_get_active(GTK_TOGGLE_TOOL_BUTTON(item));
    workspace_set_visible(on);
}

static void on_tgl_funclist(GtkToolItem *item, gpointer d)
{
    (void)d;
    gboolean on = gtk_toggle_tool_button_get_active(GTK_TOGGLE_TOOL_BUTTON(item));
    funclist_set_visible(on);
}

static void on_tgl_monitoring(GtkToolItem *item, gpointer d)
{
    (void)d;
    NppDoc *doc = editor_current_doc();
    if (!doc) return;
    gboolean on = gtk_toggle_tool_button_get_active(GTK_TOGGLE_TOOL_BUTTON(item));
    if (on && !doc->filepath) {
        /* Can't monitor an unsaved document — revert the button */
        g_signal_handlers_block_matched(GTK_WIDGET(item), G_SIGNAL_MATCH_FUNC,
            0, 0, NULL, G_CALLBACK(on_tgl_monitoring), NULL);
        gtk_toggle_tool_button_set_active(GTK_TOGGLE_TOOL_BUTTON(item), FALSE);
        g_signal_handlers_unblock_matched(GTK_WIDGET(item), G_SIGNAL_MATCH_FUNC,
            0, 0, NULL, G_CALLBACK(on_tgl_monitoring), NULL);
        return;
    }
    doc->monitoring = on;
}

static void on_macro_start(GtkToolItem *i, gpointer d)
{
    (void)i; (void)d;
    NppDoc *doc = editor_current_doc();
    if (!doc) return;
    macro_start_recording(doc->sci);
    toolbar_update_macro_buttons();
}

static void on_macro_stop(GtkToolItem *i, gpointer d)
{
    (void)i; (void)d;
    NppDoc *doc = editor_current_doc();
    if (!doc) return;
    macro_stop_recording(doc->sci);
    toolbar_update_macro_buttons();
}

static void on_macro_play(GtkToolItem *i, gpointer d)
{
    (void)i; (void)d;
    NppDoc *doc = editor_current_doc();
    if (!doc) return;
    macro_playback(doc->sci);
}

static void on_macro_playn(GtkToolItem *i, gpointer d)
{
    (void)i; (void)d;
    NppDoc *doc = editor_current_doc();
    if (!doc) return;
    macro_playback_n(doc->sci, GTK_WINDOW(s_window));
}

/* ------------------------------------------------------------------ */
/* Public API                                                          */
/* ------------------------------------------------------------------ */

GtkWidget *toolbar_init(GtkWidget *parent_window)
{
    s_window = parent_window;

    GtkWidget *tb = gtk_toolbar_new();
    gtk_toolbar_set_style(GTK_TOOLBAR(tb), GTK_TOOLBAR_ICONS);
    gtk_toolbar_set_icon_size(GTK_TOOLBAR(tb), GTK_ICON_SIZE_SMALL_TOOLBAR);

    int pos = 0;
#define ADD(item) gtk_toolbar_insert(GTK_TOOLBAR(tb), (item), pos++)

    /* ---- File group ---- */
    ADD(make_btn("new",      "New (Ctrl+N)",       G_CALLBACK(on_new),      NULL));
    ADD(make_btn("open",     "Open… (Ctrl+O)",     G_CALLBACK(on_open),     NULL));
    s_btn_save =
    GTK_WIDGET(make_btn("save",     "Save (Ctrl+S)",      G_CALLBACK(on_save),     NULL));
    ADD(GTK_TOOL_ITEM(s_btn_save));
    ADD(make_btn("saveall",  "Save All",            G_CALLBACK(on_save_all), NULL));
    ADD(make_btn("close",    "Close (Ctrl+W)",      G_CALLBACK(on_close),    NULL));
    ADD(make_btn("closeall", "Close All",           G_CALLBACK(on_close_all),NULL));
    ADD(make_btn("print", "Print… (Ctrl+P)", G_CALLBACK(on_print), NULL));
    ADD(make_sep());

    /* ---- Clipboard group ---- */
    ADD(make_btn("cut",   "Cut (Ctrl+X)",   G_CALLBACK(on_cut),   NULL));
    ADD(make_btn("copy",  "Copy (Ctrl+C)",  G_CALLBACK(on_copy),  NULL));
    ADD(make_btn("paste", "Paste (Ctrl+V)", G_CALLBACK(on_paste), NULL));
    ADD(make_sep());

    /* ---- Undo / Redo group ---- */
    s_btn_undo = GTK_WIDGET(make_btn("undo", "Undo (Ctrl+Z)",       G_CALLBACK(on_undo), NULL));
    s_btn_redo = GTK_WIDGET(make_btn("redo", "Redo (Ctrl+Shift+Z)", G_CALLBACK(on_redo), NULL));
    ADD(GTK_TOOL_ITEM(s_btn_undo));
    ADD(GTK_TOOL_ITEM(s_btn_redo));
    ADD(make_sep());

    /* ---- Find group ---- */
    ADD(make_btn("find",    "Find… (Ctrl+F)",    G_CALLBACK(on_find),    parent_window));
    ADD(make_btn("findrep", "Replace… (Ctrl+H)", G_CALLBACK(on_replace), parent_window));
    ADD(make_sep());

    /* ---- Zoom group ---- */
    ADD(make_btn("zoomIn",  "Zoom In",  G_CALLBACK(on_zoom_in),  NULL));
    ADD(make_btn("zoomOut", "Zoom Out", G_CALLBACK(on_zoom_out), NULL));
    ADD(make_sep());

    /* ---- View toggles group ---- */
    s_tgl_wrap =
    GTK_WIDGET(make_toggle("wrap",       "Toggle Word Wrap",      G_CALLBACK(on_wrap),     NULL));
    s_tgl_allchars =
    GTK_WIDGET(make_toggle("allChars",   "Show All Characters",   G_CALLBACK(on_allchars), NULL));
    s_tgl_indent =
    GTK_WIDGET(make_toggle("indentGuide","Toggle Indent Guide",   G_CALLBACK(on_indent),   NULL));
    ADD(GTK_TOOL_ITEM(s_tgl_wrap));
    ADD(GTK_TOOL_ITEM(s_tgl_allchars));
    ADD(GTK_TOOL_ITEM(s_tgl_indent));
    ADD(make_placeholder("syncH", "Synchronise Horizontal Scrolling (not supported)"));
    ADD(make_placeholder("syncV", "Synchronise Vertical Scrolling (not supported)"));
    ADD(make_sep());

    /* ---- Macro group ---- */
    s_btn_startrecord =
    GTK_WIDGET(make_btn("startrecord", "Start Recording (Ctrl+Shift+R)",
                        G_CALLBACK(on_macro_start), NULL));
    s_btn_stoprecord =
    GTK_WIDGET(make_btn("stoprecord",  "Stop Recording",
                        G_CALLBACK(on_macro_stop),  NULL));
    s_btn_play =
    GTK_WIDGET(make_btn("playrecord",  "Playback (Ctrl+Shift+P)",
                        G_CALLBACK(on_macro_play),  NULL));
    s_btn_playn =
    GTK_WIDGET(make_btn("playrecord_m","Run Macro Multiple Times…",
                        G_CALLBACK(on_macro_playn), NULL));
    s_btn_saverecord =
    GTK_WIDGET(make_btn("saverecord", "Save Current Recorded Macro As…",
                        G_CALLBACK(on_saverecord), NULL));
    ADD(GTK_TOOL_ITEM(s_btn_startrecord));
    ADD(GTK_TOOL_ITEM(s_btn_stoprecord));
    ADD(GTK_TOOL_ITEM(s_btn_play));
    ADD(GTK_TOOL_ITEM(s_btn_playn));
    ADD(GTK_TOOL_ITEM(s_btn_saverecord));
    ADD(make_sep());

    /* ---- Panels group ---- */
    s_tgl_doclist =
    GTK_WIDGET(make_toggle("docList",     "Document List",       G_CALLBACK(on_tgl_doclist),    NULL));
    s_tgl_docmap =
    GTK_WIDGET(make_toggle("docMap",      "Document Map",        G_CALLBACK(on_tgl_docmap),     NULL));
    s_tgl_workspace =
    GTK_WIDGET(make_toggle("fileBrowser", "Folder as Workspace", G_CALLBACK(on_tgl_workspace),  NULL));
    s_tgl_funclist =
    GTK_WIDGET(make_toggle("funcList",    "Function List",       G_CALLBACK(on_tgl_funclist),   NULL));
    s_tgl_monitoring =
    GTK_WIDGET(make_toggle("monitoring",  "File Monitoring (tail -f)", G_CALLBACK(on_tgl_monitoring), NULL));
    ADD(GTK_TOOL_ITEM(s_tgl_doclist));
    ADD(GTK_TOOL_ITEM(s_tgl_docmap));
    ADD(GTK_TOOL_ITEM(s_tgl_workspace));
    ADD(GTK_TOOL_ITEM(s_tgl_funclist));
    ADD(GTK_TOOL_ITEM(s_tgl_monitoring));
    ADD(make_sep());

    /* ---- Misc ---- */
    ADD(make_placeholder("udl", "User Defined Languages"));

#undef ADD

    toolbar_update_macro_buttons();
    gtk_widget_show_all(tb);
    return tb;
}

void toolbar_update_macro_buttons(void)
{
    if (!s_btn_startrecord) return;
    gboolean recording = macro_is_recording();
    gboolean has_macro = macro_has_macro();
    gtk_widget_set_sensitive(s_btn_startrecord, !recording);
    gtk_widget_set_sensitive(s_btn_stoprecord,   recording);
    gtk_widget_set_sensitive(s_btn_play,         !recording && has_macro);
    gtk_widget_set_sensitive(s_btn_playn,        !recording && has_macro);
    if (s_btn_saverecord)
        gtk_widget_set_sensitive(s_btn_saverecord, !recording && has_macro);
}

/* Helper: set a GtkToggleToolButton state without firing its callback */
static void sync_toggle(GtkWidget *btn, GCallback cb, gboolean active)
{
    if (!btn) return;
    g_signal_handlers_block_matched(btn, G_SIGNAL_MATCH_FUNC, 0, 0, NULL, cb, NULL);
    gtk_toggle_tool_button_set_active(GTK_TOGGLE_TOOL_BUTTON(btn), active);
    g_signal_handlers_unblock_matched(btn, G_SIGNAL_MATCH_FUNC, 0, 0, NULL, cb, NULL);
}

void toolbar_sync_panels(void)
{
    sync_toggle(s_tgl_doclist,    G_CALLBACK(on_tgl_doclist),    doclist_is_visible());
    sync_toggle(s_tgl_docmap,     G_CALLBACK(on_tgl_docmap),     docmap_is_visible());
    sync_toggle(s_tgl_workspace,  G_CALLBACK(on_tgl_workspace),  workspace_is_visible());
    sync_toggle(s_tgl_funclist,   G_CALLBACK(on_tgl_funclist),   funclist_is_visible());

    NppDoc *doc = editor_current_doc();
    sync_toggle(s_tgl_monitoring, G_CALLBACK(on_tgl_monitoring),
                doc ? doc->monitoring : FALSE);
}

void toolbar_sync_toggles(GtkWidget *sci)
{
    if (!sci) return;

    /* Monitoring: driven by NppDoc flag, not Scintilla */
    NppDoc *doc = editor_current_doc();
    sync_toggle(s_tgl_monitoring, G_CALLBACK(on_tgl_monitoring),
                doc ? doc->monitoring : FALSE);

    /* Block signals while syncing to avoid feedback loop */
    if (s_tgl_wrap) {
        g_signal_handlers_block_matched(s_tgl_wrap, G_SIGNAL_MATCH_FUNC,
                                        0, 0, NULL, G_CALLBACK(on_wrap), NULL);
        gboolean wrap = (scintilla_send_message(SCINTILLA(sci), SCI_GETWRAPMODE, 0, 0) != SC_WRAP_NONE);
        gtk_toggle_tool_button_set_active(GTK_TOGGLE_TOOL_BUTTON(s_tgl_wrap), wrap);
        g_signal_handlers_unblock_matched(s_tgl_wrap, G_SIGNAL_MATCH_FUNC,
                                          0, 0, NULL, G_CALLBACK(on_wrap), NULL);
    }
    if (s_tgl_allchars) {
        g_signal_handlers_block_matched(s_tgl_allchars, G_SIGNAL_MATCH_FUNC,
                                        0, 0, NULL, G_CALLBACK(on_allchars), NULL);
        gboolean ws = (scintilla_send_message(SCINTILLA(sci), SCI_GETVIEWWS, 0, 0) != SC_WS_INVISIBLE);
        gtk_toggle_tool_button_set_active(GTK_TOGGLE_TOOL_BUTTON(s_tgl_allchars), ws);
        g_signal_handlers_unblock_matched(s_tgl_allchars, G_SIGNAL_MATCH_FUNC,
                                          0, 0, NULL, G_CALLBACK(on_allchars), NULL);
    }
    if (s_tgl_indent) {
        g_signal_handlers_block_matched(s_tgl_indent, G_SIGNAL_MATCH_FUNC,
                                        0, 0, NULL, G_CALLBACK(on_indent), NULL);
        gboolean ig = (scintilla_send_message(SCINTILLA(sci), SCI_GETINDENTATIONGUIDES, 0, 0) != SC_IV_NONE);
        gtk_toggle_tool_button_set_active(GTK_TOGGLE_TOOL_BUTTON(s_tgl_indent), ig);
        g_signal_handlers_unblock_matched(s_tgl_indent, G_SIGNAL_MATCH_FUNC,
                                          0, 0, NULL, G_CALLBACK(on_indent), NULL);
    }
}
