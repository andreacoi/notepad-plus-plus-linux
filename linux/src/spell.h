#ifndef SPELL_H
#define SPELL_H

#include <gtk/gtk.h>

#define SPELL_INDICATOR  8   /* Scintilla indicator slot used for misspellings */

void     spell_init(GtkWidget *window);
void     spell_on_sci_created(GtkWidget *sci);
void     spell_schedule_check(GtkWidget *sci);
void     spell_check_document(GtkWidget *sci);
void     spell_set_enabled(gboolean enabled);
gboolean spell_is_enabled(void);

/* Called from editor.c on right-click to build suggestion menu items */
void spell_populate_context_menu(GtkWidget *sci, GtkWidget *menu, int x, int y);

#endif /* SPELL_H */
