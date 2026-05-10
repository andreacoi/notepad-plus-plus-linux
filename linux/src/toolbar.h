#ifndef TOOLBAR_H
#define TOOLBAR_H

#include <gtk/gtk.h>

/* Build and return the GtkToolbar widget. Call once, embed in the main vbox. */
GtkWidget *toolbar_init(GtkWidget *parent_window);

/* Refresh toggle-button states (wrap, allchars, indent, monitoring) from sci. */
void toolbar_sync_toggles(GtkWidget *sci);

/* Sync panel toggle buttons to actual panel visibility (call after any show/hide). */
void toolbar_sync_panels(void);

/* Enable/disable macro toolbar buttons based on current recording state. */
void toolbar_update_macro_buttons(void);

#endif /* TOOLBAR_H */
