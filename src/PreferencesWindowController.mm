#import "PreferencesWindowController.h"
#import "NppLocalizer.h"
#import "NppThemeManager.h"
#import "StyleConfiguratorWindowController.h"

// ── NSUserDefaults keys (mirrors NPP settings) ────────────────────────────────
NSString *const kPrefTabWidth           = @"tabWidth";
NSString *const kPrefUseTabs            = @"useTabs";
NSString *const kPrefAutoIndent         = @"autoIndent";
NSString *const kPrefShowLineNumbers    = @"showLineNumbers";
NSString *const kPrefHighlightCurrentLine = @"highlightCurrentLine";
NSString *const kPrefEOLType            = @"eolType";       // 0=CRLF 1=LF 2=CR
NSString *const kPrefEncoding           = @"encoding";      // 0=UTF-8 1=Latin-1
NSString *const kPrefAutoBackup         = @"autoBackup";
NSString *const kPrefBackupInterval     = @"backupInterval"; // seconds
NSString *const kPrefZoomLevel          = @"zoomLevel";
NSString *const kPrefSpellCheck         = @"spellCheck";
NSString *const kPrefAutoCompleteEnable  = @"autoCompleteEnable";
NSString *const kPrefAutoCompleteMinChars = @"autoCompleteMinChars";
NSString *const kPrefAutoCloseBrackets   = @"autoCloseBrackets";
NSString *const kPrefShowFullPathInTitle = @"showFullPathInTitle";
NSString *const kPrefCaretWidth          = @"caretWidth";
NSString *const kPrefTabMaxLabelWidth    = @"tabMaxLabelWidth";
NSString *const kPrefTabCloseButton      = @"tabCloseButton";
NSString *const kPrefDoubleClickTabClose = @"doubleClickTabClose";
NSString *const kPrefVirtualSpace        = @"virtualSpace";
NSString *const kPrefScrollBeyondLastLine= @"scrollBeyondLastLine";
NSString *const kPrefCaretBlinkRate      = @"caretBlinkRate";
NSString *const kPrefFontQuality         = @"fontQuality";
NSString *const kPrefCopyLineNoSelection = @"copyLineNoSelection";
NSString *const kPrefSmartHighlight      = @"smartHighlight";
NSString *const kPrefFillFindWithSelection = @"fillFindWithSelection";
NSString *const kPrefFuncParamsHint      = @"funcParamsHint";
NSString *const kPrefShowStatusBar       = @"showStatusBar";
NSString *const kPrefMuteSounds          = @"muteSounds";
NSString *const kPrefSaveAllConfirm      = @"saveAllConfirm";
NSString *const kPrefRightClickKeepsSel  = @"rightClickKeepsSel";
NSString *const kPrefDisableTextDragDrop = @"disableTextDragDrop";
NSString *const kPrefMonoFontFind        = @"monoFontFind";
NSString *const kPrefConfirmReplaceAll   = @"confirmReplaceAll";
NSString *const kPrefReplaceAndStop      = @"replaceAndStop";
NSString *const kPrefSmartHiliteCase     = @"smartHiliteCase";
NSString *const kPrefSmartHiliteWord     = @"smartHiliteWord";
NSString *const kPrefDateTimeReverse     = @"dateTimeReverse";
NSString *const kPrefKeepAbsentSession   = @"keepAbsentSession";
NSString *const kPrefShowBookmarkMargin  = @"showBookmarkMargin";
NSString *const kPrefShowEOL             = @"showEOL";
NSString *const kPrefShowWhitespace      = @"showWhitespace";
NSString *const kPrefEdgeColumn          = @"edgeColumn";
NSString *const kPrefEdgeMode            = @"edgeMode";
NSString *const kPrefPaddingLeft         = @"paddingLeft";
NSString *const kPrefPaddingRight        = @"paddingRight";
NSString *const kPrefPanelKeepState      = @"panelKeepState";
NSString *const kPrefFoldStyle           = @"foldStyle";
NSString *const kPrefLineNumDynWidth     = @"lineNumDynWidth";
NSString *const kPrefInSelThreshold      = @"inSelThreshold";
NSString *const kPrefFuncListUseXML      = @"funcListUseXML";

// Theme / Style Configurator keys
NSString *const kPrefThemePreset        = @"themePreset";
NSString *const kPrefStyleFg            = @"styleFg";
NSString *const kPrefStyleBg            = @"styleBg";
NSString *const kPrefStyleComment       = @"styleComment";
NSString *const kPrefStyleKeyword       = @"styleKeyword";
NSString *const kPrefStyleString        = @"styleString";
NSString *const kPrefStyleNumber        = @"styleNumber";
NSString *const kPrefStylePreproc       = @"stylePreproc";
NSString *const kPrefStyleFontName      = @"styleFontName";
NSString *const kPrefStyleFontSize      = @"styleFontSize";

// Flipped NSView so scroll content starts at top-left
@interface _NPPFlippedView : NSView
@end
@implementation _NPPFlippedView
- (BOOL)isFlipped { return YES; }
@end

// ── Sidebar page definitions ─────────────────────────────────────────────────
// Each entry: @{@"title": name} or @{@"separator": @YES}
// Pages are built lazily and cached.

// ── PreferencesWindowController ───────────────────────────────────────────────

@interface PreferencesWindowController () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation PreferencesWindowController {
    NSTableView          *_sidebarTable;
    NSScrollView         *_contentScroll;
    NSView               *_contentArea;
    NSMutableArray       *_pageNames;     // sidebar row titles (NSString or @"-" for separator)
    NSMutableDictionary  *_pageViews;     // pageTitle → NSView (lazy cache)
    NSPopUpButton        *_languagePopup; // General page — language selector
}

