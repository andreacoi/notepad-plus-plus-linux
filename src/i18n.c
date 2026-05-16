/* i18n.c — Notepad++ XML localization loader for the Linux GTK3 port. */
#include "i18n.h"
#include <glib.h>
#include <string.h>
#include <stdio.h>

#ifndef RESOURCES_DIR
#define RESOURCES_DIR "../resources"
#endif

/* Two hash tables: plain text (& stripped) and mnemonic (& → _). */
static GHashTable *s_plain    = NULL;
static GHashTable *s_mnemonic = NULL;

/* ------------------------------------------------------------------ */
/* Mnemonic conversion                                                 */
/* ------------------------------------------------------------------ */

/* & → _ for GTK mnemonic labels; && → & (literal ampersand). */
static char *conv_mnemonic(const char *s)
{
    GString *r = g_string_sized_new(strlen(s) + 4);
    while (*s) {
        if (s[0] == '&' && s[1] == '&') { g_string_append_c(r, '&'); s += 2; }
        else if (s[0] == '&')           { g_string_append_c(r, '_'); s++;     }
        else                            { g_string_append_c(r, *s++);          }
    }
    return g_string_free(r, FALSE);
}

/* Strip & markers entirely for plain text labels. */
static char *conv_plain(const char *s)
{
    GString *r = g_string_sized_new(strlen(s));
    while (*s) {
        if (s[0] == '&' && s[1] == '&') { g_string_append_c(r, '&'); s += 2; }
        else if (s[0] == '&')           { s++;                                  }
        else                            { g_string_append_c(r, *s++);           }
    }
    return g_string_free(r, FALSE);
}

static void store(const char *key, const char *raw_val)
{
    if (!key || !raw_val || !*key) return;
    g_hash_table_insert(s_plain,    g_strdup(key), conv_plain(raw_val));
    g_hash_table_insert(s_mnemonic, g_strdup(key), conv_mnemonic(raw_val));
}

/* ------------------------------------------------------------------ */
/* GMarkupParser                                                        */
/* ------------------------------------------------------------------ */

/* We track the 12 most recent ancestor element names to identify context. */
#define STACK_DEPTH 12

typedef struct {
    int  depth;
    char elems[STACK_DEPTH][80];
} PS;

static const char *anc(PS *ps, int back)
{
    int idx = ps->depth - 1 - back;   /* 0=current, 1=parent, 2=grandparent … */
    return (idx >= 0 && idx < STACK_DEPTH) ? ps->elems[idx] : "";
}

