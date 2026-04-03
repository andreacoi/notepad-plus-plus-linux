#import "PluginsAdminWindowController.h"
#import "NppPluginManager.h"
#import <CommonCrypto/CommonDigest.h>

// ═══════════════════════════════════════════════════════════════════════════
// Plugin catalog entry — parsed from the nppPluginList JSON
// ═══════════════════════════════════════════════════════════════════════════

@interface NppPluginEntry : NSObject
@property (nonatomic, copy) NSString *folderName;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *version;           // Windows version
@property (nonatomic, copy) NSString *pluginDescription;
@property (nonatomic, copy) NSString *author;
@property (nonatomic, copy) NSString *homepage;
@property (nonatomic, copy) NSString *repository;        // Windows download URL
@property (nonatomic, copy) NSString *pluginID;           // Windows SHA-256
@property (nonatomic) BOOL isInstalled;

// macOS-specific (populated from macOS plugin list)
@property (nonatomic) BOOL isMacAvailable;               // has macOS build
@property (nonatomic, copy) NSString *macVersion;         // macOS version
@property (nonatomic, copy) NSString *macRepository;      // macOS download URL
@property (nonatomic, copy) NSString *macPluginID;        // macOS SHA-256 of zip
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

// Windows x64 plugin list (full catalog — shows all plugins)
static NSString *const kWinPluginListURL =
    @"https://raw.githubusercontent.com/notepad-plus-plus/nppPluginList/master/src/pl.x64.json";
// macOS arm64 plugin list (our ported plugins — determines what's installable)
static NSString *const kMacPluginListURL =
    @"https://raw.githubusercontent.com/notepad-plus-plus-mac/nppPluginList/main/pl.macos-arm64.json";
static NSString *const kPluginListRepoURL =
    @"https://github.com/notepad-plus-plus-mac/nppPluginList";
static NSString *const kPluginListVersion = @"0.1.0";

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

    // Fetch both lists concurrently, merge when both complete
    __block NSData *winData = nil;
    __block NSData *macData = nil;
    dispatch_group_t group = dispatch_group_create();
    NSURLSession *session = [NSURLSession sharedSession];

    dispatch_group_enter(group);
    [[session dataTaskWithURL:[NSURL URLWithString:kWinPluginListURL]
            completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (!err && data) winData = data;
        else NSLog(@"[PluginsAdmin] Failed to fetch Windows plugin list: %@", err);
        dispatch_group_leave(group);
    }] resume];

    dispatch_group_enter(group);
    [[session dataTaskWithURL:[NSURL URLWithString:kMacPluginListURL]
            completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (!err && data) macData = data;
        else NSLog(@"[PluginsAdmin] Failed to fetch macOS plugin list: %@", err);
        dispatch_group_leave(group);
    }] resume];

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [self->_spinner stopAnimation:nil];
        [self mergePluginListsWin:winData mac:macData];
        [self refreshForCurrentTab];
    });
}

