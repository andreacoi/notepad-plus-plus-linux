#ifndef STYLESTORE_H
#define STYLESTORE_H

#include <gtk/gtk.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Load styles from stylers.model.xml. Call once at startup.
 * Falls back to RESOURCES_DIR/stylers.model.xml if xml_path is NULL. */
void stylestore_init(const char *xml_path);

/* Set STYLE_DEFAULT from the "Default Style" global entry.
 * Must be called BEFORE SCI_STYLECLEARALL so the values propagate. */
void stylestore_apply_default(GtkWidget *sci);

/* Apply global style overrides (line numbers, caret, selection, etc.).
 * Must be called AFTER SCI_STYLECLEARALL. */
void stylestore_apply_global(GtkWidget *sci);

/* Apply per-language colors for the Lexilla lexer name (e.g. "cpp").
 * Must be called AFTER SCI_STYLECLEARALL and after installing the lexer. */
void stylestore_apply_lexer(GtkWidget *sci, const char *lexer_id);

#ifdef __cplusplus
}
#endif

#endif /* STYLESTORE_H */
