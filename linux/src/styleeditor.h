#ifndef STYLEEDITOR_H
#define STYLEEDITOR_H

#include <gtk/gtk.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Show the Style Configurator dialog (modal).
 * parent may be NULL.  On close the caller should call
 * editor_reapply_styles() if the return value is TRUE. */
gboolean styleeditor_show(GtkWidget *parent);

#ifdef __cplusplus
}
#endif

#endif /* STYLEEDITOR_H */
