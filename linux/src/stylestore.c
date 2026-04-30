/* stylestore.c — Syntax highlighting style store for the Linux GTK3 port.
 * Ports NPPStyleStore / applyDefaultTheme / applyGlobalStyleColors /
 * applyLexerColors from StyleConfiguratorWindowController.mm + EditorView.mm.
 *
 * Parses stylers.model.xml (same XML the macOS port uses) with GLib's
 * GMarkupParser. Config override at $HOME/.config/npp/stylers.xml.
 */
#include "stylestore.h"
#include "sci_c.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <ctype.h>

#ifndef RESOURCES_DIR
#define RESOURCES_DIR "../../resources"
#endif

/* ------------------------------------------------------------------ */
/* Data model — mirrors NPPStyleEntry / NPPLexer                      */
/* ------------------------------------------------------------------ */

typedef struct {
    char name[80];    /* "Default Style", "COMMENT", etc. */
    int  style_id;    /* Scintilla style index             */
    int  fg;          /* BGR, -1 = not set                 */
    int  bg;          /* BGR, -1 = not set                 */
    int  bold;        /* 0/1, -1 = not set                 */
    int  italic;      /* 0/1, -1 = not set                 */
    int  underline;   /* 0/1, -1 = not set                 */
} StyleEntry;

typedef struct {
    char        id[64];     /* "cpp", "python", "global", etc. */
    StyleEntry *entries;
    int         count;
    int         cap;
} LexerBlock;

static LexerBlock *s_blocks      = NULL;
static int         s_block_count = 0;
static int         s_block_cap   = 0;
static gboolean    s_loaded      = FALSE;

/* ------------------------------------------------------------------ */
/* Color helpers — RRGGBB → Scintilla BGR (same as macOS sciColor())  */
/* ------------------------------------------------------------------ */

static int parse_rrggbb(const char *hex)
{
    if (!hex || !*hex) return -1;
    if (*hex == '#') hex++;
    size_t l = strlen(hex);
    if (l != 6) return -1;
    unsigned long v = strtoul(hex, NULL, 16);
    int r = (int)((v >> 16) & 0xFF);
    int g = (int)((v >>  8) & 0xFF);
    int b = (int)( v        & 0xFF);
    return r | (g << 8) | (b << 16);   /* Scintilla BGR / Windows COLORREF */
}

/* ------------------------------------------------------------------ */
/* Block management                                                    */
/* ------------------------------------------------------------------ */

static LexerBlock *get_or_create_block(const char *id)
{
    for (int i = 0; i < s_block_count; i++)
        if (strcmp(s_blocks[i].id, id) == 0)
            return &s_blocks[i];

    if (s_block_count >= s_block_cap) {
        s_block_cap = s_block_cap ? s_block_cap * 2 : 64;
        s_blocks = g_realloc(s_blocks, (gsize)(s_block_cap * (int)sizeof(LexerBlock)));
    }
    LexerBlock *b = &s_blocks[s_block_count++];
    memset(b, 0, sizeof(*b));
    g_strlcpy(b->id, id, sizeof(b->id));
    return b;
}

static void block_add(LexerBlock *b, const StyleEntry *e)
{
    if (b->count >= b->cap) {
        b->cap = b->cap ? b->cap * 2 : 16;
        b->entries = g_realloc(b->entries, (gsize)(b->cap * (int)sizeof(StyleEntry)));
    }
    b->entries[b->count++] = *e;
}

/* ------------------------------------------------------------------ */
/* GMarkupParser callbacks (SAX-style, same idea as macOS raw-scan)   */
/* ------------------------------------------------------------------ */

typedef struct {
    gboolean in_global;
    char     current_lexer[64];
} PCtx;

static const char *attr_val(const gchar **names, const gchar **vals,
                             const char *key)
{
    for (int i = 0; names[i]; i++)
        if (strcmp(names[i], key) == 0)
            return vals[i];
    return NULL;
}

