/* session.c — Session save / restore for the Linux GTK3 port.
 *
 * Persists open file paths + scroll/caret positions + text content to
 * ~/.config/notetux/session.xml in NPP-compatible XML format.
 *
 * Format:
 *   <NotepadPlus>
 *     <Session activeIndex="N">
 *       <mainView activeIndex="N">
 *         <File filename="…" firstVisibleLine="N" xOffset="N"
 *               caretPosition="N" encoding="UTF-8">
 *           <Content>base64-encoded UTF-8 text</Content>
 *         </File>
 *         …
 *       </mainView>
 *     </Session>
 *   </NotepadPlus>
 *
 * <Content> is written for every file whose text fits within
 * SESSION_CONTENT_CAP bytes. On restore, if the file no longer exists on
 * disk the saved content is loaded into a ghost tab; if the file exists the
 * content element is ignored and the file is read from disk as usual.
 *
 * Only tabs with a saved filepath are persisted; unsaved "new N" docs
 * are intentionally skipped.
 */
#include "session.h"
#include "editor.h"
#include "sci_c.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#define SESSION_CONTENT_CAP (1 * 1024 * 1024)  /* skip content for files > 1 MB */

/* ------------------------------------------------------------------ */
/* Path helper                                                         */
/* ------------------------------------------------------------------ */

static const char *session_path(void)
{
    static char s_path[512];
    if (!s_path[0])
        snprintf(s_path, sizeof(s_path), "%s/notetux/session.xml",
                 g_get_user_config_dir());
    return s_path;
}

/* ------------------------------------------------------------------ */
/* Save                                                                */
/* ------------------------------------------------------------------ */

void session_save(void)
{
    int total  = editor_page_count();
    int active = editor_current_page();

    int active_saved = 0;
    for (int i = 0; i < active; i++) {
        NppDoc *d = editor_doc_at(i);
        if (d && d->filepath) active_saved++;
    }

    GString *xml = g_string_new(
        "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n"
        "<NotepadPlus>\n");

    g_string_append_printf(xml,
        "\t<Session activeIndex=\"%d\">\n"
        "\t\t<mainView activeIndex=\"0\">\n",
        active_saved);

    for (int i = 0; i < total; i++) {
        NppDoc *doc = editor_doc_at(i);
        if (!doc || !doc->filepath) continue;

        sptr_t caret      = scintilla_send_message(SCINTILLA(doc->sci),
                                SCI_GETCURRENTPOS, 0, 0);
        sptr_t first_line = scintilla_send_message(SCINTILLA(doc->sci),
                                SCI_GETFIRSTVISIBLELINE, 0, 0);
        sptr_t xoffset    = scintilla_send_message(SCINTILLA(doc->sci),
                                SCI_GETXOFFSET, 0, 0);
        sptr_t len        = scintilla_send_message(SCINTILLA(doc->sci),
                                SCI_GETLENGTH, 0, 0);

        gchar *escaped = g_markup_escape_text(doc->filepath, -1);
        g_string_append_printf(xml,
            "\t\t\t<File filename=\"%s\""
            " firstVisibleLine=\"%ld\""
            " xOffset=\"%ld\""
            " caretPosition=\"%ld\""
            " encoding=\"%s\"",
            escaped,
            (long)first_line,
            (long)xoffset,
            (long)caret,
            doc->encoding ? doc->encoding : "UTF-8");
        g_free(escaped);

        /* Save text content (capped at SESSION_CONTENT_CAP) */
        if (len > 0 && len <= SESSION_CONTENT_CAP) {
            gchar *text = g_malloc((gsize)len + 1);
            scintilla_send_message(SCINTILLA(doc->sci),
                                   SCI_GETTEXT, (uptr_t)(len + 1), (sptr_t)text);
            gchar *b64 = g_base64_encode((guchar *)text, (gsize)len);
            g_free(text);
            g_string_append(xml, ">\n\t\t\t\t<Content>");
            g_string_append(xml, b64);
            g_string_append(xml, "</Content>\n\t\t\t</File>\n");
            g_free(b64);
        } else {
            g_string_append(xml, " />\n");
        }
    }

    g_string_append(xml,
        "\t\t</mainView>\n"
        "\t</Session>\n"
        "</NotepadPlus>\n");

    gchar *dir = g_build_filename(g_get_user_config_dir(), "notetux", NULL);
    g_mkdir_with_parents(dir, 0755);
    g_free(dir);

    GError *err = NULL;
    if (!g_file_set_contents(session_path(), xml->str, -1, &err)) {
        g_warning("session_save: %s", err->message);
        g_error_free(err);
    }
    g_string_free(xml, TRUE);
}

/* ------------------------------------------------------------------ */
/* Restore — XML parser                                               */
/* ------------------------------------------------------------------ */

typedef struct {
    char  filepath[1024];
    long  first_line;
    long  xoffset;
    long  caret_pos;
    char  encoding[32];
    char *content;      /* decoded UTF-8 text, NULL if not present */
    gsize content_len;
} SessionEntry;

