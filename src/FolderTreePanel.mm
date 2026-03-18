#import "FolderTreePanel.h"

// ── Tree item model ───────────────────────────────────────────────────────────

@interface _FTItem : NSObject
@property NSURL  *url;
@property BOOL    isDirectory;
@property (nullable) NSMutableArray<_FTItem *> *children; // nil = not yet loaded
@end

@implementation _FTItem
@end

// ── FolderTreePanel ───────────────────────────────────────────────────────────

@implementation FolderTreePanel {
    BOOL               _isLocked;
    NSURL             *_rootURL;
    NSURL             *_activeFileURL;

    // Title bar
    NSTextField       *_titleLabel;
    NSButton          *_unfoldAllButton;
    NSButton          *_foldAllButton;
    NSButton          *_locateButton;
    NSButton          *_closeButton;

    // Secondary toolbar row
    NSButton          *_lockButton;
    NSTextField       *_pathLabel;
    NSButton          *_changeFolderButton;

    // Outline
    NSScrollView      *_scrollView;
    NSOutlineView     *_outlineView;

    // Data
    NSMutableArray<_FTItem *> *_rootChildren;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _rootChildren = [NSMutableArray array];
        [self _buildUI];
    }
    return self;
}

- (instancetype)init {
    return [self initWithFrame:NSZeroRect];
}

// ── UI Construction ───────────────────────────────────────────────────────────

static NSButton *_iconBtn(NSString *iconName, NSString *subdir, NSString *tooltip, id target, SEL action) {
    NSButton *btn = [[NSButton alloc] init];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.bezelStyle = NSBezelStyleSmallSquare;
    btn.bordered = NO;
    btn.toolTip = tooltip;
    btn.target = target;
    btn.action = action;
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
        // Fallback text if icon not found
        btn.title = @"?";
    }
    return btn;
}

