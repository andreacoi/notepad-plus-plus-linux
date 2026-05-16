/* findinfiles.c — Find in Files dialog for the GTK3 Linux port. */
#include "findinfiles.h"
#include "searchresults.h"
#include "editor.h"
#include "i18n.h"
#include <string.h>
#include <stdio.h>

/* ------------------------------------------------------------------ */
/* Tree column indices                                                 */
/* ------------------------------------------------------------------ */
enum { COL_TEXT, COL_WEIGHT, COL_FILEPATH, COL_LINE, N_COLS };

/* ------------------------------------------------------------------ */
/* Module state                                                        */
/* ------------------------------------------------------------------ */
static GtkWidget    *s_dialog       = NULL;
static GtkWidget    *s_find_entry   = NULL;
static GtkWidget    *s_dir_entry    = NULL;
static GtkWidget    *s_filter_entry = NULL;
static GtkWidget    *s_chk_case     = NULL;
static GtkWidget    *s_chk_word     = NULL;
static GtkWidget    *s_chk_subdirs  = NULL;
static GtkWidget    *s_btn_find     = NULL;
static GtkWidget    *s_status_lbl   = NULL;
static GtkTreeStore *s_store        = NULL;
static GtkWidget    *s_tree_view    = NULL;
static GtkWidget    *s_parent_win   = NULL;

/* ------------------------------------------------------------------ */
/* Hit and result types                                                */
/* ------------------------------------------------------------------ */
typedef struct { char *filepath; int line; char *text; } FifHit;

typedef struct {
    GPtrArray *hits;
    int        file_count;
    char      *needle;
} FifResult;

static void fif_hit_free(gpointer p)
{
    FifHit *h = p;
    g_free(h->filepath);
    g_free(h->text);
    g_free(h);
}

/* ------------------------------------------------------------------ */
/* File filter matching                                               */
/* ------------------------------------------------------------------ */
static gboolean name_matches_filter(const char *name, const char *filter)
{
    if (!filter || !*filter || strcmp(filter, "*") == 0 || strcmp(filter, "*.*") == 0)
        return TRUE;
    gchar **parts = g_strsplit(filter, ";", -1);
    gboolean ok = FALSE;
    for (int i = 0; parts[i] && !ok; i++) {
        gchar *p = g_strstrip(parts[i]);
        if (*p) {
            GPatternSpec *spec = g_pattern_spec_new(p);
            ok = g_pattern_spec_match_string(spec, name);
            g_pattern_spec_free(spec);
        }
    }
    g_strfreev(parts);
    return ok;
}

/* ------------------------------------------------------------------ */
/* Search job (passed to thread)                                      */
/* ------------------------------------------------------------------ */
typedef struct {
    char     *needle;
    char     *directory;
    char     *filter;
    gboolean  match_case;
    gboolean  whole_word;
    gboolean  subdirs;
    GPtrArray *hits;       /* output: array of FifHit* */
    int        file_count; /* output */
} FifJob;

static void search_file(const char *filepath, FifJob *job, GRegex *regex)
{
    gchar *contents = NULL;
    gsize  length   = 0;
    if (!g_file_get_contents(filepath, &contents, &length, NULL))
        return;

    gchar **lines = g_strsplit(contents, "\n", -1);
    g_free(contents);

    gboolean any = FALSE;
    for (int i = 0; lines[i]; i++) {
        /* strip trailing \r for CRLF files */
        gsize ll = strlen(lines[i]);
        if (ll > 0 && lines[i][ll - 1] == '\r')
            lines[i][ll - 1] = '\0';

        if (g_regex_match(regex, lines[i], 0, NULL)) {
            FifHit *h   = g_new(FifHit, 1);
            h->filepath = g_strdup(filepath);
            h->line     = i + 1;
            h->text     = g_strdup(g_strstrip(lines[i]));
            g_ptr_array_add(job->hits, h);
            any = TRUE;
        }
    }
    g_strfreev(lines);
    if (any) job->file_count++;
}

