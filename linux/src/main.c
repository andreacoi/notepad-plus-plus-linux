#include <gtk/gtk.h>
#include "sci_c.h"
#include "editor.h"
#include "statusbar.h"
#include "findreplace.h"

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
    GtkWidget *file = submenu(bar, "_File");
    APPEND(file, menu_item("_New",        G_CALLBACK(cb_new),    NULL, accel, GDK_KEY_n, GDK_CONTROL_MASK));
    APPEND(file, menu_item("_Open…",      G_CALLBACK(cb_open),   NULL, accel, GDK_KEY_o, GDK_CONTROL_MASK));
    APPEND(file, sep_item());
    APPEND(file, menu_item("_Save",       G_CALLBACK(cb_save),   NULL, accel, GDK_KEY_s, GDK_CONTROL_MASK));
    APPEND(file, menu_item("Save _As…",   G_CALLBACK(cb_save_as),NULL, accel, GDK_KEY_s, GDK_CONTROL_MASK | GDK_SHIFT_MASK));
    APPEND(file, sep_item());
    APPEND(file, menu_item("_Close",      G_CALLBACK(cb_close),  NULL, accel, GDK_KEY_w, GDK_CONTROL_MASK));
    APPEND(file, sep_item());
    APPEND(file, menu_item("_Quit",       G_CALLBACK(cb_quit),   app,  accel, GDK_KEY_q, GDK_CONTROL_MASK));

    /* ---- Edit ---- */
    GtkWidget *edit = submenu(bar, "_Edit");
    APPEND(edit, menu_item("_Undo",       G_CALLBACK(cb_undo),   NULL, accel, GDK_KEY_z, GDK_CONTROL_MASK));
    APPEND(edit, menu_item("_Redo",       G_CALLBACK(cb_redo),   NULL, accel, GDK_KEY_z, GDK_CONTROL_MASK | GDK_SHIFT_MASK));
    APPEND(edit, sep_item());
    APPEND(edit, menu_item("Cu_t",        G_CALLBACK(cb_cut),    NULL, accel, GDK_KEY_x, GDK_CONTROL_MASK));
    APPEND(edit, menu_item("_Copy",       G_CALLBACK(cb_copy),   NULL, accel, GDK_KEY_c, GDK_CONTROL_MASK));
    APPEND(edit, menu_item("_Paste",      G_CALLBACK(cb_paste),  NULL, accel, GDK_KEY_v, GDK_CONTROL_MASK));
    APPEND(edit, sep_item());
    APPEND(edit, menu_item("Select _All", G_CALLBACK(cb_selall), NULL, accel, GDK_KEY_a, GDK_CONTROL_MASK));

    /* ---- Search ---- */
    GtkWidget *search = submenu(bar, "_Search");
    APPEND(search, menu_item("_Find…",       G_CALLBACK(cb_find),    NULL, accel, GDK_KEY_f, GDK_CONTROL_MASK));
    APPEND(search, menu_item("_Replace…",    G_CALLBACK(cb_replace), NULL, accel, GDK_KEY_h, GDK_CONTROL_MASK));
    APPEND(search, sep_item());
    APPEND(search, menu_item("_Go To Line…", G_CALLBACK(cb_goto),    NULL, accel, GDK_KEY_g, GDK_CONTROL_MASK));

    /* ---- View (placeholder) ---- */
    submenu(bar, "_View");

    /* ---- Settings (placeholder) ---- */
    submenu(bar, "Se_ttings");

    return bar;
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

    GtkWidget *window = gtk_application_window_new(app);
    s_main_window = window;
    gtk_window_set_title(GTK_WINDOW(window), "Notepad++ Linux");
    gtk_window_set_default_size(GTK_WINDOW(window), 1024, 700);
    g_signal_connect(window, "delete-event", G_CALLBACK(on_delete_event), app);

    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_container_add(GTK_CONTAINER(window), vbox);

    /* Menu bar */
    GtkWidget *menubar = build_menubar(GTK_WINDOW(window), G_APPLICATION(app));
    gtk_box_pack_start(GTK_BOX(vbox), menubar, FALSE, FALSE, 0);

    /* Editor (notebook) */
    GtkWidget *notebook = editor_init(window);
    gtk_box_pack_start(GTK_BOX(vbox), notebook, TRUE, TRUE, 0);

    /* Status bar */
    GtkWidget *statusbar = statusbar_init();
    gtk_box_pack_start(GTK_BOX(vbox), statusbar, FALSE, FALSE, 0);

    /* Open files passed on the command line */
    const gchar **args = g_application_get_dbus_object_path(G_APPLICATION(app))
        ? NULL : NULL;
    (void)args; /* CLI args handled below in main() via editor_open_path */

    gtk_widget_show_all(window);
    statusbar_update_from_sci(editor_current_doc()->sci);
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
