/* toolbar.c — GTK3 toolbar for the Linux port.
 * Ports the toolbar structure from MainWindowController.mm (toolbarDescriptors).
 * Uses the same Fluent PNG icons (light/dark) as the macOS version.
 */
#include "toolbar.h"
#include "editor.h"
#include "findreplace.h"
#include "sci_c.h"
#include <string.h>
#include <stdio.h>

/* ------------------------------------------------------------------ */
/* SCI view-toggle constants                                           */
/* ------------------------------------------------------------------ */
#define SCI_ZOOMIN              2333
#define SCI_ZOOMOUT             2334
#define SCI_SETWRAPMODE         2268
#define SCI_GETWRAPMODE         2269
/* SCI_SETVIEWWS / SCI_GETVIEWWS defined in sci_c.h */
#define SCI_SETINDENTATIONGUIDES 2132
#define SCI_GETINDENTATIONGUIDES 2133

#define SC_WRAP_NONE            0
#define SC_WRAP_WORD            1
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

#undef ADD

    gtk_widget_show_all(tb);
    return tb;
}

void toolbar_sync_toggles(GtkWidget *sci)
{
    if (!sci) return;

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
