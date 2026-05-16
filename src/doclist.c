#include "doclist.h"
#include "editor.h"
#include "i18n.h"
#include <gtk/gtk.h>
#include <string.h>

static GtkWidget *s_panel   = NULL;
static GtkWidget *s_listbox = NULL;
static gboolean   s_blocking_select = FALSE; /* prevent selection→switch→selection loop */

/* ------------------------------------------------------------------ */
/* Row activated: switch editor to that tab                           */
/* ------------------------------------------------------------------ */

static void on_row_activated(GtkListBox *lb, GtkListBoxRow *row, gpointer d)
{
    (void)lb; (void)d;
    if (s_blocking_select) return;
    int page = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(row), "npp-page"));
    GtkWidget *nb = editor_get_notebook();
    gtk_notebook_set_current_page(GTK_NOTEBOOK(nb), page);
}

/* ------------------------------------------------------------------ */
/* Close button in header                                             */
/* ------------------------------------------------------------------ */

static void on_close_clicked(GtkButton *btn, gpointer d)
{
    (void)btn; (void)d;
    doclist_set_visible(FALSE);
}

/* ------------------------------------------------------------------ */
/* Build one row label: "[*] basename (or new N)"                    */
/* ------------------------------------------------------------------ */

static GtkWidget *make_row_label(NppDoc *doc)
{
    char buf[512];
    const char *mod = doc->modified ? "* " : "  ";
    if (doc->filepath) {
        const char *base = strrchr(doc->filepath, '/');
        snprintf(buf, sizeof(buf), "%s%s", mod, base ? base + 1 : doc->filepath);
    } else {
        snprintf(buf, sizeof(buf), "%snew %d", mod, doc->new_index);
    }
    GtkWidget *lbl = gtk_label_new(buf);
    gtk_label_set_xalign(GTK_LABEL(lbl), 0.0f);
    gtk_label_set_ellipsize(GTK_LABEL(lbl), PANGO_ELLIPSIZE_END);
    gtk_label_set_max_width_chars(GTK_LABEL(lbl), 40);
    return lbl;
}

/* ------------------------------------------------------------------ */
/* Public API                                                         */
/* ------------------------------------------------------------------ */

GtkWidget *doclist_init(void)
{
    s_panel = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_widget_set_size_request(s_panel, 200, -1);

    /* Header: title + close button */
    GtkWidget *header = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
    gtk_style_context_add_class(gtk_widget_get_style_context(header), "doclist-header");

    GtkWidget *title = gtk_label_new(T("dlg.DocList.PanelTitle", "Document List"));
    gtk_label_set_xalign(GTK_LABEL(title), 0.0f);
    gtk_box_pack_start(GTK_BOX(header), title, TRUE, TRUE, 6);

    GtkWidget *close_btn = gtk_button_new_with_label("×");
    gtk_button_set_relief(GTK_BUTTON(close_btn), GTK_RELIEF_NONE);
    g_signal_connect(close_btn, "clicked", G_CALLBACK(on_close_clicked), NULL);
    gtk_box_pack_start(GTK_BOX(header), close_btn, FALSE, FALSE, 2);

    gtk_box_pack_start(GTK_BOX(s_panel), header, FALSE, FALSE, 0);

    /* Thin separator under header */
    gtk_box_pack_start(GTK_BOX(s_panel), gtk_separator_new(GTK_ORIENTATION_HORIZONTAL), FALSE, FALSE, 0);

    /* Scrolled list */
    GtkWidget *scroll = gtk_scrolled_window_new(NULL, NULL);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll),
                                   GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);

    s_listbox = gtk_list_box_new();
    gtk_list_box_set_selection_mode(GTK_LIST_BOX(s_listbox), GTK_SELECTION_SINGLE);
    gtk_list_box_set_activate_on_single_click(GTK_LIST_BOX(s_listbox), TRUE);
    g_signal_connect(s_listbox, "row-activated", G_CALLBACK(on_row_activated), NULL);

    gtk_container_add(GTK_CONTAINER(scroll), s_listbox);
    gtk_box_pack_start(GTK_BOX(s_panel), scroll, TRUE, TRUE, 0);

    /* Hidden by default */
    gtk_widget_hide(s_panel);

    return s_panel;
}

void doclist_refresh(void)
{
    if (!s_listbox) return;

    /* Remove all existing rows */
    GList *children = gtk_container_get_children(GTK_CONTAINER(s_listbox));
    for (GList *l = children; l; l = l->next)
        gtk_widget_destroy(GTK_WIDGET(l->data));
    g_list_free(children);

    int n = editor_page_count();
    for (int i = 0; i < n; i++) {
        NppDoc *doc = editor_doc_at(i);
        if (!doc) continue;

        GtkWidget *row_box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
        gtk_widget_set_margin_start(row_box, 4);
        gtk_widget_set_margin_end(row_box, 4);
        gtk_widget_set_margin_top(row_box, 2);
        gtk_widget_set_margin_bottom(row_box, 2);

        GtkWidget *lbl = make_row_label(doc);
        gtk_box_pack_start(GTK_BOX(row_box), lbl, TRUE, TRUE, 0);

        GtkWidget *row = gtk_list_box_row_new();
        g_object_set_data(G_OBJECT(row), "npp-page", GINT_TO_POINTER(i));
        gtk_container_add(GTK_CONTAINER(row), row_box);
        gtk_list_box_insert(GTK_LIST_BOX(s_listbox), row, -1);
    }

    gtk_widget_show_all(s_listbox);
    doclist_sync_selection(editor_current_page());
}

void doclist_sync_selection(int page)
{
    if (!s_listbox) return;
    if (page < 0) return;

    GtkListBoxRow *row = gtk_list_box_get_row_at_index(GTK_LIST_BOX(s_listbox), page);
    if (!row) return;

    s_blocking_select = TRUE;
    gtk_list_box_select_row(GTK_LIST_BOX(s_listbox), row);
    s_blocking_select = FALSE;
}

void doclist_set_visible(gboolean v)
{
    if (!s_panel) return;
    if (v)
        gtk_widget_show(s_panel);
    else
        gtk_widget_hide(s_panel);
}

gboolean doclist_is_visible(void)
{
    if (!s_panel) return FALSE;
    return gtk_widget_get_visible(s_panel);
}