+ (void)load {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        kPrefTabWidth:           @4,
        kPrefUseTabs:            @YES,
        kPrefAutoIndent:         @YES,
        kPrefShowLineNumbers:    @YES,
        kPrefHighlightCurrentLine: @YES,
        kPrefEOLType:            @1,
        kPrefEncoding:           @0,
        kPrefAutoBackup:         @YES,
        kPrefBackupInterval:     @60,
        kPrefZoomLevel:          @0,
        kPrefLanguage:           @"english",
        // Default (light) theme colors
        kPrefThemePreset:        @"Default",
        kPrefStyleFg:            @"#000000",
        kPrefStyleBg:            @"#FFFFFF",
        kPrefStyleComment:       @"#008000",
        kPrefStyleKeyword:       @"#0000FF",
        kPrefStyleString:        @"#A31515",
        kPrefStyleNumber:        @"#098658",
        kPrefStylePreproc:       @"#800080",
        kPrefStyleFontName:      @"Menlo",
        kPrefStyleFontSize:      @11,
        kPrefAutoCompleteEnable:   @YES,
        kPrefAutoCompleteMinChars: @1,
        kPrefAutoCloseBrackets:    @YES,
        kPrefShowFullPathInTitle:  @NO,
        kPrefCaretWidth:           @1,
        kPrefTabMaxLabelWidth:     @190,
        kPrefTabCloseButton:       @YES,
        kPrefDoubleClickTabClose:  @NO,
        kPrefVirtualSpace:         @NO,
        kPrefScrollBeyondLastLine: @NO,
        kPrefCaretBlinkRate:       @500,
        kPrefFontQuality:          @3,   // 0=default 1=none 2=antialiased 3=LCD
        kPrefCopyLineNoSelection:  @YES,
        kPrefSmartHighlight:       @YES,
        kPrefFillFindWithSelection:@YES,
        kPrefFuncParamsHint:       @NO,
        kPrefShowStatusBar:        @YES,
        kPrefMuteSounds:           @NO,
        kPrefSaveAllConfirm:       @NO,
        kPrefRightClickKeepsSel:   @NO,
        kPrefDisableTextDragDrop:  @NO,
        kPrefMonoFontFind:         @NO,
        kPrefConfirmReplaceAll:    @YES,
        kPrefReplaceAndStop:       @NO,
        kPrefSmartHiliteCase:      @NO,
        kPrefSmartHiliteWord:      @NO,
        kPrefDateTimeReverse:      @NO,
        kPrefKeepAbsentSession:    @NO,
        kPrefShowBookmarkMargin:   @YES,
        kPrefShowEOL:              @NO,
        kPrefShowWhitespace:       @NO,
        kPrefEdgeColumn:           @0,
        kPrefEdgeMode:             @0,    // 0=off 1=line 2=background
        kPrefPaddingLeft:          @0,
        kPrefPaddingRight:         @0,
        kPrefPanelKeepState:       @YES,
        kPrefFoldStyle:            @0,    // 0=box 1=circle 2=arrow 3=simple 4=none
        kPrefLineNumDynWidth:      @YES,
        kPrefInSelThreshold:       @1024,
        kPrefFuncListUseXML:       @YES,
        kPrefDarkMode:             @0,   // 0=Auto, 1=Light, 2=Dark
    }];
    // Force-upgrade any stale @NO value stored by earlier builds.
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (![ud objectForKey:kPrefUseTabs]) {
    } else if ([ud objectForKey:@"_useTabsDefaultApplied"] == nil) {
        [ud setBool:YES forKey:kPrefUseTabs];
        [ud setBool:YES forKey:@"_useTabsDefaultApplied"];
    }
}

+ (instancetype)sharedController {
    static PreferencesWindowController *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    NSWindow *win = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 700, 480)
                  styleMask:NSWindowStyleMaskTitled |
                            NSWindowStyleMaskClosable |
                            NSWindowStyleMaskMiniaturizable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    win.title = @"Preferences";
    [win center];
    self = [super initWithWindow:win];
    if (self) {
        [self registerDefaults];
        [self _buildSidebarLayout];
        [self retranslateUI];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_locChanged:)
                                                     name:NPPLocalizationChanged object:nil];
    }
    return self;
}

- (void)_locChanged:(NSNotification *)n {
    [self retranslateUI];
    [self _rebuildLanguagePopup];
}

- (void)retranslateUI {
    NppLocalizer *loc = [NppLocalizer shared];
    self.window.title = [loc translate:@"Preferences"];
}

- (void)registerDefaults {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        kPrefTabWidth:           @4,
        kPrefUseTabs:            @YES,
        kPrefAutoIndent:         @YES,
        kPrefShowLineNumbers:    @YES,
        kPrefHighlightCurrentLine: @YES,
        kPrefEOLType:            @1,
        kPrefEncoding:           @0,
        kPrefAutoBackup:         @YES,
        kPrefBackupInterval:     @60,
    }];
}

// ═══════════════════════════════════════════════════════════════════════════════
// Sidebar Layout
// ═══════════════════════════════════════════════════════════════════════════════