static void search_dir(const char *dirpath, FifJob *job, GRegex *regex)
{
    GDir *dir = g_dir_open(dirpath, 0, NULL);
    if (!dir) return;

    const gchar *name;
    while ((name = g_dir_read_name(dir))) {
        gchar *full = g_build_filename(dirpath, name, NULL);
        if (g_file_test(full, G_FILE_TEST_IS_DIR)) {
            if (job->subdirs && name[0] != '.')
                search_dir(full, job, regex);
        } else if (name_matches_filter(name, job->filter)) {
            search_file(full, job, regex);
        }
        g_free(full);
    }
    g_dir_close(dir);
}

static gboolean post_results(gpointer data);

static gpointer search_thread(gpointer data)
{
    FifJob *job = data;

    GRegexCompileFlags cflags = job->match_case ? 0 : G_REGEX_CASELESS;
    gchar *escaped = g_regex_escape_string(job->needle, -1);
    gchar *pattern = job->whole_word
                     ? g_strdup_printf("\\b%s\\b", escaped)
                     : g_strdup(escaped);
    g_free(escaped);

    GError *err   = NULL;
    GRegex *regex = g_regex_new(pattern, cflags, 0, &err);
    g_free(pattern);

    if (regex) {
        search_dir(job->directory, job, regex);
        g_regex_unref(regex);
    } else if (err) {
        g_error_free(err);
    }

    FifResult *res  = g_new(FifResult, 1);
    res->hits       = job->hits;
    res->file_count = job->file_count;
    res->needle     = g_strdup(job->needle); /* copy before freeing job */

    g_free(job->needle);
    g_free(job->directory);
    g_free(job->filter);
    g_free(job);

    g_idle_add(post_results, res);
    return NULL;
}

/* ------------------------------------------------------------------ */
/* Idle: populate tree with results (runs on main thread)            */
/* ------------------------------------------------------------------ */
static gboolean post_results(gpointer data)
{
    FifResult *res = data;

    if (!s_dialog) {
        g_ptr_array_unref(res->hits);
        g_free(res);
        return G_SOURCE_REMOVE;
    }

    gtk_widget_set_sensitive(s_btn_find, TRUE);

    if (res->hits->len == 0) {
        gtk_label_set_text(GTK_LABEL(s_status_lbl), "No matches found.");
        g_ptr_array_unref(res->hits);
        g_free(res->needle);
        g_free(res);
        return G_SOURCE_REMOVE;
    }

    /* Group hits by file (preserve encounter order) */
    GPtrArray  *files   = g_ptr_array_new();
    GHashTable *by_file = g_hash_table_new(g_str_hash, g_str_equal);

    for (guint i = 0; i < res->hits->len; i++) {
        FifHit    *h     = res->hits->pdata[i];
        GPtrArray *fhits = g_hash_table_lookup(by_file, h->filepath);
        if (!fhits) {
            fhits = g_ptr_array_new();
            g_hash_table_insert(by_file, h->filepath, fhits);
            g_ptr_array_add(files, h->filepath);
        }
        g_ptr_array_add(fhits, h);
    }

    /* Populate tree store */
    for (guint fi = 0; fi < files->len; fi++) {
        const char *fp    = files->pdata[fi];
        GPtrArray  *fhits = g_hash_table_lookup(by_file, fp);

        char label[512];
        snprintf(label, sizeof(label), "%s  (%u %s)",
                 fp, fhits->len, fhits->len == 1 ? "hit" : "hits");

        GtkTreeIter parent;
        gtk_tree_store_append(s_store, &parent, NULL);
        gtk_tree_store_set(s_store, &parent,
                           COL_TEXT,     label,
                           COL_WEIGHT,   PANGO_WEIGHT_BOLD,
                           COL_FILEPATH, fp,
                           COL_LINE,     -1,
                           -1);

        for (guint hi = 0; hi < fhits->len; hi++) {
            FifHit *h = fhits->pdata[hi];
            char disp[2048];
            snprintf(disp, sizeof(disp), "  Line %d:   %s", h->line, h->text);

            GtkTreeIter child;
            gtk_tree_store_append(s_store, &child, &parent);
            gtk_tree_store_set(s_store, &child,
                               COL_TEXT,     disp,
                               COL_WEIGHT,   PANGO_WEIGHT_NORMAL,
                               COL_FILEPATH, fp,
                               COL_LINE,     h->line,
                               -1);
        }
    }

    gtk_tree_view_expand_all(GTK_TREE_VIEW(s_tree_view));

    /* Feed the same results into the dockable Search Results panel */
    searchresults_begin(res->needle);
    for (guint fi = 0; fi < files->len; fi++) {
        const char *fp    = files->pdata[fi];
        GPtrArray  *fhits = g_hash_table_lookup(by_file, fp);
        searchresults_add_file(fp, (int)fhits->len);
        for (guint hi = 0; hi < fhits->len; hi++) {
            FifHit *h = fhits->pdata[hi];
            searchresults_add_hit(fp, h->line, h->text);
        }
    }
    searchresults_end((int)res->hits->len, res->file_count);

    /* Free grouping structures */
    for (guint fi = 0; fi < files->len; fi++)
        g_ptr_array_unref(g_hash_table_lookup(by_file, files->pdata[fi]));
    g_hash_table_destroy(by_file);
    g_ptr_array_unref(files);

    char status[128];
    snprintf(status, sizeof(status), "Found %u match%s in %d file%s.",
             res->hits->len, res->hits->len == 1 ? "" : "es",
             res->file_count, res->file_count == 1 ? "" : "s");
    gtk_label_set_text(GTK_LABEL(s_status_lbl), status);

    g_ptr_array_unref(res->hits);
    g_free(res->needle);
    g_free(res);
    return G_SOURCE_REMOVE;
}

