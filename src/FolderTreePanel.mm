#import "FolderTreePanel.h"
#import "StyleConfiguratorWindowController.h"

// ── Tree item model ───────────────────────────────────────────────────────────

@interface _FTItem : NSObject
@property NSURL  *url;
@property BOOL    isDirectory;
@property BOOL    isRootFolder;   // YES for user-added top-level dirs
@property (nullable) NSMutableArray<_FTItem *> *children; // nil = not yet loaded
@end

@implementation _FTItem
@end

// ── Forward declaration so _FTOutlineView can call FolderTreePanel ────────────

@interface FolderTreePanel ()
- (NSMenu *)_contextMenuForRow:(NSInteger)row;
- (nullable _FTItem *)_expandPathComponents:(NSArray<NSString *> *)components fromRoot:(_FTItem *)root;
@end

// ── Custom outline view — right-click delegates to panel ─────────────────────

@interface _FTOutlineView : NSOutlineView
@property (nonatomic, weak) FolderTreePanel *ftPanel;
@end

@implementation _FTOutlineView
- (NSMenu *)menuForEvent:(NSEvent *)event {
    NSPoint p   = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger row = [self rowAtPoint:p];
    return [_ftPanel _contextMenuForRow:row];
}
@end

// ── Constants ─────────────────────────────────────────────────────────────────

static NSString * const kDefaultsRootsKey   = @"FolderTreePanelRoots";
static NSString * const kToolbarSubdir      = @"icons/standard/panels/toolbar";
static NSString * const kTreeviewSubdir     = @"icons/standard/panels/treeview";

// ── FolderTreePanel ───────────────────────────────────────────────────────────

@implementation FolderTreePanel {
    NSURL                     *_activeFileURL;

    // Title bar
    NSView                    *_titleBar;
    NSButton                  *_unfoldAllButton;
    NSButton                  *_foldAllButton;
    NSButton                  *_locateButton;
    NSButton                  *_closeButton;

    // Tree
    NSScrollView              *_scrollView;
    _FTOutlineView            *_outlineView;

    // Data — multiple user-added root folders
    NSMutableArray<_FTItem *> *_roots;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _roots = [NSMutableArray array];
        [self _buildUI];
        [self _applyTheme];
        [self _restoreRoots];
    }
    return self;
}