- (void)_buildSidebarLayout {
    NSView *root = self.window.contentView;

    // ── Page names (sidebar rows) ────────────────────────────────────────────
    _pageNames = [NSMutableArray arrayWithArray:@[
        @"General",
        @"Editor",
        @"Tab Bar",
        @"Dark Mode",
        @"Margins",
        @"New Document",
        @"Backup",
        @"Auto-Completion",
        @"Searching",
        @"MISC.",
    // Future pages can be added here
    // @"Performance",
    // @"Delimiter",
    ]];
    _pageViews = [NSMutableDictionary dictionary];

    // ── Sidebar (source list table view) ─────────────────────────────────────
    NSScrollView *sidebarScroll = [[NSScrollView alloc] init];
    sidebarScroll.translatesAutoresizingMaskIntoConstraints = NO;
    sidebarScroll.hasVerticalScroller   = NO;
    sidebarScroll.hasHorizontalScroller = NO;
    sidebarScroll.drawsBackground = NO;

    _sidebarTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _sidebarTable.headerView = nil;
    _sidebarTable.rowHeight = 24;
    _sidebarTable.intercellSpacing = NSMakeSize(0, 2);
    _sidebarTable.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    _sidebarTable.backgroundColor = [NSColor clearColor];
    _sidebarTable.dataSource = self;
    _sidebarTable.delegate   = self;

    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    col.editable = NO;
    [_sidebarTable addTableColumn:col];
    sidebarScroll.documentView = _sidebarTable;

    // ── Content area (wrapped in scroll view for long pages) ────────────────
    _contentArea = [[NSView alloc] init];
    _contentArea.translatesAutoresizingMaskIntoConstraints = NO;

    _contentScroll = [[NSScrollView alloc] init];
    _contentScroll.translatesAutoresizingMaskIntoConstraints = NO;
    _contentScroll.hasVerticalScroller   = YES;
    _contentScroll.hasHorizontalScroller = NO;
    _contentScroll.drawsBackground       = NO;
    _contentScroll.automaticallyAdjustsContentInsets = NO;
    _contentScroll.scrollerStyle = NSScrollerStyleOverlay; // macOS overlay scrollbar

    // Document view for scroll content (regular coordinate system — page views use frame positioning)
    _contentArea = [[NSView alloc] init];
    _contentScroll.documentView = _contentArea;

    // ── Close button ─────────────────────────────────────────────────────────
    NSButton *closeBtn = [NSButton buttonWithTitle:@"Close"
                                            target:self action:@selector(closePrefs:)];
    closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    closeBtn.keyEquivalent = @"\033";

    // ── Separator between sidebar and content ────────────────────────────────
    NSBox *sep = [[NSBox alloc] init];
    sep.boxType = NSBoxSeparator;
    sep.translatesAutoresizingMaskIntoConstraints = NO;

    [root addSubview:sidebarScroll];
    [root addSubview:sep];
    [root addSubview:_contentScroll];
    [root addSubview:closeBtn];

    [NSLayoutConstraint activateConstraints:@[
        // Sidebar
        [sidebarScroll.topAnchor      constraintEqualToAnchor:root.topAnchor constant:12],
        [sidebarScroll.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor constant:12],
        [sidebarScroll.widthAnchor    constraintEqualToConstant:170],
        [sidebarScroll.bottomAnchor   constraintEqualToAnchor:closeBtn.topAnchor constant:-12],

        // Separator
        [sep.topAnchor      constraintEqualToAnchor:root.topAnchor constant:8],
        [sep.leadingAnchor  constraintEqualToAnchor:sidebarScroll.trailingAnchor constant:8],
        [sep.widthAnchor    constraintEqualToConstant:1],
        [sep.bottomAnchor   constraintEqualToAnchor:closeBtn.topAnchor constant:-8],

        // Content scroll view
        [_contentScroll.topAnchor      constraintEqualToAnchor:root.topAnchor constant:12],
        [_contentScroll.leadingAnchor  constraintEqualToAnchor:sep.trailingAnchor constant:12],
        [_contentScroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-12],
        [_contentScroll.bottomAnchor   constraintEqualToAnchor:closeBtn.topAnchor constant:-12],

        // Close button
        [closeBtn.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-16],
        [closeBtn.bottomAnchor   constraintEqualToAnchor:root.bottomAnchor constant:-12],
        [closeBtn.widthAnchor    constraintEqualToConstant:80],
    ]];

    // Select first real page — defer until after layout so contentSize is valid
    [_sidebarTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _showPageAtIndex:0];
    });
}

// ═══════════════════════════════════════════════════════════════════════════════
// Sidebar Data Source & Delegate
// ═══════════════════════════════════════════════════════════════════════════════

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv {
    return (NSInteger)_pageNames.count;
}

- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    NSString *name = _pageNames[row];

    if ([name isEqualToString:@"-"]) {
        // Separator row
        NSBox *sep = [[NSBox alloc] init];
        sep.boxType = NSBoxSeparator;
        sep.frame = NSMakeRect(8, 10, 150, 1);
        NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 170, 20)];
        [container addSubview:sep];
        return container;
    }

    NSTextField *tf = [tv makeViewWithIdentifier:@"cell" owner:nil];
    if (!tf) {
        tf = [NSTextField labelWithString:@""];
        tf.identifier = @"cell";
        tf.font = [NSFont systemFontOfSize:13];
    }
    tf.stringValue = name;
    return tf;
}

- (CGFloat)tableView:(NSTableView *)tv heightOfRow:(NSInteger)row {
    NSString *name = _pageNames[row];
    return [name isEqualToString:@"-"] ? 12 : 26;
}

- (BOOL)tableView:(NSTableView *)tv shouldSelectRow:(NSInteger)row {
    return ![_pageNames[row] isEqualToString:@"-"]; // separators not selectable
}

- (void)tableViewSelectionDidChange:(NSNotification *)n {
    NSInteger row = _sidebarTable.selectedRow;
    if (row >= 0) [self _showPageAtIndex:row];
}

// ═══════════════════════════════════════════════════════════════════════════════
// Page Switching
// ═══════════════════════════════════════════════════════════════════════════════

- (void)_showPageAtIndex:(NSInteger)index {
    NSString *name = _pageNames[index];
    if ([name isEqualToString:@"-"]) return;

    // Remove current content
    for (NSView *sub in [_contentArea.subviews copy])
        [sub removeFromSuperview];

    // Build or retrieve cached page view
    NSView *pageView = _pageViews[name];
    if (!pageView) {
        pageView = [self _buildPageForName:name];
        if (pageView) _pageViews[name] = pageView;
    }
    if (!pageView) return;

    // Page views use frame-based positioning: y starts high (e.g. 380) and decreases.
    // Find the bounding box of all subviews to determine actual content extent.
    CGFloat contentW = _contentScroll.contentSize.width;
    CGFloat visibleH = _contentScroll.contentSize.height;

    CGFloat maxY = 0, minY = CGFLOAT_MAX;
    for (NSView *sub in pageView.subviews) {
        CGFloat top = NSMaxY(sub.frame);
        CGFloat bot = NSMinY(sub.frame);
        if (top > maxY) maxY = top;
        if (bot < minY) minY = bot;
    }
    if (minY == CGFLOAT_MAX) { minY = 0; maxY = visibleH; }

    // Content height = span of controls + padding at top and bottom
    CGFloat controlsHeight = (maxY - minY) + 20; // 20px padding
    CGFloat pageHeight = MAX(visibleH, controlsHeight);

    // Shift controls so the topmost control sits 10px from the top of the page view
    CGFloat shiftY = pageHeight - maxY - 10;
    if (fabs(shiftY) > 1) {
        for (NSView *sub in pageView.subviews) {
            NSRect f = sub.frame;
            f.origin.y += shiftY;
            sub.frame = f;
        }
    }

    pageView.frame = NSMakeRect(0, 0, contentW, pageHeight);
    pageView.autoresizingMask = NSViewWidthSizable;
    [_contentArea addSubview:pageView];

    _contentArea.frame = NSMakeRect(0, 0, contentW, pageHeight);

    // Scroll to top (in non-flipped view, top = highest Y)
    [_contentArea scrollPoint:NSMakePoint(0, pageHeight)];
}

