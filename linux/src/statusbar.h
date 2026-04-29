#ifndef STATUSBAR_H
#define STATUSBAR_H

#include <gtk/gtk.h>

GtkWidget *statusbar_init(void);
void       statusbar_update_from_sci(GtkWidget *sci);
void       statusbar_set_language(const char *lang);
void       statusbar_set_encoding(const char *enc);

#endif /* STATUSBAR_H */