static void xml_start(GMarkupParseContext *ctx, const char *elem,
                      const char **names, const char **vals,
                      gpointer data, GError **err)
{
    (void)ctx; (void)err;
    PS *ps = data;

    /* Push element onto stack */
    if (ps->depth < STACK_DEPTH)
        g_strlcpy(ps->elems[ps->depth], elem, 80);
    ps->depth++;

    const char *p1 = anc(ps, 1);  /* parent   */
    const char *p2 = anc(ps, 2);  /* grandpar */
    const char *p3 = anc(ps, 3);  /* great-gp */

    /* ---- <Menu><Main><Entries><Item menuId="..." name="..."/> ---- */
    if (strcmp(elem, "Item") == 0
        && strcmp(p1, "Entries") == 0
        && strcmp(p2, "Main") == 0
        && strcmp(p3, "Menu") == 0)
    {
        const char *menu_id = NULL, *name = NULL;
        for (int i = 0; names[i]; i++) {
            if (strcmp(names[i], "menuId") == 0) menu_id = vals[i];
            else if (strcmp(names[i], "name") == 0)  name    = vals[i];
        }
        if (menu_id && name) {
            char key[128]; snprintf(key, sizeof(key), "menu.%s", menu_id);
            store(key, name);
        }
        return;
    }

    /* ---- <Menu><Main><SubEntries><Item subMenuId="..." name="..."/> ---- */
    if (strcmp(elem, "Item") == 0
        && strcmp(p1, "SubEntries") == 0
        && strcmp(p2, "Main") == 0
        && strcmp(p3, "Menu") == 0)
    {
        const char *sub_id = NULL, *name = NULL;
        for (int i = 0; names[i]; i++) {
            if (strcmp(names[i], "subMenuId") == 0) sub_id = vals[i];
            else if (strcmp(names[i], "name") == 0)  name   = vals[i];
        }
        if (sub_id && name) {
            char key[128]; snprintf(key, sizeof(key), "submenu.%s", sub_id);
            store(key, name);
        }
        return;
    }

    /* ---- <Menu><Main><Commands><Item id="..." name="..."/> ---- */
    if (strcmp(elem, "Item") == 0
        && strcmp(p1, "Commands") == 0
        && strcmp(p2, "Main") == 0
        && strcmp(p3, "Menu") == 0)
    {
        const char *id = NULL, *name = NULL;
        for (int i = 0; names[i]; i++) {
            if (strcmp(names[i], "id") == 0)   id   = vals[i];
            else if (strcmp(names[i], "name") == 0) name = vals[i];
        }
        if (id && name) {
            char key[128]; snprintf(key, sizeof(key), "cmd.%s", id);
            store(key, name);
        }
        return;
    }

    /* ---- <Dialog><Elem attrs…> — store all non-empty attributes ---- */
    if (strcmp(elem, "Item") != 0 && strcmp(p1, "Dialog") == 0)
    {
        char key[256];
        for (int i = 0; names[i]; i++) {
            if (!vals[i] || !vals[i][0]) continue;
            snprintf(key, sizeof(key), "dlg.%s.%s", elem, names[i]);
            store(key, vals[i]);
        }
        return;
    }

    /* ---- <Dialog><Elem><Item id="..." name="..."/> (direct child) ---- */
    if (strcmp(elem, "Item") == 0 && strcmp(p2, "Dialog") == 0)
    {
        const char *id = NULL, *name = NULL;
        for (int i = 0; names[i]; i++) {
            if (strcmp(names[i], "id") == 0)   id   = vals[i];
            else if (strcmp(names[i], "name") == 0) name = vals[i];
        }
        if (id && name) {
            char key[256]; snprintf(key, sizeof(key), "dlg.%s.%s", p1, id);
            store(key, name);
        }
        return;
    }

    /* ---- <Dialog><Elem><Sub><Item …> (nested one level deeper) ---- */
    if (strcmp(elem, "Item") == 0 && strcmp(p3, "Dialog") == 0)
    {
        const char *id = NULL, *name = NULL;
        for (int i = 0; names[i]; i++) {
            if (strcmp(names[i], "id") == 0)   id   = vals[i];
            else if (strcmp(names[i], "name") == 0) name = vals[i];
        }
        if (id && name) {
            /* p2 = intermediate (SubDialog/Menu/…), p3 = dialog elem name
             * Key under the named dialog element, not the intermediate. */
            char key[256]; snprintf(key, sizeof(key), "dlg.%s.%s", p2, id);
            store(key, name);
        }
        return;
    }

    /* ---- <MessageBox><Elem attrs…> ---- */
    if (strcmp(elem, "Item") != 0 && strcmp(p1, "MessageBox") == 0)
    {
        char key[256];
        for (int i = 0; names[i]; i++) {
            if (!vals[i] || !vals[i][0]) continue;
            snprintf(key, sizeof(key), "msg.%s.%s", elem, names[i]);
            store(key, vals[i]);
        }
        return;
    }
}

static void xml_end(GMarkupParseContext *ctx, const char *elem,
                    gpointer data, GError **err)
{
    (void)ctx; (void)elem; (void)err;
    PS *ps = data;
    if (ps->depth > 0) ps->depth--;
}

static const GMarkupParser kParser = {
    xml_start, xml_end, NULL, NULL, NULL
};