/* ------------------------------------------------------------------ */
/* Dialog callbacks                                                    */
/* ------------------------------------------------------------------ */
static void on_row_activated(GtkTreeView *tv, GtkTreePath *path,
                              GtkTreeViewColumn *col, gpointer d)
{
    (void)col; (void)d;
    GtkTreeModel *model = gtk_tree_view_get_model(tv);
    GtkTreeIter   iter;
    if (!gtk_tree_model_get_iter(model, &iter, path)) return;

    gchar *filepath = NULL;
    gint   line     = -1;
    gtk_tree_model_get(model, &iter, COL_FILEPATH, &filepath, COL_LINE, &line, -1);

    if (filepath && line > 0)
        editor_open_and_goto(filepath, line);
    g_free(filepath);
}

static void on_browse(GtkButton *b, gpointer d)
{
    (void)b; (void)d;
    GtkWidget *chooser = gtk_file_chooser_dialog_new(
        "Select Directory", GTK_WINDOW(s_dialog),
        GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER,
        "_Cancel", GTK_RESPONSE_CANCEL,
        "_Select", GTK_RESPONSE_ACCEPT,
        NULL);
    if (gtk_dialog_run(GTK_DIALOG(chooser)) == GTK_RESPONSE_ACCEPT) {
        gchar *folder = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(chooser));
        gtk_entry_set_text(GTK_ENTRY(s_dir_entry), folder ? folder : "");
        g_free(folder);
    }
    gtk_widget_destroy(chooser);
}

static void on_find_all(GtkButton *b, gpointer d)
{
    (void)b; (void)d;

    const char *needle = gtk_entry_get_text(GTK_ENTRY(s_find_entry));
    if (!needle || !*needle) return;
    const char *dir    = gtk_entry_get_text(GTK_ENTRY(s_dir_entry));
    if (!dir || !*dir) {
        gtk_label_set_text(GTK_LABEL(s_status_lbl), "Please select a directory.");
        return;
    }

    /* Clear previous results */
    gtk_tree_store_clear(s_store);
    gtk_label_set_text(GTK_LABEL(s_status_lbl), "Searching…");
    gtk_widget_set_sensitive(s_btn_find, FALSE);

    const char *filter  = gtk_entry_get_text(GTK_ENTRY(s_filter_entry));
    gboolean match_case = gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(s_chk_case));
    gboolean whole_word = gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(s_chk_word));
    gboolean subdirs    = gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(s_chk_subdirs));

    FifJob *job      = g_new0(FifJob, 1);
    job->needle      = g_strdup(needle);
    job->directory   = g_strdup(dir);
    job->filter      = g_strdup(filter && *filter ? filter : "*.*");
    job->match_case  = match_case;
    job->whole_word  = whole_word;
    job->subdirs     = subdirs;
    job->hits        = g_ptr_array_new_with_free_func(fif_hit_free);
    job->file_count  = 0;

    g_thread_new("fif-search", search_thread, job);
}

