#import "GitPanel.h"
#import "GitHelper.h"

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

    // Header
    NSTextField          *_branchLabel;
    NSButton             *_refreshButton;

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
    NSButton             *_browseRepoButton;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _items = @[];
        [self _buildUI];
        [self _setNoRepo:YES];
    }
    return self;
}

- (instancetype)init {
    return [self initWithFrame:NSZeroRect];
}

// ── UI Construction ───────────────────────────────────────────────────────────

- (NSTextField *)_makeLabel:(NSString *)text font:(NSFont *)font {
    NSTextField *tf = [NSTextField labelWithString:text];
    tf.font = font;
    tf.translatesAutoresizingMaskIntoConstraints = NO;
    return tf;
}

- (void)_buildUI {
    self.translatesAutoresizingMaskIntoConstraints = NO;

    NSFont *smallFont = [NSFont systemFontOfSize:11];
    NSFont *monoFont  = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];

    // ── Header ────────────────────────────────────────────────────────────────
    NSView *header = [[NSView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;

    _branchLabel = [self _makeLabel:@"" font:[NSFont systemFontOfSize:12 weight:NSFontWeightMedium]];
    _branchLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    _refreshButton = [NSButton buttonWithTitle:@"\u27F3" target:self action:@selector(_refresh:)];
    _refreshButton.translatesAutoresizingMaskIntoConstraints = NO;
    _refreshButton.bezelStyle = NSBezelStyleRounded;
    _refreshButton.font = [NSFont systemFontOfSize:14];
    [_refreshButton.widthAnchor  constraintEqualToConstant:28].active = YES;
    [_refreshButton.heightAnchor constraintEqualToConstant:24].active = YES;

    [header addSubview:_branchLabel];
    [header addSubview:_refreshButton];
    [NSLayoutConstraint activateConstraints:@[
        [header.heightAnchor constraintEqualToConstant:32],
        [_branchLabel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:8],
        [_branchLabel.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [_branchLabel.trailingAnchor constraintEqualToAnchor:_refreshButton.leadingAnchor constant:-4],
        [_refreshButton.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-4],
        [_refreshButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
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
    _tableView.usesAlternatingRowBackgroundColors = YES;
    _tableView.allowsMultipleSelection = YES;

    NSTableColumn *badgeCol = [[NSTableColumn alloc] initWithIdentifier:@"badge"];
    badgeCol.width = 20;
    badgeCol.minWidth = 20;
    badgeCol.maxWidth = 20;
    [_tableView addTableColumn:badgeCol];

    NSTableColumn *pathCol = [[NSTableColumn alloc] initWithIdentifier:@"path"];
    pathCol.resizingMask = NSTableColumnAutoresizingMask;
    [_tableView addTableColumn:pathCol];
    [_tableView sizeLastColumnToFit];

    // Context menu
    NSMenu *ctxMenu = [[NSMenu alloc] init];
    [ctxMenu addItemWithTitle:@"Stage" action:@selector(_stageSelected:) keyEquivalent:@""];
    [ctxMenu addItemWithTitle:@"Unstage" action:@selector(_unstageSelected:) keyEquivalent:@""];
    [ctxMenu addItem:[NSMenuItem separatorItem]];
    [ctxMenu addItemWithTitle:@"Open File" action:@selector(_openSelected:) keyEquivalent:@""];
    _tableView.menu = ctxMenu;
    NSMenuItem *stageItem   = ctxMenu.itemArray[0]; stageItem.target   = self;
    NSMenuItem *unstageItem = ctxMenu.itemArray[1]; unstageItem.target = self;
    NSMenuItem *openItem    = ctxMenu.itemArray[3]; openItem.target    = self;

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
        [_stageAllButton.leadingAnchor constraintEqualToAnchor:buttonRow.leadingAnchor constant:4],
        [_stageAllButton.centerYAnchor constraintEqualToAnchor:buttonRow.centerYAnchor],
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
    _noRepoLabel = [self _makeLabel:@"No git repository" font:[NSFont systemFontOfSize:13]];
    _noRepoLabel.textColor = [NSColor secondaryLabelColor];
    _noRepoLabel.alignment = NSTextAlignmentCenter;

    _browseRepoButton = [NSButton buttonWithTitle:@"Browse\u2026" target:self
                                           action:@selector(_browseForRepo:)];
    _browseRepoButton.translatesAutoresizingMaskIntoConstraints = NO;
    _browseRepoButton.bezelStyle = NSBezelStyleRounded;
    _browseRepoButton.font = smallFont;

    // ── Layout ────────────────────────────────────────────────────────────────
    for (NSView *v in @[header, sep1, _scrollView, buttonRow, sep2, _commitField, _commitButton,
                        _noRepoLabel, _browseRepoButton])
        [self addSubview:v];

    [NSLayoutConstraint activateConstraints:@[
        // Header
        [header.topAnchor constraintEqualToAnchor:self.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        // Sep1
        [sep1.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [sep1.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [sep1.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [sep1.heightAnchor constraintEqualToConstant:1],
        // Table fills middle
        [_scrollView.topAnchor constraintEqualToAnchor:sep1.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:buttonRow.topAnchor],
        // Button row
        [buttonRow.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [buttonRow.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [buttonRow.bottomAnchor constraintEqualToAnchor:sep2.topAnchor],
        // Sep2
        [sep2.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [sep2.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [sep2.heightAnchor constraintEqualToConstant:1],
        [sep2.bottomAnchor constraintEqualToAnchor:_commitField.topAnchor],
        // Commit field
        [_commitField.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4],
        [_commitField.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-4],
        [_commitField.heightAnchor constraintEqualToConstant:54],
        // Commit button
        [_commitButton.topAnchor constraintEqualToAnchor:_commitField.bottomAnchor constant:4],
        [_commitButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-4],
        [_commitButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-4],
        // No-repo state (centered)
        [_noRepoLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_noRepoLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-16],
        [_noRepoLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [_noRepoLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [_browseRepoButton.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_browseRepoButton.topAnchor constraintEqualToAnchor:_noRepoLabel.bottomAnchor constant:8],
    ]];
}

- (void)_setNoRepo:(BOOL)noRepo {
    _noRepoLabel.hidden      = !noRepo;
    _browseRepoButton.hidden = !noRepo;
    _scrollView.hidden       = noRepo;
    _stageAllButton.hidden   = noRepo;
    _unstageAllButton.hidden = noRepo;
    _commitField.hidden      = noRepo;
    _commitButton.hidden     = noRepo;
    // Header always shown; branch label shows placeholder when no repo
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
        // Show table frame immediately; data will fill in when refresh completes
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
    if ([col.identifier isEqualToString:@"badge"]) {
        NSTextField *badge = [tv makeViewWithIdentifier:@"badge" owner:nil];
        if (!badge) {
            badge = [NSTextField labelWithString:@""];
            badge.identifier = @"badge";
            badge.alignment = NSTextAlignmentCenter;
            badge.font = [NSFont systemFontOfSize:10];
        }
        // Determine color and symbol from XY
        NSString *xy = item.xy;
        unichar x = xy.length > 0 ? [xy characterAtIndex:0] : ' ';
        unichar y = xy.length > 1 ? [xy characterAtIndex:1] : ' ';
        if (x == '?' && y == '?') {
            badge.stringValue = @"\u25CB"; // ○ untracked
            badge.textColor = [NSColor systemGrayColor];
        } else if (x == 'D' || y == 'D') {
            badge.stringValue = @"\u00D7"; // × deleted
            badge.textColor = [NSColor systemRedColor];
        } else if (x != ' ' && x != '?') {
            badge.stringValue = @"\u25CF"; // ● staged
            badge.textColor = [NSColor systemGreenColor];
        } else if (y == 'M') {
            badge.stringValue = @"\u25CF"; // ● unstaged modified
            badge.textColor = [NSColor systemOrangeColor];
        } else {
            badge.stringValue = @"\u25CB";
            badge.textColor = [NSColor systemGrayColor];
        }
        return badge;
    } else {
        NSTextField *label = [tv makeViewWithIdentifier:@"path" owner:nil];
        if (!label) {
            label = [NSTextField labelWithString:@""];
            label.identifier = @"path";
            label.lineBreakMode = NSLineBreakByTruncatingMiddle;
            label.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
        }
        label.stringValue = item.path;
        return label;
    }
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
    // git add -A
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
        if (!root) root = url.path;  // treat the chosen folder as root even if not a git repo
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
