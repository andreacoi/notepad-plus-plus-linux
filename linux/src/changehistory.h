#ifndef CHANGEHISTORY_H
#define CHANGEHISTORY_H

#include <gtk/gtk.h>
#include "sci_c.h"

/* Margin and marker slots reserved for change history */
#define CH_MARGIN       4
#define CH_MARK_UNSAVED 5   /* yellow — modified since last save  */
#define CH_MARK_SAVED   6   /* green  — saved in a previous round */
#define CH_MASK         ((1 << CH_MARK_UNSAVED) | (1 << CH_MARK_SAVED))

/* Configure margin 4 and markers 5/6 on a new Scintilla widget. */
void changehistory_setup(GtkWidget *sci);

/* Called from SCN_MODIFIED: mark the lines touched by the edit. */
void changehistory_on_modified(GtkWidget *sci, Sci_Position line_start,
                                Sci_Position lines_added);

/* Called from SCN_SAVEPOINTREACHED: convert unsaved→saved markers. */
void changehistory_on_save(GtkWidget *sci);

/* Jump to the next / previous changed line. */
void changehistory_next(GtkWidget *sci);
void changehistory_prev(GtkWidget *sci);

/* Undo the most recent edit group. */
void changehistory_revert_recent(GtkWidget *sci);

/* Wipe all change markers (Clear All Changes). */
void changehistory_clear(GtkWidget *sci);

#endif /* CHANGEHISTORY_H */
