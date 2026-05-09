#include "spell.h"
#include "sci_c.h"
#include <gtk/gtk.h>
#include <dlfcn.h>
#include <string.h>
#include <stdlib.h>
#include <locale.h>

/* ------------------------------------------------------------------ */
/* Scintilla indicator slot for spelling errors                        */
/* ------------------------------------------------------------------ */

#define INDIC_SQUIGGLE   1
#define SPELL_RED_BGR    0x0000FF   /* red in Scintilla BGR format     */
#define MAX_CHECK_BYTES  200000

/* ------------------------------------------------------------------ */
/* enchant-2 runtime binding                                           */
/* ------------------------------------------------------------------ */

typedef struct _EnchantBroker EnchantBroker;
typedef struct _EnchantDict   EnchantDict;

typedef EnchantBroker *(*fn_broker_init)(void);
typedef void           (*fn_broker_free)(EnchantBroker *);
typedef EnchantDict   *(*fn_broker_request_dict)(EnchantBroker *, const char *tag);
typedef void           (*fn_broker_free_dict)(EnchantBroker *, EnchantDict *);
typedef int            (*fn_dict_check)(EnchantDict *, const char *word, ssize_t len);
typedef char         **(*fn_dict_suggest)(EnchantDict *, const char *word, ssize_t len, size_t *out_n);
typedef void           (*fn_dict_free_string_list)(EnchantDict *, char **str_list);
typedef void           (*fn_dict_add)(EnchantDict *, const char *word, ssize_t len);
typedef void           (*fn_dict_add_to_session)(EnchantDict *, const char *word, ssize_t len);

static void           *s_lib               = NULL;
static EnchantBroker  *s_broker            = NULL;
static EnchantDict    *s_dict              = NULL;

static fn_broker_init           p_broker_init;
static fn_broker_free           p_broker_free;
static fn_broker_request_dict   p_broker_request_dict;
static fn_broker_free_dict      p_broker_free_dict;
static fn_dict_check            p_dict_check;
static fn_dict_suggest          p_dict_suggest;
static fn_dict_free_string_list p_dict_free_string_list;
static fn_dict_add              p_dict_add;
static fn_dict_add_to_session   p_dict_add_to_session;

/* ------------------------------------------------------------------ */
/* Module state                                                        */
/* ------------------------------------------------------------------ */

static gboolean  s_enabled         = FALSE;
static gboolean  s_available       = FALSE; /* library loaded + dict open */
static GtkWidget *s_window         = NULL;

/* Per-sci debounce timer ids (store in GObject data) */
#define SPELL_TIMER_KEY "spell-timer-id"

/* ------------------------------------------------------------------ */
/* Internal helpers                                                    */
/* ------------------------------------------------------------------ */

static sptr_t sci(GtkWidget *w, unsigned int m, uptr_t wp, sptr_t lp)
{
    return scintilla_send_message(SCINTILLA(w), m, wp, lp);
}

static void setup_indicator(GtkWidget *w)
{
    sci(w, SCI_SETINDICATORCURRENT, SPELL_INDICATOR, 0);
    sci(w, SCI_INDICSETSTYLE,       SPELL_INDICATOR, INDIC_SQUIGGLE);
    sci(w, SCI_INDICSETFORE,        SPELL_INDICATOR, SPELL_RED_BGR);
}

/* UTF-8 aware: returns TRUE if the char is a word constituent */
static gboolean is_word_char(gunichar c)
{
    return g_unichar_isalpha(c) || c == '\'';
}

/* Returns whether the word is spell-check-worthy:
 * – at least 3 chars
 * – not all-uppercase (acronyms)
 * – contains at least one lowercase letter                           */
static gboolean should_check(const char *word, int len)
{
    if (len < 3) return FALSE;
    gboolean has_lower = FALSE;
    const char *p = word;
    while (*p) {
        gunichar c = g_utf8_get_char(p);
        if (g_unichar_islower(c)) { has_lower = TRUE; break; }
        p = g_utf8_next_char(p);
    }
    return has_lower;
}