- (instancetype)init {
    return [self initWithFrame:NSZeroRect];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// ── UI Construction ───────────────────────────────────────────────────────────

static NSButton *_panelBtn(NSString *iconName, NSString *subdir, NSString *tip, id target, SEL action) {
    NSButton *btn = [[NSButton alloc] init];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.bezelStyle = NSBezelStyleSmallSquare;
    btn.bordered   = NO;
    btn.toolTip    = tip;
    btn.target     = target;
    btn.action     = action;
    [btn.widthAnchor  constraintEqualToConstant:22].active = YES;
    [btn.heightAnchor constraintEqualToConstant:22].active = YES;
    NSURL *url = [[NSBundle mainBundle] URLForResource:iconName withExtension:@"png"
                                          subdirectory:subdir];
    NSImage *img = url ? [[NSImage alloc] initWithContentsOfURL:url] : nil;
    if (img) {
        img.size = NSMakeSize(16, 16);
        btn.image = img;
        btn.imageScaling = NSImageScaleProportionallyDown;
    } else {
        btn.title = @"?";
    }
    return btn;
}

- (void)_buildUI {
    self.translatesAutoresizingMaskIntoConstraints = NO;

    // ── Title bar ─────────────────────────────────────────────────────────
    _titleBar = [[NSView alloc] init];
    _titleBar.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *titleBar = _titleBar;

    NSTextField *titleLabel = [NSTextField labelWithString:@"Folder as Workspace"];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [NSFont boldSystemFontOfSize:11];

    _unfoldAllButton = _panelBtn(@"fb_expand_all",          kToolbarSubdir, @"Expand All",         self, @selector(_unfoldAll:));
    _foldAllButton   = _panelBtn(@"fb_fold_all",            kToolbarSubdir, @"Fold All",            self, @selector(_foldAll:));
    _locateButton    = _panelBtn(@"fb_select_current_file", kToolbarSubdir, @"Locate Current File", self, @selector(_locateCurrent:));

    _closeButton = [[NSButton alloc] init];
    _closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    _closeButton.bezelStyle = NSBezelStyleSmallSquare;
    _closeButton.bordered   = NO;
    _closeButton.title      = @"✕";
    _closeButton.font       = [NSFont systemFontOfSize:11];
    _closeButton.toolTip    = @"Close panel";
    _closeButton.target     = self;
    _closeButton.action     = @selector(_closePanel:);
    [_closeButton.widthAnchor  constraintEqualToConstant:20].active = YES;
    [_closeButton.heightAnchor constraintEqualToConstant:20].active = YES;

    for (NSView *v in @[titleLabel, _unfoldAllButton, _foldAllButton, _locateButton, _closeButton])
        [titleBar addSubview:v];

    [NSLayoutConstraint activateConstraints:@[
        [titleBar.heightAnchor constraintEqualToConstant:26],
        [titleLabel.leadingAnchor    constraintEqualToAnchor:titleBar.leadingAnchor constant:6],
        [titleLabel.centerYAnchor   constraintEqualToAnchor:titleBar.centerYAnchor],
        [titleLabel.trailingAnchor  constraintLessThanOrEqualToAnchor:_unfoldAllButton.leadingAnchor constant:-4],
        [_unfoldAllButton.trailingAnchor constraintEqualToAnchor:_foldAllButton.leadingAnchor  constant:-2],
        [_foldAllButton.trailingAnchor   constraintEqualToAnchor:_locateButton.leadingAnchor   constant:-2],
        [_locateButton.trailingAnchor    constraintEqualToAnchor:_closeButton.leadingAnchor    constant:-4],
        [_closeButton.trailingAnchor     constraintEqualToAnchor:titleBar.trailingAnchor       constant:-4],
        [_unfoldAllButton.centerYAnchor  constraintEqualToAnchor:titleBar.centerYAnchor],
        [_foldAllButton.centerYAnchor    constraintEqualToAnchor:titleBar.centerYAnchor],
        [_locateButton.centerYAnchor     constraintEqualToAnchor:titleBar.centerYAnchor],
        [_closeButton.centerYAnchor      constraintEqualToAnchor:titleBar.centerYAnchor],
    ]];

    // ── Separator ─────────────────────────────────────────────────────────
    NSBox *sep = [[NSBox alloc] init];
    sep.boxType = NSBoxSeparator;
    sep.translatesAutoresizingMaskIntoConstraints = NO;

    // ── OutlineView ───────────────────────────────────────────────────────
    _outlineView = [[_FTOutlineView alloc] init];
    _outlineView.ftPanel    = self;
    _outlineView.dataSource = self;
    _outlineView.delegate   = self;
    _outlineView.rowHeight  = 22;
    _outlineView.headerView = nil;
    _outlineView.indentationPerLevel  = 14;
    _outlineView.autoresizesOutlineColumn = NO;

    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    col.resizingMask = NSTableColumnAutoresizingMask;
    [_outlineView addTableColumn:col];
    _outlineView.outlineTableColumn = col;
    [_outlineView sizeLastColumnToFit];
    _outlineView.target       = self;
    _outlineView.doubleAction = @selector(_doubleClicked:);

    _scrollView = [[NSScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.hasVerticalScroller   = YES;
    _scrollView.hasHorizontalScroller = YES;
    _scrollView.autohidesScrollers    = YES;
    _scrollView.documentView = _outlineView;

    // Icon updates when folders expand/collapse + theme changes
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(_itemExpandedOrCollapsed:)
               name:NSOutlineViewItemDidExpandNotification  object:_outlineView];
    [nc addObserver:self selector:@selector(_itemExpandedOrCollapsed:)
               name:NSOutlineViewItemDidCollapseNotification object:_outlineView];
    [nc addObserver:self selector:@selector(_themeChanged:)
               name:@"NPPPreferencesChanged" object:nil];

    for (NSView *v in @[titleBar, sep, _scrollView])
        [self addSubview:v];

    [NSLayoutConstraint activateConstraints:@[
        [titleBar.topAnchor    constraintEqualToAnchor:self.topAnchor],
        [titleBar.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [titleBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [sep.topAnchor     constraintEqualToAnchor:titleBar.bottomAnchor],
        [sep.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [sep.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [sep.heightAnchor constraintEqualToConstant:1],
        [_scrollView.topAnchor     constraintEqualToAnchor:sep.bottomAnchor],
        [_scrollView.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_scrollView.bottomAnchor   constraintEqualToAnchor:self.bottomAnchor],
    ]];
}

// ── Theme ─────────────────────────────────────────────────────────────────────

- (void)_applyTheme {
    NSColor *bg = [[NPPStyleStore sharedStore] globalBg];
    CGFloat brightness = bg.brightnessComponent;

    // Theme only the tree/scroll area.
    self.wantsLayer = YES;
    self.layer.backgroundColor = bg.CGColor;
    _outlineView.backgroundColor = bg;
    _scrollView.backgroundColor = bg;

    // Title bar: opaque system color so it never inherits the editor theme.
    _titleBar.wantsLayer = YES;
    _titleBar.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;

    // Match disclosure-triangle (arrow) color to background: dark bg → DarkAqua appearance
    // so arrows are drawn white; light bg → Aqua so arrows are drawn dark.
    _outlineView.appearance = [NSAppearance appearanceNamed:
        brightness < 0.5 ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];

    // Reload so every visible cell picks up the new text color immediately.
    [_outlineView reloadData];
}

- (void)_themeChanged:(NSNotification *)note {
    [self _applyTheme];
}

// ── Public API ────────────────────────────────────────────────────────────────

- (void)setActiveFileURL:(NSURL *)fileURL {
    _activeFileURL = fileURL;
}

- (void)chooseRootFolder {
    [self _addFolder:nil];
}

// ── Persistence ───────────────────────────────────────────────────────────────

- (void)_saveRoots {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (_FTItem *root in _roots)
        [paths addObject:root.url.path];
    [[NSUserDefaults standardUserDefaults] setObject:paths forKey:kDefaultsRootsKey];
}

- (void)_restoreRoots {
    NSArray<NSString *> *paths = [[NSUserDefaults standardUserDefaults]
                                  arrayForKey:kDefaultsRootsKey];
    for (NSString *path in paths) {
        BOOL isDir = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] || !isDir)
            continue;
        _FTItem *root = [[_FTItem alloc] init];
        root.url          = [NSURL fileURLWithPath:path];
        root.isDirectory  = YES;
        root.isRootFolder = YES;
        [_roots addObject:root];
    }
    [_outlineView reloadData];
}

// ── Internal helpers ──────────────────────────────────────────────────────────

- (void)_addRootURL:(NSURL *)url {
    for (_FTItem *r in _roots)
        if ([r.url isEqual:url]) return;   // already present
    _FTItem *root = [[_FTItem alloc] init];
    root.url          = url;
    root.isDirectory  = YES;
    root.isRootFolder = YES;
    [_roots addObject:root];
    [_outlineView reloadData];
}

- (NSArray<_FTItem *> *)_loadChildrenOfURL:(NSURL *)url {
    NSArray<NSURL *> *contents =
        [[NSFileManager defaultManager]
            contentsOfDirectoryAtURL:url
            includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLNameKey]
            options:NSDirectoryEnumerationSkipsHiddenFiles
            error:nil] ?: @[];
    NSMutableArray<_FTItem *> *dirs  = [NSMutableArray array];
    NSMutableArray<_FTItem *> *files = [NSMutableArray array];
    for (NSURL *u in contents) {
        NSNumber *isDir = nil;
        [u getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
        _FTItem *it = [[_FTItem alloc] init];
        it.url = u; it.isDirectory = isDir.boolValue; it.children = nil;
        if (it.isDirectory) [dirs  addObject:it];
        else                [files addObject:it];
    }
    NSSortDescriptor *sd = [NSSortDescriptor
        sortDescriptorWithKey:@"url.lastPathComponent" ascending:YES
                     selector:@selector(localizedCaseInsensitiveCompare:)];
    [dirs  sortUsingDescriptors:@[sd]];
    [files sortUsingDescriptors:@[sd]];
    NSMutableArray *result = [NSMutableArray arrayWithArray:dirs];
    [result addObjectsFromArray:files];
    return result;
}

/// Recursively find the _FTItem for url, expanding parents as needed.
- (nullable _FTItem *)_findItemForURL:(NSURL *)url inItems:(NSArray<_FTItem *> *)items {
    for (_FTItem *it in items) {
        if ([it.url isEqual:url]) return it;
        if (it.isDirectory && [url.path hasPrefix:[it.url.path stringByAppendingString:@"/"]]) {
            if (!it.children) it.children = [[self _loadChildrenOfURL:it.url] mutableCopy];
            [_outlineView expandItem:it];
            _FTItem *found = [self _findItemForURL:url inItems:it.children];
            if (found) return found;
        }
    }
    return nil;
}

- (NSImage *)_treeviewIcon:(NSString *)name {
    NSURL *url = [[NSBundle mainBundle] URLForResource:name withExtension:@"png"
                                          subdirectory:kTreeviewSubdir];
    NSImage *img = url ? [[NSImage alloc] initWithContentsOfURL:url] : nil;
    if (img) img.size = NSMakeSize(16, 16);
    return img;
}

// ── Actions ───────────────────────────────────────────────────────────────────

- (void)_unfoldAll:(id)sender {
    [_outlineView expandItem:nil expandChildren:YES];
}

- (void)_foldAll:(id)sender {
    [_outlineView collapseItem:nil collapseChildren:YES];
}

- (void)_locateCurrent:(id)sender {
    if (!_activeFileURL) return;
    NSString *targetPath = _activeFileURL.path.stringByStandardizingPath;
    if (!targetPath.length) return;

    // Only locate real files on disk, not directories or untitled buffers
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:targetPath isDirectory:&isDir] || isDir)
        return;

    for (_FTItem *root in _roots) {
        NSString *rootPath = root.url.path.stringByStandardizingPath;
        if (![targetPath hasPrefix:[rootPath stringByAppendingString:@"/"]])
            continue;

        // Path components between root and file, e.g. ["src", "main.mm"]
        NSString *relative = [targetPath substringFromIndex:rootPath.length + 1];
        NSArray<NSString *> *components = [relative pathComponents];
        if (!components.count) continue;

        _FTItem *fileItem = [self _expandPathComponents:components fromRoot:root];
        if (!fileItem) return;

        NSInteger row = [_outlineView rowForItem:fileItem];
        if (row >= 0) {
            [_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                      byExtendingSelection:NO];
            [_outlineView scrollRowToVisible:row];
        }
        return;
    }
}

/// Load and expand every folder along the path, return the final file item.
- (nullable _FTItem *)_expandPathComponents:(NSArray<NSString *> *)components
                                   fromRoot:(_FTItem *)root {
    if (!root.children)
        root.children = [[self _loadChildrenOfURL:root.url] mutableCopy];
    [_outlineView expandItem:root];

    _FTItem *current = root;
    for (NSUInteger i = 0; i < components.count - 1; i++) {
        if (!current.children)
            current.children = [[self _loadChildrenOfURL:current.url] mutableCopy];
        _FTItem *next = nil;
        for (_FTItem *child in current.children)
            if ([child.url.lastPathComponent isEqualToString:components[i]]) { next = child; break; }
        if (!next) return nil;
        if (!next.children)
            next.children = [[self _loadChildrenOfURL:next.url] mutableCopy];
        [_outlineView expandItem:next];
        current = next;
    }

    // Expand the parent and find the file
    if (!current.children)
        current.children = [[self _loadChildrenOfURL:current.url] mutableCopy];
    [_outlineView expandItem:current];
    for (_FTItem *child in current.children)
        if ([child.url.lastPathComponent isEqualToString:components.lastObject]) return child;
    return nil;
}

- (void)_closePanel:(id)sender {
    [_delegate folderTreePanelDidRequestClose:self];
}

- (void)_doubleClicked:(id)sender {
    id item = [_outlineView itemAtRow:_outlineView.clickedRow];
    if (!item) return;
    _FTItem *ft = (_FTItem *)item;
    if (!ft.isDirectory && _delegate)
        [_delegate folderTreePanel:self openFileAtURL:ft.url];
}

- (void)_itemExpandedOrCollapsed:(NSNotification *)note {
    _FTItem *item = note.userInfo[@"NSObject"];
    if (item) [_outlineView reloadItem:item];
}

// ── "Add Folder…" / "Remove All" actions ─────────────────────────────────────

- (void)_addFolder:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles        = NO;
    panel.canChooseDirectories  = YES;
    panel.allowsMultipleSelection = YES;
    panel.message = @"Choose a folder to add to the workspace";
    if ([panel runModal] == NSModalResponseOK) {
        for (NSURL *url in panel.URLs)
            [self _addRootURL:url];
        [self _saveRoots];
    }
}

- (void)_removeAllFolders:(id)sender {
    [_roots removeAllObjects];
    [_outlineView reloadData];
    [self _saveRoots];
}

// ── Context menus ─────────────────────────────────────────────────────────────

- (NSMenu *)_contextMenuForRow:(NSInteger)row {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];

    if (row < 0) {
        // Blank space
        NSMenuItem *add = [[NSMenuItem alloc] initWithTitle:@"Add Folder…"
                                                     action:@selector(_addFolder:) keyEquivalent:@""];
        add.target = self;
        [menu addItem:add];
        NSMenuItem *removeAll = [[NSMenuItem alloc] initWithTitle:@"Remove All"
                                                           action:@selector(_removeAllFolders:) keyEquivalent:@""];
        removeAll.target = self;
        [menu addItem:removeAll];
        return menu;
    }

    _FTItem *ft = (_FTItem *)[_outlineView itemAtRow:row];
    if (!ft) return menu;

    if (ft.isDirectory) {
        // Root folder: show Remove at top
        if (ft.isRootFolder) {
            NSMenuItem *remove = [[NSMenuItem alloc] initWithTitle:@"Remove"
                                                            action:@selector(_menuRemoveFolder:) keyEquivalent:@""];
            remove.target            = self;
            remove.representedObject = ft;
            [menu addItem:remove];
            [menu addItem:[NSMenuItem separatorItem]];
        }
        NSMenuItem *copyPath = [[NSMenuItem alloc] initWithTitle:@"Copy Path"
                                                          action:@selector(_menuCopyPath:) keyEquivalent:@""];
        copyPath.target            = self;
        copyPath.representedObject = ft;
        [menu addItem:copyPath];

        NSMenuItem *fif = [[NSMenuItem alloc] initWithTitle:@"Find in Files"
                                                     action:@selector(_menuFindInFiles:) keyEquivalent:@""];
        fif.target            = self;
        fif.representedObject = ft;
        [menu addItem:fif];

        NSMenuItem *finder = [[NSMenuItem alloc] initWithTitle:@"Finder Here"
                                                        action:@selector(_menuFinderHere:) keyEquivalent:@""];
        finder.target            = self;
        finder.representedObject = ft;
        [menu addItem:finder];

        NSMenuItem *term = [[NSMenuItem alloc] initWithTitle:@"Terminal Here"
                                                      action:@selector(_menuTerminalHere:) keyEquivalent:@""];
        term.target            = self;
        term.representedObject = ft;
        [menu addItem:term];

    } else {
        // File
        NSMenuItem *open = [[NSMenuItem alloc] initWithTitle:@"Open"
                                                      action:@selector(_menuOpenFile:) keyEquivalent:@""];
        open.target            = self;
        open.representedObject = ft;
        [menu addItem:open];
        [menu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *copyPath = [[NSMenuItem alloc] initWithTitle:@"Copy Path"
                                                          action:@selector(_menuCopyPath:) keyEquivalent:@""];
        copyPath.target            = self;
        copyPath.representedObject = ft;
        [menu addItem:copyPath];

        NSMenuItem *copyName = [[NSMenuItem alloc] initWithTitle:@"Copy File Name"
                                                          action:@selector(_menuCopyFileName:) keyEquivalent:@""];
        copyName.target            = self;
        copyName.representedObject = ft;
        [menu addItem:copyName];
        [menu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *run = [[NSMenuItem alloc] initWithTitle:@"Run by System"
                                                     action:@selector(_menuRunBySystem:) keyEquivalent:@""];
        run.target            = self;
        run.representedObject = ft;
        [menu addItem:run];

        NSMenuItem *finder = [[NSMenuItem alloc] initWithTitle:@"Finder Here"
                                                        action:@selector(_menuFinderHere:) keyEquivalent:@""];
        finder.target            = self;
        finder.representedObject = ft;
        [menu addItem:finder];

        NSMenuItem *term = [[NSMenuItem alloc] initWithTitle:@"Terminal Here"
                                                      action:@selector(_menuTerminalHere:) keyEquivalent:@""];
        term.target            = self;
        term.representedObject = ft;
        [menu addItem:term];
    }
    return menu;
}

// ── Context menu action handlers ──────────────────────────────────────────────

- (void)_menuRemoveFolder:(NSMenuItem *)sender {
    _FTItem *ft = sender.representedObject;
    [_roots removeObject:ft];
    [_outlineView reloadData];
    [self _saveRoots];
}

- (void)_menuCopyPath:(NSMenuItem *)sender {
    _FTItem *ft = sender.representedObject;
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:ft.url.path forType:NSPasteboardTypeString];
}

- (void)_menuCopyFileName:(NSMenuItem *)sender {
    _FTItem *ft = sender.representedObject;
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:ft.url.lastPathComponent forType:NSPasteboardTypeString];
}

