#ifndef SEARCHRESULTS_H
#define SEARCHRESULTS_H

#include <gtk/gtk.h>

/* Create the panel widget (call once, pack into the window). */
GtkWidget *searchresults_init(void);

/* Called by findinfiles to feed results.
 * Call begin() once, then add_file()/add_hit() per match,
 * then end() to finalise and show the panel. */
void searchresults_begin(const char *needle);
void searchresults_add_file(const char *filepath, int hit_count);
void searchresults_add_hit(const char *filepath, int line, const char *text);
void searchresults_end(int total_hits, int total_files);

/* Show / hide the panel. */
void     searchresults_set_visible(gboolean v);
gboolean searchresults_is_visible(void);

#endif /* SEARCHRESULTS_H */
