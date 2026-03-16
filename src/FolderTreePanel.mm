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

    // Header
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

- (void)_buildUI {
    self.translatesAutoresizingMaskIntoConstraints = NO;

    // Lock / unlock button
    _lockButton = [NSButton buttonWithTitle:@"\U0001F513" // 🔓
                                     target:self
                                     action:@selector(_toggleLock:)];
    _lockButton.translatesAutoresizingMaskIntoConstraints = NO;
    _lockButton.bezelStyle = NSBezelStyleRounded;
    _lockButton.font = [NSFont systemFontOfSize:12];
    [_lockButton.widthAnchor  constraintEqualToConstant:28].active = YES;
    [_lockButton.heightAnchor constraintEqualToConstant:24].active = YES;

    // Path label
    _pathLabel = [NSTextField labelWithString:@""];
    _pathLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _pathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _pathLabel.font = [NSFont systemFontOfSize:11];
    _pathLabel.textColor = [NSColor secondaryLabelColor];

    // Change Folder button
    _changeFolderButton = [NSButton buttonWithTitle:@"\U0001F4C2" // 📂
                                              target:self
                                              action:@selector(_changeFolder:)];
    _changeFolderButton.translatesAutoresizingMaskIntoConstraints = NO;
    _changeFolderButton.bezelStyle = NSBezelStyleRounded;
    _changeFolderButton.font = [NSFont systemFontOfSize:12];
    [_changeFolderButton.widthAnchor  constraintEqualToConstant:28].active = YES;
    [_changeFolderButton.heightAnchor constraintEqualToConstant:24].active = YES;

    // Header container
    NSView *header = [[NSView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:_lockButton];
    [header addSubview:_pathLabel];
    [header addSubview:_changeFolderButton];
    [NSLayoutConstraint activateConstraints:@[
        [header.heightAnchor constraintEqualToConstant:28],
        [_lockButton.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:2],
        [_lockButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [_pathLabel.leadingAnchor constraintEqualToAnchor:_lockButton.trailingAnchor constant:4],
        [_pathLabel.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [_pathLabel.trailingAnchor constraintEqualToAnchor:_changeFolderButton.leadingAnchor constant:-4],
        [_changeFolderButton.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-2],
        [_changeFolderButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
    ]];

    // Separator
    NSBox *sep = [[NSBox alloc] init];
    sep.boxType = NSBoxSeparator;
    sep.translatesAutoresizingMaskIntoConstraints = NO;

    // OutlineView
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

    // Double-click to open
    _outlineView.target = self;
    _outlineView.doubleAction = @selector(_doubleClicked:);

    _scrollView = [[NSScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.hasVerticalScroller   = YES;
    _scrollView.hasHorizontalScroller = YES;
    _scrollView.autohidesScrollers    = YES;
    _scrollView.documentView = _outlineView;

    // Expand notification for lazy loading
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_itemWillExpand:)
               name:NSOutlineViewItemWillExpandNotification
             object:_outlineView];

    for (NSView *v in @[header, sep, _scrollView])
        [self addSubview:v];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:self.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [sep.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [sep.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [sep.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [sep.heightAnchor constraintEqualToConstant:1],
        [_scrollView.topAnchor constraintEqualToAnchor:sep.bottomAnchor],
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
    if (_isLocked) return;
    NSURL *dir = [fileURL URLByDeletingLastPathComponent];
    if ([dir isEqual:_rootURL]) return;
    [self _setRootURL:dir];
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
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSURL *> *contents = [fm contentsOfDirectoryAtURL:url
                                   includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLNameKey]
                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                        error:nil] ?: @[];
    // Sort: directories first, then alphabetical within each group
    NSMutableArray<_FTItem *> *dirs  = [NSMutableArray array];
    NSMutableArray<_FTItem *> *files = [NSMutableArray array];
    for (NSURL *u in contents) {
        NSNumber *isDir = nil;
        [u getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
        _FTItem *it = [[_FTItem alloc] init];
        it.url         = u;
        it.isDirectory = isDir.boolValue;
        it.children    = nil;  // lazy
        if (it.isDirectory) [dirs addObject:it];
        else                [files addObject:it];
    }
    NSSortDescriptor *sd = [NSSortDescriptor sortDescriptorWithKey:@"url.lastPathComponent"
                                                         ascending:YES
                                                          selector:@selector(localizedCaseInsensitiveCompare:)];
    [dirs  sortUsingDescriptors:@[sd]];
    [files sortUsingDescriptors:@[sd]];
    NSMutableArray *result = [NSMutableArray arrayWithArray:dirs];
    [result addObjectsFromArray:files];
    return result;
}

// ── Actions ───────────────────────────────────────────────────────────────────

- (void)_toggleLock:(id)sender {
    _isLocked = !_isLocked;
    // Use emoji characters directly since emoji literals work reliably in ObjC strings
    NSString *locked   = @"\U0001F512"; // 🔒
    NSString *unlocked = @"\U0001F513"; // 🔓
    _lockButton.title = _isLocked ? locked : unlocked;
    _lockButton.toolTip = _isLocked ? @"Unlock (auto-follow active tab)" : @"Lock root folder";
}

- (void)_changeFolder:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles      = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.message = @"Choose a root folder to show in the tree";
    if ([panel runModal] == NSModalResponseOK) {
        _isLocked = YES;
        NSString *locked = @"\U0001F512";
        _lockButton.title = locked;
        [self _setRootURL:panel.URLs.firstObject];
    }
}

- (void)_doubleClicked:(id)sender {
    id item = [_outlineView itemAtRow:_outlineView.clickedRow];
    if (!item) return;
    _FTItem *ft = (_FTItem *)item;
    if (!ft.isDirectory && _delegate)
        [_delegate folderTreePanel:self openFileAtURL:ft.url];
}

// ── Lazy expand ───────────────────────────────────────────────────────────────

- (void)_itemWillExpand:(NSNotification *)note {
    // Children are loaded lazily in numberOfChildrenOfItem: — nothing to do here.
    // The notification observer is kept so future logic can be added.
    (void)note;
}

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
    _FTItem *ft = (_FTItem *)item;
    return ft.children[(NSUInteger)index];
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
    // Use workspace icon
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