static void on_start(GMarkupParseContext *ctx,
                     const gchar *el,
                     const gchar **names,
                     const gchar **vals,
                     gpointer ud,
                     GError **err)
{
    (void)ctx; (void)err;
    PCtx *pc = (PCtx *)ud;

    if (strcmp(el, "GlobalStyles") == 0) {
        pc->in_global = TRUE;
        g_strlcpy(pc->current_lexer, "global", sizeof(pc->current_lexer));
        return;
    }
    if (strcmp(el, "LexerType") == 0) {
        pc->in_global = FALSE;
        const char *name = attr_val(names, vals, "name");
        if (name)
            g_strlcpy(pc->current_lexer, name, sizeof(pc->current_lexer));
        else
            pc->current_lexer[0] = '\0';
        return;
    }

    gboolean is_widget = (strcmp(el, "WidgetStyle") == 0);
    gboolean is_words  = (strcmp(el, "WordsStyle")  == 0);

    if (!((is_widget && pc->in_global) || (is_words && !pc->in_global)))
        return;
    if (!pc->current_lexer[0]) return;

    StyleEntry e;
    memset(&e, 0, sizeof(e));
    e.fg = e.bg = e.bold = e.italic = e.underline = -1;

    const char *v;
    if ((v = attr_val(names, vals, "name")))
        g_strlcpy(e.name, v, sizeof(e.name));
    if ((v = attr_val(names, vals, "styleID")))
        e.style_id = atoi(v);
    if ((v = attr_val(names, vals, "fgColor")) && strlen(v) == 6)
        e.fg = parse_rrggbb(v);
    if ((v = attr_val(names, vals, "bgColor")) && strlen(v) == 6)
        e.bg = parse_rrggbb(v);
    if ((v = attr_val(names, vals, "fontStyle"))) {
        int fs = atoi(v);
        e.bold      = (fs & 1) ? 1 : 0;
        e.italic    = (fs & 2) ? 1 : 0;
        e.underline = (fs & 4) ? 1 : 0;
    }

    LexerBlock *b = get_or_create_block(pc->current_lexer);
    block_add(b, &e);
}

static void on_end(GMarkupParseContext *ctx,
                   const gchar *el,
                   gpointer ud,
                   GError **err)
{
    (void)ctx; (void)err;
    PCtx *pc = (PCtx *)ud;
    if (strcmp(el, "GlobalStyles") == 0) pc->in_global = FALSE;
}

/* Parse a single XML file, merging into s_blocks. */
static void parse_file(const char *path)
{
    gchar  *contents = NULL;
    gsize   len      = 0;
    GError *err      = NULL;

    if (!g_file_get_contents(path, &contents, &len, &err)) {
        if (err) { g_warning("stylestore: %s", err->message); g_error_free(err); }
        return;
    }

    GMarkupParser parser = { on_start, on_end, NULL, NULL, NULL };
    PCtx pc = { FALSE, "" };
    GMarkupParseContext *ctx =
        g_markup_parse_context_new(&parser, G_MARKUP_DEFAULT_FLAGS, &pc, NULL);

    err = NULL;
    if (!g_markup_parse_context_parse(ctx, contents, (gssize)len, &err))
        g_warning("stylestore: parse error in %s: %s", path,
                  err ? err->message : "?");
    if (err) g_error_free(err);
    g_markup_parse_context_free(ctx);
    g_free(contents);
}

/* ------------------------------------------------------------------ */
/* Public: init                                                        */
/* ------------------------------------------------------------------ */

void stylestore_init(const char *xml_path)
{
    if (s_loaded) return;
    s_loaded = TRUE;

    /* 1. Load bundled model defaults */
    char model_path[512];
    if (xml_path)
        g_strlcpy(model_path, xml_path, sizeof(model_path));
    else
        snprintf(model_path, sizeof(model_path),
                 RESOURCES_DIR "/stylers.model.xml");

    parse_file(model_path);

    /* 2. Overlay user overrides from $HOME/.config/npp/stylers.xml
     *    (XDG config location for the Linux port — mirrors ~/.notepad++/stylers.xml on macOS) */
    const char *home = g_get_home_dir();
    if (home) {
        char user_path[512];
        snprintf(user_path, sizeof(user_path),
                 "%s/.config/npp/stylers.xml", home);
        if (g_file_test(user_path, G_FILE_TEST_EXISTS))
            parse_file(user_path);
    }
}

/* ------------------------------------------------------------------ */
/* SCI helper                                                          */
/* ------------------------------------------------------------------ */

static sptr_t sci_msg(GtkWidget *sci, unsigned int m, uptr_t w, sptr_t l)
{
    return scintilla_send_message(SCINTILLA(sci), m, w, l);
}

static void apply_entry(GtkWidget *sci, int sid, const StyleEntry *e)
{
    if (e->fg >= 0) sci_msg(sci, SCI_STYLESETFORE, (uptr_t)sid, e->fg);
    if (e->bg >= 0) sci_msg(sci, SCI_STYLESETBACK, (uptr_t)sid, e->bg);
    if (e->bold      >= 0) sci_msg(sci, SCI_STYLESETBOLD,      (uptr_t)sid, e->bold);
    if (e->italic    >= 0) sci_msg(sci, SCI_STYLESETITALIC,    (uptr_t)sid, e->italic);
    if (e->underline >= 0) sci_msg(sci, SCI_STYLESETUNDERLINE, (uptr_t)sid, e->underline);
}

/* Look up a global WidgetStyle by name (matches NPPStyleStore globalStyleNamed:) */
static const StyleEntry *find_global(const char *name)
{
    for (int i = 0; i < s_block_count; i++) {
        if (strcmp(s_blocks[i].id, "global") != 0) continue;
        LexerBlock *b = &s_blocks[i];
        for (int j = 0; j < b->count; j++)
            if (strcmp(b->entries[j].name, name) == 0)
                return &b->entries[j];
    }
    return NULL;
}

