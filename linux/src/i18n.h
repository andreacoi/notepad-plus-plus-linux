#ifndef I18N_H
#define I18N_H

/* Detect system locale, load matching Notepad++ XML localization file,
 * and expose translated strings by key.
 *
 * Key scheme (mirrors the XML structure):
 *   menu.{menuId}           – top-level menu bar entries
 *   cmd.{id}                – numbered menu commands
 *   dlg.{Elem}.{attr}       – dialog element attributes (e.g. dlg.Find.titleFind)
 *   dlg.{Elem}.{id}         – dialog item by numeric id
 *   msg.{Elem}.{attr}       – MessageBox element attributes
 *
 * i18n_str      – plain text (mnemonic & stripped)
 * i18n_mnemonic – GTK mnemonic text (& replaced with _)
 *
 * Both return `fallback` when the key is not present in the loaded translation.
 */

void        i18n_init(void);
const char *i18n_str     (const char *key, const char *fallback);
const char *i18n_mnemonic(const char *key, const char *fallback);

/* Convenience macros */
#define T(key, fb)  i18n_str(key, fb)
#define TM(key, fb) i18n_mnemonic(key, fb)

#endif /* I18N_H */
