#import "PluginsAdminWindowController.h"
#import "NppPluginManager.h"

// ═══════════════════════════════════════════════════════════════════════════
// Plugin catalog entry — parsed from the nppPluginList JSON
// ═══════════════════════════════════════════════════════════════════════════

@interface NppPluginEntry : NSObject
@property (nonatomic, copy) NSString *folderName;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy) NSString *pluginDescription;
@property (nonatomic, copy) NSString *author;
@property (nonatomic, copy) NSString *homepage;
@property (nonatomic, copy) NSString *repository;   // download URL
@property (nonatomic, copy) NSString *pluginID;      // SHA-256 of zip
@property (nonatomic) BOOL isInstalled;
@end

@implementation NppPluginEntry
@end

// ═══════════════════════════════════════════════════════════════════════════
// Tab identifiers
// ═══════════════════════════════════════════════════════════════════════════

typedef NS_ENUM(NSInteger, PluginAdminTab) {
    PluginAdminTabAvailable = 0,
    PluginAdminTabUpdates,
    PluginAdminTabInstalled,
    PluginAdminTabIncompatible
};

static NSString *const kPluginListURL =
    @"https://raw.githubusercontent.com/notepad-plus-plus/nppPluginList/master/src/pl.x64.json";
static NSString *const kPluginListRepoURL =
    @"https://github.com/notepad-plus-plus/nppPluginList";
static NSString *const kPluginListVersion = @"1.9.2";

// ═══════════════════════════════════════════════════════════════════════════
// Private interface
// ═══════════════════════════════════════════════════════════════════════════

@interface PluginsAdminWindowController () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) NSTabView *tabView;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSTextView *descriptionView;
@property (nonatomic, strong) NSTextField *searchField;
@property (nonatomic, strong) NSButton *actionButton;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, strong) NSTextField *versionLabel;
@property (nonatomic, strong) NSButton *repoLink;
@property (nonatomic, strong) NSProgressIndicator *spinner;

@property (nonatomic, strong) NSMutableArray<NppPluginEntry *> *allAvailable;
@property (nonatomic, strong) NSMutableArray<NppPluginEntry *> *installed;
@property (nonatomic, strong) NSMutableArray<NppPluginEntry *> *filteredList; // current display
@property (nonatomic, strong) NSMutableSet<NSString *> *checkedPlugins;      // folderNames

@property (nonatomic) PluginAdminTab currentTab;
@property (nonatomic, copy) NSString *searchText;

@end

@implementation PluginsAdminWindowController

// ── Singleton ───────────────────────────────────────────────────────────

+ (instancetype)sharedController {
    static PluginsAdminWindowController *inst;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inst = [[PluginsAdminWindowController alloc] init];
    });
    return inst;
}

// ── Init ────────────────────────────────────────────────────────────────

- (instancetype)init {
    NSWindow *win = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 780, 560)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                            NSWindowStyleMaskResizable
                    backing:NSBackingStoreBuffered
                      defer:YES];
    win.title = @"Plugins Admin";
    win.minSize = NSMakeSize(600, 450);
    [win center];

    self = [super initWithWindow:win];
    if (self) {
        _allAvailable   = [NSMutableArray array];
        _installed      = [NSMutableArray array];
        _filteredList   = [NSMutableArray array];
        _checkedPlugins = [NSMutableSet set];
        _currentTab     = PluginAdminTabAvailable;
        _searchText     = @"";
        [self buildUI];
        [self scanInstalledPlugins];
        [self fetchPluginList];
    }
    return self;
}

- (void)showWindow:(id)sender {
    [super showWindow:sender];
    [self.window center];
    [self.checkedPlugins removeAllObjects];
    [self refreshForCurrentTab];
}

// ── UI Construction ─────────────────────────────────────────────────────

