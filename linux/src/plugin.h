#pragma once
#include <gtk/gtk.h>

/* ------------------------------------------------------------------
 * Types shared between host and plugin .so files.
 * Plugin authors should include this header when writing a plugin.
 * ------------------------------------------------------------------ */

/** One menu entry contributed by a plugin. */
typedef struct {
    char   itemName[64];   /* display label (UTF-8); "-" = separator  */
    void (*pFunc)(void);   /* called on menu-item activation           */
    int    cmdID;          /* unique ID assigned by host at load time  */
    int    init2Check;     /* non-zero → item starts with a checkmark  */
} FuncItem;

/** Callback type plugins use to query the host. */
typedef long (*NppHostMsg)(unsigned int msg, unsigned long wParam, long lParam);

/** Passed to plugins that export setInfo(NppData). */
typedef struct {
    GtkWidget  *nppHandle;             /* main application window   */
    GtkWidget  *scintillaMainHandle;   /* primary Scintilla widget  */
    GtkWidget  *scintillaSecondHandle; /* secondary sci (or NULL)   */
    NppHostMsg  hostMsg;               /* send a message to host    */
} NppData;

/* ------------------------------------------------------------------
 * NPPM host-message IDs (subset implemented)
 *
 * Plugins call NppData.hostMsg(NPPM_*, wParam, lParam) to query
 * the host at runtime.
 * ------------------------------------------------------------------ */
#define NPPM_BASE                  (0x0400 + 1000)
#define NPPM_GETCURRENTSCINTILLA   (NPPM_BASE + 4)   /* → (long)(GtkWidget*) active sci        */
#define NPPM_GETNBOPENFILES        (NPPM_BASE + 7)   /* → int count of open tabs               */
#define NPPM_GETFULLCURRENTPATH    (NPPM_BASE + 38)  /* lParam = char* buf[2048], returns 1    */
#define NPPM_GETFILENAME           (NPPM_BASE + 39)  /* lParam = char* buf[256],  returns 1    */
#define NPPM_GETDIRECTORYPATH      (NPPM_BASE + 40)  /* lParam = char* buf[2048], returns 1    */
#define NPPM_SETSTATUSBAR          (NPPM_BASE + 34)  /* wParam = field ID, lParam = char* text */

/* Field IDs for NPPM_SETSTATUSBAR */
#define STATUSBAR_DOC_TYPE      0
#define STATUSBAR_DOC_SIZE      1
#define STATUSBAR_CUR_POS       2
#define STATUSBAR_EOF_FORMAT    3
#define STATUSBAR_UNICODE_TYPE  4
#define STATUSBAR_TYPING_MODE   5

/* ------------------------------------------------------------------
 * Five symbols a plugin .so must export
 *
 *   const char *getName(void);
 *   FuncItem   *getFuncsArray(int *nbF);
 *   void        beNotified(SCNotification *pNotify);
 *   long        messageProc(unsigned int msg, unsigned long wParam, long lParam);
 *   int         isUnicode(void);
 *
 * Optional (called before getFuncsArray if present):
 *   void        setInfo(NppData nppData);
 *
 * Plugin directory layout:
 *   ~/.config/notetux/plugins/<PluginName>/<PluginName>.so
 * ------------------------------------------------------------------ */

/* ------------------------------------------------------------------
 * Host API — called from main.c and editor.c
 * ------------------------------------------------------------------ */
void  plugin_init(GtkWidget *main_window);
void  plugin_load_all(void);
void  plugin_notify_all(void *pNotify);       /* pass SCNotification * cast to void * */
long  plugin_host_message(unsigned int msg, unsigned long wParam, long lParam);
void  plugin_populate_menu(GtkWidget *plugins_menu);
int   plugin_count(void);
