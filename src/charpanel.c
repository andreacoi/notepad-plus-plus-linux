#include "charpanel.h"
#include "editor.h"
#include "i18n.h"
#include <string.h>
#include <stdio.h>

/* ------------------------------------------------------------------ */
/* Unicode block table                                                 */
/* ------------------------------------------------------------------ */
typedef struct { gunichar first; gunichar last; const char *name; } UBlock;

static const UBlock k_blocks[] = {
    { 0x0000, 0x007F, "Basic Latin" },
    { 0x0080, 0x00FF, "Latin-1 Supplement" },
    { 0x0100, 0x017F, "Latin Extended-A" },
    { 0x0180, 0x024F, "Latin Extended-B" },
    { 0x0250, 0x02AF, "IPA Extensions" },
    { 0x0370, 0x03FF, "Greek and Coptic" },
    { 0x0400, 0x04FF, "Cyrillic" },
    { 0x0500, 0x052F, "Cyrillic Supplement" },
    { 0x0600, 0x06FF, "Arabic" },
    { 0x0900, 0x097F, "Devanagari" },
    { 0x0980, 0x09FF, "Bengali" },
    { 0x0E00, 0x0E7F, "Thai" },
    { 0x1100, 0x11FF, "Hangul Jamo" },
    { 0x1D00, 0x1D7F, "Phonetic Extensions" },
    { 0x1E00, 0x1EFF, "Latin Extended Additional" },
    { 0x1F00, 0x1FFF, "Greek Extended" },
    { 0x2000, 0x206F, "General Punctuation" },
    { 0x2070, 0x209F, "Superscripts and Subscripts" },
    { 0x20A0, 0x20CF, "Currency Symbols" },
    { 0x2100, 0x214F, "Letterlike Symbols" },
    { 0x2150, 0x218F, "Number Forms" },
    { 0x2190, 0x21FF, "Arrows" },
    { 0x2200, 0x22FF, "Mathematical Operators" },
    { 0x2300, 0x23FF, "Miscellaneous Technical" },
    { 0x2400, 0x243F, "Control Pictures" },
    { 0x2460, 0x24FF, "Enclosed Alphanumerics" },
    { 0x2500, 0x257F, "Box Drawing" },
    { 0x2580, 0x259F, "Block Elements" },
    { 0x25A0, 0x25FF, "Geometric Shapes" },
    { 0x2600, 0x26FF, "Miscellaneous Symbols" },
    { 0x2700, 0x27BF, "Dingbats" },
    { 0x2C00, 0x2C5F, "Glagolitic" },
    { 0x3000, 0x303F, "CJK Symbols and Punctuation" },
    { 0x3040, 0x309F, "Hiragana" },
    { 0x30A0, 0x30FF, "Katakana" },
    { 0x3100, 0x312F, "Bopomofo" },
    { 0x3400, 0x4DBF, "CJK Unified Ideographs Ext-A" },
    { 0x4E00, 0x9FFF, "CJK Unified Ideographs" },
    { 0xA000, 0xA48F, "Yi Syllables" },
    { 0xAC00, 0xD7AF, "Hangul Syllables" },
    { 0xFB00, 0xFB4F, "Alphabetic Presentation Forms" },
    { 0xFE30, 0xFE4F, "CJK Compatibility Forms" },
    { 0xFFF0, 0xFFFF, "Specials" },
    { 0x10000,0x1007F,"Linear B Syllabary" },
    { 0x1D000,0x1D0FF,"Byzantine Musical Symbols" },
    { 0x1D400,0x1D7FF,"Mathematical Alphanumeric Symbols" },
    { 0x1F300,0x1F5FF,"Miscellaneous Symbols and Pictographs" },
    { 0x1F600,0x1F64F,"Emoticons" },
    { 0x1F900,0x1F9FF,"Supplemental Symbols and Pictographs" },
};
#define N_BLOCKS (int)(sizeof(k_blocks)/sizeof(k_blocks[0]))

