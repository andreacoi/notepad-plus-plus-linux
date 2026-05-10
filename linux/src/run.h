#ifndef RUN_H
#define RUN_H

#include <gtk/gtk.h>

/* Show Run… dialog. Substitutes %FILE%/%DIR%/%NAME%/%EXT% using `filepath`.
   Pass NULL for filepath when no file is open. */
void run_dialog(GtkWindow *parent, const char *filepath);

/* Show Modify Shortcut / Delete Command… dialog. */
void run_manage_dialog(GtkWindow *parent, const char *filepath);

#endif /* RUN_H */