- (NSView *)_buildPageForName:(NSString *)name {
    if ([name isEqualToString:@"General"])         return [self _buildGeneralPage];
    if ([name isEqualToString:@"Editor"])          return [self _buildEditorPage];
    if ([name isEqualToString:@"Tab Bar"])         return [self _buildTabBarPage];
    if ([name isEqualToString:@"Dark Mode"])       return [self _buildDarkModePage];
    if ([name isEqualToString:@"Margins"])          return [self _buildMarginsPage];
    if ([name isEqualToString:@"New Document"])     return [self _buildNewDocPage];
    if ([name isEqualToString:@"Backup"])           return [self _buildBackupPage];
    if ([name isEqualToString:@"Auto-Completion"])  return [self _buildAutoCompletionPage];
    if ([name isEqualToString:@"Searching"])        return [self _buildSearchingPage];
    if ([name isEqualToString:@"MISC."])            return [self _buildMiscPage];
    return nil;
}

// ═══════════════════════════════════════════════════════════════════════════════
// Page Builders — Each returns an NSView with all controls
// ═══════════════════════════════════════════════════════════════════════════════

#pragma mark - General Page

- (NSView *)_buildGeneralPage {
    NSView *v = [[NSView alloc] init];
    CGFloat y = 380;

    // ── Localization ──
    NSTextField *sectionLabel = [NSTextField labelWithString:@"Localization"];
    sectionLabel.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
    sectionLabel.frame = NSMakeRect(20, y, 300, 20);
    [v addSubview:sectionLabel];
    y -= 30;

    NSTextField *langLabel = [NSTextField labelWithString:@"Language:"];
    langLabel.frame = NSMakeRect(20, y, 90, 20);
    [v addSubview:langLabel];

    _languagePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(120, y - 2, 250, 26) pullsDown:NO];
    _languagePopup.tag = 400;
    _languagePopup.target = self;
    _languagePopup.action = @selector(prefChanged:);
    [self _rebuildLanguagePopup];
    [v addSubview:_languagePopup];
    y -= 36;

    NSTextField *hint = [NSTextField wrappingLabelWithString:
        @"Additional language files (.xml) can be placed in:\n"
         "~/Library/Application Support/Notepad++/nativeLang/"];
    hint.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    hint.textColor = NSColor.secondaryLabelColor;
    hint.frame = NSMakeRect(20, y - 16, 400, 44);
    [v addSubview:hint];
    y -= 70;

    // ── Title Bar ──
    NSTextField *tbSection = [NSTextField labelWithString:@"Title Bar"];
    tbSection.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
    tbSection.frame = NSMakeRect(20, y, 300, 20);
    [v addSubview:tbSection];
    y -= 28;

    NSButton *fullPath = [NSButton checkboxWithTitle:@"Show full file path in title bar"
                                              target:self action:@selector(prefChanged:)];
    fullPath.frame = NSMakeRect(20, y, 350, 20);
    fullPath.state = [[NSUserDefaults standardUserDefaults] boolForKey:kPrefShowFullPathInTitle]
                     ? NSControlStateValueOn : NSControlStateValueOff;
    fullPath.tag = 900;
    [v addSubview:fullPath];
    y -= 32;

    // ── Status Bar ──
    NSTextField *sbSection = [NSTextField labelWithString:@"Status Bar"];
    sbSection.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
    sbSection.frame = NSMakeRect(20, y, 300, 20);
    [v addSubview:sbSection];
    y -= 28;

    NSButton *showSB = [NSButton checkboxWithTitle:@"Show status bar"
                                            target:self action:@selector(prefChanged:)];
    showSB.frame = NSMakeRect(20, y, 350, 20);
    showSB.state = [[NSUserDefaults standardUserDefaults] boolForKey:kPrefShowStatusBar]
                   ? NSControlStateValueOn : NSControlStateValueOff;
    showSB.tag = 901;
    [v addSubview:showSB];

    return v;
}

#pragma mark - Editor Page