- (void)buildUI {
    NSView *cv = self.window.contentView;
    cv.wantsLayer = YES;

    // ── Tab buttons (segmented-style at top) ────────────────────────
    _tabView = [[NSTabView alloc] initWithFrame:NSZeroRect];
    _tabView.translatesAutoresizingMaskIntoConstraints = NO;
    _tabView.tabViewType = NSTopTabsBezelBorder;
    _tabView.delegate = (id<NSTabViewDelegate>)self;

    NSTabViewItem *t0 = [[NSTabViewItem alloc] initWithIdentifier:@"available"];
    t0.label = @"Available";
    t0.view = [[NSView alloc] init];
    [_tabView addTabViewItem:t0];

    NSTabViewItem *t1 = [[NSTabViewItem alloc] initWithIdentifier:@"updates"];
    t1.label = @"Updates";
    t1.view = [[NSView alloc] init];
    [_tabView addTabViewItem:t1];

    NSTabViewItem *t2 = [[NSTabViewItem alloc] initWithIdentifier:@"installed"];
    t2.label = @"Installed";
    t2.view = [[NSView alloc] init];
    [_tabView addTabViewItem:t2];

    NSTabViewItem *t3 = [[NSTabViewItem alloc] initWithIdentifier:@"incompatible"];
    t3.label = @"Incompatible";
    t3.view = [[NSView alloc] init];
    [_tabView addTabViewItem:t3];

    [cv addSubview:_tabView];

    // ── Search row ──────────────────────────────────────────────────
    NSTextField *searchLabel = [NSTextField labelWithString:@"Search:"];
    searchLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [cv addSubview:searchLabel];

    _searchField = [[NSSearchField alloc] initWithFrame:NSZeroRect];
    _searchField.translatesAutoresizingMaskIntoConstraints = NO;
    _searchField.placeholderString = @"Filter plugins…";
    _searchField.target = self;
    _searchField.action = @selector(searchChanged:);
    // Also fire on every keystroke via delegate
    _searchField.delegate = (id<NSTextFieldDelegate>)self;
    [cv addSubview:_searchField];

    _actionButton = [NSButton buttonWithTitle:@"Install" target:self action:@selector(actionPressed:)];
    _actionButton.translatesAutoresizingMaskIntoConstraints = NO;
    _actionButton.bezelStyle = NSBezelStyleRounded;
    [cv addSubview:_actionButton];

    // ── Spinner (while fetching) ────────────────────────────────────
    _spinner = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    _spinner.style = NSProgressIndicatorStyleSpinning;
    _spinner.displayedWhenStopped = NO;
    [cv addSubview:_spinner];

    // ── Table view (Plugin + Version columns, with checkboxes) ──────
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;

    _tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.usesAlternatingRowBackgroundColors = NO;
    _tableView.rowHeight = 20;
    _tableView.allowsMultipleSelection = NO;
    _tableView.headerView = [[NSTableHeaderView alloc] init];

    NSTableColumn *checkCol = [[NSTableColumn alloc] initWithIdentifier:@"check"];
    checkCol.width = 24;
    checkCol.minWidth = 24;
    checkCol.maxWidth = 24;
    checkCol.title = @"";
    [_tableView addTableColumn:checkCol];

    NSTableColumn *nameCol = [[NSTableColumn alloc] initWithIdentifier:@"plugin"];
    nameCol.title = @"Plugin";
    nameCol.width = 280;
    nameCol.minWidth = 150;
    [_tableView addTableColumn:nameCol];

    NSTableColumn *verCol = [[NSTableColumn alloc] initWithIdentifier:@"version"];
    verCol.title = @"Version";
    verCol.width = 100;
    verCol.minWidth = 60;
    [_tableView addTableColumn:verCol];

    scrollView.documentView = _tableView;
    [cv addSubview:scrollView];

    // ── Description area ────────────────────────────────────────────
    NSScrollView *descScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    descScroll.translatesAutoresizingMaskIntoConstraints = NO;
    descScroll.hasVerticalScroller = YES;
    descScroll.borderType = NSBezelBorder;

    _descriptionView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 700, 100)];
    _descriptionView.editable = NO;
    _descriptionView.selectable = YES;
    _descriptionView.font = [NSFont systemFontOfSize:12];
    _descriptionView.textContainerInset = NSMakeSize(6, 6);
    descScroll.documentView = _descriptionView;
    [cv addSubview:descScroll];

    // ── Footer row: version label + repo link ───────────────────────
    _versionLabel = [NSTextField labelWithString:
        [NSString stringWithFormat:@"Plugin list version:  %@", kPluginListVersion]];
    _versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _versionLabel.font = [NSFont systemFontOfSize:11];
    _versionLabel.textColor = NSColor.secondaryLabelColor;
    [cv addSubview:_versionLabel];

    _repoLink = [NSButton buttonWithTitle:@"Plugin list repository"
                                   target:self action:@selector(openRepoLink:)];
    _repoLink.translatesAutoresizingMaskIntoConstraints = NO;
    _repoLink.bordered = NO;
    NSMutableAttributedString *linkStr = [[NSMutableAttributedString alloc]
        initWithString:@"Plugin list repository"
            attributes:@{
                NSForegroundColorAttributeName: NSColor.linkColor,
                NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
                NSFontAttributeName: [NSFont systemFontOfSize:11]
            }];
    _repoLink.attributedTitle = linkStr;
    [cv addSubview:_repoLink];

    // ── Close button ────────────────────────────────────────────────
    _closeButton = [NSButton buttonWithTitle:@"Close" target:self action:@selector(closePressed:)];
    _closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_closeButton setKeyEquivalent:@"\033"];
    [cv addSubview:_closeButton];

    // ── Layout (all anchor-based for clarity) ───────────────────────
    [NSLayoutConstraint activateConstraints:@[
        // Tab view across top
        [_tabView.topAnchor constraintEqualToAnchor:cv.topAnchor constant:8],
        [_tabView.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:12],
        [_tabView.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-12],
        [_tabView.heightAnchor constraintEqualToConstant:36],

        // Search row
        [searchLabel.topAnchor constraintEqualToAnchor:_tabView.bottomAnchor constant:8],
        [searchLabel.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:20],
        [searchLabel.centerYAnchor constraintEqualToAnchor:_searchField.centerYAnchor],

        [_searchField.leadingAnchor constraintEqualToAnchor:searchLabel.trailingAnchor constant:6],
        [_searchField.topAnchor constraintEqualToAnchor:_tabView.bottomAnchor constant:8],
        [_searchField.widthAnchor constraintGreaterThanOrEqualToConstant:200],

        [_spinner.leadingAnchor constraintEqualToAnchor:_searchField.trailingAnchor constant:8],
        [_spinner.centerYAnchor constraintEqualToAnchor:_searchField.centerYAnchor],
        [_spinner.widthAnchor constraintEqualToConstant:16],
        [_spinner.heightAnchor constraintEqualToConstant:16],

        [_actionButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:_spinner.trailingAnchor constant:10],
        [_actionButton.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-20],
        [_actionButton.centerYAnchor constraintEqualToAnchor:_searchField.centerYAnchor],
        [_actionButton.widthAnchor constraintEqualToConstant:90],

        // Table
        [scrollView.topAnchor constraintEqualToAnchor:_searchField.bottomAnchor constant:8],
        [scrollView.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:20],
        [scrollView.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-20],
        [scrollView.heightAnchor constraintGreaterThanOrEqualToConstant:150],

        // Description
        [descScroll.topAnchor constraintEqualToAnchor:scrollView.bottomAnchor constant:8],
        [descScroll.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:20],
        [descScroll.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-20],
        [descScroll.heightAnchor constraintGreaterThanOrEqualToConstant:80],
        [descScroll.heightAnchor constraintLessThanOrEqualToConstant:160],

        // Footer row: version label left, repo link right
        [_versionLabel.topAnchor constraintEqualToAnchor:descScroll.bottomAnchor constant:10],
        [_versionLabel.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:20],

        [_repoLink.centerYAnchor constraintEqualToAnchor:_versionLabel.centerYAnchor],
        [_repoLink.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-20],

        // Close button centered, pinned to bottom with adequate room
        [_closeButton.topAnchor constraintEqualToAnchor:_versionLabel.bottomAnchor constant:10],
        [_closeButton.centerXAnchor constraintEqualToAnchor:cv.centerXAnchor],
        [_closeButton.widthAnchor constraintEqualToConstant:100],
        [_closeButton.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-14],
    ]];
}

