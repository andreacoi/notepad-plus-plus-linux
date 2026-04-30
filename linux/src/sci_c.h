/*
 * C-safe Scintilla interface.
 *
 * Scintilla.h in this repo has C++-only additions (<vector>, namespaces).
 * This header provides everything a pure-C caller needs.
 */
#ifndef SCI_C_H
#define SCI_C_H

#include <stdint.h>
#include <gtk/gtk.h>

typedef uintptr_t uptr_t;
typedef intptr_t  sptr_t;
typedef intptr_t  Sci_Position;

/* SCNotification layout — must match Scintilla's internal struct exactly */
typedef struct {
    void        *hwndFrom;
    uptr_t       idFrom;
    unsigned int code;
} Sci_NotifyHeader;

typedef struct SCNotification {
    Sci_NotifyHeader nmhdr;
    Sci_Position     position;
    int              ch;
    int              modifiers;
    int              modificationType;
    const char      *text;
    Sci_Position     length;
    Sci_Position     linesAdded;
    int              message;
    uptr_t           wParam;
    sptr_t           lParam;
    Sci_Position     line;
    int              foldLevelNow;
    int              foldLevelPrev;
    int              margin;
    int              listType;
    int              x;
    int              y;
    int              token;
    Sci_Position     annotationLinesAdded;
    int              updated;
    int              listCompletionMethod;
    int              characterSource;
} SCNotification;

#include "ScintillaWidget.h"

/* ------------------------------------------------------------------ */
/* SCI_ message constants (values from Scintilla.iface)               */
/* ------------------------------------------------------------------ */
#define SCI_GETLENGTH           2006
#define SCI_GETCURRENTPOS       2008
#define SCI_REDO                2011
#define SCI_SELECTALL           2013
#define SCI_SETSAVEPOINT        2014
#define SCI_SETCODEPAGE         2037
#define SCI_GETCOLUMN           2129
#define SCI_GETMODIFY           2159
#define SCI_LINEFROMPOSITION    2166
#define SCI_EMPTYUNDOBUFFER     2175
#define SCI_UNDO                2176
#define SCI_CUT                 2177
#define SCI_COPY                2178
#define SCI_PASTE               2179
#define SCI_SETTEXT             2181
#define SCI_GETTEXT             2182
#define SCI_SETMARGINWIDTHN     2243
#define SCI_SETTABWIDTH         2036
#define SCI_SETUSETABS          2124
#define SCI_STYLESETFORE        2051
#define SCI_STYLESETBACK        2052  /* was wrong (2040=SCI_MARKERDEFINE) */
#define SCI_STYLESETBOLD        2053
#define SCI_STYLESETITALIC      2054
#define SCI_STYLESETFONT        2056
#define SCI_STYLESETSIZE        2055
#define SCI_STYLESETUNDERLINE   2059
#define SCI_STYLECLEARALL       2050
#define SCI_SETSELBACK          2068
#define SCI_SETCARETFORE        2069
#define SCI_SETWHITESPACEFORE   2084
#define SCI_SETCARETLINEVISIBLE 2096
#define SCI_SETCARETLINEBACK    2098
#define SCI_MARKERSETFORE       2041
#define SCI_MARKERSETBACK       2042
#define SCI_SETFOLDMARGINCOLOUR  2290
#define SCI_SETFOLDMARGINHICOLOUR 2291
#define SCI_MARKERENABLEHIGHLIGHT 2293
#define SCI_GOTOPOS             2025
#define SCI_GOTOLINE            2024
#define SCI_SETEOLMODE          2031
#define SCI_GETEOLMODE          2030
#define SCI_SETLEXERLANGUAGE    4006
#define SCI_SETILEXER           4033
#define SCI_SETPROPERTY         4004
#define SCI_SETKEYWORDS         4005
#define SCI_COLOURISE           4003

/* ------------------------------------------------------------------ */
/* SCN_ notification codes                                            */
/* ------------------------------------------------------------------ */
#define SCN_SAVEPOINTREACHED    2002
#define SCN_SAVEPOINTLEFT       2003
#define SCN_UPDATEUI            2007
#define SCN_MODIFIED            2008

/* SC_UPDATE_ flags (used in SCNotification.updated for SCN_UPDATEUI) */
#define SC_UPDATE_CONTENT       0x1
#define SC_UPDATE_SELECTION     0x2

/* Encoding / EOL */
#define SC_CP_UTF8              65001
#define SC_EOL_CRLF             0
#define SC_EOL_CR               1
#define SC_EOL_LF               2

/* Style indices */
#define STYLE_DEFAULT           32
#define STYLE_LINENUMBER        33
#define STYLE_BRACELIGHT        34
#define STYLE_BRACEBAD          35

/* Fold marker numbers */
#define SC_MARKNUM_FOLDER       30
#define SC_MARKNUM_FOLDEROPEN   31

#endif /* SCI_C_H */
