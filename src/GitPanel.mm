#import "GitPanel.h"
#import "GitHelper.h"
#import "NppLocalizer.h"
#import "StyleConfiguratorWindowController.h"

// ── Status item model ─────────────────────────────────────────────────────────

@interface _GitStatusItem : NSObject
@property NSString *xy;    // 2-char porcelain status (e.g. " M", "??", "A ")
@property NSString *path;  // repo-relative path
@end

@implementation _GitStatusItem
@end

// ── GitPanel implementation ───────────────────────────────────────────────────

@implementation GitPanel {
    NSString             *_repoRoot;
    NSArray<_GitStatusItem *> *_items;

    // Title bar
    NSTextField          *_titleLabel;
    NSButton             *_browseRepoButton;
    NSButton             *_refreshButton;
    NSButton             *_closeButton;

    // Header (branch info)
    NSTextField          *_branchLabel;

    // Table
    NSScrollView         *_scrollView;
    NSTableView          *_tableView;

    // Buttons
    NSButton             *_stageAllButton;
    NSButton             *_unstageAllButton;

    // Commit
    NSTextField          *_commitField;
    NSButton             *_commitButton;

    // No-repo state
    NSTextField          *_noRepoLabel;

    // Cached bullet image
    NSImage              *_bulletImage;
}

static NSString * const kLastRepoRootKey = @"GitPanelLastRepoRoot";

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _items = @[];
        [self _loadBulletImage];
        [self _buildUI];
        [self _setNoRepo:YES];
        [self _applyTheme];
        [[NSNotificationCenter defaultCenter]
            addObserver:self selector:@selector(_themeChanged:)
                   name:@"NPPPreferencesChanged" object:nil];
        [[NSNotificationCenter defaultCenter]
            addObserver:self selector:@selector(_locChanged:)
                   name:NPPLocalizationChanged object:nil];
        [self retranslateUI];
        // Restore last repo
        NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:kLastRepoRootKey];
        if (saved) {
            BOOL isDir = NO;
            if ([[NSFileManager defaultManager] fileExistsAtPath:saved isDirectory:&isDir] && isDir) {
                [self setRepoRoot:saved];
                [self refresh];
            }
        }
    }
    return self;
}

- (instancetype)init {
    return [self initWithFrame:NSZeroRect];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)_locChanged:(NSNotification *)n { [self retranslateUI]; }
- (void)retranslateUI {
    NppLocalizer *loc = [NppLocalizer shared];
    _titleLabel.stringValue = [loc translate:@"Source Control"];
    _refreshButton.toolTip  = [loc translate:@"Refresh"];
    _closeButton.toolTip    = [loc translate:@"Close"];
    _stageAllButton.title   = [loc translate:@"Stage All"];
    _unstageAllButton.title = [loc translate:@"Unstage All"];
    _commitButton.title     = [loc translate:@"Commit"];
}

- (void)_loadBulletImage {
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"bullet_red"
                                        withExtension:@"png"
                                         subdirectory:@"icons/standard/toolbar"];
    _bulletImage = url ? [[NSImage alloc] initWithContentsOfURL:url] : nil;
    if (_bulletImage) _bulletImage.size = NSMakeSize(12, 12);
}

// ── Theme ─────────────────────────────────────────────────────────────────────

- (void)_applyTheme {
    NSColor *bg = [[NPPStyleStore sharedStore] globalBg];
    NSColor *fg = [[NPPStyleStore sharedStore] globalFg];
    _scrollView.backgroundColor = bg;
    _tableView.backgroundColor  = bg;
    _branchLabel.textColor      = fg;
    _noRepoLabel.textColor      = [NSColor secondaryLabelColor];
    [_tableView reloadData];
}

- (void)_themeChanged:(NSNotification *)note {
    [self _applyTheme];
}

// ── Title-bar icon button helper ──────────────────────────────────────────────