// ── Data fetching ───────────────────────────────────────────────────────

- (void)fetchPluginList {
    [_spinner startAnimation:nil];

    NSURL *url = [NSURL URLWithString:kPluginListURL];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self->_spinner stopAnimation:nil];

                if (err || !data) {
                    NSLog(@"[PluginsAdmin] Failed to fetch plugin list: %@", err);
                    return;
                }

                [self parsePluginListJSON:data];
                [self refreshForCurrentTab];
            });
        }];
    [task resume];
}

- (void)parsePluginListJSON:(NSData *)data {
    NSError *jsonErr = nil;
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
    if (jsonErr || ![root isKindOfClass:[NSDictionary class]]) {
        NSLog(@"[PluginsAdmin] JSON parse error: %@", jsonErr);
        return;
    }

    NSArray *list = root[@"npp-plugins"];
    if (![list isKindOfClass:[NSArray class]]) return;

    [_allAvailable removeAllObjects];

    NSSet *installedNames = [self installedFolderNames];

    for (NSDictionary *entry in list) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;

        NppPluginEntry *pe = [[NppPluginEntry alloc] init];
        pe.folderName        = entry[@"folder-name"] ?: @"";
        pe.displayName       = entry[@"display-name"] ?: pe.folderName;
        pe.version           = entry[@"version"] ?: @"";
        pe.pluginDescription = entry[@"description"] ?: @"";
        pe.author            = entry[@"author"] ?: @"";
        pe.homepage          = entry[@"homepage"] ?: @"";
        pe.repository        = entry[@"repository"] ?: @"";
        pe.pluginID          = entry[@"id"] ?: @"";
        pe.isInstalled       = [installedNames containsObject:pe.folderName];

        [_allAvailable addObject:pe];
    }

    NSLog(@"[PluginsAdmin] Loaded %lu plugins from catalog", (unsigned long)_allAvailable.count);
}