- (NSView *)_buildEditorPage {
    NSView *v = [[NSView alloc] init];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    CGFloat y = 380;

    NSTextField *tabLabel = [NSTextField labelWithString:@"Tab size:"];
    tabLabel.frame = NSMakeRect(20, y, 80, 20);
    [v addSubview:tabLabel];

    NSTextField *tabField = [[NSTextField alloc] initWithFrame:NSMakeRect(110, y-2, 50, 22)];
    tabField.integerValue = [ud integerForKey:kPrefTabWidth];
    tabField.tag = 100;
    tabField.target = self;
    tabField.action = @selector(prefChanged:);
    [v addSubview:tabField];
    y -= 30;

    NSArray *checks = @[
        @[@"Use tabs (instead of spaces)",    @101, kPrefUseTabs],
        @[@"Auto-indent",                     @102, kPrefAutoIndent],
        @[@"Show line numbers",               @103, kPrefShowLineNumbers],
        @[@"Highlight current line",          @105, kPrefHighlightCurrentLine],
        @[@"Auto-close brackets ( ) [ ] { }", @700, kPrefAutoCloseBrackets],
        @[@"Enable virtual space",            @702, kPrefVirtualSpace],
        @[@"Scroll beyond last line",         @703, kPrefScrollBeyondLastLine],
        @[@"Copy/cut line without selection",  @706, kPrefCopyLineNoSelection],
        @[@"Right-click keeps selection",      @707, kPrefRightClickKeepsSel],
        @[@"Disable selected text drag-drop",  @708, kPrefDisableTextDragDrop],
        @[@"Show bookmark margin",             @709, kPrefShowBookmarkMargin],
        @[@"Show EOL markers",                 @710, kPrefShowEOL],
        @[@"Show whitespace",                  @711, kPrefShowWhitespace],
    ];
    for (NSArray *def in checks) {
        NSButton *chk = [NSButton checkboxWithTitle:def[0] target:self action:@selector(prefChanged:)];
        chk.frame = NSMakeRect(20, y, 350, 20);
        chk.state = [ud boolForKey:def[2]] ? NSControlStateValueOn : NSControlStateValueOff;
        chk.tag = [def[1] integerValue];
        [v addSubview:chk];
        y -= 28;
    }

    y -= 8;
    // Caret width
    NSTextField *cwLabel = [NSTextField labelWithString:@"Caret width:"];
    cwLabel.frame = NSMakeRect(20, y, 100, 20);
    [v addSubview:cwLabel];
    NSPopUpButton *cwPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(130, y-2, 120, 26) pullsDown:NO];
    [cwPopup addItemsWithTitles:@[@"Thin (1px)", @"Medium (2px)", @"Thick (3px)"]];
    [cwPopup selectItemAtIndex:[ud integerForKey:kPrefCaretWidth] - 1];
    cwPopup.tag = 701; cwPopup.target = self; cwPopup.action = @selector(prefChanged:);
    [v addSubview:cwPopup];
    y -= 32;

    // Caret blink rate
    NSTextField *brLabel = [NSTextField labelWithString:@"Caret blink rate (ms):"];
    brLabel.frame = NSMakeRect(20, y, 160, 20);
    [v addSubview:brLabel];
    NSTextField *brField = [[NSTextField alloc] initWithFrame:NSMakeRect(190, y-2, 60, 22)];
    brField.integerValue = [ud integerForKey:kPrefCaretBlinkRate];
    brField.tag = 704; brField.target = self; brField.action = @selector(prefChanged:);
    [v addSubview:brField];
    y -= 32;

    // Font quality
    NSTextField *fqLabel = [NSTextField labelWithString:@"Font rendering:"];
    fqLabel.frame = NSMakeRect(20, y, 120, 20);
    [v addSubview:fqLabel];
    NSPopUpButton *fqPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(150, y-2, 180, 26) pullsDown:NO];
    [fqPopup addItemsWithTitles:@[@"Default", @"None", @"Antialiased", @"LCD Optimized"]];
    [fqPopup selectItemAtIndex:[ud integerForKey:kPrefFontQuality]];
    fqPopup.tag = 705; fqPopup.target = self; fqPopup.action = @selector(prefChanged:);
    [v addSubview:fqPopup];

    return v;
}

#pragma mark - Tab Bar Page

- (NSView *)_buildTabBarPage {
    NSView *v = [[NSView alloc] init];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    CGFloat y = 380;

    NSArray *checks = @[
        @[@"Show close button on tabs",        @800, kPrefTabCloseButton],
        @[@"Double-click to close tab",        @801, kPrefDoubleClickTabClose],
    ];
    for (NSArray *def in checks) {
        NSButton *chk = [NSButton checkboxWithTitle:def[0] target:self action:@selector(prefChanged:)];
        chk.frame = NSMakeRect(20, y, 350, 20);
        chk.state = [ud boolForKey:def[2]] ? NSControlStateValueOn : NSControlStateValueOff;
        chk.tag = [def[1] integerValue];
        [v addSubview:chk];
        y -= 28;
    }

    y -= 8;
    NSTextField *mwLabel = [NSTextField labelWithString:@"Max tab width (pixels):"];
    mwLabel.frame = NSMakeRect(20, y, 170, 20);
    [v addSubview:mwLabel];
    NSTextField *mwField = [[NSTextField alloc] initWithFrame:NSMakeRect(200, y-2, 60, 22)];
    mwField.integerValue = [ud integerForKey:kPrefTabMaxLabelWidth];
    mwField.tag = 802; mwField.target = self; mwField.action = @selector(prefChanged:);
    [v addSubview:mwField];

    return v;
}

#pragma mark - Margins Page