- (void)mergePluginListsWin:(NSData *)winData mac:(NSData *)macData {
    [_allAvailable removeAllObjects];

    // ── Parse macOS list into a lookup by folder-name ──
    NSMutableDictionary<NSString *, NSDictionary *> *macByFolder = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSDictionary *> *macByName   = [NSMutableDictionary dictionary];
    if (macData) {
        NSError *err = nil;
        NSDictionary *macRoot = [NSJSONSerialization JSONObjectWithData:macData options:0 error:&err];
        if (!err && [macRoot isKindOfClass:[NSDictionary class]]) {
            NSArray *macPlugins = macRoot[@"npp-plugins"];
            if ([macPlugins isKindOfClass:[NSArray class]]) {
                for (NSDictionary *mp in macPlugins) {
                    if (![mp isKindOfClass:[NSDictionary class]]) continue;
                    NSString *folder = mp[@"folder-name"] ?: @"";
                    NSString *name   = mp[@"display-name"] ?: @"";
                    if (folder.length > 0) macByFolder[folder] = mp;
                    if (name.length > 0)   macByName[name] = mp;
                }
                NSLog(@"[PluginsAdmin] Loaded %lu macOS plugins", (unsigned long)macByFolder.count);
            }
        }
    }

    // ── Parse Windows list and join with macOS data ──
    if (!winData) {
        NSLog(@"[PluginsAdmin] No Windows plugin list data — catalog empty");
        return;
    }

    NSError *err = nil;
    NSDictionary *winRoot = [NSJSONSerialization JSONObjectWithData:winData options:0 error:&err];
    if (err || ![winRoot isKindOfClass:[NSDictionary class]]) {
        NSLog(@"[PluginsAdmin] Windows JSON parse error: %@", err);
        return;
    }

    NSArray *winPlugins = winRoot[@"npp-plugins"];
    if (![winPlugins isKindOfClass:[NSArray class]]) return;

    NSSet *installedNames = [self installedFolderNames];

    for (NSDictionary *entry in winPlugins) {
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

        // Inner join: match by folder-name first, then by display-name
        NSDictionary *macEntry = macByFolder[pe.folderName];
        if (!macEntry) macEntry = macByName[pe.displayName];

        if (macEntry) {
            pe.isMacAvailable = YES;
            pe.macVersion     = macEntry[@"version"] ?: pe.version;
            pe.macRepository  = macEntry[@"repository"] ?: @"";
            pe.macPluginID    = macEntry[@"id"] ?: @"";
            // Also check if the macOS folder-name differs (for install path)
            NSString *macFolder = macEntry[@"folder-name"];
            if (macFolder.length > 0 && ![macFolder isEqualToString:pe.folderName]) {
                pe.folderName = macFolder;  // use macOS folder name for install
            }
        }

        [_allAvailable addObject:pe];
    }

    // Sort: macOS-available first, then alphabetical
    [_allAvailable sortUsingComparator:^NSComparisonResult(NppPluginEntry *a, NppPluginEntry *b) {
        if (a.isMacAvailable != b.isMacAvailable)
            return a.isMacAvailable ? NSOrderedAscending : NSOrderedDescending;
        return [a.displayName localizedCaseInsensitiveCompare:b.displayName];
    }];

    NSInteger macCount = 0;
    for (NppPluginEntry *pe in _allAvailable)
        if (pe.isMacAvailable) macCount++;

    NSLog(@"[PluginsAdmin] Catalog: %lu total, %ld macOS-available",
          (unsigned long)_allAvailable.count, (long)macCount);
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
            // Windows-only plugins not yet ported to macOS
            for (NppPluginEntry *pe in _allAvailable) {
                if (!pe.isMacAvailable)
                    [_filteredList addObject:pe];
            }
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
    BOOL canInstall = pe.isMacAvailable || pe.isInstalled;

    if ([ident isEqualToString:@"check"]) {
        NSButton *cb = [tv makeViewWithIdentifier:@"check" owner:self];
        if (!cb) {
            cb = [NSButton checkboxWithTitle:@"" target:self action:@selector(checkboxToggled:)];
            cb.identifier = @"check";
        }

        if (_currentTab == PluginAdminTabAvailable) {
            // Only show checkboxes for macOS-available plugins
            cb.hidden = !pe.isMacAvailable;
            cb.enabled = pe.isMacAvailable;
        } else {
            cb.hidden = NO;
            cb.enabled = YES;
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
        // Show macOS version for available macOS plugins, Windows version otherwise
        if (pe.isMacAvailable && pe.macVersion.length > 0)
            tf.stringValue = pe.macVersion;
        else
            tf.stringValue = pe.version ?: @"";
    }

    // Dim text for plugins without macOS builds (Available tab only)
    if (_currentTab == PluginAdminTabAvailable && !canInstall) {
        tf.textColor = [NSColor tertiaryLabelColor];
    } else {
        tf.textColor = [NSColor labelColor];
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

    if (_currentTab == PluginAdminTabAvailable) {
        if (pe.isMacAvailable) {
            [desc appendFormat:@"[macOS available — v%@]\n\n",
             pe.macVersion.length > 0 ? pe.macVersion : pe.version];
        } else {
            [desc appendString:@"[Windows only — macOS port not yet available]\n\n"];
        }
    }

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
    // Collect macOS-available plugins that are checked
    NSMutableArray<NppPluginEntry *> *toInstall = [NSMutableArray array];
    for (NppPluginEntry *pe in _allAvailable) {
        if ([_checkedPlugins containsObject:pe.folderName] && pe.isMacAvailable)
            [toInstall addObject:pe];
    }

    if (toInstall.count == 0) return;

    NSMutableArray *names = [NSMutableArray array];
    for (NppPluginEntry *pe in toInstall)
        [names addObject:pe.displayName];

    NSAlert *confirm = [[NSAlert alloc] init];
    confirm.messageText = @"Install Plugins";
    confirm.informativeText = [NSString stringWithFormat:
        @"Install the following plugins?\n\n%@\n\n"
        @"Restart the application for changes to take effect.",
        [names componentsJoinedByString:@"\n"]];
    [confirm addButtonWithTitle:@"Install"];
    [confirm addButtonWithTitle:@"Cancel"];

    [confirm beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse resp) {
        if (resp != NSAlertFirstButtonReturn) return;
        [self downloadAndInstallPlugins:toInstall index:0];
    }];
}

- (void)downloadAndInstallPlugins:(NSArray<NppPluginEntry *> *)plugins index:(NSUInteger)idx {
    if (idx >= plugins.count) {
        // All done — refresh
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_spinner stopAnimation:nil];
            [self scanInstalledPlugins];
            // Re-merge installed state
            NSSet *inst = [self installedFolderNames];
            for (NppPluginEntry *pe in self->_allAvailable)
                pe.isInstalled = [inst containsObject:pe.folderName];
            [self refreshForCurrentTab];

            NSAlert *done = [[NSAlert alloc] init];
            done.messageText = @"Installation Complete";
            done.informativeText = @"Restart the application to load the installed plugins.";
            [done beginSheetModalForWindow:self.window completionHandler:nil];
        });
        return;
    }

    NppPluginEntry *pe = plugins[idx];
    NSString *url = pe.macRepository;
    if (url.length == 0) {
        NSLog(@"[PluginsAdmin] No macOS repository URL for %@", pe.displayName);
        [self downloadAndInstallPlugins:plugins index:idx + 1];
        return;
    }

    [_spinner startAnimation:nil];
    NSLog(@"[PluginsAdmin] Downloading %@ from %@", pe.displayName, url);

    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:url]
                                         cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                     timeoutInterval:120];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (err || !data) {
                    NSLog(@"[PluginsAdmin] Download failed for %@: %@", pe.displayName, err);
                    [self showInstallError:pe.displayName
                                   detail:[NSString stringWithFormat:@"Download failed: %@",
                                           err.localizedDescription ?: @"unknown error"]];
                    [self downloadAndInstallPlugins:plugins index:idx + 1];
                    return;
                }

                // Verify SHA-256
                if (pe.macPluginID.length == 64) {
                    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
                    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
                    NSMutableString *hexHash = [NSMutableString stringWithCapacity:64];
                    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++)
                        [hexHash appendFormat:@"%02x", hash[i]];

                    if (![hexHash isEqualToString:pe.macPluginID.lowercaseString]) {
                        NSLog(@"[PluginsAdmin] SHA-256 mismatch for %@: expected %@, got %@",
                              pe.displayName, pe.macPluginID, hexHash);
                        [self showInstallError:pe.displayName
                                       detail:@"SHA-256 hash mismatch — download may be corrupt."];
                        [self downloadAndInstallPlugins:plugins index:idx + 1];
                        return;
                    }
                }

                // Extract ZIP to ~/.notepad++/plugins/
                NSString *pluginsDir = [NSHomeDirectory()
                    stringByAppendingPathComponent:@".notepad++/plugins"];
                NSFileManager *fm = [NSFileManager defaultManager];
                [fm createDirectoryAtPath:pluginsDir withIntermediateDirectories:YES
                               attributes:nil error:nil];

                if (![self extractZipData:data toDirectory:pluginsDir forPlugin:pe]) {
                    [self showInstallError:pe.displayName detail:@"Failed to extract ZIP archive."];
                }

                [self downloadAndInstallPlugins:plugins index:idx + 1];
            });
        }];
    [task resume];
}