static NSButton *_gitPanelBtn(NSString *iconName, NSString *subdir, NSString *tip,
                               id target, SEL action, CGFloat iconSize)
{
    NSButton *btn = [[NSButton alloc] init];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.bezelStyle = NSBezelStyleSmallSquare;
    btn.bordered   = NO;
    btn.toolTip    = tip;
    btn.target     = target;
    btn.action     = action;
    CGFloat btnSize = iconSize + 5;
    [btn.widthAnchor  constraintEqualToConstant:btnSize].active = YES;
    [btn.heightAnchor constraintEqualToConstant:btnSize].active = YES;
    NSURL *url = [[NSBundle mainBundle] URLForResource:iconName withExtension:@"png"
                                          subdirectory:subdir];
    NSImage *img = url ? [[NSImage alloc] initWithContentsOfURL:url] : nil;
    if (img) {
        img.size = NSMakeSize(iconSize, iconSize);
        btn.image = img;
        btn.imageScaling = NSImageScaleProportionallyDown;
    } else {
        btn.title = @"?";
    }
    return btn;
}

// ── UI Construction ───────────────────────────────────────────────────────────

- (void)_buildUI {
    NSFont *titleFont = [NSFont boldSystemFontOfSize:11];
    NSFont *smallFont = [NSFont systemFontOfSize:11];
    NSFont *monoFont  = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];

    // ── Title bar ─────────────────────────────────────────────────────────────
    NSView *titleBar = [[NSView alloc] init];
    titleBar.translatesAutoresizingMaskIntoConstraints = NO;
    titleBar.wantsLayer = YES;
    titleBar.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;

    _titleLabel = [NSTextField labelWithString:@"Source Control"];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = titleFont;
    _titleLabel.textColor = [NSColor labelColor];
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [titleBar addSubview:_titleLabel];

    _refreshButton = _gitPanelBtn(@"funclstReload",          @"icons/standard/panels/toolbar",
                                   @"Refresh",                self, @selector(_refresh:), 10);
    _browseRepoButton = _gitPanelBtn(@"project_folder_open",  @"icons/light/panels/treeview",
                                     @"Browse for repository…", self, @selector(_browseForRepo:), 12);

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

    for (NSView *v in @[_titleLabel, _browseRepoButton, _refreshButton, _closeButton])
        [titleBar addSubview:v];

    [NSLayoutConstraint activateConstraints:@[
        [titleBar.heightAnchor constraintEqualToConstant:26],
        [_titleLabel.leadingAnchor    constraintEqualToAnchor:titleBar.leadingAnchor constant:6],
        [_titleLabel.centerYAnchor    constraintEqualToAnchor:titleBar.centerYAnchor],
        [_titleLabel.trailingAnchor   constraintLessThanOrEqualToAnchor:_browseRepoButton.leadingAnchor constant:-4],
        [_browseRepoButton.trailingAnchor constraintEqualToAnchor:_refreshButton.leadingAnchor  constant:-2],
        [_refreshButton.trailingAnchor    constraintEqualToAnchor:_closeButton.leadingAnchor    constant:-4],
        [_closeButton.trailingAnchor      constraintEqualToAnchor:titleBar.trailingAnchor       constant:-4],
        [_browseRepoButton.centerYAnchor  constraintEqualToAnchor:titleBar.centerYAnchor],
        [_refreshButton.centerYAnchor     constraintEqualToAnchor:titleBar.centerYAnchor],
        [_closeButton.centerYAnchor       constraintEqualToAnchor:titleBar.centerYAnchor],
    ]];

    // ── Separator under title ──────────────────────────────────────────────────
    NSBox *sep0 = [[NSBox alloc] init];
    sep0.boxType = NSBoxSeparator;
    sep0.translatesAutoresizingMaskIntoConstraints = NO;

    // ── Branch header ─────────────────────────────────────────────────────────
    NSView *header = [[NSView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;

    _branchLabel = [NSTextField labelWithString:@""];
    _branchLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _branchLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    _branchLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    [header addSubview:_branchLabel];
    [NSLayoutConstraint activateConstraints:@[
        [header.heightAnchor constraintEqualToConstant:28],
        [_branchLabel.leadingAnchor  constraintEqualToAnchor:header.leadingAnchor constant:6],
        [_branchLabel.centerYAnchor  constraintEqualToAnchor:header.centerYAnchor],
        [_branchLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-6],
    ]];

    // ── Separator ─────────────────────────────────────────────────────────────
    NSBox *sep1 = [[NSBox alloc] init];
    sep1.boxType = NSBoxSeparator;
    sep1.translatesAutoresizingMaskIntoConstraints = NO;

    // ── Table ─────────────────────────────────────────────────────────────────
    _tableView = [[NSTableView alloc] init];
    _tableView.dataSource = self;
    _tableView.delegate   = self;
    _tableView.rowHeight  = 22;
    _tableView.headerView = nil;
    _tableView.usesAlternatingRowBackgroundColors = NO;
    _tableView.allowsMultipleSelection = YES;
    _tableView.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;

    NSTableColumn *badgeCol = [[NSTableColumn alloc] initWithIdentifier:@"badge"];
    badgeCol.width = 20;
    badgeCol.minWidth = 20;
    badgeCol.maxWidth = 20;
    [_tableView addTableColumn:badgeCol];

    NSTableColumn *pathCol = [[NSTableColumn alloc] initWithIdentifier:@"path"];
    pathCol.resizingMask = NSTableColumnAutoresizingMask;
    [_tableView addTableColumn:pathCol];
    [_tableView sizeLastColumnToFit];

    _tableView.target = self;
    _tableView.action = @selector(_rowSingleClicked:);

    // Context menu
    NSMenu *ctxMenu = [[NSMenu alloc] init];
    [ctxMenu addItemWithTitle:@"Stage"     action:@selector(_stageSelected:)   keyEquivalent:@""];
    [ctxMenu addItemWithTitle:@"Unstage"   action:@selector(_unstageSelected:) keyEquivalent:@""];
    [ctxMenu addItem:[NSMenuItem separatorItem]];
    [ctxMenu addItemWithTitle:@"Open File" action:@selector(_openSelected:)    keyEquivalent:@""];
    _tableView.menu = ctxMenu;
    ctxMenu.itemArray[0].target = self;
    ctxMenu.itemArray[1].target = self;
    ctxMenu.itemArray[3].target = self;

    _scrollView = [[NSScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.hasVerticalScroller   = YES;
    _scrollView.hasHorizontalScroller = NO;
    _scrollView.autohidesScrollers    = YES;
    _scrollView.documentView = _tableView;

    // ── Stage / Unstage All ───────────────────────────────────────────────────
    _stageAllButton = [NSButton buttonWithTitle:@"Stage All" target:self
                                         action:@selector(_stageAll:)];
    _stageAllButton.translatesAutoresizingMaskIntoConstraints = NO;
    _stageAllButton.bezelStyle = NSBezelStyleRounded;
    _stageAllButton.font = smallFont;

    _unstageAllButton = [NSButton buttonWithTitle:@"Unstage All" target:self
                                           action:@selector(_unstageAll:)];
    _unstageAllButton.translatesAutoresizingMaskIntoConstraints = NO;
    _unstageAllButton.bezelStyle = NSBezelStyleRounded;
    _unstageAllButton.font = smallFont;

    NSView *buttonRow = [[NSView alloc] init];
    buttonRow.translatesAutoresizingMaskIntoConstraints = NO;
    [buttonRow addSubview:_stageAllButton];
    [buttonRow addSubview:_unstageAllButton];
    [NSLayoutConstraint activateConstraints:@[
        [buttonRow.heightAnchor constraintEqualToConstant:28],
        [_stageAllButton.leadingAnchor  constraintEqualToAnchor:buttonRow.leadingAnchor constant:4],
        [_stageAllButton.centerYAnchor  constraintEqualToAnchor:buttonRow.centerYAnchor],
        [_unstageAllButton.leadingAnchor constraintEqualToAnchor:_stageAllButton.trailingAnchor constant:4],
        [_unstageAllButton.centerYAnchor constraintEqualToAnchor:buttonRow.centerYAnchor],
    ]];

    // ── Separator ─────────────────────────────────────────────────────────────
    NSBox *sep2 = [[NSBox alloc] init];
    sep2.boxType = NSBoxSeparator;
    sep2.translatesAutoresizingMaskIntoConstraints = NO;

    // ── Commit message ────────────────────────────────────────────────────────
    _commitField = [[NSTextField alloc] init];
    _commitField.translatesAutoresizingMaskIntoConstraints = NO;
    _commitField.placeholderString = @"Commit message\u2026";
    _commitField.font = monoFont;
    _commitField.cell.wraps = YES;
    _commitField.cell.scrollable = NO;
    _commitField.delegate = (id<NSTextFieldDelegate>)self;

    // ── Commit button ─────────────────────────────────────────────────────────
    _commitButton = [NSButton buttonWithTitle:@"Commit" target:self
                                       action:@selector(_commit:)];
    _commitButton.translatesAutoresizingMaskIntoConstraints = NO;
    _commitButton.bezelStyle = NSBezelStyleRounded;
    _commitButton.font = smallFont;
    _commitButton.enabled = NO;
    _commitButton.keyEquivalent = @"\r";

    // ── No-repo label ─────────────────────────────────────────────────────────
    _noRepoLabel = [NSTextField labelWithString:@"No git repository\nUse Browse to open a repo."];
    _noRepoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _noRepoLabel.font = [NSFont systemFontOfSize:13];
    _noRepoLabel.textColor = [NSColor secondaryLabelColor];
    _noRepoLabel.alignment = NSTextAlignmentCenter;
    _noRepoLabel.maximumNumberOfLines = 2;

    // ── Assemble layout ───────────────────────────────────────────────────────
    for (NSView *v in @[titleBar, sep0, header, sep1, _scrollView, buttonRow, sep2,
                        _commitField, _commitButton, _noRepoLabel])
        [self addSubview:v];

    [NSLayoutConstraint activateConstraints:@[
        // Title bar
        [titleBar.topAnchor      constraintEqualToAnchor:self.topAnchor],
        [titleBar.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [titleBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        // Sep0
        [sep0.topAnchor      constraintEqualToAnchor:titleBar.bottomAnchor],
        [sep0.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [sep0.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [sep0.heightAnchor   constraintEqualToConstant:1],
        // Branch header
        [header.topAnchor      constraintEqualToAnchor:sep0.bottomAnchor],
        [header.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        // Sep1
        [sep1.topAnchor      constraintEqualToAnchor:header.bottomAnchor],
        [sep1.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [sep1.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [sep1.heightAnchor   constraintEqualToConstant:1],
        // Table fills middle
        [_scrollView.topAnchor      constraintEqualToAnchor:sep1.bottomAnchor],
        [_scrollView.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_scrollView.bottomAnchor   constraintEqualToAnchor:buttonRow.topAnchor],
        // Button row
        [buttonRow.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [buttonRow.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [buttonRow.bottomAnchor   constraintEqualToAnchor:sep2.topAnchor],
        // Sep2
        [sep2.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [sep2.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [sep2.heightAnchor   constraintEqualToConstant:1],
        [sep2.bottomAnchor   constraintEqualToAnchor:_commitField.topAnchor],
        // Commit field — full width
        [_commitField.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor constant:4],
        [_commitField.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-4],
        [_commitField.heightAnchor   constraintEqualToConstant:54],
        // Commit button — right-aligned
        [_commitButton.topAnchor     constraintEqualToAnchor:_commitField.bottomAnchor constant:4],
        [_commitButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-4],
        [_commitButton.bottomAnchor  constraintEqualToAnchor:self.bottomAnchor constant:-4],
        // No-repo state (centered)
        [_noRepoLabel.centerXAnchor  constraintEqualToAnchor:self.centerXAnchor],
        [_noRepoLabel.centerYAnchor  constraintEqualToAnchor:self.centerYAnchor],
        [_noRepoLabel.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor constant:16],
        [_noRepoLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
    ]];
}

- (void)_setNoRepo:(BOOL)noRepo {
    _noRepoLabel.hidden      = !noRepo;
    _scrollView.hidden       = noRepo;
    _stageAllButton.hidden   = noRepo;
    _unstageAllButton.hidden = noRepo;
    _commitField.hidden      = noRepo;
    _commitButton.hidden     = noRepo;
    if (noRepo) _branchLabel.stringValue = @"(no repository)";
}

// ── Public API ────────────────────────────────────────────────────────────────

- (void)setRepoRoot:(nullable NSString *)root {
    _repoRoot = [root copy];
    if (!root) {
        _items = @[];
        [_tableView reloadData];
        [self _setNoRepo:YES];
    } else {
        [[NSUserDefaults standardUserDefaults] setObject:root forKey:kLastRepoRootKey];
        [self _setNoRepo:NO];
    }
}

- (void)refresh {
    if (!_repoRoot) { [self _setNoRepo:YES]; return; }
    NSString *root = _repoRoot;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *branch = [GitHelper currentBranchAtRoot:root];
        NSArray<NSDictionary *> *status = [GitHelper statusAtRoot:root];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self->_branchLabel.stringValue =
                branch ? [NSString stringWithFormat:@"\u2387 %@", branch] : @"(detached)";
            NSMutableArray *items = [NSMutableArray array];
            for (NSDictionary *d in status) {
                _GitStatusItem *it = [[_GitStatusItem alloc] init];
                it.xy   = d[@"xy"];
                it.path = d[@"path"];
                [items addObject:it];
            }
            self->_items = items;
            [self->_tableView reloadData];
            [self _setNoRepo:NO];
        });
    });
}

// ── NSTableViewDataSource ─────────────────────────────────────────────────────

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv {
    return (NSInteger)_items.count;
}

- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    _GitStatusItem *item = _items[row];
    NSColor *fg = [[NPPStyleStore sharedStore] globalFg];

    if ([col.identifier isEqualToString:@"badge"]) {
        NSImageView *iv = [tv makeViewWithIdentifier:@"badge" owner:nil];
        if (!iv) {
            iv = [[NSImageView alloc] init];
            iv.identifier = @"badge";
            iv.imageFrameStyle = NSImageFrameNone;
            iv.imageScaling = NSImageScaleProportionallyDown;
        }
        // Use bullet_red.png for all changed/untracked files; nil for others
        NSString *xy = item.xy;
        unichar x = xy.length > 0 ? [xy characterAtIndex:0] : ' ';
        unichar y = xy.length > 1 ? [xy characterAtIndex:1] : ' ';
        BOOL hasChange = !(x == ' ' && y == ' ');
        iv.image = hasChange ? _bulletImage : nil;
        return iv;
    } else {
        NSTextField *label = [tv makeViewWithIdentifier:@"path" owner:nil];
        if (!label) {
            label = [NSTextField labelWithString:@""];
            label.identifier = @"path";
            label.lineBreakMode = NSLineBreakByTruncatingMiddle;
            label.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
        }
        label.stringValue = item.path;
        label.textColor = fg;
        return label;
    }
}

// ── Row click ─────────────────────────────────────────────────────────────────

- (void)_rowSingleClicked:(id)sender {
    NSInteger row = _tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)_items.count) return;
    _GitStatusItem *item = _items[row];
    if (!_repoRoot) return;
    NSString *fullPath = [_repoRoot stringByAppendingPathComponent:item.path];
    if (_delegate) [_delegate gitPanel:self diffFileAtPath:fullPath];
}

// ── Close button ──────────────────────────────────────────────────────────────

- (void)_closePanel:(id)sender {
    [_delegate gitPanelDidRequestClose:self];
}

// ── Context menu / button actions ─────────────────────────────────────────────

- (nullable _GitStatusItem *)_itemAtClickedRow {
    NSInteger row = _tableView.clickedRow;
    if (row < 0 || row >= (NSInteger)_items.count) return nil;
    return _items[row];
}

- (void)_stageSelected:(id)sender {
    _GitStatusItem *it = [self _itemAtClickedRow];
    if (!it || !_repoRoot) return;
    NSString *root = _repoRoot, *path = it.path;
    [GitHelper stageFile:path root:root completion:^(BOOL ok) { [self refresh]; }];
}

- (void)_unstageSelected:(id)sender {
    _GitStatusItem *it = [self _itemAtClickedRow];
    if (!it || !_repoRoot) return;
    NSString *root = _repoRoot, *path = it.path;
    [GitHelper unstageFile:path root:root completion:^(BOOL ok) { [self refresh]; }];
}

- (void)_openSelected:(id)sender {
    _GitStatusItem *it = [self _itemAtClickedRow];
    if (!it || !_repoRoot) return;
    NSString *fullPath = [_repoRoot stringByAppendingPathComponent:it.path];
    if (_delegate) [_delegate gitPanel:self openFileAtPath:fullPath];
}

- (void)_stageAll:(id)sender {
    if (!_repoRoot) return;
    NSString *root = _repoRoot;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSTask *task = [[NSTask alloc] init];
        task.launchPath = @"/usr/bin/git";
        task.arguments = @[@"add", @"-A"];
        task.currentDirectoryPath = root;
        task.standardOutput = [NSPipe pipe];
        task.standardError  = [NSPipe pipe];
        @try { [task launch]; [task waitUntilExit]; } @catch (NSException *) {}
        dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; });
    });
}

- (void)_unstageAll:(id)sender {
    if (!_repoRoot) return;
    NSString *root = _repoRoot;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSTask *task = [[NSTask alloc] init];
        task.launchPath = @"/usr/bin/git";
        task.arguments = @[@"restore", @"--staged", @"."];
        task.currentDirectoryPath = root;
        task.standardOutput = [NSPipe pipe];
        task.standardError  = [NSPipe pipe];
        @try { [task launch]; [task waitUntilExit]; } @catch (NSException *) {}
        dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; });
    });
}