/* ------------------------------------------------------------------ */
/* Module state                                                        */
/* ------------------------------------------------------------------ */
static GtkWidget  *s_panel     = NULL;
static GtkWidget  *s_grid      = NULL;   /* GtkGrid of char buttons */
static GtkWidget  *s_detail    = NULL;   /* GtkLabel for detail */
static GtkWidget  *s_search    = NULL;   /* GtkEntry for search */
static gunichar    s_block_first = 0x0020;
static gunichar    s_block_last  = 0x007F;
static GtkWidget  *s_window    = NULL;

/* ------------------------------------------------------------------ */
/* Insert character into active editor                                 */
/* ------------------------------------------------------------------ */
static void insert_char(gunichar cp)
{
    NppDoc *doc = editor_current_doc();
    if (!doc) return;
    char utf8[8] = {0};
    int n = (int)g_unichar_to_utf8(cp, utf8);
    if (n > 0)
        scintilla_send_message(SCINTILLA(doc->sci),
            SCI_REPLACESEL, 0, (sptr_t)utf8);
}

/* ------------------------------------------------------------------ */
/* Detail label for a codepoint                                        */
/* ------------------------------------------------------------------ */
static void show_detail(gunichar cp)
{
    /* Build UTF-8 bytes string */
    char utf8[8] = {0};
    int ulen = (int)g_unichar_to_utf8(cp, utf8);
    GString *detail = g_string_new(NULL);
    g_string_append_printf(detail, "U+%04X", cp);
    if (cp < 0xD800 || cp > 0xDFFF) {
        g_string_append(detail, "  UTF-8:");
        for (int i = 0; i < ulen; i++)
            g_string_append_printf(detail, " %02X", (unsigned char)utf8[i]);
    }
    /* Unicode category */
    GUnicodeType cat = g_unichar_type(cp);
    const char *cat_names[] = {
        "Control", "Format", "Unassigned", "Private Use", "Surrogate",
        "Lowercase Letter", "Modifier Letter", "Other Letter",
        "Titlecase Letter", "Uppercase Letter",
        "Spacing Mark", "Enclosing Mark", "Non-spacing Mark",
        "Decimal Number", "Letter Number", "Other Number",
        "Connect Punctuation", "Dash Punctuation", "Close Punctuation",
        "Final Punctuation", "Initial Punctuation", "Other Punctuation",
        "Open Punctuation",
        "Currency Symbol", "Modifier Symbol", "Math Symbol", "Other Symbol",
        "Line Separator", "Paragraph Separator", "Space Separator"
    };
    if ((int)cat < (int)(sizeof(cat_names)/sizeof(cat_names[0])))
        g_string_append_printf(detail, "  [%s]", cat_names[cat]);
    gtk_label_set_text(GTK_LABEL(s_detail), detail->str);
    g_string_free(detail, TRUE);
}

/* ------------------------------------------------------------------ */
/* Button clicked                                                      */
/* ------------------------------------------------------------------ */
static void on_char_btn(GtkButton *b, gpointer ud)
{
    (void)b;
    gunichar cp = (gunichar)GPOINTER_TO_UINT(ud);
    show_detail(cp);
    insert_char(cp);
}

/* ------------------------------------------------------------------ */
/* Populate the character grid for the current block                   */
/* ------------------------------------------------------------------ */
#define GRID_COLS 16