- (NSView *)_buildMarginsPage {
    NSView *v = [[NSView alloc] init];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    CGFloat y = 380;

    // ── Edge Column ──
    NSTextField *edgeSection = [NSTextField labelWithString:@"Vertical Edge"];
    edgeSection.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
    edgeSection.frame = NSMakeRect(20, y, 300, 20);
    [v addSubview:edgeSection];
    y -= 28;

    NSTextField *emLabel = [NSTextField labelWithString:@"Edge mode:"];
    emLabel.frame = NSMakeRect(20, y, 90, 20);
    [v addSubview:emLabel];
    NSPopUpButton *emPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(120, y-2, 160, 26) pullsDown:NO];
    [emPopup addItemsWithTitles:@[@"Off", @"Line", @"Background"]];
    [emPopup selectItemAtIndex:[ud integerForKey:kPrefEdgeMode]];
    emPopup.tag = 1101; emPopup.target = self; emPopup.action = @selector(prefChanged:);
    [v addSubview:emPopup];
    y -= 30;

    NSTextField *ecLabel = [NSTextField labelWithString:@"Edge column:"];
    ecLabel.frame = NSMakeRect(20, y, 100, 20);
    [v addSubview:ecLabel];
    NSTextField *ecField = [[NSTextField alloc] initWithFrame:NSMakeRect(130, y-2, 50, 22)];
    ecField.integerValue = [ud integerForKey:kPrefEdgeColumn];
    ecField.tag = 1100; ecField.target = self; ecField.action = @selector(prefChanged:);
    [v addSubview:ecField];
    y -= 36;

    // ── Fold Margin Style ──
    NSTextField *foldSection = [NSTextField labelWithString:@"Fold Margin Style"];
    foldSection.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
    foldSection.frame = NSMakeRect(20, y, 300, 20);
    [v addSubview:foldSection];
    y -= 28;

    NSPopUpButton *foldPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, y-2, 180, 26) pullsDown:NO];
    [foldPopup addItemsWithTitles:@[@"Box tree", @"Circle tree", @"Arrow", @"Simple +/-", @"None"]];
    [foldPopup selectItemAtIndex:[ud integerForKey:kPrefFoldStyle]];
    foldPopup.tag = 1104; foldPopup.target = self; foldPopup.action = @selector(prefChanged:);
    [v addSubview:foldPopup];
    y -= 36;

    // ── Line Numbers ──
    NSButton *dynWidth = [NSButton checkboxWithTitle:@"Dynamic line number width"
                                              target:self action:@selector(prefChanged:)];
    dynWidth.frame = NSMakeRect(20, y, 350, 20);
    dynWidth.state = [ud boolForKey:kPrefLineNumDynWidth] ? NSControlStateValueOn : NSControlStateValueOff;
    dynWidth.tag = 1105;
    [v addSubview:dynWidth];
    y -= 36;

    // ── Padding ──
    NSTextField *padSection = [NSTextField labelWithString:@"Padding"];
    padSection.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
    padSection.frame = NSMakeRect(20, y, 300, 20);
    [v addSubview:padSection];
    y -= 28;

    NSTextField *plLabel = [NSTextField labelWithString:@"Left:"];
    plLabel.frame = NSMakeRect(20, y, 40, 20);
    [v addSubview:plLabel];
    NSTextField *plField = [[NSTextField alloc] initWithFrame:NSMakeRect(65, y-2, 50, 22)];
    plField.integerValue = [ud integerForKey:kPrefPaddingLeft];
    plField.tag = 1102; plField.target = self; plField.action = @selector(prefChanged:);
    [v addSubview:plField];

    NSTextField *prLabel = [NSTextField labelWithString:@"Right:"];
    prLabel.frame = NSMakeRect(140, y, 50, 20);
    [v addSubview:prLabel];
    NSTextField *prField = [[NSTextField alloc] initWithFrame:NSMakeRect(195, y-2, 50, 22)];
    prField.integerValue = [ud integerForKey:kPrefPaddingRight];
    prField.tag = 1103; prField.target = self; prField.action = @selector(prefChanged:);
    [v addSubview:prField];

    return v;
}

#pragma mark - Dark Mode Page

- (NSView *)_buildDarkModePage {
    NSView *v = [[NSView alloc] init];
    CGFloat y = 380;

    NSTextField *dmLabel = [NSTextField labelWithString:@"Appearance"];
    dmLabel.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
    dmLabel.frame = NSMakeRect(20, y, 300, 20);
    [v addSubview:dmLabel];
    y -= 32;

    NSArray *titles = @[@"Auto (Follow System)", @"Light", @"Dark"];
    for (NSInteger i = 0; i < 3; i++) {
        NSButton *radio = [NSButton radioButtonWithTitle:titles[i] target:self action:@selector(_darkModeRadioChanged:)];
        radio.frame = NSMakeRect(20, y, 300, 20);
        radio.tag = 500 + i;
        radio.state = ([NppThemeManager shared].mode == i) ? NSControlStateValueOn : NSControlStateValueOff;
        [v addSubview:radio];
        y -= 24;
    }

    return v;
}

- (void)_darkModeRadioChanged:(id)sender {
    NSInteger mode = [(NSButton *)sender tag] - 500;
    // Deselect other radios
    NSView *page = [(NSButton *)sender superview];
    for (NSView *sub in page.subviews) {
        if ([sub isKindOfClass:[NSButton class]] && [(NSButton *)sub tag] >= 500 && [(NSButton *)sub tag] <= 502) {
            [(NSButton *)sub setState:((NSButton *)sub).tag == [(NSButton *)sender tag]
                ? NSControlStateValueOn : NSControlStateValueOff];
        }
    }
    [NppThemeManager shared].mode = (NppDarkModeOption)mode;

    // Switch theme to match dark/light mode
    NPPStyleStore *store = [NPPStyleStore sharedStore];
    BOOL effectiveDark = (mode == NppDarkModeDark) ||
        (mode == NppDarkModeAuto && [NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:
            @[NSAppearanceNameDarkAqua]] != nil);
    NSString *targetTheme = effectiveDark ? @"DarkModeDefault" : @"Default (stylers.xml)";
    if (![store.activeThemeName isEqualToString:targetTheme]) {
        NSArray *lexers = [store lexersForTheme:targetTheme];
        [store commitLexers:lexers themeName:targetTheme];
    }
}

#pragma mark - New Document Page

- (NSView *)_buildNewDocPage {
    NSView *v = [[NSView alloc] init];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    CGFloat y = 380;

    NSTextField *eolLabel = [NSTextField labelWithString:@"Default line ending:"];
    eolLabel.frame = NSMakeRect(20, y, 150, 20);
    [v addSubview:eolLabel];

    NSPopUpButton *eolPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(180, y-2, 180, 26) pullsDown:NO];
    [eolPopup addItemsWithTitles:@[@"Windows (CRLF)", @"Unix (LF)", @"Mac (CR)"]];
    [eolPopup selectItemAtIndex:[ud integerForKey:kPrefEOLType]];
    eolPopup.tag = 200;
    eolPopup.target = self;
    eolPopup.action = @selector(prefChanged:);
    [v addSubview:eolPopup];
    y -= 36;

    NSTextField *encLabel = [NSTextField labelWithString:@"Default encoding:"];
    encLabel.frame = NSMakeRect(20, y, 150, 20);
    [v addSubview:encLabel];

    NSPopUpButton *encPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(180, y-2, 180, 26) pullsDown:NO];
    [encPopup addItemsWithTitles:@[@"UTF-8", @"Latin-1 (ISO-8859-1)"]];
    [encPopup selectItemAtIndex:[ud integerForKey:kPrefEncoding]];
    encPopup.tag = 201;
    encPopup.target = self;
    encPopup.action = @selector(prefChanged:);
    [v addSubview:encPopup];

    return v;
}