/* ------------------------------------------------------------------ */
/* Public: apply functions                                             */
/* ------------------------------------------------------------------ */

/* Set STYLE_DEFAULT — must come BEFORE SCI_STYLECLEARALL.
 * Mirrors the first block of applyDefaultTheme: / applyThemeColors:. */
void stylestore_apply_default(GtkWidget *sci)
{
    const StyleEntry *def = find_global("Default Style");
    if (!def) return;

    /* Apply font/color to STYLE_DEFAULT */
    apply_entry(sci, STYLE_DEFAULT, def);

    /* Default caret = same as foreground if not overridden */
    if (def->fg >= 0)
        sci_msg(sci, SCI_SETCARETFORE, (uptr_t)def->fg, 0);
}

/* Apply global override styles that SCI_STYLECLEARALL resets.
 * Mirrors applyGlobalStyleColors: + the global part of applyDefaultTheme:. */
void stylestore_apply_global(GtkWidget *sci)
{
    /* Line number margin (styleID=33) */
    const StyleEntry *ln = find_global("Line number margin");
    if (ln) apply_entry(sci, STYLE_LINENUMBER, ln);

    /* Indent guideline (styleID=37) */
    const StyleEntry *ig = find_global("Indent guideline style");
    if (ig) apply_entry(sci, 37, ig);

    /* Brace highlight (styleID=34) */
    const StyleEntry *bh = find_global("Brace highlight style");
    if (bh) apply_entry(sci, STYLE_BRACELIGHT, bh);

    /* Bad brace (styleID=35) */
    const StyleEntry *bb = find_global("Bad brace colour");
    if (bb) apply_entry(sci, STYLE_BRACEBAD, bb);

    /* Caret colour */
    const StyleEntry *cc = find_global("Caret colour");
    if (cc && cc->fg >= 0)
        sci_msg(sci, SCI_SETCARETFORE, (uptr_t)cc->fg, 0);

    /* Current line highlight */
    const StyleEntry *cl = find_global("Current line background colour");
    if (cl && cl->bg >= 0) {
        sci_msg(sci, SCI_SETCARETLINEVISIBLE, 1, 0);
        sci_msg(sci, SCI_SETCARETLINEBACK,    (uptr_t)cl->bg, 0);
    }

    /* Selection background */
    const StyleEntry *sel = find_global("Selected text colour");
    if (sel && sel->bg >= 0)
        sci_msg(sci, SCI_SETSELBACK, 1, sel->bg);

    /* Whitespace symbol colour */
    const StyleEntry *ws = find_global("White space symbol");
    if (ws && ws->fg >= 0)
        sci_msg(sci, SCI_SETWHITESPACEFORE, 1, ws->fg);

    /* Fold margin colours */
    const StyleEntry *fm = find_global("Fold margin");
    int fmbg = (fm && fm->bg >= 0) ? fm->bg : 0xE9E9E9;
    sci_msg(sci, SCI_SETFOLDMARGINCOLOUR,   1, fmbg);
    sci_msg(sci, SCI_SETFOLDMARGINHICOLOUR, 1, fmbg);

    /* Fold marker foreground/background */
    const StyleEntry *fold = find_global("Fold");
    int fold_fg = (fold && fold->fg >= 0) ? fold->fg : 0x808080;
    int fold_bg = (fold && fold->bg >= 0) ? fold->bg : 0xF3F3F3;
    for (int mn = SC_MARKNUM_FOLDER; mn <= SC_MARKNUM_FOLDEROPEN; mn++) {
        sci_msg(sci, SCI_MARKERSETFORE, (uptr_t)mn, fold_fg);
        sci_msg(sci, SCI_MARKERSETBACK, (uptr_t)mn, fold_bg);
    }
    sci_msg(sci, SCI_MARKERENABLEHIGHLIGHT, 1, 0);
}

/* Apply per-language colors from <LexerType name="lexer_id"> entries.
 * Mirrors applyLexerColors:. */
void stylestore_apply_lexer(GtkWidget *sci, const char *lexer_id)
{
    if (!s_loaded || !lexer_id || !*lexer_id) return;

    /* Lower-case lookup, same as macOS lowercaseString */
    char lid[64];
    g_strlcpy(lid, lexer_id, sizeof(lid));
    for (int i = 0; lid[i]; i++) lid[i] = (char)tolower((unsigned char)lid[i]);

    LexerBlock *b = NULL;
    for (int i = 0; i < s_block_count; i++) {
        if (strcmp(s_blocks[i].id, lid) == 0) {
            b = &s_blocks[i];
            break;
        }
    }
    if (!b || !b->count) return;

    for (int j = 0; j < b->count; j++)
        apply_entry(sci, b->entries[j].style_id, &b->entries[j]);
}
