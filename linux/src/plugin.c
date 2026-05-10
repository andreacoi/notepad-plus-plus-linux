#include "plugin.h"
#include "editor.h"
#include <dlfcn.h>
#include <dirent.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

/* ------------------------------------------------------------------
 * Plugin symbol typedefs
 * ------------------------------------------------------------------ */
typedef const char *(*GetName_t)(void);
typedef FuncItem   *(*GetFuncsArray_t)(int *);
typedef void        (*BeNotified_t)(void *);
typedef long        (*MessageProc_t)(unsigned int, unsigned long, long);
typedef int         (*IsUnicode_t)(void);
typedef void        (*SetInfo_t)(NppData);

/* ------------------------------------------------------------------
 * Internal plugin record
 * ------------------------------------------------------------------ */
typedef struct {
    void          *dl_handle;
    char           name[128];
    FuncItem      *funcs;
    int            n_funcs;
    BeNotified_t   be_notified;
    MessageProc_t  message_proc;
} LoadedPlugin;

#define MAX_PLUGINS   64
#define CMD_ID_BASE   10000

static LoadedPlugin  s_plugins[MAX_PLUGINS];
static int           s_n_plugins   = 0;
static GtkWidget    *s_window      = NULL;
static NppData       s_npp_data;
static int           s_next_cmd_id = CMD_ID_BASE;

/* forward declaration */
static long host_msg_cb(unsigned int msg, unsigned long wParam, long lParam);

/* ------------------------------------------------------------------
 * Load one plugin from a .so path; silently skip if invalid
 * ------------------------------------------------------------------ */
static void load_plugin(const char *sopath)
{
    if (s_n_plugins >= MAX_PLUGINS) return;

    void *h = dlopen(sopath, RTLD_LAZY | RTLD_LOCAL);
    if (!h) return;

    GetName_t       get_name     = (GetName_t)      dlsym(h, "getName");
    GetFuncsArray_t get_funcs    = (GetFuncsArray_t) dlsym(h, "getFuncsArray");
    BeNotified_t    be_notified  = (BeNotified_t)   dlsym(h, "beNotified");
    MessageProc_t   msg_proc     = (MessageProc_t)  dlsym(h, "messageProc");
    IsUnicode_t     is_unicode   = (IsUnicode_t)    dlsym(h, "isUnicode");

    if (!get_name || !get_funcs || !be_notified || !msg_proc || !is_unicode) {
        dlclose(h);
        return;
    }

    /* Optional: pass NppData before querying func array */
    SetInfo_t set_info = (SetInfo_t) dlsym(h, "setInfo");
    if (set_info) set_info(s_npp_data);

    LoadedPlugin *p = &s_plugins[s_n_plugins];
    p->dl_handle   = h;
    p->be_notified = be_notified;
    p->message_proc = msg_proc;

    const char *raw = get_name();
    snprintf(p->name, sizeof(p->name), "%s", raw ? raw : "Plugin");

    int n = 0;
    FuncItem *funcs = get_funcs(&n);
    p->funcs   = (n > 0 && funcs) ? funcs : NULL;
    p->n_funcs = (n > 0 && funcs) ? n     : 0;

    for (int i = 0; i < p->n_funcs; i++)
        p->funcs[i].cmdID = s_next_cmd_id++;

    s_n_plugins++;
    g_message("plugin: loaded '%s' (%d items) from %s", p->name, p->n_funcs, sopath);
}

/* ------------------------------------------------------------------
 * Scan a directory for plugins laid out as <dir>/<Name>/<Name>.so
 * ------------------------------------------------------------------ */
static void scan_dir(const char *dir)
{
    DIR *d = opendir(dir);
    if (!d) return;
    struct dirent *ent;
    while ((ent = readdir(d))) {
        if (ent->d_name[0] == '.') continue;
        char sopath[2048];
        snprintf(sopath, sizeof(sopath), "%s/%s/%s.so",
                 dir, ent->d_name, ent->d_name);
        load_plugin(sopath);
    }
    closedir(d);
}

/* ------------------------------------------------------------------
 * Menu helper: wrap pFunc so it matches GtkWidget "activate" signature
 * ------------------------------------------------------------------ */
static void on_plugin_item_activated(GtkMenuItem *item, gpointer data)
{
    (void)item;
    void (*fn)(void) = data;
    if (fn) fn();
}