- (void)_browseForRepo:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.message = @"Choose a git repository folder";
    if ([panel runModal] == NSModalResponseOK) {
        NSURL *url = panel.URLs.firstObject;
        NSString *root = [GitHelper gitRootForPath:url.path];
        if (!root) root = url.path;
        [self setRepoRoot:root];
        [self refresh];
    }
}

- (void)_refresh:(id)sender {
    [self refresh];
}

- (void)_commit:(id)sender {
    NSString *msg = _commitField.stringValue;
    if (!msg.length || !_repoRoot) return;
    NSString *root = _repoRoot;
    _commitButton.enabled = NO;
    [GitHelper commitMessage:msg root:root completion:^(BOOL ok, NSString *errMsg) {
        if (ok) {
            self->_commitField.stringValue = @"";
            [self refresh];
        } else {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Commit Failed";
            alert.informativeText = errMsg ?: @"Unknown error";
            [alert runModal];
        }
        self->_commitButton.enabled = self->_commitField.stringValue.length > 0;
    }];
}

// ── NSTextFieldDelegate (commit field) ────────────────────────────────────────

- (void)controlTextDidChange:(NSNotification *)obj {
    if (obj.object == _commitField) {
        _commitButton.enabled = _commitField.stringValue.length > 0;
    }
}

@end