typedef struct {
    int           active_index;
    SessionEntry *entries;
    int           count;
    int           cap;
    gboolean      in_content;   /* currently inside a <Content> element */
    GString      *content_buf;  /* accumulates base64 text */
} ParseState;

static void xml_start(GMarkupParseContext *ctx, const gchar *el,
                      const gchar **names, const gchar **vals,
                      gpointer ud, GError **err)
{
    (void)ctx; (void)err;
    ParseState *st = (ParseState *)ud;

    if (strcmp(el, "Session") == 0) {
        for (int i = 0; names[i]; i++)
            if (strcmp(names[i], "activeIndex") == 0)
                st->active_index = atoi(vals[i]);
        return;
    }

    if (strcmp(el, "Content") == 0) {
        st->in_content = TRUE;
        if (!st->content_buf)
            st->content_buf = g_string_new(NULL);
        else
            g_string_truncate(st->content_buf, 0);
        return;
    }

    if (strcmp(el, "File") != 0) return;

    if (st->count >= st->cap) {
        st->cap = st->cap ? st->cap * 2 : 8;
        st->entries = g_realloc(st->entries,
                                (gsize)st->cap * sizeof(SessionEntry));
    }

    SessionEntry *e = &st->entries[st->count];
    memset(e, 0, sizeof(*e));
    snprintf(e->encoding, sizeof(e->encoding), "UTF-8");

    for (int i = 0; names[i]; i++) {
        if      (strcmp(names[i], "filename")         == 0)
            snprintf(e->filepath, sizeof(e->filepath), "%s", vals[i]);
        else if (strcmp(names[i], "firstVisibleLine") == 0)
            e->first_line = atol(vals[i]);
        else if (strcmp(names[i], "xOffset")          == 0)
            e->xoffset    = atol(vals[i]);
        else if (strcmp(names[i], "caretPosition")    == 0)
            e->caret_pos  = atol(vals[i]);
        else if (strcmp(names[i], "encoding")         == 0)
            snprintf(e->encoding, sizeof(e->encoding), "%s", vals[i]);
    }

    if (e->filepath[0]) st->count++;
}

static void xml_text(GMarkupParseContext *ctx, const gchar *text,
                     gsize text_len, gpointer ud, GError **err)
{
    (void)ctx; (void)err;
    ParseState *st = (ParseState *)ud;
    if (st->in_content && st->content_buf)
        g_string_append_len(st->content_buf, text, (gssize)text_len);
}

static void xml_end(GMarkupParseContext *ctx, const gchar *el,
                    gpointer ud, GError **err)
{
    (void)ctx; (void)err;
    ParseState *st = (ParseState *)ud;
    if (strcmp(el, "Content") != 0 || !st->in_content) return;
    st->in_content = FALSE;
    if (st->content_buf && st->count > 0) {
        guchar *decoded = g_base64_decode(st->content_buf->str, &st->entries[st->count - 1].content_len);
        st->entries[st->count - 1].content = (char *)decoded;
    }
}

static GMarkupParser s_parser = { xml_start, xml_end, xml_text, NULL, NULL };

void session_restore(void)
{
    gchar *xml = NULL;
    if (!g_file_get_contents(session_path(), &xml, NULL, NULL))
        return;

    ParseState st = { 0, NULL, 0, 0, FALSE, NULL };

    GMarkupParseContext *ctx = g_markup_parse_context_new(&s_parser, 0, &st, NULL);
    g_markup_parse_context_parse(ctx, xml, -1, NULL);
    g_markup_parse_context_free(ctx);
    g_free(xml);

    if (st.content_buf)
        g_string_free(st.content_buf, TRUE);

    if (st.count == 0) {
        g_free(st.entries);
        return;
    }

    int restored  = 0;
    int last_page = -1;

    for (int i = 0; i < st.count; i++) {
        SessionEntry *e = &st.entries[i];

        if (!g_file_test(e->filepath, G_FILE_TEST_EXISTS)) {
            editor_open_missing(e->filepath, e->content, e->content_len);
            if (restored == st.active_index)
                last_page = editor_current_page();
            restored++;
            g_free(e->content);
            continue;
        }

        if (!editor_open_path(e->filepath)) {
            g_free(e->content);
            continue;
        }

        NppDoc *doc = editor_current_doc();
        if (doc) {
            scintilla_send_message(SCINTILLA(doc->sci),
                SCI_SETFIRSTVISIBLELINE, (uptr_t)e->first_line, 0);
            scintilla_send_message(SCINTILLA(doc->sci),
                SCI_SETXOFFSET, (uptr_t)e->xoffset, 0);
            scintilla_send_message(SCINTILLA(doc->sci),
                SCI_GOTOPOS, (uptr_t)e->caret_pos, 0);
            scintilla_send_message(SCINTILLA(doc->sci),
                SCI_SCROLLCARET, 0, 0);

            if (doc->encoding) g_free(doc->encoding);
            doc->encoding = g_strdup(e->encoding);
        }

        if (restored == st.active_index)
            last_page = editor_current_page();
        restored++;
        g_free(e->content);
    }

    if (last_page >= 0)
        gtk_notebook_set_current_page(GTK_NOTEBOOK(editor_get_notebook()), last_page);

    g_free(st.entries);
}
