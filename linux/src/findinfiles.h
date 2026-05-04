#ifndef FINDINFILES_H
#define FINDINFILES_H

#include <gtk/gtk.h>

/* Show (or raise) the Find in Files dialog.
 * find_text: pre-fill the search entry if non-NULL. */
void findinfiles_show(GtkWidget *parent, const char *find_text);

#endif /* FINDINFILES_H */
