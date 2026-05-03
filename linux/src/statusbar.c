#include "statusbar.h"
#include "sci_c.h"
#include <stdio.h>

static GtkWidget *s_lbl_pos;
static GtkWidget *s_lbl_enc;
static GtkWidget *s_lbl_eol;
static GtkWidget *s_lbl_lang;
static GtkWidget *s_lbl_ovr;
static GtkWidget *s_lbl_indent;

static GtkWidget *vsep(void)
{
    GtkWidget *s = gtk_separator_new(GTK_ORIENTATION_VERTICAL);
    gtk_widget_set_margin_start(s, 4);
    gtk_widget_set_margin_end(s, 4);
    return s;
}

static GtkWidget *rlabel(const char *text)
{
    GtkWidget *l = gtk_label_new(text);
    gtk_widget_set_margin_start(l, 4);
    gtk_widget_set_margin_end(l, 4);
    return l;
}

GtkWidget *statusbar_init(void)
{
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_widget_set_margin_top(box, 2);
    gtk_widget_set_margin_bottom(box, 2);

    s_lbl_pos = rlabel("Ln 1, Col 1");
    gtk_box_pack_start(GTK_BOX(box), s_lbl_pos, FALSE, FALSE, 0);

    /* right-aligned group */
    gtk_box_pack_end(GTK_BOX(box), (s_lbl_lang = rlabel("Normal Text")), FALSE, FALSE, 0);
    gtk_box_pack_end(GTK_BOX(box), vsep(),                                FALSE, FALSE, 0);
    gtk_box_pack_end(GTK_BOX(box), (s_lbl_eol = rlabel("LF")),           FALSE, FALSE, 0);
    gtk_box_pack_end(GTK_BOX(box), vsep(),                                FALSE, FALSE, 0);
    gtk_box_pack_end(GTK_BOX(box), (s_lbl_ovr = rlabel("INS")),          FALSE, FALSE, 0);
    gtk_box_pack_end(GTK_BOX(box), vsep(),                                FALSE, FALSE, 0);
    gtk_box_pack_end(GTK_BOX(box), (s_lbl_enc = rlabel("UTF-8")),           FALSE, FALSE, 0);
    gtk_box_pack_end(GTK_BOX(box), vsep(),                                   FALSE, FALSE, 0);
    gtk_box_pack_end(GTK_BOX(box), (s_lbl_indent = rlabel("Spaces: 4")),    FALSE, FALSE, 0);
    gtk_box_pack_end(GTK_BOX(box), vsep(),                                   FALSE, FALSE, 0);

    /* top border */
    GtkWidget *frame = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_box_pack_start(GTK_BOX(frame), gtk_separator_new(GTK_ORIENTATION_HORIZONTAL), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(frame), box, FALSE, FALSE, 0);
    return frame;
}

void statusbar_update_from_sci(GtkWidget *sci)
{
    if (!sci || !s_lbl_pos) return;
    sptr_t pos  = scintilla_send_message(SCINTILLA(sci), SCI_GETCURRENTPOS, 0, 0);
    int    line = (int)scintilla_send_message(SCINTILLA(sci), SCI_LINEFROMPOSITION, (uptr_t)pos, 0);
    int    col  = (int)scintilla_send_message(SCINTILLA(sci), SCI_GETCOLUMN, (uptr_t)pos, 0);
    char   buf[64];
    snprintf(buf, sizeof(buf), "Ln %d, Col %d", line + 1, col + 1);
    gtk_label_set_text(GTK_LABEL(s_lbl_pos), buf);

    int eol = (int)scintilla_send_message(SCINTILLA(sci), SCI_GETEOLMODE, 0, 0);
    gtk_label_set_text(GTK_LABEL(s_lbl_eol),
        eol == SC_EOL_CRLF ? "CRLF" : eol == SC_EOL_CR ? "CR" : "LF");

    int ovr = (int)scintilla_send_message(SCINTILLA(sci), SCI_GETOVERTYPE, 0, 0);
    gtk_label_set_text(GTK_LABEL(s_lbl_ovr), ovr ? "OVR" : "INS");

    int use_tabs = (int)scintilla_send_message(SCINTILLA(sci), SCI_GETUSETABS, 0, 0);
    int tab_w    = (int)scintilla_send_message(SCINTILLA(sci), SCI_GETTABWIDTH, 0, 0);
    if (tab_w < 1) tab_w = 4;
    snprintf(buf, sizeof(buf), use_tabs ? "Tabs: %d" : "Spaces: %d", tab_w);
    gtk_label_set_text(GTK_LABEL(s_lbl_indent), buf);
}

void statusbar_set_language(const char *lang)
{
    if (s_lbl_lang) gtk_label_set_text(GTK_LABEL(s_lbl_lang), lang ? lang : "Normal Text");
}

void statusbar_set_encoding(const char *enc)
{
    if (s_lbl_enc) gtk_label_set_text(GTK_LABEL(s_lbl_enc), enc ? enc : "UTF-8");
}

void statusbar_set_overtype(gboolean ovr)
{
    if (s_lbl_ovr) gtk_label_set_text(GTK_LABEL(s_lbl_ovr), ovr ? "OVR" : "INS");
}