- (BOOL)extractZipData:(NSData *)zipData toDirectory:(NSString *)destDir
             forPlugin:(NppPluginEntry *)pe {
    // Write ZIP to a temp file, then use NSFileCoordinator/unzip
    NSString *tmpPath = [NSTemporaryDirectory()
        stringByAppendingPathComponent:
            [NSString stringWithFormat:@"npp_plugin_%@.zip", pe.folderName]];
    if (![zipData writeToFile:tmpPath atomically:YES]) return NO;

    // Use /usr/bin/ditto to extract (handles ZIP natively on macOS)
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/ditto";
    task.arguments = @[@"-xk", tmpPath, destDir];
    task.standardOutput = [NSPipe pipe];
    task.standardError  = [NSPipe pipe];

    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *e) {
        NSLog(@"[PluginsAdmin] ditto failed for %@: %@", pe.displayName, e);
        [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
        return NO;
    }

    [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];

    if (task.terminationStatus != 0) {
        NSLog(@"[PluginsAdmin] ditto exit %d for %@", task.terminationStatus, pe.displayName);
        return NO;
    }

    // Verify the dylib exists after extraction
    NSString *dylibPath = [destDir stringByAppendingPathComponent:
        [NSString stringWithFormat:@"%@/%@.dylib", pe.folderName, pe.folderName]];
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:dylibPath];
    if (!exists) {
        NSLog(@"[PluginsAdmin] Warning: %@ not found after extraction", dylibPath);
    } else {
        NSLog(@"[PluginsAdmin] Installed %@ → %@", pe.displayName, dylibPath);
    }
    return exists;
}

- (void)showInstallError:(NSString *)pluginName detail:(NSString *)detail {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Failed to Install %@", pluginName];
    alert.informativeText = detail;
    alert.alertStyle = NSAlertStyleWarning;
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