#pragma mark - Backup Page

- (NSView *)_buildBackupPage {
    NSView *v = [[NSView alloc] init];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    CGFloat y = 380;

    NSButton *autoBackup = [NSButton checkboxWithTitle:@"Enable auto-backup"
                                                target:self action:@selector(prefChanged:)];
    autoBackup.frame = NSMakeRect(20, y, 350, 20);
    autoBackup.state = [ud boolForKey:kPrefAutoBackup] ? NSControlStateValueOn : NSControlStateValueOff;
    autoBackup.tag = 300;
    [v addSubview:autoBackup];
    y -= 30;

    NSTextField *intLabel = [NSTextField labelWithString:@"Backup interval (seconds):"];
    intLabel.frame = NSMakeRect(20, y, 200, 20);
    [v addSubview:intLabel];

    NSTextField *intField = [[NSTextField alloc] initWithFrame:NSMakeRect(230, y-2, 60, 22)];
    intField.integerValue = [ud integerForKey:kPrefBackupInterval];
    intField.tag = 301;
    intField.target = self;
    intField.action = @selector(prefChanged:);
    [v addSubview:intField];
    y -= 36;

    NSTextField *backupDirLabel = [NSTextField labelWithString:@"Backup location:"];
    backupDirLabel.frame = NSMakeRect(20, y, 140, 20);
    [v addSubview:backupDirLabel];
    y -= 20;

    NSTextField *backupPath = [NSTextField labelWithString:
        [NSHomeDirectory() stringByAppendingPathComponent:@".notepad++/backup/"]];
    backupPath.frame = NSMakeRect(20, y, 400, 20);
    backupPath.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    [v addSubview:backupPath];

    return v;
}

#pragma mark - Auto-Completion Page

- (NSView *)_buildAutoCompletionPage {
    NSView *v = [[NSView alloc] init];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    CGFloat y = 380;

    NSArray *checks = @[
        @[@"Enable auto-completion on each input",     @600, kPrefAutoCompleteEnable],
        @[@"Function parameters hint on input",        @602, kPrefFuncParamsHint],
    ];
    for (NSArray *def in checks) {
        NSButton *chk = [NSButton checkboxWithTitle:def[0] target:self action:@selector(prefChanged:)];
        chk.frame = NSMakeRect(20, y, 400, 20);
        chk.state = [ud boolForKey:def[2]] ? NSControlStateValueOn : NSControlStateValueOff;
        chk.tag = [def[1] integerValue];
        [v addSubview:chk];
        y -= 28;
    }

    y -= 4;
    NSTextField *minLabel = [NSTextField labelWithString:@"From Nth character:"];
    minLabel.frame = NSMakeRect(20, y, 160, 20);
    [v addSubview:minLabel];

    NSTextField *minField = [[NSTextField alloc] initWithFrame:NSMakeRect(190, y-2, 50, 22)];
    minField.integerValue = [ud integerForKey:kPrefAutoCompleteMinChars];
    minField.tag = 601;
    minField.target = self;
    minField.action = @selector(prefChanged:);
    [v addSubview:minField];

    return v;
}

#pragma mark - Searching Page

- (NSView *)_buildSearchingPage {
    NSView *v = [[NSView alloc] init];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    CGFloat y = 380;

    NSArray *checks = @[
        @[@"Enable smart highlighting",              @1000, kPrefSmartHighlight],
        @[@"Smart highlighting: match case",          @1002, kPrefSmartHiliteCase],
        @[@"Smart highlighting: whole word only",     @1003, kPrefSmartHiliteWord],
        @[@"Fill find field with selected text",      @1001, kPrefFillFindWithSelection],
        @[@"Use monospaced font in Find dialog",      @1004, kPrefMonoFontFind],
        @[@"Confirm Replace All in open documents",   @1005, kPrefConfirmReplaceAll],
        @[@"Replace: don't move to next occurrence",  @1006, kPrefReplaceAndStop],
    ];
    for (NSArray *def in checks) {
        NSButton *chk = [NSButton checkboxWithTitle:def[0] target:self action:@selector(prefChanged:)];
        chk.frame = NSMakeRect(20, y, 400, 20);
        chk.state = [ud boolForKey:def[2]] ? NSControlStateValueOn : NSControlStateValueOff;
        chk.tag = [def[1] integerValue];
        [v addSubview:chk];
        y -= 28;
    }

    y -= 8;
    NSTextField *threshLabel = [NSTextField labelWithString:@"In-selection auto-check threshold (bytes):"];
    threshLabel.frame = NSMakeRect(20, y, 300, 20);
    [v addSubview:threshLabel];
    NSTextField *threshField = [[NSTextField alloc] initWithFrame:NSMakeRect(330, y-2, 60, 22)];
    threshField.integerValue = [ud integerForKey:kPrefInSelThreshold];
    threshField.tag = 1007; threshField.target = self; threshField.action = @selector(prefChanged:);
    [v addSubview:threshField];

    return v;
}

// Search Engine page removed — merged into Searching

#pragma mark - MISC. Page

