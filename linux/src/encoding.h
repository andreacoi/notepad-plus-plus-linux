#ifndef ENCODING_H
#define ENCODING_H

#include <glib.h>

typedef struct {
    const char *display;   /* label shown in menu and statusbar  */
    const char *iconv;     /* name accepted by g_convert / iconv */
    gboolean    bom;       /* write BOM on save                  */
} EncDef;

extern const EncDef npp_encodings[];
extern const int    npp_encoding_count;

/* Detect encoding from raw file bytes (BOM → UTF-8 validate → Latin-1).
   Returns a pointer into npp_encodings[].display — do NOT free. */
const char *encoding_detect(const guchar *data, gsize len);

/* Decode raw bytes to a g_malloc'd NUL-terminated UTF-8 string.
   Strips any leading BOM.  *out_len receives byte count (excl. NUL).
   Falls back to ISO-8859-1 if conversion fails. */
char *encoding_to_utf8(const char *enc,
                       const guchar *raw, gsize raw_len,
                       gsize *out_len);

/* Encode a NUL-terminated UTF-8 string to the target encoding,
   prepending a BOM when the encoding requires one.
   Returns g_malloc'd bytes; *out_len receives byte count. */
guchar *encoding_from_utf8(const char *enc,
                            const char *utf8, gsize utf8_len,
                            gsize *out_len);

#endif /* ENCODING_H */
