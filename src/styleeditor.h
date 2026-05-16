#ifndef STYLEEDITOR_H
#define STYLEEDITOR_H

#include <gtk/gtk.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Callback invoked when the user applies or saves styles. */
typedef void (*SEApplyFn)(void);

/* Show the Style Configurator dialog.
 * on_apply is called (if non-NULL) when styles should be re-applied to
 * open editors (on Save or Apply to Editors).  The dialog is modal but
 * non-blocking: this function returns immediately after showing it. */
void styleeditor_show(GtkWidget *parent, SEApplyFn on_apply);

#ifdef __cplusplus
}
#endif

#endif /* STYLEEDITOR_H */
