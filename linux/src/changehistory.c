#include "changehistory.h"

#define SC_MARK_FULLRECT 26
#define SC_MARK_LEFTRECT 27

static sptr_t sci_msg(GtkWidget *sci, unsigned int m, uptr_t w, sptr_t l)
{
    return scintilla_send_message(SCINTILLA(sci), m, w, l);
}

void changehistory_setup(GtkWidget *sci)
{
    sci_msg(sci, SCI_SETMARGINTYPE,      CH_MARGIN, SC_MARGIN_SYMBOL);
    sci_msg(sci, SCI_SETMARGINSENSITIVE, CH_MARGIN, 0);
    sci_msg(sci, SCI_SETMARGINWIDTHN,    CH_MARGIN, 4);
    sci_msg(sci, SCI_SETMARGINMASKN,     CH_MARGIN, (sptr_t)CH_MASK);

    /* Unsaved: gold/yellow vertical bar */
    sci_msg(sci, SCI_MARKERDEFINE,  CH_MARK_UNSAVED, SC_MARK_FULLRECT);
    sci_msg(sci, SCI_MARKERSETBACK, CH_MARK_UNSAVED, 0x00CCEE); /* BGR ~gold */
    sci_msg(sci, SCI_MARKERSETFORE, CH_MARK_UNSAVED, 0x00CCEE);

    /* Saved: green vertical bar */
    sci_msg(sci, SCI_MARKERDEFINE,  CH_MARK_SAVED, SC_MARK_FULLRECT);
    sci_msg(sci, SCI_MARKERSETBACK, CH_MARK_SAVED, 0x00AA00); /* BGR green */
    sci_msg(sci, SCI_MARKERSETFORE, CH_MARK_SAVED, 0x00AA00);
}

void changehistory_on_modified(GtkWidget *sci, Sci_Position line_start,
                                Sci_Position lines_added)
{
    Sci_Position count = (lines_added > 0 ? lines_added : 0) + 1;
    for (Sci_Position i = 0; i < count; i++) {
        Sci_Position line = line_start + i;
        int cur = (int)sci_msg(sci, SCI_MARKERGET, (uptr_t)line, 0);
        if (!(cur & (1 << CH_MARK_UNSAVED))) {
            if (cur & (1 << CH_MARK_SAVED))
                sci_msg(sci, SCI_MARKERDELETE, (uptr_t)line, CH_MARK_SAVED);
            sci_msg(sci, SCI_MARKERADD, (uptr_t)line, CH_MARK_UNSAVED);
        }
    }
}

void changehistory_on_save(GtkWidget *sci)
{
    Sci_Position total = (Sci_Position)sci_msg(sci, SCI_GETLINECOUNT, 0, 0);
    for (Sci_Position line = 0; line < total; line++) {
        int cur = (int)sci_msg(sci, SCI_MARKERGET, (uptr_t)line, 0);
        if (cur & (1 << CH_MARK_UNSAVED)) {
            sci_msg(sci, SCI_MARKERDELETE, (uptr_t)line, CH_MARK_UNSAVED);
            sci_msg(sci, SCI_MARKERADD,    (uptr_t)line, CH_MARK_SAVED);
        }
    }
}

void changehistory_next(GtkWidget *sci)
{
    Sci_Position cur_line = (Sci_Position)sci_msg(sci, SCI_LINEFROMPOSITION,
        (uptr_t)sci_msg(sci, SCI_GETCURRENTPOS, 0, 0), 0);
    Sci_Position found = (Sci_Position)sci_msg(sci,
        SCI_MARKERNEXT, (uptr_t)(cur_line + 1), (sptr_t)CH_MASK);
    if (found < 0) /* wrap around */
        found = (Sci_Position)sci_msg(sci, SCI_MARKERNEXT, 0, (sptr_t)CH_MASK);
    if (found >= 0) {
        sci_msg(sci, SCI_GOTOLINE, (uptr_t)found, 0);
        sci_msg(sci, SCI_SCROLLCARET, 0, 0);
    }
}

void changehistory_prev(GtkWidget *sci)
{
    Sci_Position cur_line = (Sci_Position)sci_msg(sci, SCI_LINEFROMPOSITION,
        (uptr_t)sci_msg(sci, SCI_GETCURRENTPOS, 0, 0), 0);
    Sci_Position from = cur_line > 0 ? cur_line - 1 : 0;
    Sci_Position found = (Sci_Position)sci_msg(sci,
        SCI_MARKERPREV, (uptr_t)from, (sptr_t)CH_MASK);
    if (found < 0) { /* wrap around */
        Sci_Position n = (Sci_Position)sci_msg(sci, SCI_GETLINECOUNT, 0, 0);
        found = (Sci_Position)sci_msg(sci,
            SCI_MARKERPREV, (uptr_t)(n > 0 ? n - 1 : 0), (sptr_t)CH_MASK);
    }
    if (found >= 0) {
        sci_msg(sci, SCI_GOTOLINE, (uptr_t)found, 0);
        sci_msg(sci, SCI_SCROLLCARET, 0, 0);
    }
}

void changehistory_revert_recent(GtkWidget *sci)
{
    sci_msg(sci, SCI_UNDO, 0, 0);
}

void changehistory_clear(GtkWidget *sci)
{
    sci_msg(sci, SCI_MARKERDELETEALL, CH_MARK_UNSAVED, 0);
    sci_msg(sci, SCI_MARKERDELETEALL, CH_MARK_SAVED,   0);
}