- (void)_menuFindInFiles:(NSMenuItem *)sender {
    _FTItem *ft = sender.representedObject;
    NSString *path = ft.isDirectory ? ft.url.path
                                    : ft.url.URLByDeletingLastPathComponent.path;
    [_delegate folderTreePanel:self findInFilesAtPath:path];
}

- (void)_menuFinderHere:(NSMenuItem *)sender {
    _FTItem *ft = sender.representedObject;
    if (ft.isDirectory) {
        [[NSWorkspace sharedWorkspace] openURL:ft.url];
    } else {
        [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ft.url]];
    }
}

- (void)_menuTerminalHere:(NSMenuItem *)sender {
    _FTItem *ft = sender.representedObject;
    NSString *dir = ft.isDirectory ? ft.url.path
                                   : ft.url.URLByDeletingLastPathComponent.path;
    // open -a Terminal <dir> always opens a NEW Terminal window at that path
    [NSTask launchedTaskWithLaunchPath:@"/usr/bin/open"
                             arguments:@[@"-a", @"Terminal", dir]];
}

- (void)_menuOpenFile:(NSMenuItem *)sender {
    _FTItem *ft = sender.representedObject;
    [_delegate folderTreePanel:self openFileAtURL:ft.url];
}

- (void)_menuRunBySystem:(NSMenuItem *)sender {
    _FTItem *ft = sender.representedObject;
    NSString *escaped = [ft.url.path stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    NSString *script  = [NSString stringWithFormat:
        @"tell application \"Terminal\"\n"
         "  activate\n"
         "  do script \"'%@'\"\n"
         "end tell", escaped];
    NSAppleScript *as = [[NSAppleScript alloc] initWithSource:script];
    [as executeAndReturnError:nil];
}

// ── NSOutlineViewDataSource ───────────────────────────────────────────────────

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(nullable id)item {
    if (!item) return (NSInteger)_roots.count;
    _FTItem *ft = (_FTItem *)item;
    if (!ft.isDirectory) return 0;
    if (!ft.children) ft.children = [[self _loadChildrenOfURL:ft.url] mutableCopy];
    return (NSInteger)ft.children.count;
}

- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)index ofItem:(nullable id)item {
    if (!item) return _roots[(NSUInteger)index];
    return ((_FTItem *)item).children[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item {
    return ((_FTItem *)item).isDirectory;
}

// ── NSOutlineViewDelegate ─────────────────────────────────────────────────────

- (NSView *)outlineView:(NSOutlineView *)ov viewForTableColumn:(NSTableColumn *)col item:(id)item {
    _FTItem *ft = (_FTItem *)item;
    NSTableCellView *cell = [ov makeViewWithIdentifier:@"cell" owner:nil];
    if (!cell) {
        cell = [[NSTableCellView alloc] init];
        cell.identifier = @"cell";
        NSImageView *iv = [[NSImageView alloc] init];
        iv.translatesAutoresizingMaskIntoConstraints = NO;
        iv.imageFrameStyle = NSImageFrameNone;
        [iv.widthAnchor  constraintEqualToConstant:16].active = YES;
        [iv.heightAnchor constraintEqualToConstant:16].active = YES;
        cell.imageView = iv;
        NSTextField *tf = [NSTextField labelWithString:@""];
        tf.translatesAutoresizingMaskIntoConstraints = NO;
        tf.lineBreakMode = NSLineBreakByTruncatingMiddle;
        tf.font = [NSFont systemFontOfSize:12];
        cell.textField = tf;
        [cell addSubview:iv];
        [cell addSubview:tf];
        [NSLayoutConstraint activateConstraints:@[
            [iv.leadingAnchor   constraintEqualToAnchor:cell.leadingAnchor constant:2],
            [iv.centerYAnchor   constraintEqualToAnchor:cell.centerYAnchor],
            [tf.leadingAnchor   constraintEqualToAnchor:iv.trailingAnchor  constant:4],
            [tf.centerYAnchor   constraintEqualToAnchor:cell.centerYAnchor],
            [tf.trailingAnchor  constraintEqualToAnchor:cell.trailingAnchor constant:-2],
        ]];
    }

    cell.textField.stringValue = ft.url.lastPathComponent ?: @"";
    cell.textField.textColor   = [[NPPStyleStore sharedStore] globalFg];

    NSImage *icon = nil;
    if (ft.isDirectory) {
        BOOL expanded = [ov isItemExpanded:ft];
        NSString *iconName;
        if (ft.isRootFolder)
            iconName = expanded ? @"fb_root_open"          : @"fb_root_close";
        else
            iconName = expanded ? @"project_folder_open"   : @"project_folder_close";
        icon = [self _treeviewIcon:iconName];
        if (!icon) {
            icon = [[NSWorkspace sharedWorkspace] iconForFileType:NSFileTypeForHFSTypeCode(kGenericFolderIcon)];
            icon.size = NSMakeSize(16, 16);
        }
    } else {
        NSString *ext = ft.url.pathExtension;
        icon = ext.length ? [[NSWorkspace sharedWorkspace] iconForFileType:ext]
                          : [[NSWorkspace sharedWorkspace] iconForFileType:@""];
        icon.size = NSMakeSize(16, 16);
    }
    cell.imageView.image = icon;
    return cell;
}

- (CGFloat)outlineView:(NSOutlineView *)ov heightOfRowByItem:(id)item {
    return 22;
}

@end