- (void)_buildUI {
    self.translatesAutoresizingMaskIntoConstraints = NO;

    // ── Title bar ────────────────────────────────────────────────────────────
    NSView *titleBar = [[NSView alloc] init];
    titleBar.translatesAutoresizingMaskIntoConstraints = NO;

    _titleLabel = [NSTextField labelWithString:@"Folder as Workspace"];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [NSFont boldSystemFontOfSize:11];

    NSString *wsSubdir = @"icons/light/panels/workspace";
    _unfoldAllButton = _iconBtn(@"unfoldall",            wsSubdir, @"Unfold All Folders", self, @selector(_unfoldAll:));
    _foldAllButton   = _iconBtn(@"foldall",              wsSubdir, @"Fold All Folders",   self, @selector(_foldAll:));
    _locateButton    = _iconBtn(@"locate_current_file",  wsSubdir, @"Locate Current File",self, @selector(_locateCurrent:));

    _closeButton = [[NSButton alloc] init];
    _closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    _closeButton.bezelStyle = NSBezelStyleSmallSquare;
    _closeButton.bordered = NO;
    _closeButton.title = @"✕";
    _closeButton.font = [NSFont systemFontOfSize:11];
    _closeButton.toolTip = @"Close panel";
    _closeButton.target = self;
    _closeButton.action = @selector(_closePanel:);
    [_closeButton.widthAnchor  constraintEqualToConstant:20].active = YES;
    [_closeButton.heightAnchor constraintEqualToConstant:20].active = YES;

    [titleBar addSubview:_titleLabel];
    [titleBar addSubview:_unfoldAllButton];
    [titleBar addSubview:_foldAllButton];
    [titleBar addSubview:_locateButton];
    [titleBar addSubview:_closeButton];
    [NSLayoutConstraint activateConstraints:@[
        [titleBar.heightAnchor constraintEqualToConstant:26],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:titleBar.leadingAnchor constant:6],
        [_titleLabel.centerYAnchor constraintEqualToAnchor:titleBar.centerYAnchor],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_unfoldAllButton.leadingAnchor constant:-4],
        [_unfoldAllButton.trailingAnchor constraintEqualToAnchor:_foldAllButton.leadingAnchor constant:-2],
        [_foldAllButton.trailingAnchor constraintEqualToAnchor:_locateButton.leadingAnchor constant:-2],
        [_locateButton.trailingAnchor constraintEqualToAnchor:_closeButton.leadingAnchor constant:-4],
        [_closeButton.trailingAnchor constraintEqualToAnchor:titleBar.trailingAnchor constant:-4],
        [_unfoldAllButton.centerYAnchor constraintEqualToAnchor:titleBar.centerYAnchor],
        [_foldAllButton.centerYAnchor constraintEqualToAnchor:titleBar.centerYAnchor],
        [_locateButton.centerYAnchor constraintEqualToAnchor:titleBar.centerYAnchor],
        [_closeButton.centerYAnchor constraintEqualToAnchor:titleBar.centerYAnchor],
    ]];

    // ── Secondary toolbar (lock / path / change folder) ──────────────────────
    NSView *toolbar = [[NSView alloc] init];
    toolbar.translatesAutoresizingMaskIntoConstraints = NO;

    _lockButton = [NSButton buttonWithTitle:@"\U0001F513"
                                     target:self action:@selector(_toggleLock:)];
    _lockButton.translatesAutoresizingMaskIntoConstraints = NO;
    _lockButton.bezelStyle = NSBezelStyleRounded;
    _lockButton.font = [NSFont systemFontOfSize:11];
    [_lockButton.widthAnchor  constraintEqualToConstant:26].active = YES;
    [_lockButton.heightAnchor constraintEqualToConstant:22].active = YES;

    _pathLabel = [NSTextField labelWithString:@""];
    _pathLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _pathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _pathLabel.font = [NSFont systemFontOfSize:11];
    _pathLabel.textColor = [NSColor secondaryLabelColor];

    _changeFolderButton = [NSButton buttonWithTitle:@"\U0001F4C2"
                                             target:self action:@selector(_changeFolder:)];
    _changeFolderButton.translatesAutoresizingMaskIntoConstraints = NO;
    _changeFolderButton.bezelStyle = NSBezelStyleRounded;
    _changeFolderButton.font = [NSFont systemFontOfSize:11];
    [_changeFolderButton.widthAnchor  constraintEqualToConstant:26].active = YES;
    [_changeFolderButton.heightAnchor constraintEqualToConstant:22].active = YES;

    [toolbar addSubview:_lockButton];
    [toolbar addSubview:_pathLabel];
    [toolbar addSubview:_changeFolderButton];
    [NSLayoutConstraint activateConstraints:@[
        [toolbar.heightAnchor constraintEqualToConstant:26],
        [_lockButton.leadingAnchor constraintEqualToAnchor:toolbar.leadingAnchor constant:2],
        [_lockButton.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],
        [_pathLabel.leadingAnchor constraintEqualToAnchor:_lockButton.trailingAnchor constant:4],
        [_pathLabel.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],
        [_pathLabel.trailingAnchor constraintEqualToAnchor:_changeFolderButton.leadingAnchor constant:-4],
        [_changeFolderButton.trailingAnchor constraintEqualToAnchor:toolbar.trailingAnchor constant:-2],
        [_changeFolderButton.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],
    ]];

    // ── Separators ───────────────────────────────────────────────────────────
    NSBox *sep1 = [[NSBox alloc] init];
    sep1.boxType = NSBoxSeparator;
    sep1.translatesAutoresizingMaskIntoConstraints = NO;
    NSBox *sep2 = [[NSBox alloc] init];
    sep2.boxType = NSBoxSeparator;
    sep2.translatesAutoresizingMaskIntoConstraints = NO;

    // ── OutlineView ──────────────────────────────────────────────────────────
    _outlineView = [[NSOutlineView alloc] init];
    _outlineView.dataSource = self;
    _outlineView.delegate   = self;
    _outlineView.rowHeight  = 22;
    _outlineView.headerView = nil;
    _outlineView.indentationPerLevel = 14;
    _outlineView.autoresizesOutlineColumn = NO;

    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    col.resizingMask = NSTableColumnAutoresizingMask;
    [_outlineView addTableColumn:col];
    _outlineView.outlineTableColumn = col;
    [_outlineView sizeLastColumnToFit];
    _outlineView.target = self;
    _outlineView.doubleAction = @selector(_doubleClicked:);

    _scrollView = [[NSScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.hasVerticalScroller   = YES;
    _scrollView.hasHorizontalScroller = YES;
    _scrollView.autohidesScrollers    = YES;
    _scrollView.documentView = _outlineView;

    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(_itemWillExpand:)
                name:NSOutlineViewItemWillExpandNotification object:_outlineView];

    for (NSView *v in @[titleBar, sep1, toolbar, sep2, _scrollView])
        [self addSubview:v];

    [NSLayoutConstraint activateConstraints:@[
        [titleBar.topAnchor constraintEqualToAnchor:self.topAnchor],
        [titleBar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [titleBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [sep1.topAnchor constraintEqualToAnchor:titleBar.bottomAnchor],
        [sep1.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [sep1.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [sep1.heightAnchor constraintEqualToConstant:1],
        [toolbar.topAnchor constraintEqualToAnchor:sep1.bottomAnchor],
        [toolbar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [toolbar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [sep2.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor],
        [sep2.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [sep2.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [sep2.heightAnchor constraintEqualToConstant:1],
        [_scrollView.topAnchor constraintEqualToAnchor:sep2.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// ── Public API ────────────────────────────────────────────────────────────────

- (void)setActiveFileURL:(NSURL *)fileURL {
    _activeFileURL = fileURL;
    if (_isLocked) return;
    NSURL *dir = [fileURL URLByDeletingLastPathComponent];
    if ([dir isEqual:_rootURL]) return;
    [self _setRootURL:dir];
}

/// Open an NSOpenPanel and set the selected folder as root (called from File > Open Folder as Workspace).
- (void)chooseRootFolder {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.message = @"Choose a folder to show in Folder as Workspace";
    if ([panel runModal] == NSModalResponseOK) {
        _isLocked = YES;
        _lockButton.title = @"\U0001F512";
        [self _setRootURL:panel.URLs.firstObject];
    }
}

// ── Private helpers ───────────────────────────────────────────────────────────

- (void)_setRootURL:(NSURL *)url {
    _rootURL = url;
    _pathLabel.stringValue = url.path.lastPathComponent ?: url.path;
    _pathLabel.toolTip = url.path;
    [self _reloadRoot];
}

- (void)_reloadRoot {
    _rootChildren = [NSMutableArray array];
    [_rootChildren addObjectsFromArray:[self _loadChildrenOfURL:_rootURL]];
    [_outlineView reloadData];
}

- (NSArray<_FTItem *> *)_loadChildrenOfURL:(NSURL *)url {
    NSArray<NSURL *> *contents =
        [[NSFileManager defaultManager]
            contentsOfDirectoryAtURL:url
            includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLNameKey]
            options:NSDirectoryEnumerationSkipsHiddenFiles
            error:nil] ?: @[];
    NSMutableArray<_FTItem *> *dirs = [NSMutableArray array];
    NSMutableArray<_FTItem *> *files = [NSMutableArray array];
    for (NSURL *u in contents) {
        NSNumber *isDir = nil;
        [u getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
        _FTItem *it = [[_FTItem alloc] init];
        it.url = u; it.isDirectory = isDir.boolValue; it.children = nil;
        if (it.isDirectory) [dirs addObject:it];
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

/// Recursively find the item for a given URL, expanding as needed.
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

// ── Actions ───────────────────────────────────────────────────────────────────

- (void)_toggleLock:(id)sender {
    _isLocked = !_isLocked;
    _lockButton.title = _isLocked ? @"\U0001F512" : @"\U0001F513";
    _lockButton.toolTip = _isLocked ? @"Unlock (auto-follow active tab)" : @"Lock root folder";
}

- (void)_changeFolder:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.message = @"Choose a root folder to show in the tree";
    if ([panel runModal] == NSModalResponseOK) {
        _isLocked = YES;
        _lockButton.title = @"\U0001F512";
        [self _setRootURL:panel.URLs.firstObject];
    }
}

- (void)_unfoldAll:(id)sender {
    [_outlineView expandItem:nil expandChildren:YES];
}

- (void)_foldAll:(id)sender {
    [_outlineView collapseItem:nil collapseChildren:YES];
}

- (void)_locateCurrent:(id)sender {
    if (!_activeFileURL || !_rootURL) return;
    // File must be under the current root
    if (![_activeFileURL.path hasPrefix:[_rootURL.path stringByAppendingString:@"/"]]) return;
    _FTItem *found = [self _findItemForURL:_activeFileURL inItems:_rootChildren];
    if (found) {
        NSInteger row = [_outlineView rowForItem:found];
        if (row >= 0) {
            [_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                      byExtendingSelection:NO];
            [_outlineView scrollRowToVisible:row];
        }
    }
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

// ── Lazy expand ───────────────────────────────────────────────────────────────

- (void)_itemWillExpand:(NSNotification *)note { (void)note; }

// ── NSOutlineViewDataSource ───────────────────────────────────────────────────

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(nullable id)item {
    if (!item) return (NSInteger)_rootChildren.count;
    _FTItem *ft = (_FTItem *)item;
    if (!ft.isDirectory) return 0;
    if (!ft.children) ft.children = [[self _loadChildrenOfURL:ft.url] mutableCopy];
    return (NSInteger)ft.children.count;
}

- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)index ofItem:(nullable id)item {
    if (!item) return _rootChildren[index];
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
            [iv.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
            [iv.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [tf.leadingAnchor constraintEqualToAnchor:iv.trailingAnchor constant:4],
            [tf.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [tf.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
        ]];
    }
    cell.textField.stringValue = ft.url.lastPathComponent ?: @"";
    NSImage *icon;
    if (ft.isDirectory) {
        icon = [[NSWorkspace sharedWorkspace] iconForFileType:NSFileTypeForHFSTypeCode(kGenericFolderIcon)];
    } else {
        NSString *ext = ft.url.pathExtension;
        icon = ext.length ? [[NSWorkspace sharedWorkspace] iconForFileType:ext]
                          : [[NSWorkspace sharedWorkspace] iconForFileType:@""];
    }
    icon.size = NSMakeSize(16, 16);
    cell.imageView.image = icon;
    return cell;
}

- (CGFloat)outlineView:(NSOutlineView *)ov heightOfRowByItem:(id)item {
    return 22;
}

@end