static void populate_grid(void)
{
    /* Remove old buttons */
    GList *children = gtk_container_get_children(GTK_CONTAINER(s_grid));
    for (GList *l = children; l; l = l->next)
        gtk_widget_destroy(GTK_WIDGET(l->data));
    g_list_free(children);

    int row = 0, col = 0;
    for (gunichar cp = s_block_first; cp <= s_block_last; cp++) {
        if (!g_unichar_validate(cp) || g_unichar_type(cp) == G_UNICODE_SURROGATE)
            continue;

        char utf8[8] = {0};
        int n = (int)g_unichar_to_utf8(cp, utf8);
        if (n <= 0) continue;

        GtkWidget *btn;
        if (g_unichar_isprint(cp) && g_unichar_type(cp) != G_UNICODE_CONTROL) {
            btn = gtk_button_new_with_label(utf8);
        } else {
            char hex[8];
            snprintf(hex, sizeof(hex), "%04X", cp);
            btn = gtk_button_new_with_label(hex);
        }
        gtk_widget_set_size_request(btn, 32, 28);
        gtk_button_set_relief(GTK_BUTTON(btn), GTK_RELIEF_NONE);
        g_signal_connect(btn, "clicked", G_CALLBACK(on_char_btn),
                         GUINT_TO_POINTER((guint)cp));
        gtk_grid_attach(GTK_GRID(s_grid), btn, col, row, 1, 1);

        col++;
        if (col >= GRID_COLS) { col = 0; row++; }
    }
    gtk_widget_show_all(s_grid);
}

/* ------------------------------------------------------------------ */
/* Block tree selection                                                */
/* ------------------------------------------------------------------ */
enum { BCOL_IDX=0, BCOL_NAME, BCOL_FIRST, BCOL_LAST, BCOL_N };

static void on_block_selected(GtkTreeSelection *sel, gpointer d)
{
    (void)d;
    GtkTreeIter it;
    GtkTreeModel *m;
    if (!gtk_tree_selection_get_selected(sel, &m, &it)) return;
    guint first, last;
    gtk_tree_model_get(m, &it, BCOL_FIRST, &first, BCOL_LAST, &last, -1);
    s_block_first = (gunichar)first;
    s_block_last  = (gunichar)last;
    populate_grid();
}

/* ------------------------------------------------------------------ */
/* Search by codepoint or name prefix                                  */
/* ------------------------------------------------------------------ */
static void on_search_activate(GtkEntry *entry, gpointer d)
{
    (void)d;
    const char *text = gtk_entry_get_text(entry);
    if (!text || !*text) return;

    /* Try hex codepoint */
    unsigned long cp_val = strtoul(text, NULL, 16);
    if (cp_val > 0 && cp_val <= 0x10FFFF) {
        /* Find block */
        for (int i = 0; i < N_BLOCKS; i++) {
            if (cp_val >= k_blocks[i].first && cp_val <= k_blocks[i].last) {
                s_block_first = k_blocks[i].first;
                s_block_last  = k_blocks[i].last;
                populate_grid();
                show_detail((gunichar)cp_val);
                return;
            }
        }
    }
}

/* ------------------------------------------------------------------ */
/* Public API                                                          */
/* ------------------------------------------------------------------ */