- (void)scanInstalledPlugins {
    [_installed removeAllObjects];
    NSString *pluginsDir = [NSHomeDirectory() stringByAppendingPathComponent:@".notepad++/plugins"];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *subdirs = [fm contentsOfDirectoryAtPath:pluginsDir error:nil];

    for (NSString *dirName in subdirs) {
        NSString *dirPath = [pluginsDir stringByAppendingPathComponent:dirName];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:dirPath isDirectory:&isDir] || !isDir) continue;

        NSString *dylibPath = [dirPath stringByAppendingPathComponent:
            [dirName stringByAppendingPathExtension:@"dylib"]];
        if (![fm fileExistsAtPath:dylibPath]) continue;

        NppPluginEntry *pe = [[NppPluginEntry alloc] init];
        pe.folderName   = dirName;
        pe.displayName  = dirName;
        pe.version      = @"";
        pe.isInstalled  = YES;

        // Try to get version from the loaded plugin manager
        pe.pluginDescription = @"Installed macOS plugin";

        [_installed addObject:pe];
    }
}

- (NSSet<NSString *> *)installedFolderNames {
    NSMutableSet *names = [NSMutableSet set];
    for (NppPluginEntry *pe in _installed)
        [names addObject:pe.folderName];
    return names;
}

// ── Tab & filter logic ──────────────────────────────────────────────────

- (void)refreshForCurrentTab {
    [_checkedPlugins removeAllObjects];
    [_filteredList removeAllObjects];

    switch (_currentTab) {
        case PluginAdminTabAvailable:
            _actionButton.title = @"Install";
            _actionButton.hidden = NO;
            for (NppPluginEntry *pe in _allAvailable) {
                if (!pe.isInstalled)
                    [_filteredList addObject:pe];
            }
            break;

        case PluginAdminTabUpdates:
            _actionButton.title = @"Update";
            _actionButton.hidden = NO;
            // No updates mechanism yet — empty
            break;

        case PluginAdminTabInstalled:
            _actionButton.title = @"Remove";
            _actionButton.hidden = NO;
            [_filteredList addObjectsFromArray:_installed];
            break;

        case PluginAdminTabIncompatible:
            _actionButton.hidden = YES;
            // Empty for now
            break;
    }

    // Apply search filter
    if (_searchText.length > 0) {
        NSPredicate *pred = [NSPredicate predicateWithFormat:
            @"displayName CONTAINS[cd] %@ OR pluginDescription CONTAINS[cd] %@",
            _searchText, _searchText];
        NSArray *filtered = [_filteredList filteredArrayUsingPredicate:pred];
        [_filteredList setArray:[filtered mutableCopy]];
    }

    [_tableView reloadData];
    [_descriptionView setString:@""];
    _actionButton.enabled = NO;
}

// ── NSTabViewDelegate ───────────────────────────────────────────────────

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    NSInteger idx = [tabView indexOfTabViewItem:tabViewItem];
    _currentTab = (PluginAdminTab)idx;
    [self refreshForCurrentTab];
}

// ── NSTableViewDataSource ───────────────────────────────────────────────

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv {
    return (NSInteger)_filteredList.count;
}

- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    NppPluginEntry *pe = _filteredList[row];
    NSString *ident = col.identifier;

    if ([ident isEqualToString:@"check"]) {
        NSButton *cb = [tv makeViewWithIdentifier:@"check" owner:self];
        if (!cb) {
            cb = [NSButton checkboxWithTitle:@"" target:self action:@selector(checkboxToggled:)];
            cb.identifier = @"check";
        }
        cb.state = [_checkedPlugins containsObject:pe.folderName]
                     ? NSControlStateValueOn : NSControlStateValueOff;
        cb.tag = row;
        return cb;
    }

    NSTextField *tf = [tv makeViewWithIdentifier:ident owner:self];
    if (!tf) {
        tf = [NSTextField labelWithString:@""];
        tf.identifier = ident;
        tf.lineBreakMode = NSLineBreakByTruncatingTail;
        tf.font = [NSFont systemFontOfSize:12];
    }

    if ([ident isEqualToString:@"plugin"]) {
        tf.stringValue = pe.displayName ?: @"";
    } else if ([ident isEqualToString:@"version"]) {
        tf.stringValue = pe.version ?: @"";
    }
    return tf;
}

