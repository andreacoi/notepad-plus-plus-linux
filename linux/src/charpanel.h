#ifndef CHARPANEL_H
#define CHARPANEL_H

#include <gtk/gtk.h>

/* Create the Character Panel widget. Call once; embed in the main window. */
GtkWidget *charpanel_init(GtkWidget *window);

/* Show/hide the panel. */
void     charpanel_set_visible(gboolean v);
gboolean charpanel_is_visible(void);

#endif /* CHARPANEL_H */
