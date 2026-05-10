#ifndef PROJECT_H
#define PROJECT_H

#include <gtk/gtk.h>

/* Create the Project Manager panel widget. Call once; embed in main layout. */
GtkWidget *project_init(GtkWidget *window);

/* Show/hide the panel. */
void     project_set_visible(gboolean v);
gboolean project_is_visible(void);

/* Open a .nppproject file (NULL = show open dialog). */
void project_open(const char *path);

/* Save the current project to its current path (or show save dialog). */
void project_save(void);

/* Close the current project. */
void project_close(void);

/* Create a new empty project (shows save dialog for name). */
void project_new(void);

#endif /* PROJECT_H */