static void on_clear(GtkButton *b, gpointer d)
{
    (void)b; (void)d;
    gtk_tree_store_clear(s_store);
    gtk_label_set_text(GTK_LABEL(s_status_lbl), "");
}

static void on_close(GtkButton *b, gpointer d)
{
    (void)b; (void)d;
    gtk_widget_hide(s_dialog);
}

/* ------------------------------------------------------------------ */
/* Dialog construction                                                 */
/* ------------------------------------------------------------------ */
static void build_dialog(GtkWidget *parent)
{
    s_dialog = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(s_dialog), T("dlg.Find.titleFindInFiles", "Find in Files"));
    gtk_window_set_default_size(GTK_WINDOW(s_dialog), 720, 540);
    if (parent)
        gtk_window_set_transient_for(GTK_WINDOW(s_dialog), GTK_WINDOW(parent));
    gtk_window_set_destroy_with_parent(GTK_WINDOW(s_dialog), TRUE);
    g_signal_connect(s_dialog, "delete-event", G_CALLBACK(gtk_widget_hide_on_delete), NULL);

    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    gtk_widget_set_margin_start (vbox, 12);
    gtk_widget_set_margin_end   (vbox, 12);
    gtk_widget_set_margin_top   (vbox, 10);
    gtk_widget_set_margin_bottom(vbox, 10);
    gtk_container_add(GTK_CONTAINER(s_dialog), vbox);

    /* ---- Input grid ---- */
    GtkWidget *grid = gtk_grid_new();
    gtk_grid_set_row_spacing   (GTK_GRID(grid), 6);
    gtk_grid_set_column_spacing(GTK_GRID(grid), 8);
    gtk_box_pack_start(GTK_BOX(vbox), grid, FALSE, FALSE, 0);

    /* Row 0: Find what */
    GtkWidget *lbl_find = gtk_label_new(T("dlg.Find.1620", "Find what:"));
    gtk_widget_set_halign(lbl_find, GTK_ALIGN_END);
    s_find_entry = gtk_entry_new();
    gtk_widget_set_hexpand(s_find_entry, TRUE);
    g_signal_connect(s_find_entry, "activate", G_CALLBACK(on_find_all), NULL);
    gtk_grid_attach(GTK_GRID(grid), lbl_find,    0, 0, 1, 1);
    gtk_grid_attach(GTK_GRID(grid), s_find_entry, 1, 0, 2, 1);

    /* Row 1: Directory */
    GtkWidget *lbl_dir = gtk_label_new(T("dlg.Find.1655", "Directory:"));
    gtk_widget_set_halign(lbl_dir, GTK_ALIGN_END);
    s_dir_entry = gtk_entry_new();
    gtk_widget_set_hexpand(s_dir_entry, TRUE);
    GtkWidget *btn_browse = gtk_button_new_with_label("Browse…");
    g_signal_connect(btn_browse, "clicked", G_CALLBACK(on_browse), NULL);
    gtk_grid_attach(GTK_GRID(grid), lbl_dir,    0, 1, 1, 1);
    gtk_grid_attach(GTK_GRID(grid), s_dir_entry, 1, 1, 1, 1);
    gtk_grid_attach(GTK_GRID(grid), btn_browse,  2, 1, 1, 1);

    /* Row 2: Filters */
    GtkWidget *lbl_flt = gtk_label_new(T("dlg.Find.1654", "Filters:"));
    gtk_widget_set_halign(lbl_flt, GTK_ALIGN_END);
    s_filter_entry = gtk_entry_new();
    gtk_entry_set_text(GTK_ENTRY(s_filter_entry), "*.*");
    gtk_widget_set_hexpand(s_filter_entry, TRUE);
    gtk_grid_attach(GTK_GRID(grid), lbl_flt,       0, 2, 1, 1);
    gtk_grid_attach(GTK_GRID(grid), s_filter_entry, 1, 2, 2, 1);

    /* ---- Options ---- */
    GtkWidget *opts = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 20);
    gtk_box_pack_start(GTK_BOX(vbox), opts, FALSE, FALSE, 0);
    s_chk_case   = gtk_check_button_new_with_label(T("dlg.Find.1604", "Match case"));
    s_chk_word   = gtk_check_button_new_with_label(T("dlg.Find.1603", "Whole word"));
    s_chk_subdirs = gtk_check_button_new_with_label(T("dlg.Find.1658", "Search in subdirectories"));
    gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(s_chk_subdirs), TRUE);
    gtk_box_pack_start(GTK_BOX(opts), s_chk_case,   FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(opts), s_chk_word,   FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(opts), s_chk_subdirs, FALSE, FALSE, 0);

    /* ---- Buttons ---- */
    GtkWidget *btns = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    gtk_box_pack_start(GTK_BOX(vbox), btns, FALSE, FALSE, 0);
    s_btn_find         = gtk_button_new_with_label(T("dlg.Find.1656", "Find All"));
    GtkWidget *btn_clr = gtk_button_new_with_label("Clear Results");
    GtkWidget *btn_cls = gtk_button_new_with_label(T("dlg.Find.2", "Close"));
    g_signal_connect(s_btn_find, "clicked", G_CALLBACK(on_find_all), NULL);
    g_signal_connect(btn_clr,    "clicked", G_CALLBACK(on_clear),    NULL);
    g_signal_connect(btn_cls,    "clicked", G_CALLBACK(on_close),    NULL);
    gtk_box_pack_start(GTK_BOX(btns), s_btn_find, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(btns), btn_clr,    FALSE, FALSE, 0);
    gtk_box_pack_end  (GTK_BOX(btns), btn_cls,    FALSE, FALSE, 0);

    gtk_box_pack_start(GTK_BOX(vbox), gtk_separator_new(GTK_ORIENTATION_HORIZONTAL),
                       FALSE, FALSE, 2);

    /* ---- Results tree ---- */
    s_store = gtk_tree_store_new(N_COLS,
                                 G_TYPE_STRING,  /* COL_TEXT     */
                                 G_TYPE_INT,     /* COL_WEIGHT   */
                                 G_TYPE_STRING,  /* COL_FILEPATH */
                                 G_TYPE_INT);    /* COL_LINE     */

    s_tree_view = gtk_tree_view_new_with_model(GTK_TREE_MODEL(s_store));
    gtk_tree_view_set_headers_visible(GTK_TREE_VIEW(s_tree_view), FALSE);
    gtk_tree_view_set_activate_on_single_click(GTK_TREE_VIEW(s_tree_view), FALSE);
    g_signal_connect(s_tree_view, "row-activated", G_CALLBACK(on_row_activated), NULL);

    GtkCellRenderer   *renderer = gtk_cell_renderer_text_new();
    GtkTreeViewColumn *col      = gtk_tree_view_column_new_with_attributes(
        "Result", renderer, "text", COL_TEXT, "weight", COL_WEIGHT, NULL);
    gtk_tree_view_column_set_expand(col, TRUE);
    gtk_tree_view_append_column(GTK_TREE_VIEW(s_tree_view), col);

    GtkWidget *scroll = gtk_scrolled_window_new(NULL, NULL);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll),
                                   GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
    gtk_container_add(GTK_CONTAINER(scroll), s_tree_view);
    gtk_box_pack_start(GTK_BOX(vbox), scroll, TRUE, TRUE, 0);

    /* ---- Status label ---- */
    s_status_lbl = gtk_label_new("");
    gtk_label_set_xalign(GTK_LABEL(s_status_lbl), 0.0);
    gtk_box_pack_start(GTK_BOX(vbox), s_status_lbl, FALSE, FALSE, 0);

    gtk_widget_show_all(vbox);
}

/* ------------------------------------------------------------------ */
/* Public API                                                          */
/* ------------------------------------------------------------------ */
void findinfiles_show(GtkWidget *parent, const char *find_text)
{
    s_parent_win = parent;
    if (!s_dialog)
        build_dialog(parent);

    if (find_text && *find_text)
        gtk_entry_set_text(GTK_ENTRY(s_find_entry), find_text);

    gtk_window_present(GTK_WINDOW(s_dialog));
    gtk_widget_grab_focus(s_find_entry);
}