/* ------------------------------------------------------------------
 * Public API
 * ------------------------------------------------------------------ */

void plugin_init(GtkWidget *main_window)
{
    s_window                         = main_window;
    s_npp_data.nppHandle             = main_window;
    s_npp_data.scintillaMainHandle   = NULL;
    s_npp_data.scintillaSecondHandle = NULL;
    s_npp_data.hostMsg               = host_msg_cb;
}

void plugin_load_all(void)
{
    /* User plugins */
    char user_dir[1024];
    snprintf(user_dir, sizeof(user_dir),
             "%s/.config/notetux/plugins", g_get_home_dir());
    g_mkdir_with_parents(user_dir, 0755);
    scan_dir(user_dir);

    /* System-wide plugins (optional) */
    scan_dir("/usr/lib/notetux/plugins");
    scan_dir("/usr/local/lib/notetux/plugins");
}

void plugin_notify_all(void *pNotify)
{
    for (int i = 0; i < s_n_plugins; i++) {
        if (s_plugins[i].be_notified)
            s_plugins[i].be_notified(pNotify);
    }
}

int plugin_count(void)
{
    return s_n_plugins;
}

void plugin_populate_menu(GtkWidget *plugins_menu)
{
    for (int i = 0; i < s_n_plugins; i++) {
        LoadedPlugin *p = &s_plugins[i];
        if (p->n_funcs == 0) continue;

        GtkWidget *sub      = gtk_menu_new();
        GtkWidget *sub_item = gtk_menu_item_new_with_label(p->name);
        gtk_menu_item_set_submenu(GTK_MENU_ITEM(sub_item), sub);
        gtk_menu_shell_append(GTK_MENU_SHELL(plugins_menu), sub_item);

        for (int j = 0; j < p->n_funcs; j++) {
            FuncItem  *fi   = &p->funcs[j];
            GtkWidget *item;

            if (fi->itemName[0] == '-' && fi->itemName[1] == '\0') {
                item = gtk_separator_menu_item_new();
            } else if (fi->init2Check) {
                item = gtk_check_menu_item_new_with_label(fi->itemName);
                gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(item), TRUE);
            } else {
                item = gtk_menu_item_new_with_label(fi->itemName);
            }

            if (fi->pFunc)
                g_signal_connect(item, "activate",
                                 G_CALLBACK(on_plugin_item_activated),
                                 (gpointer)fi->pFunc);
            gtk_menu_shell_append(GTK_MENU_SHELL(sub), item);
        }
    }
}

/* ------------------------------------------------------------------
 * NPPM host message router
 * ------------------------------------------------------------------ */
static long host_msg_cb(unsigned int msg, unsigned long wParam, long lParam)
{
    return plugin_host_message(msg, wParam, lParam);
}

long plugin_host_message(unsigned int msg, unsigned long wParam, long lParam)
{
    (void)wParam;
    switch (msg) {

    case NPPM_GETCURRENTSCINTILLA: {
        NppDoc *doc = editor_current_doc();
        return doc ? (long)(intptr_t)doc->sci : 0L;
    }

    case NPPM_GETNBOPENFILES:
        return (long)editor_page_count();

    case NPPM_GETFULLCURRENTPATH: {
        char *buf = (char *)(intptr_t)lParam;
        if (!buf) return 0L;
        NppDoc *doc = editor_current_doc();
        if (doc && doc->filepath)
            snprintf(buf, 2048, "%s", doc->filepath);
        else
            buf[0] = '\0';
        return 1L;
    }

    case NPPM_GETFILENAME: {
        char *buf = (char *)(intptr_t)lParam;
        if (!buf) return 0L;
        NppDoc *doc = editor_current_doc();
        if (doc && doc->filepath) {
            const char *base = strrchr(doc->filepath, '/');
            snprintf(buf, 256, "%s", base ? base + 1 : doc->filepath);
        } else {
            buf[0] = '\0';
        }
        return 1L;
    }

    case NPPM_GETDIRECTORYPATH: {
        char *buf = (char *)(intptr_t)lParam;
        if (!buf) return 0L;
        NppDoc *doc = editor_current_doc();
        if (doc && doc->filepath) {
            char *dir = g_path_get_dirname(doc->filepath);
            snprintf(buf, 2048, "%s", dir);
            g_free(dir);
        } else {
            buf[0] = '\0';
        }
        return 1L;
    }

    default:
        return 0L;
    }
}