- (NSView *)_buildMiscPage {
    NSView *v = [[NSView alloc] init];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    CGFloat y = 380;

    NSArray *checks = @[
        @[@"Mute all sounds",                          @1200, kPrefMuteSounds],
        @[@"Confirm before Save All",                  @1201, kPrefSaveAllConfirm],
        @[@"Reverse default date/time order",          @1202, kPrefDateTimeReverse],
        @[@"Keep absent file entries in session",      @1203, kPrefKeepAbsentSession],
        @[@"Remember panel visibility across sessions", @1204, kPrefPanelKeepState],
        @[@"Use XML-based function list parsers",      @1205, kPrefFuncListUseXML],
    ];
    for (NSArray *def in checks) {
        NSButton *chk = [NSButton checkboxWithTitle:def[0] target:self action:@selector(prefChanged:)];
        chk.frame = NSMakeRect(20, y, 400, 20);
        chk.state = [ud boolForKey:def[2]] ? NSControlStateValueOn : NSControlStateValueOff;
        chk.tag = [def[1] integerValue];
        [v addSubview:chk];
        y -= 28;
    }

    return v;
}

// ═══════════════════════════════════════════════════════════════════════════════
// Language Popup Helper
// ═══════════════════════════════════════════════════════════════════════════════

- (void)_rebuildLanguagePopup {
    if (!_languagePopup) return;

    NSDictionary<NSString *, NSString *> *langMap = [NppLocalizer availableLanguagesMap];
    NSArray<NSString *> *names = [[langMap allKeys]
        sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

    [_languagePopup removeAllItems];
    [_languagePopup addItemsWithTitles:names];

    NSString *currentFile = [NppLocalizer shared].currentLanguageFile;
    for (NSString *name in names) {
        if ([langMap[name].lowercaseString isEqualToString:currentFile.lowercaseString]) {
            [_languagePopup selectItemWithTitle:name];
            break;
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Actions
// ═══════════════════════════════════════════════════════════════════════════════

- (void)prefChanged:(id)sender {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSInteger tag = [(NSControl *)sender tag];

    switch (tag) {
        case 100: [ud setInteger:[(NSTextField *)sender integerValue] forKey:kPrefTabWidth]; break;
        case 101: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefUseTabs]; break;
        case 102: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefAutoIndent]; break;
        case 103: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefShowLineNumbers]; break;
        case 105: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefHighlightCurrentLine]; break;
        case 200: [ud setInteger:[(NSPopUpButton *)sender indexOfSelectedItem] forKey:kPrefEOLType]; break;
        case 201: [ud setInteger:[(NSPopUpButton *)sender indexOfSelectedItem] forKey:kPrefEncoding]; break;
        case 300: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefAutoBackup]; break;
        case 301: [ud setInteger:[(NSTextField *)sender integerValue] forKey:kPrefBackupInterval]; break;
        case 400: {
            NSPopUpButton *popup = (NSPopUpButton *)sender;
            NSString *selectedName = popup.selectedItem.title;
            if (selectedName.length > 0) {
                NSDictionary *langMap = [NppLocalizer availableLanguagesMap];
                NSString *stem = langMap[selectedName];
                if (stem) {
                    [[NppLocalizer shared] loadLanguageNamed:stem];
                }
            }
            return;
        }
        case 600: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefAutoCompleteEnable]; break;
        case 601: [ud setInteger:[(NSTextField *)sender integerValue] forKey:kPrefAutoCompleteMinChars]; break;
        case 602: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefFuncParamsHint]; break;
        // Editor settings
        case 700: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefAutoCloseBrackets]; break;
        case 701: [ud setInteger:[(NSPopUpButton *)sender indexOfSelectedItem] + 1 forKey:kPrefCaretWidth]; break;
        case 702: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefVirtualSpace]; break;
        case 703: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefScrollBeyondLastLine]; break;
        case 704: [ud setInteger:[(NSTextField *)sender integerValue] forKey:kPrefCaretBlinkRate]; break;
        case 705: [ud setInteger:[(NSPopUpButton *)sender indexOfSelectedItem] forKey:kPrefFontQuality]; break;
        case 706: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefCopyLineNoSelection]; break;
        // Tab Bar settings
        case 800: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefTabCloseButton]; break;
        case 801: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefDoubleClickTabClose]; break;
        case 802: [ud setInteger:[(NSTextField *)sender integerValue] forKey:kPrefTabMaxLabelWidth]; break;
        // General
        case 900: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefShowFullPathInTitle]; break;
        // Searching
        case 1000: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefSmartHighlight]; break;
        case 1001: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefFillFindWithSelection]; break;
        case 1002: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefSmartHiliteCase]; break;
        case 1003: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefSmartHiliteWord]; break;
        case 1004: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefMonoFontFind]; break;
        case 1005: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefConfirmReplaceAll]; break;
        case 1006: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefReplaceAndStop]; break;
        case 1007: [ud setInteger:[(NSTextField *)sender integerValue] forKey:kPrefInSelThreshold]; break;
        // General
        case 901: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefShowStatusBar]; break;
        // Editor
        case 707: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefRightClickKeepsSel]; break;
        case 708: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefDisableTextDragDrop]; break;
        case 709: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefShowBookmarkMargin]; break;
        case 710: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefShowEOL]; break;
        case 711: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefShowWhitespace]; break;
        // Margins
        case 1100: [ud setInteger:[(NSTextField *)sender integerValue] forKey:kPrefEdgeColumn]; break;
        case 1101: [ud setInteger:[(NSPopUpButton *)sender indexOfSelectedItem] forKey:kPrefEdgeMode]; break;
        case 1102: [ud setInteger:[(NSTextField *)sender integerValue] forKey:kPrefPaddingLeft]; break;
        case 1103: [ud setInteger:[(NSTextField *)sender integerValue] forKey:kPrefPaddingRight]; break;
        case 1104: [ud setInteger:[(NSPopUpButton *)sender indexOfSelectedItem] forKey:kPrefFoldStyle]; break;
        case 1105: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefLineNumDynWidth]; break;
        // MISC
        case 1200: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefMuteSounds]; break;
        case 1201: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefSaveAllConfirm]; break;
        case 1202: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefDateTimeReverse]; break;
        case 1203: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefKeepAbsentSession]; break;
        case 1204: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefPanelKeepState]; break;
        case 1205: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefFuncListUseXML]; break;
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:@"NPPPreferencesChanged" object:nil];
}

- (void)closePrefs:(id)sender {
    [self.window orderOut:nil];
}

@end