static void parse_file(const char *path)
{
    gchar  *xml = NULL;
    gsize   len = 0;
    GError *err = NULL;

    if (!g_file_get_contents(path, &xml, &len, &err)) {
        g_printerr("i18n: cannot read %s: %s\n", path, err->message);
        g_error_free(err);
        return;
    }

    PS ps;
    memset(&ps, 0, sizeof(ps));
    GMarkupParseContext *ctx = g_markup_parse_context_new(&kParser, 0, &ps, NULL);

    if (!g_markup_parse_context_parse(ctx, xml, (gssize)len, &err)) {
        g_printerr("i18n: parse error in %s: %s\n", path, err->message);
        g_error_free(err);
    }
    g_markup_parse_context_free(ctx);
    g_free(xml);
}

/* ------------------------------------------------------------------ */
/* Locale → filename stem mapping                                      */
/* ------------------------------------------------------------------ */

static const struct { const char *code; const char *stem; } kLangMap[] = {
    /* ISO 639-1 and common BCP 47 codes */
    {"ab",    "abkhazian"},
    {"af",    "afrikaans"},
    {"sq",    "albanian"},
    {"am",    "amharic"},
    {"ar",    "arabic"},
    {"an",    "aragonese"},
    {"hy",    "armenian"},
    {"as",    "assamese"},
    {"ay",    "aymara"},
    {"az",    "azerbaijani"},
    {"bm",    "bambara"},
    {"eu",    "basque"},
    {"be",    "belarusian"},
    {"bn",    "bengali"},
    {"bho",   "bhojpuri"},
    {"bs",    "bosnian"},
    {"pt_BR", "brazilian_portuguese"},
    {"br",    "breton"},
    {"bg",    "bulgarian"},
    {"ca",    "catalan"},
    {"ceb",   "cebuano"},
    {"ny",    "chichewa"},
    {"zh_CN", "chineseSimplified"},
    {"zh",    "chineseSimplified"},
    {"co",    "corsican"},
    {"hr",    "croatian"},
    {"cs",    "czech"},
    {"da",    "danish"},
    {"dv",    "dhivehi"},
    {"doi",   "dogri"},
    {"nl",    "dutch"},
    {"en",    "english"},
    {"eo",    "esperanto"},
    {"et",    "estonian"},
    {"ee",    "ewe"},
    {"ext",   "extremaduran"},
    {"fa",    "farsi"},
    {"fi",    "finnish"},
    {"fr",    "french"},
    {"fur",   "friulian"},
    {"gl",    "galician"},
    {"ka",    "georgian"},
    {"de",    "german"},
    {"el",    "greek"},
    {"gn",    "guarani"},
    {"gu",    "gujarati"},
    {"ha",    "hausa"},
    {"haw",   "hawaiian"},
    {"he",    "hebrew"},
    {"hi",    "hindi"},
    {"hmn",   "hmong"},
    {"yue",   "hongKongCantonese"},
    {"hu",    "hungarian"},
    {"ig",    "igbo"},
    {"ilo",   "ilocano"},
    {"id",    "indonesian"},
    {"ga",    "irish"},
    {"it",    "italian"},
    {"ja",    "japanese"},
    {"jv",    "javanese"},
    {"kab",   "kabyle"},
    {"kn",    "kannada"},
    {"kk",    "kazakh"},
    {"rw",    "kinyarwanda"},
    {"kok",   "konkani"},
    {"ko",    "korean"},
    {"kri",   "krio"},
    {"ku",    "kurdish"},
    {"ky",    "kyrgyz"},
    {"lo",    "lao"},
    {"lv",    "latvian"},
    {"lij",   "ligurian"},
    {"ln",    "lingala"},
    {"lt",    "lithuanian"},
    {"lb",    "luxembourgish"},
    {"mk",    "macedonian"},
    {"mai",   "maithili"},
    {"mg",    "malagasy"},
    {"ml",    "malayalam"},
    {"ms",    "malay"},
    {"mr",    "marathi"},
    {"lus",   "mizo"},
    {"mn",    "mongolian"},
    {"my",    "myanmar"},
    {"ne",    "nepali"},
    {"nb",    "norwegian"},
    {"no",    "norwegian"},
    {"nn",    "nynorsk"},
    {"oc",    "occitan"},
    {"or",    "odia"},
    {"ps",    "pashto"},
    {"pl",    "polish"},
    {"pt",    "portuguese"},
    {"pa",    "punjabi"},
    {"qu",    "quechua"},
    {"ro",    "romanian"},
    {"ru",    "russian"},
    {"sgs",   "samogitian"},
    {"sc",    "sardinian"},
    {"nso",   "sepedi"},
    {"sr_Cyrl","serbianCyrillic"},
    {"sr",    "serbian"},
    {"st",    "sesotho"},
    {"sn",    "shona"},
    {"si",    "sinhala"},
    {"sk",    "slovak"},
    {"sl",    "slovenian"},
    {"so",    "somali"},
    {"es_AR", "spanish_ar"},
    {"es",    "spanish"},
    {"su",    "sundanese"},
    {"sw",    "swahili"},
    {"sv",    "swedish"},
    {"tl",    "tagalog"},
    {"zh_TW", "taiwaneseMandarin"},
    {"tg",    "tajikCyrillic"},
    {"ta",    "tamil"},
    {"tt",    "tatar"},
    {"te",    "telugu"},
    {"th",    "thai"},
    {"ti",    "tigrinya"},
    {"ts",    "tsonga"},
    {"tr",    "turkish"},
    {"tk",    "turkmen"},
    {"tw",    "twi"},
    {"uk",    "ukrainian"},
    {"ur",    "urdu"},
    {"ug",    "uyghur"},
    {"uz_Cyrl","uzbekCyrillic"},
    {"uz",    "uzbek"},
    {"vec",   "venetian"},
    {"vi",    "vietnamese"},
    {"cy",    "welsh"},
    {"xh",    "xhosa"},
    {"yo",    "yoruba"},
    {"zu",    "zulu"},
    {NULL, NULL}
};

