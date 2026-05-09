#ifndef DOCLIST_H
#define DOCLIST_H

#include <gtk/gtk.h>

/* Create the panel widget; embed the returned widget in the layout. */
GtkWidget *doclist_init(void);

/* Rebuild the list to match current editor state. */
void doclist_refresh(void);

/* Highlight the row that corresponds to the given notebook page. */
void doclist_sync_selection(int page);

/* Show / hide the panel. */
void     doclist_set_visible(gboolean v);
gboolean doclist_is_visible(void);

#endif /* DOCLIST_H */