GtkWidget *charpanel_init(GtkWidget *window)
{
    s_window = window;

    GtkWidget *outer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);

    /* Header */
    GtkWidget *hdr   = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
    GtkWidget *title = gtk_label_new("Character Panel");
    gtk_widget_set_halign(title, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(hdr), title, TRUE, TRUE, 4);
    GtkWidget *close_btn = gtk_button_new_from_icon_name(
        "window-close-symbolic", GTK_ICON_SIZE_MENU);
    gtk_button_set_relief(GTK_BUTTON(close_btn), GTK_RELIEF_NONE);
    g_signal_connect_swapped(close_btn, "clicked",
                             G_CALLBACK(charpanel_set_visible),
                             GINT_TO_POINTER(FALSE));
    gtk_box_pack_end(GTK_BOX(hdr), close_btn, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(outer), hdr, FALSE, FALSE, 0);

    /* Search bar */
    GtkWidget *sbar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
    gtk_container_set_border_width(GTK_CONTAINER(sbar), 2);
    gtk_box_pack_start(GTK_BOX(sbar), gtk_label_new("Go to U+:"), FALSE, FALSE, 0);
    s_search = gtk_entry_new();
    gtk_entry_set_width_chars(GTK_ENTRY(s_search), 8);
    gtk_entry_set_placeholder_text(GTK_ENTRY(s_search), "e.g. 1F600");
    g_signal_connect(s_search, "activate", G_CALLBACK(on_search_activate), NULL);
    gtk_box_pack_start(GTK_BOX(sbar), s_search, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(outer), sbar, FALSE, FALSE, 0);

    /* Horizontal pane: block list | character grid */
    GtkWidget *hpaned = gtk_paned_new(GTK_ORIENTATION_HORIZONTAL);
    gtk_box_pack_start(GTK_BOX(outer), hpaned, TRUE, TRUE, 0);

    /* Block list */
    GtkListStore *bls = gtk_list_store_new(BCOL_N,
        G_TYPE_INT, G_TYPE_STRING, G_TYPE_UINT, G_TYPE_UINT);
    for (int i = 0; i < N_BLOCKS; i++) {
        GtkTreeIter it;
        gtk_list_store_append(bls, &it);
        gtk_list_store_set(bls, &it,
            BCOL_IDX,   i,
            BCOL_NAME,  k_blocks[i].name,
            BCOL_FIRST, (guint)k_blocks[i].first,
            BCOL_LAST,  (guint)k_blocks[i].last,
            -1);
    }
    GtkWidget *btv = gtk_tree_view_new_with_model(GTK_TREE_MODEL(bls));
    g_object_unref(bls);
    gtk_tree_view_set_headers_visible(GTK_TREE_VIEW(btv), FALSE);
    GtkCellRenderer *br = gtk_cell_renderer_text_new();
    gtk_tree_view_append_column(GTK_TREE_VIEW(btv),
        gtk_tree_view_column_new_with_attributes("Block", br, "text", BCOL_NAME, NULL));
    GtkTreeSelection *bsel = gtk_tree_view_get_selection(GTK_TREE_VIEW(btv));
    g_signal_connect(bsel, "changed", G_CALLBACK(on_block_selected), NULL);

    GtkWidget *bscroll = gtk_scrolled_window_new(NULL, NULL);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(bscroll),
        GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
    gtk_container_add(GTK_CONTAINER(bscroll), btv);
    gtk_widget_set_size_request(bscroll, 160, -1);
    gtk_paned_pack1(GTK_PANED(hpaned), bscroll, FALSE, FALSE);

    /* Right: grid + detail */
    GtkWidget *right_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);

    s_grid = gtk_grid_new();
    gtk_grid_set_row_spacing(GTK_GRID(s_grid), 1);
    gtk_grid_set_column_spacing(GTK_GRID(s_grid), 1);
    GtkWidget *gscroll = gtk_scrolled_window_new(NULL, NULL);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(gscroll),
        GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
    gtk_container_add(GTK_CONTAINER(gscroll), s_grid);
    gtk_box_pack_start(GTK_BOX(right_box), gscroll, TRUE, TRUE, 0);

    s_detail = gtk_label_new("Click a character to see its details");
    gtk_label_set_selectable(GTK_LABEL(s_detail), TRUE);
    gtk_widget_set_halign(s_detail, GTK_ALIGN_START);
    gtk_widget_set_margin_start(s_detail, 4);
    gtk_box_pack_start(GTK_BOX(right_box), s_detail, FALSE, FALSE, 2);

    gtk_paned_pack2(GTK_PANED(hpaned), right_box, TRUE, TRUE);

    /* Populate initial block (Basic Latin) */
    populate_grid();

    s_panel = outer;
    return s_panel;
}

void charpanel_set_visible(gboolean v)
{
    if (!s_panel) return;
    if (v) gtk_widget_show(s_panel);
    else    gtk_widget_hide(s_panel);
}

gboolean charpanel_is_visible(void)
{
    return s_panel && gtk_widget_get_visible(s_panel);
}
