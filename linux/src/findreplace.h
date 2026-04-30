#ifndef FINDREPLACE_H
#define FINDREPLACE_H

#include <gtk/gtk.h>

/* Show (or raise) the Find/Replace dialog.
 * parent_window: the main application window (used for positioning).
 * find_text:     pre-fill the "Find what" field if non-NULL.
 * show_replace:  TRUE to show the Replace widgets, FALSE for Find-only. */
void findreplace_show(GtkWidget *parent_window, const char *find_text, gboolean show_replace);

/* Must be called whenever the active Scintilla widget changes. */
void findreplace_set_sci(GtkWidget *sci);

#endif /* FINDREPLACE_H */