/* ------------------------------------------------------------------ */
/* Core check pass                                                     */
/* ------------------------------------------------------------------ */

static void do_check(GtkWidget *w)
{
    if (!s_available || !s_enabled) return;

    Sci_Position doc_len = (Sci_Position)sci(w, SCI_GETLENGTH, 0, 0);
    Sci_Position check_len = doc_len < MAX_CHECK_BYTES ? doc_len : MAX_CHECK_BYTES;
    if (check_len <= 0) return;

    /* Fetch text */
    char *buf = g_malloc(check_len + 1);
    Sci_TextRangeFull tr;
    tr.chrg.cpMin  = 0;
    tr.chrg.cpMax  = check_len;
    tr.lpstrText   = buf;
    sci(w, SCI_GETTEXTRANGEFULL, 0, (sptr_t)&tr);
    buf[check_len] = '\0';

    /* Clear old indicators */
    sci(w, SCI_SETINDICATORCURRENT, SPELL_INDICATOR, 0);
    sci(w, SCI_INDICATORCLEARRANGE, 0, (sptr_t)check_len);

    /* Walk UTF-8 characters, collect words */
    Sci_Position byte_pos = 0;
    const char  *p        = buf;

    while (byte_pos < check_len) {
        gunichar c = g_utf8_get_char(p);

        if (is_word_char(c)) {
            /* word start */
            const char  *word_start     = p;
            Sci_Position word_start_pos = byte_pos;

            while (byte_pos < check_len) {
                gunichar wc = g_utf8_get_char(p);
                if (!is_word_char(wc)) break;
                int char_bytes = (int)(g_utf8_next_char(p) - p);
                p        += char_bytes;
                byte_pos += char_bytes;
            }

            int word_bytes = (int)(p - word_start);
            if (should_check(word_start, word_bytes)) {
                char *word = g_strndup(word_start, word_bytes);
                if (p_dict_check(s_dict, word, word_bytes) != 0) {
                    /* misspelled — mark with indicator */
                    sci(w, SCI_INDICATORFILLRANGE,
                        (uptr_t)word_start_pos, (sptr_t)word_bytes);
                }
                g_free(word);
            }
        } else {
            int char_bytes = (int)(g_utf8_next_char(p) - p);
            p        += char_bytes;
            byte_pos += char_bytes;
        }
    }

    g_free(buf);
}

/* ------------------------------------------------------------------ */
/* Debounce timer                                                      */
/* ------------------------------------------------------------------ */

static gboolean on_check_timer(gpointer data)
{
    GtkWidget *w = data;
    g_object_steal_data(G_OBJECT(w), SPELL_TIMER_KEY);
    do_check(w);
    return G_SOURCE_REMOVE;
}

/* ------------------------------------------------------------------ */
/* Public API                                                          */
/* ------------------------------------------------------------------ */

