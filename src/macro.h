#ifndef MACRO_H
#define MACRO_H

#include <gtk/gtk.h>
#include "sci_c.h"

/* Start/stop Scintilla macro recording. */
void macro_start_recording(GtkWidget *sci);
void macro_stop_recording(GtkWidget *sci);

/* Called from SCN_MACRORECORD: store one recorded step. */
void macro_on_record(unsigned int msg, uptr_t wp, sptr_t lp);

/* Play back the stored macro once, or n times (prompts for n). */
void macro_playback(GtkWidget *sci);
void macro_playback_n(GtkWidget *sci, GtkWindow *parent);

/* State queries */
gboolean macro_is_recording(void);
gboolean macro_has_macro(void);

/* Named macro management (item 66) */
void macro_save_as_dialog(GtkWidget *sci, GtkWindow *parent);
void macro_manage_dialog(GtkWidget *sci, GtkWindow *parent);
void macro_trim_and_save(GtkWidget *sci);

/* Build dynamic saved-macro menu items into `menu` (called from main.c). */
void macro_populate_saved_menu(GtkWidget *menu, GtkWidget *sci);

#endif /* MACRO_H */