/* Strip encoding suffix ("it_IT.UTF-8" → "it_IT") and normalise. */
static void normalise_locale(const char *in, char *out, int out_size)
{
    int i = 0;
    while (in[i] && in[i] != '.' && in[i] != '@' && i < out_size - 1) {
        out[i] = in[i];
        i++;
    }
    out[i] = '\0';
}

static const char *locale_to_stem(const char *locale)
{
    char norm[64];
    normalise_locale(locale, norm, sizeof(norm));

    /* Try exact match first, then prefix up to '_'. */
    for (int pass = 0; pass < 2; pass++) {
        for (int i = 0; kLangMap[i].code; i++) {
            if (strcmp(kLangMap[i].code, norm) == 0)
                return kLangMap[i].stem;
        }
        /* Second pass: strip country code ("it_IT" → "it") */
        char *under = strchr(norm, '_');
        if (!under) break;
        *under = '\0';
    }
    return NULL;
}

/* ------------------------------------------------------------------ */
/* Public API                                                          */
/* ------------------------------------------------------------------ */

void i18n_init(void)
{
    s_plain    = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, g_free);
    s_mnemonic = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, g_free);

    const gchar * const *langs = g_get_language_names();
    char path[1024] = "";

    for (int i = 0; langs[i] && !path[0]; i++) {
        const char *stem = locale_to_stem(langs[i]);
        if (!stem) continue;
        snprintf(path, sizeof(path), RESOURCES_DIR "/localization/%s.xml", stem);
        if (!g_file_test(path, G_FILE_TEST_EXISTS))
            path[0] = '\0';
    }

    if (!path[0])
        snprintf(path, sizeof(path), RESOURCES_DIR "/localization/english.xml");

    parse_file(path);
}

const char *i18n_str(const char *key, const char *fallback)
{
    if (!s_plain) return fallback;
    const char *v = g_hash_table_lookup(s_plain, key);
    return v ? v : fallback;
}

const char *i18n_mnemonic(const char *key, const char *fallback)
{
    if (!s_mnemonic) return fallback;
    const char *v = g_hash_table_lookup(s_mnemonic, key);
    return v ? v : fallback;
}