// ── NSTableViewDelegate ─────────────────────────────────────────────────

- (void)tableViewSelectionDidChange:(NSNotification *)notif {
    NSInteger row = _tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)_filteredList.count) {
        [_descriptionView setString:@""];
        return;
    }

    NppPluginEntry *pe = _filteredList[row];
    NSMutableString *desc = [NSMutableString string];

    if (pe.pluginDescription.length > 0)
        [desc appendFormat:@"%@\n\n", pe.pluginDescription];
    if (pe.author.length > 0)
        [desc appendFormat:@"Author: %@\n", pe.author];
    if (pe.homepage.length > 0)
        [desc appendFormat:@"Homepage: %@\n", pe.homepage];

    [_descriptionView setString:desc];
}

// ── Actions ─────────────────────────────────────────────────────────────

- (void)checkboxToggled:(NSButton *)sender {
    NSInteger row = sender.tag;
    if (row < 0 || row >= (NSInteger)_filteredList.count) return;

    NppPluginEntry *pe = _filteredList[row];
    if (sender.state == NSControlStateValueOn)
        [_checkedPlugins addObject:pe.folderName];
    else
        [_checkedPlugins removeObject:pe.folderName];

    _actionButton.enabled = _checkedPlugins.count > 0;
}

- (void)searchChanged:(id)sender {
    _searchText = _searchField.stringValue;
    [self refreshForCurrentTab];
}

// Live filter on every keystroke
- (void)controlTextDidChange:(NSNotification *)notif {
    if (notif.object == _searchField) {
        _searchText = _searchField.stringValue;
        [self refreshForCurrentTab];
    }
}

- (void)actionPressed:(id)sender {
    if (_checkedPlugins.count == 0) return;

    switch (_currentTab) {
        case PluginAdminTabAvailable:
            [self installCheckedPlugins];
            break;
        case PluginAdminTabInstalled:
            [self removeCheckedPlugins];
            break;
        case PluginAdminTabUpdates:
        case PluginAdminTabIncompatible:
            break;
    }
}

- (void)installCheckedPlugins {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Install Plugins";
    alert.informativeText = [NSString stringWithFormat:
        @"Plugin installation from the catalog is not yet available.\n\n"
        @"The catalog lists Windows (x64) plugins which are not compatible "
        @"with this macOS port.\n\n"
        @"To install a macOS plugin manually, place a .dylib in:\n"
        @"~/.notepad++/plugins/PluginName/PluginName.dylib\n\n"
        @"Then restart the application."];
    alert.alertStyle = NSAlertStyleInformational;
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

- (void)removeCheckedPlugins {
    NSString *names = [[_checkedPlugins allObjects] componentsJoinedByString:@", "];
    NSAlert *confirm = [[NSAlert alloc] init];
    confirm.messageText = @"Remove Plugins";
    confirm.informativeText = [NSString stringWithFormat:
        @"Remove the following plugins?\n\n%@\n\nThis will delete the plugin files. "
        @"Restart the application for changes to take effect.", names];
    [confirm addButtonWithTitle:@"Remove"];
    [confirm addButtonWithTitle:@"Cancel"];
    confirm.alertStyle = NSAlertStyleWarning;

    [confirm beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse resp) {
        if (resp != NSAlertFirstButtonReturn) return;

        NSString *pluginsDir = [NSHomeDirectory()
            stringByAppendingPathComponent:@".notepad++/plugins"];
        NSFileManager *fm = [NSFileManager defaultManager];

        for (NSString *name in self->_checkedPlugins) {
            NSString *dir = [pluginsDir stringByAppendingPathComponent:name];
            NSError *err = nil;
            [fm removeItemAtPath:dir error:&err];
            if (err)
                NSLog(@"[PluginsAdmin] Failed to remove %@: %@", name, err);
        }

        [self scanInstalledPlugins];
        [self refreshForCurrentTab];
    }];
}

- (void)closePressed:(id)sender {
    [self.window close];
}

- (void)openRepoLink:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:kPluginListRepoURL]];
}

@end
