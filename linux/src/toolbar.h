#ifndef TOOLBAR_H
#define TOOLBAR_H

#include <gtk/gtk.h>

/* Build and return the GtkToolbar widget. Call once, embed in the main vbox. */
GtkWidget *toolbar_init(GtkWidget *parent_window);

/* Refresh toggle-button states (wrap, allchars, indent) from the current doc. */
void toolbar_sync_toggles(GtkWidget *sci);

#endif /* TOOLBAR_H */