void spell_init(GtkWidget *window)
{
    s_window = window;

    s_lib = dlopen("libenchant-2.so.2", RTLD_LAZY);
    if (!s_lib) return;

#define LOAD(sym) p_##sym = (fn_##sym)dlsym(s_lib, "enchant_" #sym); \
                  if (!p_##sym) { dlclose(s_lib); s_lib = NULL; return; }

    LOAD(broker_init)
    LOAD(broker_free)
    LOAD(broker_request_dict)
    LOAD(broker_free_dict)
    LOAD(dict_check)
    LOAD(dict_suggest)
    LOAD(dict_free_string_list)
    LOAD(dict_add)
    LOAD(dict_add_to_session)
#undef LOAD

    s_broker = p_broker_init();
    if (!s_broker) return;

    /* Use system locale language tag (e.g. "en_US", "it_IT") */
    const char *locale = setlocale(LC_MESSAGES, NULL);
    char tag[32] = "en";
    if (locale && strlen(locale) >= 2) {
        strncpy(tag, locale, sizeof(tag) - 1);
        /* strip encoding suffix: "en_US.UTF-8" → "en_US" */
        char *dot = strchr(tag, '.');
        if (dot) *dot = '\0';
    }

    s_dict = p_broker_request_dict(s_broker, tag);
    if (!s_dict && strchr(tag, '_')) {
        /* fall back to base language "en" */
        tag[2] = '\0';
        s_dict = p_broker_request_dict(s_broker, tag);
    }

    s_available = (s_dict != NULL);
}

void spell_on_sci_created(GtkWidget *w)
{
    setup_indicator(w);
}

void spell_schedule_check(GtkWidget *w)
{
    if (!s_available || !s_enabled) return;
    guint existing = GPOINTER_TO_UINT(g_object_get_data(G_OBJECT(w), SPELL_TIMER_KEY));
    if (existing)
        g_source_remove(existing);
    guint id = g_timeout_add(1200, on_check_timer, w);
    g_object_set_data(G_OBJECT(w), SPELL_TIMER_KEY, GUINT_TO_POINTER(id));
}

void spell_check_document(GtkWidget *w)
{
    if (!s_available || !s_enabled) return;
    /* Cancel pending timer and run immediately */
    guint existing = GPOINTER_TO_UINT(g_object_get_data(G_OBJECT(w), SPELL_TIMER_KEY));
    if (existing) {
        g_source_remove(existing);
        g_object_steal_data(G_OBJECT(w), SPELL_TIMER_KEY);
    }
    do_check(w);
}

void spell_set_enabled(gboolean enabled)
{
    s_enabled = enabled;
}

gboolean spell_is_enabled(void)
{
    return s_enabled;
}

/* ------------------------------------------------------------------ */
/* Context-menu suggestions                                            */
/* ------------------------------------------------------------------ */

typedef struct {
    GtkWidget *sci;
    char      *word;
} SuggCtx;

static void on_suggestion_activate(GtkMenuItem *item, gpointer data)
{
    SuggCtx *ctx = data;
    const char *sugg = gtk_menu_item_get_label(item);

    /* Replace the word under the stored position (stored in item label —
     * find word start/end around the saved cursor position)            */
    uptr_t *pos_ptr = g_object_get_data(G_OBJECT(item), "spell-pos");
    if (!pos_ptr) return;
    Sci_Position click_pos = (Sci_Position)*pos_ptr;

    Sci_Position ws = (Sci_Position)sci(ctx->sci, SCI_WORDSTARTPOSITION,
                                        (uptr_t)click_pos, 1);
    Sci_Position we = (Sci_Position)sci(ctx->sci, SCI_WORDENDPOSITION,
                                        (uptr_t)click_pos, 1);
    if (ws >= we) return;

    sci(ctx->sci, SCI_SETSEL, (uptr_t)ws, (sptr_t)we);
    sci(ctx->sci, SCI_REPLACESEL, 0, (sptr_t)sugg);
    /* Re-check after replacement */
    spell_schedule_check(ctx->sci);
}

static void on_add_to_dict(GtkMenuItem *item, gpointer data)
{
    (void)item;
    SuggCtx *ctx = data;
    if (s_dict && ctx->word)
        p_dict_add(s_dict, ctx->word, (ssize_t)strlen(ctx->word));
    spell_check_document(ctx->sci);
}

static void on_ignore_word(GtkMenuItem *item, gpointer data)
{
    (void)item;
    SuggCtx *ctx = data;
    if (s_dict && ctx->word)
        p_dict_add_to_session(s_dict, ctx->word, (ssize_t)strlen(ctx->word));
    spell_check_document(ctx->sci);
}

static void sugg_ctx_free(gpointer data)
{
    SuggCtx *ctx = data;
    g_free(ctx->word);
    g_free(ctx);
}

void spell_populate_context_menu(GtkWidget *w, GtkWidget *menu, int x, int y)
{
    if (!s_available || !s_enabled) return;

    /* Find document position under the click */
    Sci_Position click_pos = (Sci_Position)sci(w, SCI_POSITIONFROMPOINTCLOSE,
                                               (uptr_t)x, (sptr_t)y);
    if (click_pos < 0) return;

    /* Check whether that position is inside a spell indicator */
    sci(w, SCI_SETINDICATORCURRENT, SPELL_INDICATOR, 0);
    Sci_Position val = (Sci_Position)sci(w, SCI_INDICATORVALUEAT,
                                         SPELL_INDICATOR, (sptr_t)click_pos);
    if (!val) return;

    Sci_Position ws = (Sci_Position)sci(w, SCI_WORDSTARTPOSITION,
                                        (uptr_t)click_pos, 1);
    Sci_Position we = (Sci_Position)sci(w, SCI_WORDENDPOSITION,
                                        (uptr_t)click_pos, 1);
    if (ws >= we) return;

    int wlen = (int)(we - ws);
    char *word = g_malloc(wlen + 1);
    Sci_TextRangeFull tr;
    tr.chrg.cpMin = ws;
    tr.chrg.cpMax = we;
    tr.lpstrText  = word;
    sci(w, SCI_GETTEXTRANGEFULL, 0, (sptr_t)&tr);
    word[wlen] = '\0';

    /* Build suggestions */
    size_t  n_sugg = 0;
    char  **suggs  = p_dict_suggest(s_dict, word, (ssize_t)wlen, &n_sugg);

    SuggCtx *ctx = g_new0(SuggCtx, 1);
    ctx->sci  = w;
    ctx->word = word; /* ownership transferred */
    /* ctx is freed when the menu widget is destroyed */
    g_object_set_data_full(G_OBJECT(menu), "spell-ctx", ctx,
                           (GDestroyNotify)sugg_ctx_free);

    /* Separator */
    GtkWidget *sep = gtk_separator_menu_item_new();
    gtk_widget_show(sep);
    gtk_menu_shell_prepend(GTK_MENU_SHELL(menu), sep);

    /* "Ignore" and "Add to Dictionary" */
    GtkWidget *add_item = gtk_menu_item_new_with_label("Add to Dictionary");
    GtkWidget *ign_item = gtk_menu_item_new_with_label("Ignore Word");
    g_signal_connect(add_item, "activate", G_CALLBACK(on_add_to_dict), ctx);
    g_signal_connect(ign_item, "activate", G_CALLBACK(on_ignore_word), ctx);
    gtk_widget_show(add_item);
    gtk_widget_show(ign_item);
    gtk_menu_shell_prepend(GTK_MENU_SHELL(menu), add_item);
    gtk_menu_shell_prepend(GTK_MENU_SHELL(menu), ign_item);

    /* Suggestion items (up to 8) */
    int limit = (int)n_sugg < 8 ? (int)n_sugg : 8;
    for (int i = limit - 1; i >= 0; i--) {
        GtkWidget *mi = gtk_menu_item_new_with_label(suggs[i]);
        uptr_t *pos_storage = g_new(uptr_t, 1);
        *pos_storage = (uptr_t)click_pos;
        g_object_set_data_full(G_OBJECT(mi), "spell-pos", pos_storage, g_free);
        g_signal_connect(mi, "activate", G_CALLBACK(on_suggestion_activate), ctx);
        gtk_widget_show(mi);
        gtk_menu_shell_prepend(GTK_MENU_SHELL(menu), mi);
    }

    if (suggs)
        p_dict_free_string_list(s_dict, suggs);

    /* Separator at very top */
    GtkWidget *sep2 = gtk_separator_menu_item_new();
    gtk_widget_show(sep2);
    gtk_menu_shell_prepend(GTK_MENU_SHELL(menu), sep2);

    /* Header label (non-clickable) */
    char header[128];
    snprintf(header, sizeof(header), "Spell: \"%s\"", ctx->word);
    GtkWidget *lbl_item = gtk_menu_item_new_with_label(header);
    gtk_widget_set_sensitive(lbl_item, FALSE);
    gtk_widget_show(lbl_item);
    gtk_menu_shell_prepend(GTK_MENU_SHELL(menu), lbl_item);
}
