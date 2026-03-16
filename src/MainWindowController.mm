#import "MainWindowController.h"
#import "TabManager.h"
#import "EditorView.h"
#import "FindReplacePanel.h"
#import "MenuBuilder.h"
#import "ColumnEditorPanel.h"
#import "FindInFilesPanel.h"
#import "SidePanelHost.h"
#import "DocumentListPanel.h"
#import "ClipboardHistoryPanel.h"
#import "FunctionListPanel.h"
#import "DocumentMapPanel.h"
#import "ProjectPanel.h"
#import "PreferencesWindowController.h"
#import "IncrementalSearchBar.h"
#import "CommandPalettePanel.h"
#import "GitHelper.h"
#import "GitPanel.h"
#import "FolderTreePanel.h"
#import <objc/runtime.h>

// ── Private helper for the Windows… dialog ───────────────────────────────────
@interface _NPPWindowsListHelper : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSArray<NSDictionary *> *rows;
@property (nonatomic, weak)   NSTableView *tableView;
@property (nonatomic, copy)   void (^activateHandler)(void);
@property (nonatomic, copy)   void (^closeHandler)(void);
- (instancetype)initWithRows:(NSArray<NSDictionary *> *)rows;
- (void)activatePressed:(id)sender;
- (void)closePressed:(id)sender;
@end

@implementation _NPPWindowsListHelper
- (instancetype)initWithRows:(NSArray<NSDictionary *> *)rows {
    self = [super init];
    _rows = rows;
    return self;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return (NSInteger)_rows.count; }
- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    NSTextField *f = [tv makeViewWithIdentifier:col.identifier owner:nil];
    if (!f) {
        f = [NSTextField labelWithString:@""];
        f.identifier = col.identifier;
        f.lineBreakMode = NSLineBreakByTruncatingMiddle;
    }
    NSDictionary *entry = _rows[row];
    if ([col.identifier isEqualToString:@"name"]) {
        NSString *name = entry[@"name"];
        f.stringValue = [entry[@"modified"] boolValue]
            ? [NSString stringWithFormat:@"* %@", name] : name;
    } else if ([col.identifier isEqualToString:@"ext"]) {
        NSString *path = entry[@"path"];
        f.stringValue = path.length ? path.pathExtension : @"";
    } else {
        f.stringValue = entry[@"path"];
    }
    return f;
}
- (void)activatePressed:(id)sender { if (_activateHandler) _activateHandler(); }
- (void)closePressed:(id)sender    { if (_closeHandler)    _closeHandler();    }
@end

static NSString *const kWindowFrameKey = @"MainWindowFrame";

// ── ~/.notepad++ paths (mirrors %APPDATA%\Notepad++ on Windows) ───────────────
static NSString *nppConfigDir(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@".notepad++"];
}
static NSString *nppBackupDir(void) {
    return [nppConfigDir() stringByAppendingPathComponent:@"backup"];
}
static NSString *nppSessionPath(void) {
    return [nppConfigDir() stringByAppendingPathComponent:@"session.plist"];
}
static void ensureNppDirs(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:nppBackupDir()
  withIntermediateDirectories:YES attributes:nil error:nil];
}

// Toolbar item identifiers
static NSToolbarItemIdentifier const kTBNew         = @"TB_New";
static NSToolbarItemIdentifier const kTBOpen        = @"TB_Open";
static NSToolbarItemIdentifier const kTBSave        = @"TB_Save";
static NSToolbarItemIdentifier const kTBSaveAll     = @"TB_SaveAll";
static NSToolbarItemIdentifier const kTBClose       = @"TB_Close";
static NSToolbarItemIdentifier const kTBCloseAll    = @"TB_CloseAll";
static NSToolbarItemIdentifier const kTBPrint       = @"TB_Print";
static NSToolbarItemIdentifier const kTBCut         = @"TB_Cut";
static NSToolbarItemIdentifier const kTBCopy        = @"TB_Copy";
static NSToolbarItemIdentifier const kTBPaste       = @"TB_Paste";
static NSToolbarItemIdentifier const kTBUndo        = @"TB_Undo";
static NSToolbarItemIdentifier const kTBRedo        = @"TB_Redo";
static NSToolbarItemIdentifier const kTBFind        = @"TB_Find";
static NSToolbarItemIdentifier const kTBFindRep     = @"TB_FindRep";
static NSToolbarItemIdentifier const kTBZoomIn      = @"TB_ZoomIn";
static NSToolbarItemIdentifier const kTBZoomOut     = @"TB_ZoomOut";
static NSToolbarItemIdentifier const kTBWrap        = @"TB_Wrap";
static NSToolbarItemIdentifier const kTBAllChars    = @"TB_AllChars";
static NSToolbarItemIdentifier const kTBUDL         = @"TB_UDL";
static NSToolbarItemIdentifier const kTBDocMap      = @"TB_DocMap";
static NSToolbarItemIdentifier const kTBDocList     = @"TB_DocList";
static NSToolbarItemIdentifier const kTBFuncList    = @"TB_FuncList";
static NSToolbarItemIdentifier const kTBFileBrowser = @"TB_FileBrowser";
static NSToolbarItemIdentifier const kTBStartRecord = @"TB_StartRecord";
static NSToolbarItemIdentifier const kTBStopRecord  = @"TB_StopRecord";
static NSToolbarItemIdentifier const kTBPlayRecord  = @"TB_PlayRecord";
static NSToolbarItemIdentifier const kTBPlayRecordM = @"TB_PlayRecordM";
static NSToolbarItemIdentifier const kTBSep         = @"TB_Sep";
static NSToolbarItemIdentifier const kTBTabControls = @"TB_TabControls"; // +  ▾  × right-aligned
// Grouped toolbar items — each group becomes a single NSToolbarItem with tight icon packing
static NSToolbarItemIdentifier const kTBGroup1 = @"TB_G1"; // file ops
static NSToolbarItemIdentifier const kTBGroup2 = @"TB_G2"; // clipboard
static NSToolbarItemIdentifier const kTBGroup3 = @"TB_G3"; // undo/redo
static NSToolbarItemIdentifier const kTBGroup4 = @"TB_G4"; // find
static NSToolbarItemIdentifier const kTBGroup5 = @"TB_G5"; // zoom
static NSToolbarItemIdentifier const kTBGroup6 = @"TB_G6"; // view toggles
static NSToolbarItemIdentifier const kTBGroup7 = @"TB_G7"; // panels
static NSToolbarItemIdentifier const kTBGroup8 = @"TB_G8"; // macro

// Load a toolbar icon from Resources/icons/standard/toolbar/{fileName}.png.
static NSImage *nppToolbarIcon(NSString *fileName) {
    NSString *path = [[[NSBundle mainBundle] resourcePath]
        stringByAppendingPathComponent:
            [NSString stringWithFormat:@"icons/standard/toolbar/%@.png", fileName]];
    return [[NSImage alloc] initWithContentsOfFile:path];
}

// ── Compact flat toolbar button (16×16 pt, 1-px rounded hover border) ───────
// Mirrors NPP's TBSTYLE_FLAT + TB_SETBUTTONSIZE(16,16) + CDIS_HOT paintRoundRect.
@interface NppToolbarButton : NSButton {
    BOOL _hovering;
}
@end

@implementation NppToolbarButton

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setBordered:NO];
        [self setButtonType:NSButtonTypeMomentaryChange];
        [self setImageScaling:NSImageScaleProportionallyUpOrDown];
        NSTrackingArea *ta = [[NSTrackingArea alloc]
            initWithRect:NSZeroRect
                 options:(NSTrackingMouseEnteredAndExited |
                          NSTrackingActiveInActiveApp     |
                          NSTrackingInVisibleRect)
                   owner:self userInfo:nil];
        [self addTrackingArea:ta];
    }
    return self;
}

- (void)mouseEntered:(NSEvent *)event { _hovering = YES;  [self setNeedsDisplay:YES]; }
- (void)mouseExited:(NSEvent *)event  { _hovering = NO;   [self setNeedsDisplay:YES]; }

- (void)drawRect:(NSRect)dirtyRect {
    if (self.image) {
        [self.image drawInRect:NSInsetRect(self.bounds, 1, 1)
                      fromRect:NSZeroRect
                     operation:NSCompositingOperationSourceOver
                      fraction:1.0
                respectFlipped:YES
                         hints:nil];
    }
    if (_hovering) {
        [[NSColor colorWithWhite:0.25 alpha:0.85] set];
        NSBezierPath *path = [NSBezierPath
            bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5)
                              xRadius:2.0
                              yRadius:2.0];
        path.lineWidth = 1.0;
        [path stroke];
    }
}

@end

// ── Thin vertical | separator between toolbar groups ─────────────────────────
@interface NppSeparatorView : NSView @end
@implementation NppSeparatorView
- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor colorWithWhite:0.30 alpha:0.90] set];
    NSRect line = NSMakeRect(floor(NSMidX(self.bounds)) - 0.5, 3, 1, self.bounds.size.height - 6);
    NSRectFill(line);
}
@end

// Toolbar descriptor: {identifier, label, tooltip, icon-base-name, action-selector-string}
// icon-base-name maps to icons/light|dark/toolbar/filled/{name}_off.png
static NSArray<NSArray *> *toolbarDescriptors() {
    return @[
        // id              label          tooltip                       icon filename        action
        // filename → icons/standard/toolbar/{filename}.png
        @[kTBNew,         @"New",        @"New Tab",                  @"newFile",          @"newDocument:"],
        @[kTBOpen,        @"Open",       @"Open File",                @"openFile",         @"openDocument:"],
        @[kTBSave,        @"Save",       @"Save",                     @"saveFile",         @"saveDocument:"],
        @[kTBSaveAll,     @"Save All",   @"Save All",                 @"saveAll",          @"saveAllDocuments:"],
        @[kTBClose,       @"Close",      @"Close Tab",                @"closeFile",        @"closeCurrentTab:"],
        @[kTBCloseAll,    @"Close All",  @"Close All Tabs",           @"closeAll",         @"closeAllTabs:"],
        @[kTBPrint,       @"Print",      @"Print",                    @"print",            @"printDocument:"],
        @[kTBCut,         @"Cut",        @"Cut",                      @"cut",              @"cut:"],
        @[kTBCopy,        @"Copy",       @"Copy",                     @"copy",             @"copy:"],
        @[kTBPaste,       @"Paste",      @"Paste",                    @"paste",            @"paste:"],
        @[kTBUndo,        @"Undo",       @"Undo",                     @"undo",             @"undo:"],
        @[kTBRedo,        @"Redo",       @"Redo",                     @"redo",             @"redo:"],
        @[kTBFind,        @"Find",       @"Find",                     @"find",             @"showFindPanel:"],
        @[kTBFindRep,     @"Replace",    @"Find and Replace",         @"findReplace",      @"showReplacePanel:"],
        @[kTBZoomIn,      @"Zoom In",    @"Zoom In",                  @"zoomIn",           @"zoomIn:"],
        @[kTBZoomOut,     @"Zoom Out",   @"Zoom Out",                 @"zoomOut",          @"zoomOut:"],
        @[kTBWrap,        @"Word Wrap",  @"Toggle Word Wrap",         @"wrap",             @"toggleWordWrap:"],
        @[kTBAllChars,    @"All Chars",  @"Show All Characters",      @"allChars",         @"toggleShowAllChars:"],
        @[kTBUDL,         @"Language",   @"Define Your Language",     @"udl",              @"showDefineLanguage:"],
        @[kTBDocMap,      @"Doc Map",    @"Document Map",             @"docMap",           @"showDocumentMap:"],
        @[kTBDocList,     @"Doc List",   @"Document List",            @"docList",          @"showDocumentList:"],
        @[kTBFuncList,    @"Func List",  @"Function List",            @"funcList",         @"showFunctionList:"],
        @[kTBFileBrowser, @"Workspace",  @"Folder as Workspace",      @"fileBrowser",      @"showFolderAsWorkspace:"],
        @[kTBStartRecord, @"Record",     @"Start Recording",          @"startRecord",      @"startMacroRecording:"],
        @[kTBStopRecord,  @"Stop",       @"Stop Recording",           @"stopRecord",       @"stopMacroRecording:"],
        @[kTBPlayRecord,  @"Playback",   @"Run Macro",                @"playRecord",       @"runMacro:"],
        @[kTBPlayRecordM, @"Run ×N",     @"Run Macro Multiple Times", @"playRecord_m",     @"runMacroMultipleTimes:"],
    ];
}

// Maps group toolbar-item identifiers → ordered list of button identifiers within that group.
static NSDictionary<NSString *, NSArray *> *toolbarGroupMap(void) {
    return @{
        kTBGroup1: @[kTBNew, kTBOpen, kTBSave, kTBSaveAll, kTBClose, kTBCloseAll, kTBPrint],
        kTBGroup2: @[kTBCut, kTBCopy, kTBPaste],
        kTBGroup3: @[kTBUndo, kTBRedo],
        kTBGroup4: @[kTBFind, kTBFindRep],
        kTBGroup5: @[kTBZoomIn, kTBZoomOut],
        kTBGroup6: @[kTBWrap, kTBAllChars],
        kTBGroup7: @[kTBUDL, kTBDocMap, kTBDocList, kTBFuncList, kTBFileBrowser],
        kTBGroup8: @[kTBStartRecord, kTBStopRecord, kTBPlayRecord, kTBPlayRecordM],
    };
}

@interface MainWindowController ()
    <TabManagerDelegate, NSWindowDelegate,
     NSToolbarDelegate, FindReplacePanelDelegate, NSUserInterfaceValidations,
     NSSplitViewDelegate, IncrementalSearchBarDelegate,
     FolderTreePanelDelegate, GitPanelDelegate>
@end

@implementation MainWindowController {
    TabManager       *_tabManager;
    FindReplacePanel *_findPanel;
    NSView           *_statusBar;
    NSTextField      *_statusLeft;
    NSTextField      *_statusRight;
    NSTextField      *_gitBranchLabel;
    NSLayoutConstraint *_findPanelHeightConstraint;
    NSTimer          *_autoSaveTimer;

    // Side panel host
    NSSplitView       *_editorSplitView;
    SidePanelHost     *_sidePanelHost;
    DocumentListPanel *_docListPanel;
    ClipboardHistoryPanel *_clipboardPanel;
    FunctionListPanel     *_funcListPanel;
    DocumentMapPanel      *_docMapPanel;
    CommandPalettePanel   *_commandPalette;
    NSView                *_folderTreePanel;   // FolderTreePanel
    NSView                *_gitPanel;          // GitPanel

    // Second editor view — horizontal (top/bottom)
    NSSplitView   *_hSplitView;
    TabManager    *_subTabManagerH;
    NSView        *_subEditorContainerH;

    // Second editor view — vertical (left/right)
    NSSplitView   *_vSplitView;
    TabManager    *_subTabManagerV;
    NSView        *_subEditorContainerV;

    TabManager    *_activeTabManager;   // defaults to _tabManager

    // View state
    BOOL _showAllChars;
    BOOL _showIndentGuides;
    BOOL _showLineNumbers;

    // Scroll synchronization
    BOOL _syncVerticalScrolling;
    BOOL _syncHorizontalScrolling;

    // Incremental search bar
    IncrementalSearchBar *_incSearchBar;
    NSLayoutConstraint   *_incSearchBarHeightConstraint;

    // View display modes
    BOOL              _postItMode;
    NSWindowStyleMask _savedStyleMask;
    NSColor          *_savedBgColor;
    BOOL              _distractionFreeMode;
    BOOL              _savedToolbarVisible;
}

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 1024, 768)
                  styleMask:(NSWindowStyleMaskTitled |
                             NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable |
                             NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = @"Notepad++";
    window.minSize = NSMakeSize(480, 320);
    [window center];

    self = [super initWithWindow:window];
    if (self) {
        _showLineNumbers = [[NSUserDefaults standardUserDefaults] boolForKey:kPrefShowLineNumbers];
        window.delegate = self;
        [self buildToolbar];
        [self buildContentView];
        [self restoreWindowFrame];
        [[NSNotificationCenter defaultCenter]
            addObserver:self selector:@selector(editorCursorMoved:)
                   name:EditorViewCursorDidMoveNotification object:nil];
        [self rebuildRecentFilesMenu];
        _autoSaveTimer = [NSTimer scheduledTimerWithTimeInterval:10.0
                                                          target:self
                                                        selector:@selector(autoSaveTick:)
                                                        userInfo:nil
                                                         repeats:YES];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Active editor accessor

/// Returns the current editor in whichever view the user last interacted with.
- (EditorView *)currentEditor { return _activeTabManager.currentEditor; }

/// Returns the EditorView that owns the window's first responder, falling back to currentEditor.
- (EditorView *)focusedEditor {
    NSView *v = [self.window.firstResponder isKindOfClass:[NSView class]]
                ? (NSView *)self.window.firstResponder : nil;
    while (v) {
        if ([v isKindOfClass:[EditorView class]]) return (EditorView *)v;
        v = v.superview;
    }
    return [self currentEditor];
}

#pragma mark - Toolbar (NSToolbarDelegate)

- (void)buildToolbar {
    NSToolbar *tb = [[NSToolbar alloc] initWithIdentifier:@"NppToolbar"];
    tb.delegate = self;
    tb.allowsUserCustomization = NO;
    tb.displayMode = NSToolbarDisplayModeIconOnly;
    self.window.toolbar = tb;
    // Expanded style puts the toolbar in its own row below the title bar,
    // so items are always left-aligned (not scattered around a centered title).
    if (@available(macOS 11.0, *)) {
        self.window.toolbarStyle = NSWindowToolbarStyleExpanded;
    }
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)tb {
    return @[kTBGroup1, kTBSep,
             kTBGroup2, kTBSep,
             kTBGroup3, kTBSep,
             kTBGroup4, kTBSep,
             kTBGroup5, kTBSep,
             kTBGroup6, kTBSep,
             kTBGroup7, kTBSep,
             kTBGroup8,
             NSToolbarFlexibleSpaceItemIdentifier,
             kTBTabControls];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)tb {
    return [self toolbarDefaultItemIdentifiers:tb];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)tb
     itemForItemIdentifier:(NSToolbarItemIdentifier)ident
 willBeInsertedIntoToolbar:(BOOL)flag {
    // Dark-grey group separator
    if ([ident isEqualToString:kTBSep]) {
        NSToolbarItem *sep = [[NSToolbarItem alloc] initWithItemIdentifier:ident];
        NppSeparatorView *v = [[NppSeparatorView alloc] initWithFrame:NSMakeRect(0, 0, 8, 19)];
        sep.view    = v;
        sep.minSize = NSMakeSize(8, 19);
        sep.maxSize = NSMakeSize(8, 19);
        return sep;
    }

    if ([ident isEqualToString:kTBTabControls])
        return [self makeTabControlsToolbarItem];

    NSArray *idents = toolbarGroupMap()[ident];
    if (idents) return [self makeGroupToolbarItem:ident identifiers:idents];
    return nil;
}

// Pack a set of buttons into a single NSToolbarItem view with 1pt spacing.
- (NSToolbarItem *)makeGroupToolbarItem:(NSString *)ident identifiers:(NSArray *)idents {
    static const CGFloat kBtnSize = 19.0;
    static const CGFloat kSpacing =  1.0;
    NSInteger n = (NSInteger)idents.count;
    CGFloat totalW = n * kBtnSize + (n - 1) * kSpacing;

    NSMutableDictionary *descMap = [NSMutableDictionary dictionary];
    for (NSArray *desc in toolbarDescriptors()) descMap[desc[0]] = desc;

    NSView *groupView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, totalW, kBtnSize)];
    CGFloat x = 0;
    for (NSString *btnIdent in idents) {
        NSArray *desc = descMap[btnIdent];
        if (desc) {
            NSImage *img = nppToolbarIcon(desc[3]);
            if (!img) img = [NSImage imageWithSystemSymbolName:@"doc" accessibilityDescription:desc[1]];
            NppToolbarButton *btn = [[NppToolbarButton alloc]
                initWithFrame:NSMakeRect(x, 0, kBtnSize, kBtnSize)];
            btn.image   = img;
            btn.action  = NSSelectorFromString(desc[4]);
            btn.target  = self;
            btn.toolTip = desc[2];
            [groupView addSubview:btn];
        }
        x += kBtnSize + kSpacing;
    }

    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:ident];
    item.view    = groupView;
    item.minSize = NSMakeSize(totalW, kBtnSize);
    item.maxSize = NSMakeSize(totalW, kBtnSize);
    return item;
}

// Builds the right-aligned +  ▾  × tab-control group.
- (NSToolbarItem *)makeTabControlsToolbarItem {
    static const CGFloat kW = 20.0, kH = 19.0, kSpc = 1.0;
    CGFloat totalW = 3 * kW + 2 * kSpc;

    NSView *groupView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, totalW, kH)];

    struct { NSString *title; NSString *tip; SEL action; } btns[3] = {
        { @"+", @"New Tab",         @selector(_tabControlNew:)   },
        { @"▾", @"Tab List",        @selector(_tabControlList:)  },
        { @"×", @"Close Active Tab",@selector(_tabControlClose:) },
    };

    for (int i = 0; i < 3; i++) {
        CGFloat x = i * (kW + kSpc);
        NSButton *btn = [[NSButton alloc] initWithFrame:NSMakeRect(x, 0, kW, kH)];
        [btn setBordered:NO];
        btn.buttonType = NSButtonTypeMomentaryChange;
        btn.title      = btns[i].title;
        btn.font       = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        btn.toolTip    = btns[i].tip;
        btn.action     = btns[i].action;
        btn.target     = self;
        [groupView addSubview:btn];
    }

    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:kTBTabControls];
    item.view    = groupView;
    item.minSize = NSMakeSize(totalW, kH);
    item.maxSize = NSMakeSize(totalW, kH);
    return item;
}

// ── Tab-control toolbar actions ───────────────────────────────────────────────

- (void)_tabControlNew:(id)sender {
    [_activeTabManager addNewTab];
    [self.window makeFirstResponder:[_activeTabManager currentEditor].scintillaView];
}

- (void)_tabControlList:(id)sender {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    // Collect tabs from all three tab managers, prefixing group headers when
    // more than one manager has tabs.
    NSArray<TabManager *> *managers = @[_tabManager, _subTabManagerH, _subTabManagerV];
    NSArray<NSString *>   *labels   = @[@"Main", @"Bottom", @"Right"];

    BOOL multiGroup = NO;
    for (TabManager *tm in managers)
        if (tm.allEditors.count > 0) multiGroup = !multiGroup ? YES : (multiGroup = YES);
    // Only show group headers when more than one group has tabs
    NSUInteger groupsWithTabs = 0;
    for (TabManager *tm in managers) if (tm.allEditors.count) groupsWithTabs++;

    for (NSUInteger g = 0; g < managers.count; g++) {
        TabManager *tm = managers[g];
        if (!tm.allEditors.count) continue;
        if (groupsWithTabs > 1) {
            NSMenuItem *hdr = [[NSMenuItem alloc] initWithTitle:labels[g] action:nil keyEquivalent:@""];
            hdr.enabled = NO;
            [menu addItem:hdr];
        }
        for (EditorView *ed in tm.allEditors) {
            NSString *name = ed.displayName ?: @"Untitled";
            NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:name action:@selector(_tabControlListSelect:) keyEquivalent:@""];
            mi.target = self;
            mi.representedObject = @{ @"editor": ed, @"manager": tm };
            if (ed == tm.currentEditor) mi.state = NSControlStateValueOn;
            [menu addItem:mi];
        }
        if (groupsWithTabs > 1 && g < managers.count - 1)
            [menu addItem:[NSMenuItem separatorItem]];
    }

    // Pop up directly below the ▾ button
    NSButton *btn = (NSButton *)sender;
    NSPoint origin = NSMakePoint(0, -2);
    [menu popUpMenuPositioningItem:nil atLocation:origin inView:btn];
}

- (void)_tabControlListSelect:(NSMenuItem *)sender {
    NSDictionary *info  = sender.representedObject;
    TabManager   *tm    = info[@"manager"];
    EditorView   *ed    = info[@"editor"];
    NSArray      *all   = tm.allEditors;
    NSInteger     idx   = [all indexOfObject:ed];
    if (idx != NSNotFound) {
        _activeTabManager = tm;
        [tm selectTabAtIndex:idx];
        [self.window makeFirstResponder:ed.scintillaView];
    }
}

- (void)_tabControlClose:(id)sender {
    [_activeTabManager closeCurrentTab];
}

#pragma mark - Content View Layout

- (void)buildContentView {
    NSView *content = self.window.contentView;
    content.wantsLayer = YES;

    // ── Primary TabManager ─────────────────────────────────────────────────────
    _tabManager = [[TabManager alloc] init];
    _tabManager.delegate = self;
    _activeTabManager = _tabManager;   // primary is default active

    NppTabBar *primaryTabBar = _tabManager.tabBar;
    primaryTabBar.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *primaryContentView = _tabManager.contentView;
    primaryContentView.translatesAutoresizingMaskIntoConstraints = NO;

    // Primary container wraps tab bar + editor content
    NSView *primaryContainer = [[NSView alloc] init];
    primaryContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [primaryContainer addSubview:primaryTabBar];
    [primaryContainer addSubview:primaryContentView];
    [NSLayoutConstraint activateConstraints:@[
        [primaryTabBar.topAnchor constraintEqualToAnchor:primaryContainer.topAnchor],
        [primaryTabBar.leadingAnchor constraintEqualToAnchor:primaryContainer.leadingAnchor],
        [primaryTabBar.trailingAnchor constraintEqualToAnchor:primaryContainer.trailingAnchor],
        [primaryTabBar.heightAnchor constraintEqualToConstant:25],
        [primaryContentView.topAnchor constraintEqualToAnchor:primaryTabBar.bottomAnchor],
        [primaryContentView.leadingAnchor constraintEqualToAnchor:primaryContainer.leadingAnchor],
        [primaryContentView.trailingAnchor constraintEqualToAnchor:primaryContainer.trailingAnchor],
        [primaryContentView.bottomAnchor constraintEqualToAnchor:primaryContainer.bottomAnchor],
    ]];

    // ── Secondary TabManager (second view, starts collapsed) ──────────────────
    _subTabManagerH = [[TabManager alloc] init];
    _subTabManagerH.delegate = self;

    NppTabBar *subTabBar = _subTabManagerH.tabBar;
    subTabBar.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *subContentView = _subTabManagerH.contentView;
    subContentView.translatesAutoresizingMaskIntoConstraints = NO;

    _subEditorContainerH = [[NSView alloc] init];
    _subEditorContainerH.translatesAutoresizingMaskIntoConstraints = NO;
    [_subEditorContainerH addSubview:subTabBar];
    [_subEditorContainerH addSubview:subContentView];
    [NSLayoutConstraint activateConstraints:@[
        [subTabBar.topAnchor constraintEqualToAnchor:_subEditorContainerH.topAnchor],
        [subTabBar.leadingAnchor constraintEqualToAnchor:_subEditorContainerH.leadingAnchor],
        [subTabBar.trailingAnchor constraintEqualToAnchor:_subEditorContainerH.trailingAnchor],
        [subTabBar.heightAnchor constraintEqualToConstant:25],
        [subContentView.topAnchor constraintEqualToAnchor:subTabBar.bottomAnchor],
        [subContentView.leadingAnchor constraintEqualToAnchor:_subEditorContainerH.leadingAnchor],
        [subContentView.trailingAnchor constraintEqualToAnchor:_subEditorContainerH.trailingAnchor],
        [subContentView.bottomAnchor constraintEqualToAnchor:_subEditorContainerH.bottomAnchor],
    ]];

    // ── Secondary TabManager V (vertical/right view, starts collapsed) ─────────
    _subTabManagerV = [[TabManager alloc] init];
    _subTabManagerV.delegate = self;

    NppTabBar *subTabBarV = _subTabManagerV.tabBar;
    subTabBarV.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *subContentViewV = _subTabManagerV.contentView;
    subContentViewV.translatesAutoresizingMaskIntoConstraints = NO;

    _subEditorContainerV = [[NSView alloc] init];
    _subEditorContainerV.translatesAutoresizingMaskIntoConstraints = NO;
    [_subEditorContainerV addSubview:subTabBarV];
    [_subEditorContainerV addSubview:subContentViewV];
    [NSLayoutConstraint activateConstraints:@[
        [subTabBarV.topAnchor constraintEqualToAnchor:_subEditorContainerV.topAnchor],
        [subTabBarV.leadingAnchor constraintEqualToAnchor:_subEditorContainerV.leadingAnchor],
        [subTabBarV.trailingAnchor constraintEqualToAnchor:_subEditorContainerV.trailingAnchor],
        [subTabBarV.heightAnchor constraintEqualToConstant:25],
        [subContentViewV.topAnchor constraintEqualToAnchor:subTabBarV.bottomAnchor],
        [subContentViewV.leadingAnchor constraintEqualToAnchor:_subEditorContainerV.leadingAnchor],
        [subContentViewV.trailingAnchor constraintEqualToAnchor:_subEditorContainerV.trailingAnchor],
        [subContentViewV.bottomAnchor constraintEqualToAnchor:_subEditorContainerV.bottomAnchor],
    ]];

    // ── Left/right split between primary and vertical secondary ───────────────
    _vSplitView = [[NSSplitView alloc] init];
    _vSplitView.vertical = YES;   // left/right split
    _vSplitView.dividerStyle = NSSplitViewDividerStyleThin;
    _vSplitView.delegate = self;
    _vSplitView.translatesAutoresizingMaskIntoConstraints = NO;
    [_vSplitView addSubview:primaryContainer];
    [_vSplitView addSubview:_subEditorContainerV];
    [primaryContainer.widthAnchor constraintGreaterThanOrEqualToConstant:100].active = YES;
    [_subEditorContainerV.widthAnchor constraintGreaterThanOrEqualToConstant:100].active = YES;

    // ── Top/bottom split between _vSplitView and horizontal secondary ─────────
    _hSplitView = [[NSSplitView alloc] init];
    _hSplitView.vertical = NO;    // top/bottom split
    _hSplitView.dividerStyle = NSSplitViewDividerStyleThin;
    _hSplitView.delegate = self;
    _hSplitView.translatesAutoresizingMaskIntoConstraints = NO;
    [_hSplitView addSubview:_vSplitView];
    [_hSplitView addSubview:_subEditorContainerH];
    [_vSplitView.heightAnchor constraintGreaterThanOrEqualToConstant:100].active = YES;
    [_subEditorContainerH.heightAnchor constraintGreaterThanOrEqualToConstant:100].active = YES;

    // ── Incremental search bar ─────────────────────────────────────────────────
    _incSearchBar = [[IncrementalSearchBar alloc] initWithFrame:NSZeroRect];
    _incSearchBar.translatesAutoresizingMaskIntoConstraints = NO;
    _incSearchBar.hidden = YES;
    _incSearchBar.delegate = self;

    // ── Find panel ─────────────────────────────────────────────────────────────
    _findPanel = [[FindReplacePanel alloc] initWithFrame:NSZeroRect];
    _findPanel.translatesAutoresizingMaskIntoConstraints = NO;
    _findPanel.hidden = YES;
    _findPanel.delegate = self;

    // ── Status bar ─────────────────────────────────────────────────────────────
    _statusBar = [[NSView alloc] init];
    _statusBar.translatesAutoresizingMaskIntoConstraints = NO;
    _statusBar.wantsLayer = YES;
    _statusBar.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;

    NSBox *sep = [[NSBox alloc] init];
    sep.boxType = NSBoxSeparator;
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    [_statusBar addSubview:sep];

    _statusLeft  = [self makeStatusLabel:NSTextAlignmentLeft];
    _statusRight = [self makeStatusLabel:NSTextAlignmentRight];
    // Git branch label: right-aligned, muted gray, before _statusRight
    _gitBranchLabel = [self makeStatusLabel:NSTextAlignmentRight];
    _gitBranchLabel.textColor = [NSColor secondaryLabelColor];
    [_statusBar addSubview:_statusLeft];
    [_statusBar addSubview:_statusRight];
    [_statusBar addSubview:_gitBranchLabel];

    [NSLayoutConstraint activateConstraints:@[
        [sep.topAnchor constraintEqualToAnchor:_statusBar.topAnchor],
        [sep.leadingAnchor constraintEqualToAnchor:_statusBar.leadingAnchor],
        [sep.trailingAnchor constraintEqualToAnchor:_statusBar.trailingAnchor],
        [sep.heightAnchor constraintEqualToConstant:1],
        [_statusLeft.leadingAnchor constraintEqualToAnchor:_statusBar.leadingAnchor constant:8],
        [_statusLeft.centerYAnchor constraintEqualToAnchor:_statusBar.centerYAnchor constant:1],
        [_statusLeft.trailingAnchor constraintLessThanOrEqualToAnchor:_statusBar.centerXAnchor],
        [_statusRight.trailingAnchor constraintEqualToAnchor:_statusBar.trailingAnchor constant:-8],
        [_statusRight.centerYAnchor constraintEqualToAnchor:_statusBar.centerYAnchor constant:1],
        [_statusRight.leadingAnchor constraintGreaterThanOrEqualToAnchor:_statusBar.centerXAnchor],
        [_gitBranchLabel.trailingAnchor constraintEqualToAnchor:_statusRight.leadingAnchor constant:-16],
        [_gitBranchLabel.centerYAnchor constraintEqualToAnchor:_statusBar.centerYAnchor constant:1],
    ]];

    // ── Horizontal (left/right) split: views | side panels ────────────────────
    _sidePanelHost = [[SidePanelHost alloc] init];
    _sidePanelHost.translatesAutoresizingMaskIntoConstraints = NO;

    _editorSplitView = [[NSSplitView alloc] init];
    _editorSplitView.vertical = YES;
    _editorSplitView.dividerStyle = NSSplitViewDividerStyleThin;
    _editorSplitView.delegate = self;
    _editorSplitView.translatesAutoresizingMaskIntoConstraints = NO;
    [_editorSplitView addSubview:_hSplitView];
    [_editorSplitView addSubview:_sidePanelHost];

    [_hSplitView.widthAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;
    [_sidePanelHost.widthAnchor constraintGreaterThanOrEqualToConstant:150].active = YES;

    for (NSView *v in @[_editorSplitView, _incSearchBar, _findPanel, _statusBar]) {
        [content addSubview:v];
    }

    _incSearchBarHeightConstraint = [_incSearchBar.heightAnchor constraintEqualToConstant:0];
    _findPanelHeightConstraint = [_findPanel.heightAnchor constraintEqualToConstant:0];

    [NSLayoutConstraint activateConstraints:@[
        // Split view fills from top to incremental search bar
        [_editorSplitView.topAnchor constraintEqualToAnchor:content.topAnchor],
        [_editorSplitView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [_editorSplitView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [_editorSplitView.bottomAnchor constraintEqualToAnchor:_incSearchBar.topAnchor],

        // Incremental search bar (sits between editor and find panel)
        [_incSearchBar.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [_incSearchBar.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        _incSearchBarHeightConstraint,
        [_incSearchBar.bottomAnchor constraintEqualToAnchor:_findPanel.topAnchor],

        // Find panel
        [_findPanel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [_findPanel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        _findPanelHeightConstraint,

        // Status bar at bottom
        [_statusBar.topAnchor constraintEqualToAnchor:_findPanel.bottomAnchor],
        [_statusBar.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [_statusBar.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [_statusBar.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [_statusBar.heightAnchor constraintEqualToConstant:22],
    ]];

    // Collapse secondary views and side panel initially
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_vSplitView   setPosition:MAX(NSWidth(self->_vSplitView.frame),   9999) ofDividerAtIndex:0];
        [self->_hSplitView   setPosition:MAX(NSHeight(self->_hSplitView.frame),  9999) ofDividerAtIndex:0];
        [self->_editorSplitView setPosition:MAX(NSWidth(self->_editorSplitView.frame), 9999) ofDividerAtIndex:0];
    });

    // Restore previous session; open an untitled tab only on first launch
    if (![self restoreLastSession]) [_tabManager addNewTab];
    [self rebuildMacroMenu];
    [self updateStatusBar];

    // Accept file drag-and-drop onto the primary editor area
    __weak typeof(self) weakSelf = self;
    ((NppDropView *)_tabManager.contentView).dropHandler = ^(NSArray<NSString *> *paths) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        for (NSString *path in paths) {
            [strongSelf->_tabManager openFileAtPath:path];
            [strongSelf addToRecentFiles:path];
        }
        [strongSelf updateTitle];
    };
}

- (NSTextField *)makeStatusLabel:(NSTextAlignment)align {
    NSTextField *f = [[NSTextField alloc] init];
    f.translatesAutoresizingMaskIntoConstraints = NO;
    f.editable = NO; f.bordered = NO; f.drawsBackground = NO;
    f.textColor = [NSColor secondaryLabelColor];
    f.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
    f.alignment = align;
    return f;
}

#pragma mark - Session

/// Save session to ~/.notepad++/session.plist.
/// Untitled modified tabs are written to ~/.notepad++/backup/ automatically.
- (void)saveSession {
    ensureNppDirs();
    NSString *backupDir = nppBackupDir();

    // Persist ALL open tabs so they reopen on next launch.
    // External files: record their path only (no backup — they live on disk).
    // Untitled tabs: back up content to ~/.notepad++/backup/ (auto-save only for these).
    NSMutableArray *tabs = [NSMutableArray array];
    for (EditorView *ed in _tabManager.allEditors) {
        NSMutableDictionary *info = [NSMutableDictionary dictionary];

        if (!ed.filePath) {
            // Untitled tab — only worth restoring if it has content
            if (!ed.isModified) continue;
            NSString *backup = [ed saveBackupToDirectory:backupDir];
            if (backup) info[@"backupFilePath"] = backup;
            info[@"untitledIndex"] = @(ed.untitledIndex);
        } else {
            // External file — just record the path; reopen from disk on restore
            info[@"filePath"] = ed.filePath;
        }

        if (ed.currentLanguage.length) info[@"language"] = ed.currentLanguage;
        info[@"cursorLine"] = @(ed.cursorLine);
        [tabs addObject:info];
    }

    NSDictionary *session = @{
        @"tabs":          tabs,
        @"selectedIndex": @(_tabManager.tabBar.selectedIndex)
    };
    [session writeToFile:nppSessionPath() atomically:YES];
}

/// Restore session from ~/.notepad++/session.plist.
/// Returns YES if at least one tab was restored.
- (BOOL)restoreLastSession {
    NSDictionary *session = [NSDictionary dictionaryWithContentsOfFile:nppSessionPath()];
    NSArray<NSDictionary *> *tabs = session[@"tabs"];
    if (!tabs.count) return NO;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSInteger opened = 0;

    for (NSDictionary *info in tabs) {
        NSString *filePath   = info[@"filePath"];
        NSString *backupPath = info[@"backupFilePath"];
        NSString *lang       = info[@"language"];

        // Prefer backup (more recent snapshot) if it exists
        NSString *loadPath   = nil;
        BOOL      fromBackup = NO;
        if (backupPath && [fm fileExistsAtPath:backupPath]) {
            loadPath = backupPath; fromBackup = YES;
        } else if (filePath && [fm fileExistsAtPath:filePath]) {
            loadPath = filePath;
        }
        if (!loadPath) continue;

        // Use addNewTab so we can configure the editor directly
        EditorView *ed = [_tabManager addNewTab];
        NSError *err;
        if (![ed loadFileAtPath:loadPath error:&err]) { [_tabManager closeEditor:ed]; continue; }

        if (fromBackup) {
            // Restore untitled index so tab name and future backup filename match
            NSInteger savedIndex = [info[@"untitledIndex"] integerValue];
            if (savedIndex > 0) [ed restoreUntitledIndex:savedIndex];
            // Point filePath back to original (nil for untitled) and mark modified
            ed.filePath = filePath; // nil for untitled — custom setter handles presenter
            ed.backupFilePath = backupPath;
            [ed markAsModified];
        }
        if (lang.length) [ed setLanguage:lang];
        [_tabManager refreshCurrentTabTitle];
        opened++;
    }

    if (opened == 0) return NO;

    NSInteger sel = [session[@"selectedIndex"] integerValue];
    if (sel < (NSInteger)_tabManager.allEditors.count)
        [_tabManager selectTabAtIndex:sel];
    return YES;
}

#pragma mark - Session Load/Save (user-triggered)

static NSString *nppMacrosPath(void) {
    return [nppConfigDir() stringByAppendingPathComponent:@"macros.plist"];
}

- (void)loadSessionFromPath:(NSString *)path {
    NSDictionary *session = [NSDictionary dictionaryWithContentsOfFile:path];
    NSArray<NSDictionary *> *tabs = session[@"tabs"];
    if (!tabs.count) {
        NSAlert *a = [[NSAlert alloc] init];
        a.messageText = @"Empty Session";
        a.informativeText = @"The selected session file contains no tabs.";
        [a runModal];
        return;
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSDictionary *info in tabs) {
        NSString *filePath = info[@"filePath"];
        if (filePath && [fm fileExistsAtPath:filePath])
            [self openFileAtPath:filePath];
    }
}

- (void)saveSessionToPath:(NSString *)path {
    NSMutableArray *tabs = [NSMutableArray array];
    for (EditorView *ed in _tabManager.allEditors) {
        if (!ed.filePath) continue;
        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        info[@"filePath"] = ed.filePath;
        if (ed.currentLanguage.length) info[@"language"] = ed.currentLanguage;
        info[@"cursorLine"] = @(ed.cursorLine);
        [tabs addObject:info];
    }
    NSDictionary *session = @{
        @"tabs": tabs,
        @"selectedIndex": @(_tabManager.tabBar.selectedIndex)
    };
    [session writeToFile:path atomically:YES];
}

- (void)loadSession:(id)sender {
    NSOpenPanel *p = [NSOpenPanel openPanel];
    p.title = @"Load Session";
    p.allowedFileTypes = @[@"plist"];
    if ([p runModal] != NSModalResponseOK) return;
    [self loadSessionFromPath:p.URL.path];
}

- (void)saveSessionAs:(id)sender {
    NSSavePanel *p = [NSSavePanel savePanel];
    p.title = @"Save Session";
    p.nameFieldStringValue = @"session.plist";
    p.allowedFileTypes = @[@"plist"];
    if ([p runModal] != NSModalResponseOK) return;
    [self saveSessionToPath:p.URL.path];
}

#pragma mark - Auto-save

/// Every 60 s: write all modified editors to ~/.notepad++/backup/ — never to the original file.
/// Mirrors NPP's background snapshot thread (NPPM_INTERNAL_SAVEBACKUP).
- (void)autoSaveTick:(NSTimer *)t {
    ensureNppDirs();
    NSString *backupDir = nppBackupDir();
    for (EditorView *ed in _tabManager.allEditors)
        if (ed.isModified && !ed.filePath) [ed saveBackupToDirectory:backupDir];
}

#pragma mark - Public

- (void)openFileAtPath:(NSString *)path {
    [_tabManager openFileAtPath:path];
    [self addToRecentFiles:path];
    [self updateTitle];
}

#pragma mark - Recent Files

- (void)addToRecentFiles:(NSString *)path {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSMutableArray *recents = [([ud stringArrayForKey:@"RecentFiles"] ?: @[]) mutableCopy];
    [recents removeObject:path];
    [recents insertObject:path atIndex:0];
    if (recents.count > 15) [recents removeLastObject];
    [ud setObject:recents forKey:@"RecentFiles"];
    [self rebuildRecentFilesMenu];
}

- (void)rebuildRecentFilesMenu {
    NSMenu *fileMenu = [[NSApp mainMenu].itemArray[1] submenu];
    NSMenuItem *recentItem = [fileMenu itemWithTag:1001];
    if (!recentItem) return;
    NSMenu *recentMenu = recentItem.submenu;
    [recentMenu removeAllItems];
    NSArray<NSString *> *recents = [[NSUserDefaults standardUserDefaults]
                                     stringArrayForKey:@"RecentFiles"] ?: @[];
    for (NSString *path in recents) {
        NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:path.lastPathComponent
                                                    action:@selector(openRecentFile:)
                                             keyEquivalent:@""];
        it.representedObject = path;
        it.toolTip = path;
        [recentMenu addItem:it];
    }
    if (recents.count) {
        [recentMenu addItem:[NSMenuItem separatorItem]];
        [recentMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Clear Recent Files"
                                                       action:@selector(clearRecentFiles:)
                                                keyEquivalent:@""]];
    }
}

- (void)openRecentFile:(id)sender {
    NSString *path = [sender representedObject];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSAlert *a = [[NSAlert alloc] init];
        a.messageText = @"File not found";
        a.informativeText = path;
        [a runModal];
        return;
    }
    [_tabManager openFileAtPath:path];
    [self addToRecentFiles:path]; // move to top
    [self updateTitle];
}

- (void)clearRecentFiles:(id)sender {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"RecentFiles"];
    [self rebuildRecentFilesMenu];
}

#pragma mark - File menu actions

- (void)newDocument:(id)sender {
    [_tabManager addNewTab];
    [self updateTitle];
}

- (void)openDocument:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = YES;
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    [panel beginWithCompletionHandler:^(NSModalResponse r) {
        if (r == NSModalResponseOK)
            for (NSURL *u in panel.URLs) {
                [self->_tabManager openFileAtPath:u.path];
                [self addToRecentFiles:u.path];
            }
        [self updateTitle];
    }];
}

- (void)saveDocument:(id)sender {
    EditorView *ed = [self currentEditor];
    if (!ed) return;
    if (!ed.filePath) { [self saveDocumentAs:sender]; return; }
    NSError *err;
    if (![ed saveError:&err]) [[NSAlert alertWithError:err] runModal];
    [self refreshCurrentTab];
}

- (void)saveDocumentAs:(id)sender {
    EditorView *ed = [self currentEditor];
    if (!ed) return;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = ed.displayName;
    [panel beginWithCompletionHandler:^(NSModalResponse r) {
        if (r == NSModalResponseOK) {
            NSError *err;
            if (![ed saveToPath:panel.URL.path error:&err])
                [[NSAlert alertWithError:err] runModal];
            [self refreshCurrentTab];
        }
    }];
}

- (void)saveAllDocuments:(id)sender {
    NSMutableArray *allEditors = [NSMutableArray arrayWithArray:_tabManager.allEditors];
    [allEditors addObjectsFromArray:_subTabManagerH.allEditors];
    [allEditors addObjectsFromArray:_subTabManagerV.allEditors];
    for (EditorView *ed in allEditors) {
        if (!ed.filePath) continue;
        NSError *err;
        [ed saveError:&err];
    }
    [self refreshCurrentTab];
}

- (void)closeCurrentTab:(id)sender {
    NSInteger sel = _activeTabManager.tabBar.selectedIndex;
    if (sel >= 0 && [_activeTabManager.tabBar isTabPinnedAtIndex:sel]) return;
    [_activeTabManager closeCurrentTab];
    [self updateTitle];
}

- (void)closeAllTabs:(id)sender {
    for (EditorView *ed in _tabManager.allEditors.copy)
        [_tabManager closeEditor:ed];
}

- (void)printDocument:(id)sender {
    EditorView *ed = [self currentEditor];
    if (!ed) return;
    NSPrintOperation *op = [NSPrintOperation printOperationWithView:ed.scintillaView];
    [op runOperation];
}

#pragma mark - Edit / clipboard actions forwarded to first responder

// Cut/Copy/Paste/Undo/Redo/SelectAll are handled by the responder chain (ScintillaView).
// We just need to make sure the toolbar buttons reach the first responder.

- (void)cut:(id)sender   { [[NSApp keyWindow].firstResponder tryToPerform:@selector(cut:)   with:sender]; }
- (void)copy:(id)sender  { [[NSApp keyWindow].firstResponder tryToPerform:@selector(copy:)  with:sender]; }
- (void)paste:(id)sender { [[NSApp keyWindow].firstResponder tryToPerform:@selector(paste:) with:sender]; }
- (void)undo:(id)sender  { [[NSApp keyWindow].firstResponder tryToPerform:@selector(undo:)  with:sender]; }
- (void)redo:(id)sender  { [[NSApp keyWindow].firstResponder tryToPerform:@selector(redo:)  with:sender]; }

- (void)indentSelection:(id)sender {
    [[[self currentEditor] scintillaView] message:SCI_TAB];
}
- (void)unindentSelection:(id)sender {
    [[[self currentEditor] scintillaView] message:SCI_BACKTAB];
}
- (void)toggleLineComment:(id)sender   { [[self currentEditor] toggleLineComment:sender]; }
- (void)toggleBlockComment:(id)sender  { [[self currentEditor] toggleBlockComment:sender]; }

#pragma mark - Line operation actions

- (void)duplicateLine:(id)sender  { [[self currentEditor] duplicateLine:sender]; }
- (void)deleteLine:(id)sender     { [[self currentEditor] deleteLine:sender]; }
- (void)moveLineUp:(id)sender     { [[self currentEditor] moveLineUp:sender]; }
- (void)moveLineDown:(id)sender   { [[self currentEditor] moveLineDown:sender]; }
- (void)toggleOverwriteMode:(id)sender {
    [[self currentEditor] toggleOverwriteMode];
    [self updateStatusBar];
}

#pragma mark - Folding actions

- (void)foldAll:(id)sender          { [[self currentEditor] foldAll:sender]; }
- (void)unfoldAll:(id)sender        { [[self currentEditor] unfoldAll:sender]; }
- (void)foldCurrentLevel:(id)sender { [[self currentEditor] foldCurrentLevel:sender]; }

#pragma mark - Bookmark actions

- (void)toggleBookmark:(id)sender    { [[self currentEditor] toggleBookmark:sender]; }
- (void)nextBookmark:(id)sender      { [[self currentEditor] nextBookmark:sender]; }
- (void)previousBookmark:(id)sender  { [[self currentEditor] previousBookmark:sender]; }
- (void)clearAllBookmarks:(id)sender { [[self currentEditor] clearAllBookmarks:sender]; }

#pragma mark - Macro actions

- (void)toggleMacroRecording:(id)sender {
    EditorView *ed = [self currentEditor];
    if (!ed) return;
    if (ed.isRecordingMacro) [ed stopMacroRecording];
    else                     [ed startMacroRecording];
}

- (void)startMacroRecording:(id)sender {
    [[self currentEditor] startMacroRecording];
}

- (void)stopMacroRecording:(id)sender {
    [[self currentEditor] stopMacroRecording];
}

- (void)runMacro:(id)sender {
    [[self currentEditor] runMacro];
}

- (void)runMacroMultipleTimes:(id)sender {
    EditorView *ed = [self currentEditor];
    if (!ed) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Run Macro Multiple Times";
    [alert addButtonWithTitle:@"Run"];
    [alert addButtonWithTitle:@"Cancel"];
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 80, 22)];
    input.placeholderString = @"Times";
    input.integerValue = 1;
    alert.accessoryView = input;
    [alert.window makeFirstResponder:input];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSInteger times = MAX(1, input.integerValue);
        for (NSInteger i = 0; i < times; i++) [ed runMacro];
    }
}

- (void)saveCurrentMacro:(id)sender {
    EditorView *ed = [self currentEditor];
    NSArray *actions = ed.macroActions;
    if (!actions.count) {
        NSAlert *a = [[NSAlert alloc] init];
        a.messageText = @"No Macro Recorded";
        a.informativeText = @"Record a macro first using Start Recording.";
        [a runModal];
        return;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Save Current Recorded Macro";
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Cancel"];
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 22)];
    input.placeholderString = @"Macro name";
    alert.accessoryView = input;
    [alert.window makeFirstResponder:input];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSString *name = [input.stringValue stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!name.length) return;

    ensureNppDirs();
    NSMutableDictionary *macros = [([NSDictionary dictionaryWithContentsOfFile:nppMacrosPath()]
                                    ?: @{}) mutableCopy];
    macros[name] = actions;
    [macros writeToFile:nppMacrosPath() atomically:YES];
    [self rebuildMacroMenu];
}

- (void)runSavedMacro:(NSMenuItem *)sender {
    NSArray<NSDictionary *> *actions = sender.representedObject;
    EditorView *ed = [self currentEditor];
    if (!ed || !actions.count) return;
    [ed runMacroActions:actions];
}

- (void)rebuildMacroMenu {
    NSMenuItem *macroItem = [[NSApp mainMenu] itemWithTitle:@"Macro"];
    NSMenu *macroMenu = macroItem.submenu;
    // Saved macros appear after the separator tagged 9901
    NSMenuItem *sep = [macroMenu itemWithTag:9901];
    if (!sep) return;
    NSInteger sepIdx = [macroMenu indexOfItem:sep];
    while (macroMenu.numberOfItems > sepIdx + 1)
        [macroMenu removeItemAtIndex:(NSInteger)macroMenu.numberOfItems - 1];

    NSDictionary *macros = [NSDictionary dictionaryWithContentsOfFile:nppMacrosPath()];
    for (NSString *name in [[macros allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:name
                                                      action:@selector(runSavedMacro:)
                                               keyEquivalent:@""];
        item.representedObject = macros[name];
        [macroMenu addItem:item];
    }
}

- (void)trimTrailingSpaceAndSave:(id)sender {
    for (EditorView *ed in _tabManager.allEditors) {
        [ed trimTrailingWhitespace:sender];
        if (ed.filePath && ed.isModified) {
            NSError *err;
            [ed saveError:&err];
        }
    }
}

#pragma mark - Panel placeholder actions

- (void)showDefineLanguage:(id)sender {
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = @"User Defined Language";
    a.informativeText = @"The UDL editor is not yet implemented.";
    [a runModal];
}

#pragma mark - Side panel show/hide

- (void)_setPanelVisible:(NSView *)panel title:(NSString *)title show:(BOOL)show {
    if (show) {
        [_sidePanelHost showPanel:panel withTitle:title];
        if ([_editorSplitView isSubviewCollapsed:_sidePanelHost]) {
            CGFloat w = NSWidth(_editorSplitView.frame);
            [_editorSplitView setPosition:MAX(200, w - 280) ofDividerAtIndex:0];
        }
    } else {
        [_sidePanelHost hidePanel:panel];
        if (!_sidePanelHost.hasVisiblePanels)
            [_editorSplitView setPosition:NSWidth(_editorSplitView.frame)
                         ofDividerAtIndex:0];
    }
}

- (void)showDocumentList:(id)sender {
    if (!_docListPanel)
        _docListPanel = [[DocumentListPanel alloc] initWithTabManager:_tabManager];
    BOOL open = [_sidePanelHost hasPanel:_docListPanel];
    if (!open) [_docListPanel reloadData];
    [self _setPanelVisible:_docListPanel title:@"Document List" show:!open];
}

- (void)showClipboardHistory:(id)sender {
    if (!_clipboardPanel) _clipboardPanel = [[ClipboardHistoryPanel alloc] init];
    BOOL open = [_sidePanelHost hasPanel:_clipboardPanel];
    if (!open) [_clipboardPanel startMonitoring];
    else       [_clipboardPanel stopMonitoring];
    [self _setPanelVisible:_clipboardPanel title:@"Clipboard History" show:!open];
}

- (void)showCommandPalette:(id)sender {
    if (!_commandPalette) _commandPalette = [[CommandPalettePanel alloc] init];
    if (_commandPalette.isVisible) {
        [_commandPalette orderOut:nil];
    } else {
        [_commandPalette showOverWindow:self.window];
    }
}

- (void)showDocumentMap:(id)sender {
    if (!_docMapPanel) _docMapPanel = [[DocumentMapPanel alloc] init];
    BOOL open = [_sidePanelHost hasPanel:_docMapPanel];
    if (!open) [_docMapPanel setTrackedEditor:[self currentEditor]];
    [self _setPanelVisible:_docMapPanel title:@"Document Map" show:!open];
}

- (void)showFunctionList:(id)sender {
    if (!_funcListPanel) _funcListPanel = [[FunctionListPanel alloc] init];
    BOOL open = [_sidePanelHost hasPanel:_funcListPanel];
    if (!open) [_funcListPanel loadEditor:[self currentEditor]];
    [self _setPanelVisible:_funcListPanel title:@"Function List" show:!open];
}

- (void)showFolderAsWorkspace:(id)sender {
    // Phase 2 stub — superseded by showFolderTreePanel:
    [self showFolderTreePanel:sender];
}

- (void)showFolderTreePanel:(id)sender {
    if (!_folderTreePanel) {
        FolderTreePanel *ftp = [[FolderTreePanel alloc] init];
        ftp.delegate = self;
        _folderTreePanel = ftp;
    }
    BOOL open = [_sidePanelHost hasPanel:_folderTreePanel];
    if (!open) {
        NSString *path = [self currentEditor].filePath;
        [(FolderTreePanel *)_folderTreePanel setActiveFileURL:
            path ? [NSURL fileURLWithPath:path] : [NSURL fileURLWithPath:NSHomeDirectory()]];
    }
    [self _setPanelVisible:_folderTreePanel title:@"Folder Tree" show:!open];
}

- (void)showGitPanel:(id)sender {
    if (!_gitPanel) {
        GitPanel *gp = [[GitPanel alloc] init];
        gp.delegate = self;
        _gitPanel = gp;
    }
    BOOL open = [_sidePanelHost hasPanel:_gitPanel];
    if (!open) [self _updateGitPanelForPath:[self currentEditor].filePath];
    [self _setPanelVisible:_gitPanel title:@"Git" show:!open];
}

- (void)_updateGitPanelForPath:(NSString *)filePath {
    if (!_gitPanel) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        // Try file path first, fall back to working directory
        NSString *root = nil;
        if (filePath.length) root = [GitHelper gitRootForPath:filePath];
        if (!root) root = [GitHelper gitRootForPath:
                           [NSFileManager defaultManager].currentDirectoryPath];
        dispatch_async(dispatch_get_main_queue(), ^{
            [(GitPanel *)self->_gitPanel setRepoRoot:root];
            [(GitPanel *)self->_gitPanel refresh];
        });
    });
}

- (void)toggleSpellCheck:(id)sender {
    EditorView *ed = [self currentEditor];
    ed.spellCheckEnabled = !ed.spellCheckEnabled;
}

- (void)_updateGitBranch:(NSString *)filePath {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *root   = filePath ? [GitHelper gitRootForPath:filePath] : nil;
        NSString *branch = root ? [GitHelper currentBranchAtRoot:root] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_gitBranchLabel.stringValue =
                branch ? [@"\u2387 " stringByAppendingString:branch] : @"";
        });
    });
}

- (void)showProjectPanel1:(id)sender {
    // Phase 2 stub
}

- (void)showProjectPanel2:(id)sender {
    // Phase 2 stub
}

- (void)showProjectPanel3:(id)sender {
    // Phase 2 stub
}

- (void)_ensureHorizontalViewVisible {
    if ([_hSplitView isSubviewCollapsed:_subEditorContainerH]) {
        CGFloat h = NSHeight(_hSplitView.frame);
        [_hSplitView setPosition:MAX(100, h / 2.0) ofDividerAtIndex:0];
    }
}

- (void)_ensureVerticalViewVisible {
    if ([_vSplitView isSubviewCollapsed:_subEditorContainerV]) {
        CGFloat w = NSWidth(_vSplitView.frame);
        [_vSplitView setPosition:MAX(100, w / 2.0) ofDividerAtIndex:0];
    }
}

// Move the same EditorView object (no content copy, no save prompt).
// Clicking the same direction again is a toggle: moves back to primary and collapses.
- (void)_moveEditor:(EditorView *)ed toVertical:(BOOL)vertical {
    if (!ed) return;
    TabManager *sub = vertical ? _subTabManagerV : _subTabManagerH;

    if (_activeTabManager == sub) {
        // Toggle: move back to primary and collapse the secondary pane
        [sub evictEditor:ed];
        [_tabManager adoptEditor:ed];
        if (vertical)
            [_vSplitView setPosition:MAX(NSWidth(_vSplitView.frame),   9999) ofDividerAtIndex:0];
        else
            [_hSplitView setPosition:MAX(NSHeight(_hSplitView.frame),  9999) ofDividerAtIndex:0];
    } else {
        // Move from current pane to secondary
        [_activeTabManager evictEditor:ed];
        // If primary became empty (last tab moved out), add a blank tab to keep it usable
        if (_activeTabManager == _tabManager && _tabManager.allEditors.count == 0)
            [_tabManager addNewTab];
        [sub adoptEditor:ed];
        if (vertical) [self _ensureVerticalViewVisible];
        else          [self _ensureHorizontalViewVisible];
    }
    [self updateTitle];
}

// Clone: open the same file in the other view (new EditorView, same document path).
// No save prompt — purely additive.
- (void)_cloneEditor:(EditorView *)ed toVertical:(BOOL)vertical {
    if (!ed) return;
    TabManager *sub = vertical ? _subTabManagerV : _subTabManagerH;
    if (ed.filePath) {
        [sub openFileAtPath:ed.filePath];
    } else {
        EditorView *newEd = [sub addNewTab];
        [newEd loadContentFromEditor:ed];
    }
    if (vertical) [self _ensureVerticalViewVisible];
    else          [self _ensureHorizontalViewVisible];
    [self updateTitle];
}

- (void)moveToOtherVerticalView:(id)sender {
    [self _moveEditor:[self currentEditor] toVertical:YES];
}

- (void)cloneToOtherVerticalView:(id)sender {
    [self _cloneEditor:[self currentEditor] toVertical:YES];
}

- (void)moveToOtherHorizontalView:(id)sender {
    [self _moveEditor:[self currentEditor] toVertical:NO];
}

- (void)cloneToOtherHorizontalView:(id)sender {
    [self _cloneEditor:[self currentEditor] toVertical:NO];
}

- (void)resetView:(id)sender {
    // Move every editor from V secondary back to primary
    for (EditorView *e in [_subTabManagerV.allEditors copy]) {
        [_subTabManagerV evictEditor:e];
        [_tabManager adoptEditor:e];
    }
    // Move every editor from H secondary back to primary
    for (EditorView *e in [_subTabManagerH.allEditors copy]) {
        [_subTabManagerH evictEditor:e];
        [_tabManager adoptEditor:e];
    }
    // Collapse both secondary panes
    [_vSplitView setPosition:MAX(NSWidth(_vSplitView.frame),   9999) ofDividerAtIndex:0];
    [_hSplitView setPosition:MAX(NSHeight(_hSplitView.frame),  9999) ofDividerAtIndex:0];
    [self updateTitle];
}

#pragma mark - Pin / Lock Tab

- (void)pinCurrentTab:(id)sender {
    NSInteger sel = _activeTabManager.tabBar.selectedIndex;
    if (sel < 0) return;
    BOOL currently = [_activeTabManager.tabBar isTabPinnedAtIndex:sel];
    [_activeTabManager.tabBar pinTabAtIndex:sel toggle:!currently];
}

// "Lock Tab" in View > Tab is an alias for pin.
- (void)lockCurrentTab:(id)sender { [self pinCurrentTab:sender]; }

#pragma mark - Tab Bar Wrap

- (void)toggleTabBarWrap:(id)sender {
    BOOL newWrap = !_tabManager.tabBar.wrapMode;
    _tabManager.tabBar.wrapMode     = newWrap;
    _subTabManagerH.tabBar.wrapMode = newWrap;
    _subTabManagerV.tabBar.wrapMode = newWrap;
}

#pragma mark - Sort Tabs

- (void)_sortTabsBy:(NSInteger)key ascending:(BOOL)asc {
    NSArray<EditorView *> *sorted = [_activeTabManager.allEditors
        sortedArrayUsingComparator:^NSComparisonResult(EditorView *a, EditorView *b) {
            NSString *ka, *kb;
            if (key == 0) {          // name
                ka = a.displayName;
                kb = b.displayName;
            } else if (key == 1) {   // extension / type
                ka = a.filePath.pathExtension ?: @"";
                kb = b.filePath.pathExtension ?: @"";
            } else {                 // full path
                ka = a.filePath ?: a.displayName;
                kb = b.filePath ?: b.displayName;
            }
            NSComparisonResult r = [ka compare:kb options:NSCaseInsensitiveSearch];
            return asc ? r : (NSComparisonResult)(-(NSInteger)r);
        }];
    [_activeTabManager reorderEditors:sorted];
}

- (void)sortTabsByFileNameAsc:(id)sender  { [self _sortTabsBy:0 ascending:YES];  }
- (void)sortTabsByFileNameDesc:(id)sender { [self _sortTabsBy:0 ascending:NO];   }
- (void)sortTabsByFileTypeAsc:(id)sender  { [self _sortTabsBy:1 ascending:YES];  }
- (void)sortTabsByFileTypeDesc:(id)sender { [self _sortTabsBy:1 ascending:NO];   }
- (void)sortTabsByFullPathAsc:(id)sender  { [self _sortTabsBy:2 ascending:YES];  }
- (void)sortTabsByFullPathDesc:(id)sender { [self _sortTabsBy:2 ascending:NO];   }

#pragma mark - Windows… dialog

- (void)showWindowsList:(id)sender {
    // Collect all editors from primary + both secondary tab managers.
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    NSArray<TabManager *> *managers = @[_tabManager, _subTabManagerH, _subTabManagerV];
    for (NSInteger mi = 0; mi < 3; mi++) {
        NSArray<EditorView *> *eds = managers[mi].allEditors;
        for (NSInteger ei = 0; ei < (NSInteger)eds.count; ei++) {
            EditorView *ed = eds[ei];
            [rows addObject:@{
                @"name":     ed.displayName,
                @"path":     ed.filePath ?: @"",
                @"modified": @(ed.isModified),
                @"mgr":      @(mi),
                @"idx":      @(ei),
            }];
        }
    }
    if (!rows.count) return;

    // Build a modal panel with a table.
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,540,300)
                                                styleMask:NSWindowStyleMaskTitled |
                                                          NSWindowStyleMaskClosable |
                                                          NSWindowStyleMaskResizable
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    panel.title = @"Windows";
    [panel center];

    NSView *content = panel.contentView;

    // Table
    NSTableView *tv = [[NSTableView alloc] init];
    tv.allowsMultipleSelection = YES;
    tv.usesAlternatingRowBackgroundColors = YES;
    tv.focusRingType = NSFocusRingTypeNone;
    tv.rowHeight = 17;

    NSTableColumn *col1 = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    col1.title = @"File Name";  col1.width = 160; col1.resizingMask = NSTableColumnUserResizingMask;
    NSTableColumn *col2 = [[NSTableColumn alloc] initWithIdentifier:@"ext"];
    col2.title = @"Type";       col2.width = 60;  col2.resizingMask = NSTableColumnUserResizingMask;
    NSTableColumn *col3 = [[NSTableColumn alloc] initWithIdentifier:@"path"];
    col3.title = @"Path";       col3.width = 260; col3.resizingMask = NSTableColumnUserResizingMask;
    [tv addTableColumn:col1]; [tv addTableColumn:col2]; [tv addTableColumn:col3];

    // Use a simple block-based datasource object.
    NSScrollView *sv = [[NSScrollView alloc] init];
    sv.translatesAutoresizingMaskIntoConstraints = NO;
    sv.hasVerticalScroller = YES;
    sv.documentView = tv;
    [content addSubview:sv];

    NSButton *activateBtn = [NSButton buttonWithTitle:@"Activate" target:nil action:nil];
    activateBtn.translatesAutoresizingMaskIntoConstraints = NO;
    activateBtn.keyEquivalent = @"\r";
    NSButton *closeBtn = [NSButton buttonWithTitle:@"Close" target:nil action:nil];
    closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    closeBtn.keyEquivalent = @"\033";
    [content addSubview:activateBtn];
    [content addSubview:closeBtn];

    [NSLayoutConstraint activateConstraints:@[
        [sv.topAnchor    constraintEqualToAnchor:content.topAnchor    constant:8],
        [sv.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:8],
        [sv.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-8],
        [sv.bottomAnchor  constraintEqualToAnchor:activateBtn.topAnchor constant:-8],

        [activateBtn.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-8],
        [activateBtn.bottomAnchor   constraintEqualToAnchor:content.bottomAnchor   constant:-12],
        [closeBtn.trailingAnchor    constraintEqualToAnchor:activateBtn.leadingAnchor constant:-8],
        [closeBtn.bottomAnchor      constraintEqualToAnchor:activateBtn.bottomAnchor],
    ]];

    // Datasource/delegate via a local helper block-object stored in associated objects.
    _NPPWindowsListHelper *helper = [[_NPPWindowsListHelper alloc] initWithRows:rows];
    helper.tableView = tv;
    tv.dataSource = helper;
    tv.delegate   = helper;
    [tv reloadData];
    if (rows.count) [tv selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    objc_setAssociatedObject(panel, "helper", helper, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // Activate button
    __weak typeof(self) wSelf = self;
    __weak NSPanel *wPanel = panel;
    __weak _NPPWindowsListHelper *wHelper = helper;
    activateBtn.target = helper;
    activateBtn.action = @selector(activatePressed:);
    helper.activateHandler = ^{
        NSInteger row = wHelper.tableView.selectedRow;
        if (row < 0 || row >= (NSInteger)rows.count) return;
        NSDictionary *entry = rows[row];
        NSInteger mi = [entry[@"mgr"] integerValue];
        NSInteger ei = [entry[@"idx"] integerValue];
        typeof(self) sSelf = wSelf;
        if (!sSelf) return;
        NSArray<TabManager *> *mgrs = @[sSelf->_tabManager, sSelf->_subTabManagerH, sSelf->_subTabManagerV];
        TabManager *tm = mgrs[mi];
        [tm selectTabAtIndex:ei];
        [NSApp stopModal];
        [wPanel orderOut:nil];
    };
    closeBtn.target = helper;
    closeBtn.action = @selector(closePressed:);
    helper.closeHandler = ^{
        [NSApp stopModal];
        [wPanel orderOut:nil];
    };

    // Double-click = activate
    tv.doubleAction = @selector(activatePressed:);
    tv.target = helper;

    [NSApp runModalForWindow:panel];
}

#pragma mark - UI Validation

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
    SEL action = item.action;
    EditorView *ed = [self currentEditor];
    BOOL recording = ed && ed.isRecordingMacro;

    // Dynamic menu title for toggle item
    if (action == @selector(toggleMacroRecording:)) {
        if ([(NSObject *)item respondsToSelector:@selector(setTitle:)])
            [(NSMenuItem *)item setTitle:recording ? @"Stop Recording" : @"Start Recording"];
        return ed != nil;
    }

    if (action == @selector(startMacroRecording:)) return ed && !recording;
    if (action == @selector(stopMacroRecording:))  return ed && recording;
    if (action == @selector(runMacro:))             return ed && !recording;
    if (action == @selector(runMacroMultipleTimes:)) return ed && !recording;
    if (action == @selector(saveCurrentMacro:))     return ed && !recording && ed.macroActions.count > 0;
    if (action == @selector(runSavedMacro:))        return ed && !recording;
    if (action == @selector(trimTrailingSpaceAndSave:)) return _tabManager.allEditors.count > 0;

    // Scroll sync checkmarks
    if (action == @selector(toggleSyncVerticalScrolling:)) {
        [(NSMenuItem *)item setState:_syncVerticalScrolling ? NSControlStateValueOn : NSControlStateValueOff];
        return YES;
    }
    if (action == @selector(toggleSyncHorizontalScrolling:)) {
        [(NSMenuItem *)item setState:_syncHorizontalScrolling ? NSControlStateValueOn : NSControlStateValueOff];
        return YES;
    }

    // Split-view mutual exclusion: V and H secondary views can't both be active
    BOOL vHasTabs = (_subTabManagerV.allEditors.count > 0);
    BOOL hHasTabs = (_subTabManagerH.allEditors.count > 0);

    if (action == @selector(moveToOtherVerticalView:)   ||
        action == @selector(cloneToOtherVerticalView:))
        return !hHasTabs;

    if (action == @selector(moveToOtherHorizontalView:)  ||
        action == @selector(cloneToOtherHorizontalView:))
        return !vHasTabs;

    if (action == @selector(resetView:))
        return vHasTabs || hHasTabs;

    // Post-It checkmark
    if (action == @selector(togglePostItMode:)) {
        [(NSMenuItem *)item setState:_postItMode ? NSControlStateValueOn : NSControlStateValueOff];
        return YES;
    }
    // Distraction Free checkmark
    if (action == @selector(toggleDistractionFreeMode:)) {
        [(NSMenuItem *)item setState:_distractionFreeMode ? NSControlStateValueOn : NSControlStateValueOff];
        return YES;
    }
    // Monitoring checkmark — only enabled for tabs with a real file
    if (action == @selector(toggleMonitoring:)) {
        BOOL hasFile = ed && ed.filePath.length > 0;
        [(NSMenuItem *)item setState:(hasFile && ed.monitoringMode) ? NSControlStateValueOn : NSControlStateValueOff];
        return hasFile;
    }
    if (action == @selector(showSummary:))       return ed != nil;
    if (action == @selector(focusOnAnotherView:)) return (vHasTabs || hHasTabs);
    if (action == @selector(setTextDirectionRTL:) ||
        action == @selector(setTextDirectionLTR:)) return ed != nil;

    // Pin / Lock Tab checkmark
    if (action == @selector(pinCurrentTab:) || action == @selector(lockCurrentTab:)) {
        NSInteger sel = _activeTabManager.tabBar.selectedIndex;
        BOOL pinned = (sel >= 0 && [_activeTabManager.tabBar isTabPinnedAtIndex:sel]);
        [(NSMenuItem *)item setState:pinned ? NSControlStateValueOn : NSControlStateValueOff];
        return sel >= 0;
    }

    // Tab Wrap checkmark
    if (action == @selector(toggleTabBarWrap:)) {
        [(NSMenuItem *)item setState:_tabManager.tabBar.wrapMode
            ? NSControlStateValueOn : NSControlStateValueOff];
        return YES;
    }

    // Sort/Windows enabled whenever there are tabs
    if (action == @selector(sortTabsByFileNameAsc:)  ||
        action == @selector(sortTabsByFileNameDesc:) ||
        action == @selector(sortTabsByFileTypeAsc:)  ||
        action == @selector(sortTabsByFileTypeDesc:) ||
        action == @selector(sortTabsByFullPathAsc:)  ||
        action == @selector(sortTabsByFullPathDesc:))
        return _activeTabManager.allEditors.count > 1;

    if (action == @selector(showWindowsList:))
        return _tabManager.allEditors.count > 0;

    if (action == @selector(closeAllButPinned:))
        return _activeTabManager.allEditors.count > 0;

    // Spell check checkmark
    if (action == @selector(toggleSpellCheck:)) {
        [(NSMenuItem *)item setState:ed.spellCheckEnabled ? NSControlStateValueOn : NSControlStateValueOff];
        return ed != nil;
    }

    return YES;
}

#pragma mark - Search menu actions

- (void)showFindPanel:(id)sender {
    [_findPanel openForFind];
    [self animateFindPanel];
}

- (void)showReplacePanel:(id)sender {
    [_findPanel openForReplace];
    [self animateFindPanel];
}

- (void)findNext:(id)sender {
    NSString *text = _findPanel.currentSearchText;
    if (!text.length) { [self showFindPanel:sender]; return; }
    EditorView *ed = [self currentEditor];
    if (!ed) return;
    if (![ed findNext:text matchCase:_findPanel.currentMatchCase
           wholeWord:_findPanel.currentWholeWord wrap:_findPanel.currentWrap]) NSBeep();
}

- (void)findPrevious:(id)sender {
    NSString *text = _findPanel.currentSearchText;
    if (!text.length) { [self showFindPanel:sender]; return; }
    EditorView *ed = [self currentEditor];
    if (!ed) return;
    if (![ed findPrev:text matchCase:_findPanel.currentMatchCase
           wholeWord:_findPanel.currentWholeWord wrap:_findPanel.currentWrap]) NSBeep();
}

// Find Volatile: same as Find Next/Prev but never wraps
- (void)findVolatileNext:(id)sender {
    NSString *text = _findPanel.currentSearchText;
    if (!text.length) return;
    EditorView *ed = [self currentEditor];
    if (!ed) return;
    if (![ed findNext:text matchCase:_findPanel.currentMatchCase
           wholeWord:_findPanel.currentWholeWord wrap:NO]) NSBeep();
}

- (void)findVolatilePrevious:(id)sender {
    NSString *text = _findPanel.currentSearchText;
    if (!text.length) return;
    EditorView *ed = [self currentEditor];
    if (!ed) return;
    if (![ed findPrev:text matchCase:_findPanel.currentMatchCase
           wholeWord:_findPanel.currentWholeWord wrap:NO]) NSBeep();
}

// ── Incremental Search ────────────────────────────────────────────────────────

- (void)showIncrementalSearch:(id)sender {
    if (_incSearchBar.hidden) {
        _incSearchBar.hidden = NO;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = 0.12;
            self->_incSearchBarHeightConstraint.animator.constant = _incSearchBar.preferredHeight;
        } completionHandler:^{
            [self->_incSearchBar activate];
        }];
    } else {
        [_incSearchBar activate];
    }
}

// ── IncrementalSearchBarDelegate ──────────────────────────────────────────────

- (void)incrementalSearchBar:(id)bar findText:(NSString *)text
                   matchCase:(BOOL)mc forward:(BOOL)fwd {
    EditorView *ed = [self currentEditor];
    if (!ed) return;
    if (!text.length) {
        [ed clearIncrementalSearchHighlights];
        [_incSearchBar setStatus:@"" found:YES];
        return;
    }
    [ed highlightAllMatches:text matchCase:mc];
    BOOL found = fwd
        ? [ed findNext:text matchCase:mc wholeWord:NO wrap:YES]
        : [ed findPrev:text matchCase:mc wholeWord:NO wrap:YES];
    NSString *status = found ? @"" : @"Not found";
    [_incSearchBar setStatus:status found:found];
}

- (void)incrementalSearchBarDidClose:(id)bar {
    EditorView *ed = [self currentEditor];
    [ed clearIncrementalSearchHighlights];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = 0.12;
        self->_incSearchBarHeightConstraint.animator.constant = 0;
    } completionHandler:^{
        self->_incSearchBar.hidden = YES;
    }];
    [self.window makeFirstResponder:ed.scintillaView];
}

// ── Change History ────────────────────────────────────────────────────────────

- (void)goToNextChange:(id)sender     { [[self currentEditor] goToNextChange:sender]; }
- (void)goToPreviousChange:(id)sender { [[self currentEditor] goToPreviousChange:sender]; }
- (void)clearAllChanges:(id)sender    { [[self currentEditor] clearAllChanges:sender]; }

- (void)goToLine:(id)sender {
    EditorView *ed = [self currentEditor];
    if (!ed) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Go to Line";
    [alert addButtonWithTitle:@"Go"];
    [alert addButtonWithTitle:@"Cancel"];
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0,0,160,22)];
    input.placeholderString = [NSString stringWithFormat:@"1 – %ld", (long)ed.lineCount];
    alert.accessoryView = input;
    [alert.window makeFirstResponder:input];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSInteger line = input.integerValue;
        if (line > 0) [ed goToLineNumber:line];
    }
}

#pragma mark - Edit: Case conversion

- (void)convertToUppercase:(id)sender         { [[self currentEditor] convertToUppercase:sender]; }
- (void)convertToLowercase:(id)sender         { [[self currentEditor] convertToLowercase:sender]; }
- (void)convertToProperCase:(id)sender        { [[self currentEditor] convertToProperCase:sender]; }
- (void)convertToProperCaseBlend:(id)sender   { [[self currentEditor] convertToProperCaseBlend:sender]; }
- (void)convertToSentenceCase:(id)sender      { [[self currentEditor] convertToSentenceCase:sender]; }
- (void)convertToSentenceCaseBlend:(id)sender { [[self currentEditor] convertToSentenceCaseBlend:sender]; }
- (void)convertToInvertedCase:(id)sender      { [[self currentEditor] convertToInvertedCase:sender]; }
- (void)convertToRandomCase:(id)sender        { [[self currentEditor] convertToRandomCase:sender]; }

#pragma mark - Edit: Sort / cleanup

- (void)sortLinesAscending:(id)sender          { [[self currentEditor] sortLinesAscending:sender]; }
- (void)sortLinesDescending:(id)sender         { [[self currentEditor] sortLinesDescending:sender]; }
- (void)sortLinesAscendingCI:(id)sender        { [[self currentEditor] sortLinesAscendingCI:sender]; }
- (void)sortLinesByLengthAsc:(id)sender        { [[self currentEditor] sortLinesByLengthAsc:sender]; }
- (void)sortLinesByLengthDesc:(id)sender       { [[self currentEditor] sortLinesByLengthDesc:sender]; }
- (void)sortLinesRandomly:(id)sender           { [[self currentEditor] sortLinesRandomly:sender]; }
- (void)sortLinesReverse:(id)sender            { [[self currentEditor] sortLinesReverse:sender]; }
- (void)sortLinesIntAsc:(id)sender             { [[self currentEditor] sortLinesIntAsc:sender]; }
- (void)sortLinesIntDesc:(id)sender            { [[self currentEditor] sortLinesIntDesc:sender]; }
- (void)sortLinesDecimalDotAsc:(id)sender      { [[self currentEditor] sortLinesDecimalDotAsc:sender]; }
- (void)sortLinesDecimalDotDesc:(id)sender     { [[self currentEditor] sortLinesDecimalDotDesc:sender]; }
- (void)sortLinesDecimalCommaAsc:(id)sender    { [[self currentEditor] sortLinesDecimalCommaAsc:sender]; }
- (void)sortLinesDecimalCommaDesc:(id)sender   { [[self currentEditor] sortLinesDecimalCommaDesc:sender]; }
- (void)removeDuplicateLines:(id)sender        { [[self currentEditor] removeDuplicateLines:sender]; }
- (void)removeConsecutiveDuplicateLines:(id)sender { [[self currentEditor] removeConsecutiveDuplicateLines:sender]; }
- (void)trimTrailingWhitespace:(id)sender      { [[self currentEditor] trimTrailingWhitespace:sender]; }
- (void)trimLeadingSpaces:(id)sender           { [[self currentEditor] trimLeadingSpaces:sender]; }
- (void)trimLeadingAndTrailingSpaces:(id)sender{ [[self currentEditor] trimLeadingAndTrailingSpaces:sender]; }
- (void)eolToSpace:(id)sender                  { [[self currentEditor] eolToSpace:sender]; }
- (void)removeBlankLines:(id)sender            { [[self currentEditor] removeBlankLines:sender]; }
- (void)mergeBlankLines:(id)sender             { [[self currentEditor] mergeBlankLines:sender]; }
- (void)spacesToTabsLeading:(id)sender         { [[self currentEditor] spacesToTabsLeading:sender]; }
- (void)spacesToTabsAll:(id)sender             { [[self currentEditor] spacesToTabsAll:sender]; }
- (void)tabsToSpaces:(id)sender                { [[self currentEditor] tabsToSpaces:sender]; }
- (void)joinLines:(id)sender                   { [[self currentEditor] joinLines:sender]; }

#pragma mark - Edit: Insert

- (void)insertBlankLineAbove:(id)sender { [[self currentEditor] insertBlankLineAbove:sender]; }
- (void)insertBlankLineBelow:(id)sender { [[self currentEditor] insertBlankLineBelow:sender]; }
- (void)insertDateTimeShort:(id)sender  { [[self currentEditor] insertDateTimeShort:sender]; }
- (void)insertDateTimeLong:(id)sender   { [[self currentEditor] insertDateTimeLong:sender]; }

#pragma mark - Edit: Copy to Clipboard

- (void)copyFullFilePath:(id)sender {
    EditorView *ed = [self currentEditor];
    if (!ed.filePath) return;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:ed.filePath forType:NSPasteboardTypeString];
}

- (void)copyFileName:(id)sender {
    EditorView *ed = [self currentEditor];
    NSString *path = ed.filePath;
    if (!path) return;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:path.lastPathComponent forType:NSPasteboardTypeString];
}

- (void)copyCurrentDirectoryPath:(id)sender {
    EditorView *ed = [self currentEditor];
    NSString *path = ed.filePath;
    if (!path) return;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:path.stringByDeletingLastPathComponent forType:NSPasteboardTypeString];
}

- (void)copyAllFileNames:(id)sender {
    NSMutableArray *names = [NSMutableArray array];
    for (EditorView *ed in _tabManager.allEditors)
        [names addObject:ed.filePath ? ed.filePath.lastPathComponent : @"new"];
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:[names componentsJoinedByString:@"\n"] forType:NSPasteboardTypeString];
}

- (void)copyAllFilePaths:(id)sender {
    NSMutableArray *paths = [NSMutableArray array];
    for (EditorView *ed in _tabManager.allEditors)
        if (ed.filePath) [paths addObject:ed.filePath];
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:[paths componentsJoinedByString:@"\n"] forType:NSPasteboardTypeString];
}

#pragma mark - Edit: Read-Only / Selection

- (void)toggleReadOnly:(id)sender          { [[self currentEditor] toggleReadOnly:sender]; }
- (void)clearReadOnlyFlag:(id)sender       { [[self currentEditor] clearReadOnlyFlag:sender]; }
- (void)goToMatchingBrace:(id)sender       { [[self currentEditor] goToMatchingBrace:sender]; }
- (void)selectAndFindNext:(id)sender       { [[self currentEditor] selectAndFindNext:sender]; }
- (void)selectAndFindPrevious:(id)sender   { [[self currentEditor] selectAndFindPrevious:sender]; }

- (void)toggleReadOnlyAttribute:(id)sender {
    EditorView *ed = [self currentEditor];
    if (!ed || !ed.filePath) return;
    NSString *path = ed.filePath;
    NSError *err;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&err];
    if (!attrs) return;
    NSUInteger perms = [[attrs objectForKey:NSFilePosixPermissions] unsignedShortValue];
    BOOL isReadOnly = !(perms & S_IWUSR);
    NSUInteger newPerms = isReadOnly ? (perms | S_IWUSR) : (perms & ~(S_IWUSR | S_IWGRP | S_IWOTH));
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @(newPerms)}
                                     ofItemAtPath:path error:nil];
}

// ── Multi-select (forwarded to current editor) ────────────────────────────────

- (void)beginEndSelect:(id)sender         { [[self currentEditor] beginEndSelect:sender]; }
- (void)beginEndSelectColumnMode:(id)sender { [[self currentEditor] beginEndSelectColumnMode:sender]; }
- (void)multiSelectAllInCurrentDocument:(id)sender   { [[self currentEditor] multiSelectAllInCurrentDocument:sender]; }
- (void)multiSelectNextInCurrentDocument:(id)sender  { [[self currentEditor] multiSelectNextInCurrentDocument:sender]; }
- (void)undoLatestMultiSelect:(id)sender             { [[self currentEditor] undoLatestMultiSelect:sender]; }
- (void)skipCurrentAndGoToNextMultiSelect:(id)sender { [[self currentEditor] skipCurrentAndGoToNextMultiSelect:sender]; }

// ── Split Lines ───────────────────────────────────────────────────────────────

- (void)splitLines:(id)sender { [[self currentEditor] splitLines:sender]; }

// ── Block Comment explicit add/remove ────────────────────────────────────────

- (void)addBlockComment:(id)sender    { [[self currentEditor] addBlockComment:sender]; }
- (void)removeBlockComment:(id)sender { [[self currentEditor] removeBlockComment:sender]; }

// ── Remove Unnecessary Blank and EOL ─────────────────────────────────────────

- (void)removeUnnecessaryBlankAndEOL:(id)sender { [[self currentEditor] removeUnnecessaryBlankAndEOL:sender]; }

// ── Paste Special ─────────────────────────────────────────────────────────────

- (void)copyBinaryContent:(id)sender  { [NSApp sendAction:@selector(copy:)  to:nil from:sender]; }
- (void)pasteBinaryContent:(id)sender { [NSApp sendAction:@selector(paste:) to:nil from:sender]; }

- (void)pasteHTMLContent:(id)sender {
    EditorView *ed = [self currentEditor];
    if (!ed) return;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSString *html = [pb stringForType:NSPasteboardTypeHTML];
    if (!html.length) { NSBeep(); return; }
    // Strip HTML tags
    NSError *regErr;
    NSRegularExpression *rx = [NSRegularExpression regularExpressionWithPattern:@"<[^>]+>"
                                                                         options:0 error:&regErr];
    NSString *plain = [rx stringByReplacingMatchesInString:html options:0
                                                     range:NSMakeRange(0, html.length)
                                              withTemplate:@""];
    plain = [plain stringByReplacingOccurrencesOfString:@"&lt;"   withString:@"<"];
    plain = [plain stringByReplacingOccurrencesOfString:@"&gt;"   withString:@">"];
    plain = [plain stringByReplacingOccurrencesOfString:@"&amp;"  withString:@"&"];
    plain = [plain stringByReplacingOccurrencesOfString:@"&nbsp;" withString:@" "];
    plain = [plain stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
    [ed.scintillaView message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)plain.UTF8String];
}

- (void)pasteRTFContent:(id)sender {
    EditorView *ed = [self currentEditor];
    if (!ed) return;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSData *rtfData = [pb dataForType:NSPasteboardTypeRTF];
    if (!rtfData.length) { NSBeep(); return; }
    NSAttributedString *attr = [[NSAttributedString alloc] initWithRTF:rtfData
                                                    documentAttributes:nil];
    NSString *plain = attr.string;
    if (!plain.length) { NSBeep(); return; }
    [ed.scintillaView message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)plain.UTF8String];
}

// ── Insert Date/Time (Custom Format) ─────────────────────────────────────────

- (void)insertDateTimeCustom:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Insert Date/Time";
    alert.informativeText = @"Enter an NSDateFormatter format string:";
    [alert addButtonWithTitle:@"Insert"];
    [alert addButtonWithTitle:@"Cancel"];
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 22)];
    input.stringValue = @"yyyy-MM-dd HH:mm:ss";
    alert.accessoryView = input;
    [alert.window makeFirstResponder:input];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSString *fmt = input.stringValue;
    if (!fmt.length) return;
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = fmt;
    NSString *dateStr = [df stringFromDate:[NSDate date]];
    EditorView *ed = [self currentEditor];
    if (!ed) return;
    [ed.scintillaView message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)dateStr.UTF8String];
}

#pragma mark - Edit: Bookmark line operations

- (void)cutBookmarkedLines:(id)sender      { [[self currentEditor] cutBookmarkedLines:sender]; }
- (void)copyBookmarkedLines:(id)sender     { [[self currentEditor] copyBookmarkedLines:sender]; }
- (void)removeBookmarkedLines:(id)sender   { [[self currentEditor] removeBookmarkedLines:sender]; }
- (void)removeNonBookmarkedLines:(id)sender{ [[self currentEditor] removeNonBookmarkedLines:sender]; }
- (void)inverseBookmark:(id)sender         { [[self currentEditor] inverseBookmark:sender]; }

#pragma mark - View: Whitespace / EOL symbols

- (void)showWhiteSpaceAndTab:(id)sender    { [[self currentEditor] showWhiteSpaceAndTab:sender]; }
- (void)showEndOfLine:(id)sender           { [[self currentEditor] showEndOfLine:sender]; }

#pragma mark - View: Fold levels

- (void)foldLevel1:(id)s   { [[self currentEditor] foldLevel1:s]; }
- (void)foldLevel2:(id)s   { [[self currentEditor] foldLevel2:s]; }
- (void)foldLevel3:(id)s   { [[self currentEditor] foldLevel3:s]; }
- (void)foldLevel4:(id)s   { [[self currentEditor] foldLevel4:s]; }
- (void)foldLevel5:(id)s   { [[self currentEditor] foldLevel5:s]; }
- (void)foldLevel6:(id)s   { [[self currentEditor] foldLevel6:s]; }
- (void)foldLevel7:(id)s   { [[self currentEditor] foldLevel7:s]; }
- (void)foldLevel8:(id)s   { [[self currentEditor] foldLevel8:s]; }
- (void)unfoldLevel1:(id)s { [[self currentEditor] unfoldLevel1:s]; }
- (void)unfoldLevel2:(id)s { [[self currentEditor] unfoldLevel2:s]; }
- (void)unfoldLevel3:(id)s { [[self currentEditor] unfoldLevel3:s]; }
- (void)unfoldLevel4:(id)s { [[self currentEditor] unfoldLevel4:s]; }
- (void)unfoldLevel5:(id)s { [[self currentEditor] unfoldLevel5:s]; }
- (void)unfoldLevel6:(id)s { [[self currentEditor] unfoldLevel6:s]; }
- (void)unfoldLevel7:(id)s { [[self currentEditor] unfoldLevel7:s]; }
- (void)unfoldLevel8:(id)s { [[self currentEditor] unfoldLevel8:s]; }
- (void)unfoldCurrentLevel:(id)sender { [[self currentEditor] unfoldCurrentLevel:sender]; }

#pragma mark - Window: Always on Top

- (void)toggleAlwaysOnTop:(id)sender {
    NSWindow *w = self.window;
    w.level = (w.level == NSFloatingWindowLevel) ? NSNormalWindowLevel : NSFloatingWindowLevel;
}

// ── Post-It mode ──────────────────────────────────────────────────────────────
// Borderless, always-on-top, movable by background — like a sticky note.

- (void)togglePostItMode:(id)sender {
    NSWindow *w = self.window;
    _postItMode = !_postItMode;

    if (_postItMode) {
        _savedStyleMask = w.styleMask;
        _savedBgColor   = w.backgroundColor;
        w.styleMask = NSWindowStyleMaskBorderless | NSWindowStyleMaskResizable;
        w.level = NSFloatingWindowLevel;
        w.backgroundColor = [NSColor colorWithRed:1.0 green:0.97 blue:0.75 alpha:0.95];
        w.opaque = NO;
        w.movableByWindowBackground = YES;
        w.hasShadow = YES;
    } else {
        w.styleMask = _savedStyleMask;
        w.level = NSNormalWindowLevel;
        w.backgroundColor = _savedBgColor ?: [NSColor windowBackgroundColor];
        w.opaque = YES;
        w.movableByWindowBackground = NO;
    }
}

// ── Distraction Free mode ─────────────────────────────────────────────────────
// Full screen + hide toolbar, status bar, tab bar.

- (void)toggleDistractionFreeMode:(id)sender {
    _distractionFreeMode = !_distractionFreeMode;
    NSWindow *w = self.window;
    BOOL isFullScreen = (w.styleMask & NSWindowStyleMaskFullScreen) != 0;

    if (_distractionFreeMode) {
        _savedToolbarVisible = w.toolbar.isVisible;
        [w.toolbar setVisible:NO];
        _statusBar.hidden = YES;
        _tabManager.tabBar.hidden = YES;
        if (!isFullScreen) [w toggleFullScreen:nil];
    } else {
        [w.toolbar setVisible:_savedToolbarVisible];
        _statusBar.hidden = NO;
        _tabManager.tabBar.hidden = NO;
        if (isFullScreen) [w toggleFullScreen:nil];
    }
}

// ── Summary ───────────────────────────────────────────────────────────────────

- (void)showSummary:(id)sender {
    EditorView *ed = [self currentEditor];
    if (!ed) return;
    NSString *text = ed.scintillaView.string ?: @"";

    NSInteger lines = ed.lineCount;
    NSInteger totalChars = (NSInteger)text.length;

    // Count chars without whitespace
    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSInteger charsNoSpace = 0;
    for (NSUInteger i = 0; i < text.length; i++) {
        if (![ws characterIsMember:[text characterAtIndex:i]]) charsNoSpace++;
    }

    // Count words
    NSArray *tokens = [text componentsSeparatedByCharactersInSet:ws];
    NSInteger words = 0;
    for (NSString *t in tokens) if (t.length > 0) words++;

    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = [NSString stringWithFormat:@"Summary — %@", ed.displayName];
    a.informativeText = [NSString stringWithFormat:
        @"Lines:                %ld\n"
         "Words:               %ld\n"
         "Characters (total):  %ld\n"
         "Characters (no spc): %ld",
        (long)lines, (long)words, (long)totalChars, (long)charsNoSpace];
    [a runModal];
}

// ── Focus on Another View ────────────────────────────────────────────────────

- (void)focusOnAnotherView:(id)sender {
    TabManager *candidates[] = { _subTabManagerV, _subTabManagerH, _tabManager };
    for (int i = 0; i < 3; i++) {
        TabManager *tm = candidates[i];
        if (tm != _activeTabManager && tm.allEditors.count > 0) {
            [self.window makeFirstResponder:tm.currentEditor.scintillaView];
            _activeTabManager = tm;
            return;
        }
    }
}

// ── Text Direction ────────────────────────────────────────────────────────────

- (void)setTextDirectionRTL:(id)sender { [[self currentEditor] setTextDirectionRTL:sender]; }
- (void)setTextDirectionLTR:(id)sender { [[self currentEditor] setTextDirectionLTR:sender]; }

// ── Monitoring (tail -f) ──────────────────────────────────────────────────────

- (void)toggleMonitoring:(id)sender {
    EditorView *ed = [self currentEditor];
    if (!ed || !ed.filePath) return;
    ed.monitoringMode = !ed.monitoringMode;
}

#pragma mark - Not Yet Implemented

- (void)notYetImplemented:(id)sender {
    NSString *title = [(NSMenuItem *)sender title];
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = @"Not Yet Implemented";
    a.informativeText = [NSString stringWithFormat:@"'%@' is not yet implemented in this version.", title];
    [a runModal];
}

#pragma mark - Edit: Column editor

- (void)showColumnEditor:(id)sender {
    EditorView *ed = [self currentEditor];
    if (!ed) return;
    [ColumnEditorPanel showForEditor:ed parentWindow:self.window];
}

#pragma mark - Find in Files

- (void)showFindInFiles:(id)sender {
    FindInFilesPanel *panel = [FindInFilesPanel sharedPanel];
    panel.delegate = self;
    [panel showWindow:nil];
}

- (void)findInFilesPanel:(FindInFilesPanel *)panel
                openFile:(NSString *)path
                  atLine:(NSInteger)line
               matchText:(NSString *)matchText
               matchCase:(BOOL)matchCase {
    [self openFileAtPath:path];
    EditorView *ed = [self currentEditor];
    [ed goToLineNumber:line];
    // Highlight the match on the target line (search forward without wrapping).
    if (matchText.length)
        [ed findNext:matchText matchCase:matchCase wholeWord:NO wrap:NO];
}

#pragma mark - FolderTreePanelDelegate

- (void)folderTreePanel:(FolderTreePanel *)panel openFileAtURL:(NSURL *)url {
    [self openFileAtPath:url.path];
}

#pragma mark - GitPanelDelegate

- (void)gitPanel:(GitPanel *)panel openFileAtPath:(NSString *)path {
    [self openFileAtPath:path];
}

#pragma mark - View menu actions

- (void)toggleWordWrap:(id)sender {
    EditorView *ed = [self currentEditor];
    if (!ed) return;
    ed.wordWrapEnabled = !ed.wordWrapEnabled;
}

- (void)zoomIn:(id)sender {
    EditorView *ed = [self focusedEditor];
    if (!ed) return;
    [ed.scintillaView message:SCI_ZOOMIN];
    [[NSUserDefaults standardUserDefaults]
        setInteger:[ed.scintillaView message:SCI_GETZOOM] forKey:kPrefZoomLevel];
}

- (void)zoomOut:(id)sender {
    EditorView *ed = [self focusedEditor];
    if (!ed) return;
    [ed.scintillaView message:SCI_ZOOMOUT];
    [[NSUserDefaults standardUserDefaults]
        setInteger:[ed.scintillaView message:SCI_GETZOOM] forKey:kPrefZoomLevel];
}

- (void)resetZoom:(id)sender {
    EditorView *ed = [self focusedEditor];
    if (!ed) return;
    [ed.scintillaView message:SCI_SETZOOM wParam:0];
    [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:kPrefZoomLevel];
}

- (void)toggleShowAllChars:(id)sender {
    _showAllChars = !_showAllChars;
    int flags = _showAllChars ? (SCWS_VISIBLEALWAYS) : SCWS_INVISIBLE;
    ScintillaView *sci = [self currentEditor].scintillaView;
    [sci message:SCI_SETVIEWWS wParam:flags];
}

- (void)toggleIndentGuides:(id)sender {
    _showIndentGuides = !_showIndentGuides;
    ScintillaView *sci = [self currentEditor].scintillaView;
    [sci message:SCI_SETINDENTATIONGUIDES wParam:_showIndentGuides ? SC_IV_LOOKBOTH : SC_IV_NONE];
}

- (void)toggleLineNumbers:(id)sender {
    _showLineNumbers = !_showLineNumbers;
    [[NSUserDefaults standardUserDefaults] setBool:_showLineNumbers forKey:kPrefShowLineNumbers];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"NPPPreferencesChanged" object:nil];
}

#pragma mark - View: Scroll Synchronization

- (void)toggleSyncVerticalScrolling:(id)sender {
    _syncVerticalScrolling = !_syncVerticalScrolling;
}

- (void)toggleSyncHorizontalScrolling:(id)sender {
    _syncHorizontalScrolling = !_syncHorizontalScrolling;
}

- (void)_propagateScrollFrom:(EditorView *)source {
    if (!_syncVerticalScrolling && !_syncHorizontalScrolling) return;
    static BOOL syncing = NO;
    if (syncing) return;
    syncing = YES;
    ScintillaView *src = source.scintillaView;
    sptr_t firstLine = [src message:SCI_GETFIRSTVISIBLELINE];
    sptr_t xOffset   = [src message:SCI_GETXOFFSET];
    NSMutableArray *all = [NSMutableArray arrayWithArray:_tabManager.allEditors];
    [all addObjectsFromArray:_subTabManagerV.allEditors];
    [all addObjectsFromArray:_subTabManagerH.allEditors];
    for (EditorView *ed in all) {
        if (ed == source) continue;
        ScintillaView *sci = ed.scintillaView;
        if (_syncVerticalScrolling)
            [sci message:SCI_SETFIRSTVISIBLELINE wParam:(uptr_t)firstLine];
        if (_syncHorizontalScrolling)
            [sci message:SCI_SETXOFFSET wParam:(uptr_t)xOffset];
    }
    syncing = NO;
}

#pragma mark - Edit: Auto-Completion forwarders

- (void)triggerWordCompletion:(id)sender          { [[self currentEditor] triggerWordCompletion:sender]; }
- (void)triggerFunctionParametersHint:(id)sender  { [[self currentEditor] triggerFunctionParametersHint:sender]; }
- (void)finishOrSelectAutocompleteItem:(id)sender { [[self currentEditor] finishOrSelectAutocompleteItem:sender]; }

#pragma mark - Plugins: Converter forwarders

- (void)asciiToHex:(id)sender { [[self currentEditor] asciiToHex:sender]; }
- (void)hexToAscii:(id)sender { [[self currentEditor] hexToAscii:sender]; }

#pragma mark - Encoding menu actions

// Shared helpers
- (void)_setCurrentEditorEncoding:(NSStringEncoding)enc hasBOM:(BOOL)bom {
    EditorView *ed = [self currentEditor];
    if (!ed) return;
    [ed setFileEncoding:enc hasBOM:bom];
    [self updateStatusBar];
}

- (void)_convertCurrentEditorToEncoding:(NSStringEncoding)enc hasBOM:(BOOL)bom {
    EditorView *ed = [self currentEditor];
    if (!ed) return;
    [ed setFileEncoding:enc hasBOM:bom];
    if (ed.filePath) {
        NSError *err = nil;
        if (![ed saveError:&err] && err)
            [[NSAlert alertWithError:err] runModal];
    }
    [self updateStatusBar];
}

// ── Set Encoding (change metadata only; user must save) ──────────────────────
- (void)setEncodingANSI:(id)sender {
    [self _setCurrentEditorEncoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingWindowsLatin1) hasBOM:NO];
}
- (void)setEncodingUTF8:(id)sender {
    [self _setCurrentEditorEncoding:NSUTF8StringEncoding hasBOM:NO];
}
- (void)setEncodingUTF8BOM:(id)sender {
    [self _setCurrentEditorEncoding:NSUTF8StringEncoding hasBOM:YES];
}
- (void)setEncodingUTF16BEBOM:(id)sender {
    [self _setCurrentEditorEncoding:NSUTF16BigEndianStringEncoding hasBOM:YES];
}
- (void)setEncodingUTF16LEBOM:(id)sender {
    [self _setCurrentEditorEncoding:NSUTF16LittleEndianStringEncoding hasBOM:YES];
}
- (void)setEncodingLatin1:(id)sender {
    [self _setCurrentEditorEncoding:NSISOLatin1StringEncoding hasBOM:NO];
}
- (void)setEncodingLatin9:(id)sender {
    [self _setCurrentEditorEncoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatin9) hasBOM:NO];
}
- (void)setEncodingWindows1252:(id)sender {
    [self _setCurrentEditorEncoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingWindowsLatin1) hasBOM:NO];
}
- (void)setEncodingWindows1250:(id)sender {
    [self _setCurrentEditorEncoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingWindowsLatin2) hasBOM:NO];
}
- (void)setEncodingWindows1251:(id)sender {
    [self _setCurrentEditorEncoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingWindowsCyrillic) hasBOM:NO];
}
- (void)setEncodingWindows1253:(id)sender {
    [self _setCurrentEditorEncoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingWindowsGreek) hasBOM:NO];
}
- (void)setEncodingWindows1257:(id)sender {
    [self _setCurrentEditorEncoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingWindowsBalticRim) hasBOM:NO];
}
- (void)setEncodingWindows1254:(id)sender {
    [self _setCurrentEditorEncoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingWindowsLatin5) hasBOM:NO];
}
- (void)setEncodingBig5:(id)sender {
    [self _setCurrentEditorEncoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingBig5) hasBOM:NO];
}
- (void)setEncodingGB2312:(id)sender {
    [self _setCurrentEditorEncoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_2312_80) hasBOM:NO];
}
- (void)setEncodingShiftJIS:(id)sender {
    [self _setCurrentEditorEncoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingShiftJIS) hasBOM:NO];
}
- (void)setEncodingEUCKR:(id)sender {
    [self _setCurrentEditorEncoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingEUC_KR) hasBOM:NO];
}

// ── Convert To (change encoding and immediately re-save) ──────────────────────
- (void)convertToEncodingANSI:(id)sender {
    [self _convertCurrentEditorToEncoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingWindowsLatin1) hasBOM:NO];
}
- (void)convertToEncodingUTF8:(id)sender {
    [self _convertCurrentEditorToEncoding:NSUTF8StringEncoding hasBOM:NO];
}
- (void)convertToEncodingUTF8BOM:(id)sender {
    [self _convertCurrentEditorToEncoding:NSUTF8StringEncoding hasBOM:YES];
}
- (void)convertToEncodingUTF16BEBOM:(id)sender {
    [self _convertCurrentEditorToEncoding:NSUTF16BigEndianStringEncoding hasBOM:YES];
}
- (void)convertToEncodingUTF16LEBOM:(id)sender {
    [self _convertCurrentEditorToEncoding:NSUTF16LittleEndianStringEncoding hasBOM:YES];
}

- (void)setEOLCRLF:(id)sender {
    [[[self currentEditor] scintillaView] message:SCI_SETEOLMODE wParam:SC_EOL_CRLF];
    [[[self currentEditor] scintillaView] message:SCI_CONVERTEOLS wParam:SC_EOL_CRLF];
    [self updateStatusBar];
}

- (void)setEOLLF:(id)sender {
    [[[self currentEditor] scintillaView] message:SCI_SETEOLMODE wParam:SC_EOL_LF];
    [[[self currentEditor] scintillaView] message:SCI_CONVERTEOLS wParam:SC_EOL_LF];
    [self updateStatusBar];
}

- (void)setEOLCR:(id)sender {
    [[[self currentEditor] scintillaView] message:SCI_SETEOLMODE wParam:SC_EOL_CR];
    [[[self currentEditor] scintillaView] message:SCI_CONVERTEOLS wParam:SC_EOL_CR];
    [self updateStatusBar];
}

#pragma mark - Language menu action

- (void)setLanguageFromMenu:(id)sender {
    NSString *lang = [sender representedObject] ?: @"";
    [[self currentEditor] setLanguage:lang];
    [self updateStatusBar];
}

#pragma mark - Tab navigation

- (void)selectNextTab:(id)sender {
    NSInteger next = (_activeTabManager.tabBar.selectedIndex + 1) % _activeTabManager.tabBar.tabCount;
    [_activeTabManager selectTabAtIndex:next];
}

- (void)selectPreviousTab:(id)sender {
    NSInteger count = _activeTabManager.tabBar.tabCount;
    NSInteger prev  = (_activeTabManager.tabBar.selectedIndex - 1 + count) % count;
    [_activeTabManager selectTabAtIndex:prev];
}

#pragma mark - Find panel animation

- (void)animateFindPanel {
    CGFloat h = _findPanel.preferredHeight;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = 0.15;
        self->_findPanelHeightConstraint.animator.constant = h;
    }];
}

#pragma mark - FindReplacePanelDelegate

- (void)findPanel:(FindReplacePanel *)panel findNext:(NSString *)text
        matchCase:(BOOL)mc wholeWord:(BOOL)ww wrap:(BOOL)wrap {
    if (![[self currentEditor] findNext:text matchCase:mc wholeWord:ww wrap:wrap]) NSBeep();
}

- (void)findPanel:(FindReplacePanel *)panel findPrev:(NSString *)text
        matchCase:(BOOL)mc wholeWord:(BOOL)ww wrap:(BOOL)wrap {
    if (![[self currentEditor] findPrev:text matchCase:mc wholeWord:ww wrap:wrap]) NSBeep();
}

- (void)findPanel:(FindReplacePanel *)panel replace:(NSString *)text
             with:(NSString *)replacement matchCase:(BOOL)mc wholeWord:(BOOL)ww {
    if (![[self currentEditor] replace:text with:replacement matchCase:mc wholeWord:ww]) NSBeep();
}

- (void)findPanel:(FindReplacePanel *)panel replaceAll:(NSString *)text
             with:(NSString *)replacement matchCase:(BOOL)mc wholeWord:(BOOL)ww {
    NSInteger n = [[self currentEditor] replaceAll:text with:replacement matchCase:mc wholeWord:ww];
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = n > 0 ? [NSString stringWithFormat:@"%ld replacement(s) made.", (long)n]
                           : @"No occurrences found.";
    [a runModal];
}

- (void)findPanelDidClose:(FindReplacePanel *)panel {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = 0.12;
        self->_findPanelHeightConstraint.animator.constant = 0;
    } completionHandler:^{ self->_findPanel.hidden = YES; }];
    [self.window makeFirstResponder:[self currentEditor].scintillaView];
}

#pragma mark - NSSplitViewDelegate

- (BOOL)splitView:(NSSplitView *)sv canCollapseSubview:(NSView *)sub {
    if (sv == _editorSplitView) return sub == _sidePanelHost;
    if (sv == _hSplitView)      return sub == _subEditorContainerH;
    if (sv == _vSplitView)      return sub == _subEditorContainerV;
    return NO;
}

// Hide (and disable) the divider whenever the adjacent collapsible pane is
// fully collapsed — prevents the user from accidentally grabbing the invisible
// NSSplitView divider when trying to resize the window from its right edge.
- (BOOL)splitView:(NSSplitView *)sv shouldHideDividerAtIndex:(NSInteger)idx {
    if (sv == _editorSplitView && idx == 0)
        return [sv isSubviewCollapsed:_sidePanelHost];
    if (sv == _hSplitView && idx == 0)
        return [sv isSubviewCollapsed:_subEditorContainerH];
    if (sv == _vSplitView && idx == 0)
        return [sv isSubviewCollapsed:_subEditorContainerV];
    return NO;
}

- (CGFloat)splitView:(NSSplitView *)sv constrainMinCoordinate:(CGFloat)p ofSubviewAt:(NSInteger)i {
    if (sv == _hSplitView || sv == _vSplitView) return p + 100;
    if (sv == _editorSplitView) return p + 200;
    return p + 200;
}

- (CGFloat)splitView:(NSSplitView *)sv constrainMaxCoordinate:(CGFloat)p ofSubviewAt:(NSInteger)i {
    if (sv == _hSplitView || sv == _vSplitView) return p - 100;
    return p - 150;   // panel at least 150pt when visible
}

#pragma mark - TabManagerDelegate

- (void)tabManager:(id)tabManager didSelectEditor:(EditorView *)editor {
    _activeTabManager = tabManager;
    [self updateTitle];
    [self updateStatusBar];
    if (_docListPanel) [_docListPanel reloadData];
    if (_funcListPanel && [_sidePanelHost hasPanel:_funcListPanel])
        [_funcListPanel loadEditor:editor];
    if (_docMapPanel && [_sidePanelHost hasPanel:_docMapPanel])
        [_docMapPanel setTrackedEditor:editor];
    if (_folderTreePanel && [_sidePanelHost hasPanel:_folderTreePanel]) {
        NSString *path = editor.filePath;
        [(FolderTreePanel *)_folderTreePanel setActiveFileURL:
            path ? [NSURL fileURLWithPath:path] : [NSURL fileURLWithPath:NSHomeDirectory()]];
    }
    if (_gitPanel && [_sidePanelHost hasPanel:_gitPanel]) {
        [self _updateGitPanelForPath:editor.filePath];
    }
    [self _updateGitBranch:editor.filePath];
    [editor updateGitDiffMarkers];
}

- (void)tabManager:(id)tabManager didCloseEditor:(EditorView *)editor {
    [self updateTitle];
    if (_docListPanel) [_docListPanel reloadData];
}

#pragma mark - Cursor notification

- (void)editorCursorMoved:(NSNotification *)note {
    EditorView *ed = note.object;
    if (ed == [self currentEditor]) {
        [self updateStatusBar];
        [self refreshCurrentTab];
    }
    [self _propagateScrollFrom:ed];
}

#pragma mark - File: Reload / Reveal / Copy / Rename / Trash

- (void)reloadFromDisk:(id)sender {
    EditorView *ed = [self currentEditor];
    NSString *path = ed.filePath;
    if (!path) return;
    if (ed.isModified) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Reload from Disk";
        alert.informativeText = [NSString stringWithFormat:@"'%@' has unsaved changes.\nReload and discard changes?",
                                 path.lastPathComponent];
        [alert addButtonWithTitle:@"Reload"];
        [alert addButtonWithTitle:@"Cancel"];
        if ([alert runModal] != NSAlertFirstButtonReturn) return;
    }
    NSError *err;
    if (![ed loadFileAtPath:path error:&err])
        [[NSAlert alertWithError:err] runModal];
    [self updateTitle];
    [self updateStatusBar];
}

- (void)revealInFinder:(id)sender {
    NSString *path = [self currentEditor].filePath;
    if (path)
        [[NSWorkspace sharedWorkspace] selectFile:path inFileViewerRootedAtPath:@""];
}

- (void)openInTerminal:(id)sender {
    NSString *path = [self currentEditor].filePath;
    if (!path) return;
    NSString *dir = path.stringByDeletingLastPathComponent;
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/open"];
    task.arguments = @[@"-a", @"Terminal", dir];
    [task launch];
}

- (void)saveDocumentCopyAs:(id)sender {
    EditorView *ed = [self currentEditor];
    if (!ed) return;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.title = @"Save a Copy As";
    if (ed.filePath)
        panel.directoryURL = [NSURL fileURLWithPath:ed.filePath.stringByDeletingLastPathComponent];
    panel.nameFieldStringValue = ed.displayName;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
        if (r != NSModalResponseOK) return;
        NSError *err;
        if (![ed saveToPath:panel.URL.path error:&err])
            [[NSAlert alertWithError:err] beginSheetModalForWindow:self.window completionHandler:nil];
    }];
}

- (void)renameDocument:(id)sender {
    EditorView *ed = [self currentEditor];
    NSString *path = ed.filePath;
    if (!path) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Rename";
    alert.informativeText = @"Enter a new filename:";
    NSTextField *tf = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 22)];
    tf.stringValue = path.lastPathComponent;
    alert.accessoryView = tf;
    [alert addButtonWithTitle:@"Rename"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.window.initialFirstResponder = tf;
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSString *newName = tf.stringValue;
    if (!newName.length || [newName isEqualToString:path.lastPathComponent]) return;
    NSString *newPath = [path.stringByDeletingLastPathComponent
                         stringByAppendingPathComponent:newName];
    NSError *err;
    if ([[NSFileManager defaultManager] moveItemAtPath:path toPath:newPath error:&err]) {
        ed.filePath = newPath;
        [_tabManager refreshCurrentTabTitle];
        [self updateTitle];
        [self addToRecentFiles:newPath];
    } else {
        [[NSAlert alertWithError:err] runModal];
    }
}

- (void)moveToTrash:(id)sender {
    EditorView *ed = [self currentEditor];
    NSString *path = ed.filePath;
    if (!path) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Move to Trash";
    alert.informativeText = [NSString stringWithFormat:@"Move '%@' to the Trash?",
                             path.lastPathComponent];
    [alert addButtonWithTitle:@"Move to Trash"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSError *err;
    if ([[NSFileManager defaultManager] trashItemAtURL:[NSURL fileURLWithPath:path]
                                     resultingItemURL:nil error:&err]) {
        [_tabManager closeEditor:ed];
        [self updateTitle];
    } else {
        [[NSAlert alertWithError:err] runModal];
    }
}

- (void)printNow:(id)sender {
    EditorView *ed = [self currentEditor];
    if (!ed) return;
    NSPrintOperation *op = [NSPrintOperation printOperationWithView:ed.scintillaView
                                                          printInfo:[NSPrintInfo sharedPrintInfo]];
    op.showsPrintPanel = NO;
    op.showsProgressPanel = YES;
    [op runOperation];
}

#pragma mark - File: Close Multiple Documents

/// Prompt to save a modified editor synchronously. Returns YES if safe to close.
- (BOOL)_promptSaveBeforeClose:(EditorView *)ed {
    if (!ed.isModified) return YES;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Save '%@' before closing?", ed.displayName];
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Don't Save"];
    [alert addButtonWithTitle:@"Cancel"];
    NSModalResponse r = [alert runModal];
    if (r == NSAlertThirdButtonReturn) return NO;  // Cancel
    if (r == NSAlertFirstButtonReturn) {            // Save
        if (ed.filePath) {
            NSError *err;
            return [ed saveError:&err];
        }
        // Untitled — run modal save panel
        NSSavePanel *sp = [NSSavePanel savePanel];
        sp.nameFieldStringValue = ed.displayName;
        if ([sp runModal] == NSModalResponseOK) {
            NSError *err;
            return [ed saveToPath:sp.URL.path error:&err];
        }
        return NO;
    }
    return YES; // Don't Save
}

- (void)closeAllButCurrent:(id)sender {
    EditorView *current = [self currentEditor];
    NSArray *all = _activeTabManager.allEditors.copy;
    for (NSInteger i = 0; i < (NSInteger)all.count; i++) {
        EditorView *ed = all[i];
        if (ed == current) continue;
        if ([_activeTabManager.tabBar isTabPinnedAtIndex:i]) continue;
        if ([self _promptSaveBeforeClose:ed])
            [_activeTabManager closeEditor:ed];
    }
    [self updateTitle];
}

- (void)closeAllToLeft:(id)sender {
    EditorView *current = [self currentEditor];
    NSArray *all = _activeTabManager.allEditors;
    NSInteger idx = [all indexOfObject:current];
    if (idx == NSNotFound) return;
    for (NSInteger i = idx - 1; i >= 0; i--) {
        if ([_activeTabManager.tabBar isTabPinnedAtIndex:i]) continue;
        EditorView *ed = all[i];
        if ([self _promptSaveBeforeClose:ed])
            [_activeTabManager closeEditor:ed];
    }
    [self updateTitle];
}

- (void)closeAllToRight:(id)sender {
    EditorView *current = [self currentEditor];
    NSArray *all = _activeTabManager.allEditors;
    NSInteger idx = [all indexOfObject:current];
    if (idx == NSNotFound) return;
    for (NSInteger i = (NSInteger)all.count - 1; i > idx; i--) {
        if ([_activeTabManager.tabBar isTabPinnedAtIndex:i]) continue;
        EditorView *ed = all[i];
        if ([self _promptSaveBeforeClose:ed])
            [_activeTabManager closeEditor:ed];
    }
    [self updateTitle];
}

- (void)closeAllUnchanged:(id)sender {
    NSArray *all = _activeTabManager.allEditors.copy;
    for (NSInteger i = 0; i < (NSInteger)all.count; i++) {
        EditorView *ed = all[i];
        if (ed.isModified) continue;
        if ([_activeTabManager.tabBar isTabPinnedAtIndex:i]) continue;
        [_activeTabManager closeEditor:ed];
    }
    [self updateTitle];
}

- (void)closeAllButPinned:(id)sender {
    NSArray *all = _activeTabManager.allEditors.copy;
    for (NSInteger i = 0; i < (NSInteger)all.count; i++) {
        if ([_activeTabManager.tabBar isTabPinnedAtIndex:i]) continue;
        EditorView *ed = all[i];
        if ([self _promptSaveBeforeClose:ed])
            [_activeTabManager closeEditor:ed];
    }
    [self updateTitle];
}

#pragma mark - Edit: Column Mode / Character Panel / Brace Select

- (void)columnMode:(id)sender          { [[self currentEditor] columnMode:sender]; }
- (void)selectAllInBraces:(id)sender   { [[self currentEditor] selectAllInBraces:sender]; }
- (void)characterPanel:(id)sender      { [NSApp orderFrontCharacterPalette:sender]; }

#pragma mark - Edit: On Selection

- (void)openSelectionAsFile:(id)sender {
    NSString *sel = [[[self currentEditor] selectedText]
                     stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!sel) return;
    if ([[NSFileManager defaultManager] fileExistsAtPath:sel])
        [self openFileAtPath:sel];
}

- (void)openSelectionInDefaultViewer:(id)sender {
    NSString *sel = [[[self currentEditor] selectedText]
                     stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!sel.length) return;
    NSString *path = sel;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return;
    [[NSWorkspace sharedWorkspace] openFile:path];
}

- (void)searchSelectionOnInternet:(id)sender {
    NSString *sel = [[self currentEditor] selectedText];
    if (!sel) return;
    NSString *encoded = [sel stringByAddingPercentEncodingWithAllowedCharacters:
                         [NSCharacterSet URLQueryAllowedCharacterSet]];
    [[NSWorkspace sharedWorkspace]
     openURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://www.google.com/search?q=%@", encoded]]];
}

#pragma mark - Tools: Hash

- (void)hashMD5Generate:(id)sender      { [[self currentEditor] generateHashForAlgorithm:@"MD5"]; }
- (void)hashMD5ToClipboard:(id)sender   { [[self currentEditor] copyHashForAlgorithm:@"MD5"]; }
- (void)hashSHA1Generate:(id)sender     { [[self currentEditor] generateHashForAlgorithm:@"SHA-1"]; }
- (void)hashSHA1ToClipboard:(id)sender  { [[self currentEditor] copyHashForAlgorithm:@"SHA-1"]; }
- (void)hashSHA256Generate:(id)sender   { [[self currentEditor] generateHashForAlgorithm:@"SHA-256"]; }
- (void)hashSHA256ToClipboard:(id)sender{ [[self currentEditor] copyHashForAlgorithm:@"SHA-256"]; }
- (void)hashSHA512Generate:(id)sender   { [[self currentEditor] generateHashForAlgorithm:@"SHA-512"]; }
- (void)hashSHA512ToClipboard:(id)sender{ [[self currentEditor] copyHashForAlgorithm:@"SHA-512"]; }

#pragma mark - Plugins: Base64 (all variants)

- (void)base64Encode:(id)sender              { [[self currentEditor] base64Encode:sender]; }
- (void)base64Decode:(id)sender              { [[self currentEditor] base64Decode:sender]; }
- (void)base64EncodeWithPadding:(id)sender   { [[self currentEditor] base64EncodeWithPadding:sender]; }
- (void)base64DecodeStrict:(id)sender        { [[self currentEditor] base64DecodeStrict:sender]; }
- (void)base64URLSafeEncode:(id)sender       { [[self currentEditor] base64URLSafeEncode:sender]; }
- (void)base64URLSafeDecode:(id)sender       { [[self currentEditor] base64URLSafeDecode:sender]; }

#pragma mark - Plugins: Export RTF / HTML

- (void)copyRTFToClipboard:(id)sender {
    NSString *rtf = [[self currentEditor] generateRTF];
    if (!rtf) return;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:rtf forType:NSPasteboardTypeRTF];
}

- (void)copyHTMLToClipboard:(id)sender {
    NSString *html = [[self currentEditor] generateHTML];
    if (!html) return;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:html forType:NSPasteboardTypeHTML];
}

- (void)exportToRTF:(id)sender {
    EditorView *ed = [self currentEditor]; if (!ed) return;
    NSString *rtf = [ed generateRTF]; if (!rtf) return;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedFileTypes = @[@"rtf"];
    panel.nameFieldStringValue = [ed.displayName.stringByDeletingPathExtension stringByAppendingPathExtension:@"rtf"];
    if ([panel runModal] == NSModalResponseOK) {
        NSError *err;
        [rtf writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:&err];
        if (err) [[NSAlert alertWithError:err] runModal];
    }
}

- (void)exportToHTML:(id)sender {
    EditorView *ed = [self currentEditor]; if (!ed) return;
    NSString *html = [ed generateHTML]; if (!html) return;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedFileTypes = @[@"html"];
    panel.nameFieldStringValue = [ed.displayName.stringByDeletingPathExtension stringByAppendingPathExtension:@"html"];
    if ([panel runModal] == NSModalResponseOK) {
        NSError *err;
        [html writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:&err];
        if (err) [[NSAlert alertWithError:err] runModal];
    }
}

#pragma mark - Tools: Hash from Files

- (void)_hashFilesForAlgorithm:(NSString *)algo {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles    = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = YES;
    panel.title = [NSString stringWithFormat:@"Choose files for %@ hash", algo];
    if ([panel runModal] != NSModalResponseOK) return;

    NSMutableString *results = [NSMutableString string];
    for (NSURL *url in panel.URLs) {
        NSData *data = [NSData dataWithContentsOfURL:url];
        if (!data) { [results appendFormat:@"Error reading %@\n", url.path]; continue; }
        NSString *hash = [EditorView hexHashForAlgorithm:algo data:data];
        [results appendFormat:@"%@  %@\n", hash ?: @"(error)", url.path];
    }
    if (!results.length) return;
    EditorView *ed = [self currentEditor];
    if (ed) {
        const char *u = results.UTF8String;
        [ed.scintillaView message:SCI_APPENDTEXT wParam:(uptr_t)strlen(u) lParam:(sptr_t)u];
    }
}

- (void)hashMD5FromFiles:(id)sender    { [self _hashFilesForAlgorithm:@"MD5"]; }
- (void)hashSHA1FromFiles:(id)sender   { [self _hashFilesForAlgorithm:@"SHA-1"]; }
- (void)hashSHA256FromFiles:(id)sender { [self _hashFilesForAlgorithm:@"SHA-256"]; }
- (void)hashSHA512FromFiles:(id)sender { [self _hashFilesForAlgorithm:@"SHA-512"]; }

#pragma mark - View symbol toggles / Hide Lines

- (void)toggleWrapSymbol:(id)sender     { [[self currentEditor] toggleWrapSymbol:sender]; }
- (void)toggleHideLineMarks:(id)sender  { [[self currentEditor] toggleHideLineMarks:sender]; }
- (void)hideLinesInSelection:(id)sender { [[self currentEditor] hideLinesInSelection:sender]; }

#pragma mark - View in Browser

- (void)_viewCurrentFileInBrowserWithBundleID:(NSString *)bundleID {
    EditorView *ed = [self currentEditor];
    NSString *path = ed.filePath;
    if (!path.length) return;
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    if (bundleID.length)
        [[NSWorkspace sharedWorkspace] openURLs:@[fileURL]
                        withAppBundleIdentifier:bundleID
                                        options:0
                 additionalEventParamDescriptor:nil
                              launchIdentifiers:nil];
    else
        [[NSWorkspace sharedWorkspace] openURL:fileURL];
}

- (void)viewInFirefox:(id)sender       { [self _viewCurrentFileInBrowserWithBundleID:@"org.mozilla.firefox"]; }
- (void)viewInChrome:(id)sender        { [self _viewCurrentFileInBrowserWithBundleID:@"com.google.Chrome"]; }
- (void)viewInSafari:(id)sender        { [self _viewCurrentFileInBrowserWithBundleID:@"com.apple.Safari"]; }
- (void)viewInCustomBrowser:(id)sender { [self _viewCurrentFileInBrowserWithBundleID:nil]; }

#pragma mark - File Actions

- (void)openInDefaultViewer:(id)sender {
    NSString *path = [self currentEditor].filePath;
    if (path.length) [[NSWorkspace sharedWorkspace] openFile:path];
}

- (void)openFolderAsWorkspace:(id)sender {
    NSString *path = [self currentEditor].filePath;
    NSString *dir  = path.length ? path.stringByDeletingLastPathComponent : NSHomeDirectory();
    [[NSWorkspace sharedWorkspace] selectFile:path
                     inFileViewerRootedAtPath:dir];
}

- (void)openSelectedFileInNewInstance:(id)sender {
    NSString *sel = [[self currentEditor] selectedText];
    if (!sel.length) return;
    sel = [sel stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([[NSFileManager defaultManager] fileExistsAtPath:sel])
        [_activeTabManager openFileAtPath:sel];
}

#pragma mark - Run Menu

- (void)getPHPHelp:(id)sender {
    NSString *sel = [[self currentEditor] selectedText] ?: @"";
    NSString *q = [sel stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:
        [NSString stringWithFormat:@"https://www.php.net/manual-lookup.php?pattern=%@", q]]];
}

- (void)wikiSearch:(id)sender {
    NSString *sel = [[self currentEditor] selectedText] ?: @"";
    NSString *q = [sel stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:
        [NSString stringWithFormat:@"https://en.wikipedia.org/wiki/Special:Search?search=%@", q]]];
}

- (void)showRunDialog:(id)sender {
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,480,90)
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    panel.title = @"Run";
    [panel center];
    NSView *cv = panel.contentView;

    NSTextField *tf = [[NSTextField alloc] init];
    tf.translatesAutoresizingMaskIntoConstraints = NO;
    tf.placeholderString = @"Shell command…";
    NSButton *runBtn = [NSButton buttonWithTitle:@"Run" target:nil action:nil];
    runBtn.translatesAutoresizingMaskIntoConstraints = NO;
    runBtn.keyEquivalent = @"\r";
    NSButton *cancelBtn = [NSButton buttonWithTitle:@"Cancel" target:nil action:nil];
    cancelBtn.translatesAutoresizingMaskIntoConstraints = NO;
    cancelBtn.keyEquivalent = @"\033";
    [cv addSubview:tf]; [cv addSubview:runBtn]; [cv addSubview:cancelBtn];
    [NSLayoutConstraint activateConstraints:@[
        [tf.topAnchor constraintEqualToAnchor:cv.topAnchor constant:16],
        [tf.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:16],
        [tf.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-16],
        [runBtn.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-16],
        [runBtn.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-16],
        [cancelBtn.trailingAnchor constraintEqualToAnchor:runBtn.leadingAnchor constant:-8],
        [cancelBtn.bottomAnchor constraintEqualToAnchor:runBtn.bottomAnchor],
    ]];
    [panel makeFirstResponder:tf];

    __block BOOL didRun = NO;
    __weak NSPanel *wPanel = panel;
    __weak NSTextField *wTF = tf;
    runBtn.target = [NSBlockOperation blockOperationWithBlock:^{
        NSString *cmd = wTF.stringValue;
        if (cmd.length) {
            [NSTask launchedTaskWithLaunchPath:@"/bin/sh" arguments:@[@"-c", cmd]];
            didRun = YES;
        }
        [NSApp stopModal];
        [wPanel orderOut:nil];
    }];
    runBtn.action = @selector(main);
    cancelBtn.target = [NSBlockOperation blockOperationWithBlock:^{
        [NSApp stopModal];
        [wPanel orderOut:nil];
    }];
    cancelBtn.action = @selector(main);
    [NSApp runModalForWindow:panel];
    (void)didRun;
}

#pragma mark - Search: Mark Text

// Forwarded to current editor — style is encoded in sender.tag (1-5).
- (void)styleAllOccurrences:(id)sender {
    NSInteger st = [(NSMenuItem *)sender tag];
    EditorView *ed = [self currentEditor]; if (!ed) return;
    NSString *sel = [ed selectedText];
    if (!sel.length) {
        // Try word at caret via find current word
        sel = [ed.scintillaView string]; // fallback; use selected word if any
        return;
    }
    [ed markStyle:st allOccurrencesOf:sel matchCase:YES wholeWord:NO];
}

- (void)styleOneToken:(id)sender {
    NSInteger st = [(NSMenuItem *)sender tag];
    [[self currentEditor] markStyleSelection:st];
}

- (void)clearMarkStyleN:(id)sender {
    NSInteger st = [(NSMenuItem *)sender tag];
    [[self currentEditor] clearMarkStyle:st];
}

- (void)clearAllMarkStyles:(id)sender {
    [[self currentEditor] clearAllMarkStyles];
}

- (void)jumpToNextStyledTokenBelow:(id)sender { [[self currentEditor] jumpToNextMark:1];  }
- (void)jumpToNextStyledTokenAbove:(id)sender { [[self currentEditor] jumpToNextMark:-1]; }
- (void)jumpToNextBookmarkBelow:(id)sender    { [[self currentEditor] nextBookmark:sender]; }
- (void)jumpToNextBookmarkAbove:(id)sender    { [[self currentEditor] previousBookmark:sender]; }

- (void)copyStyledText:(id)sender {
    NSInteger st = [(NSMenuItem *)sender tag];
    [[self currentEditor] copyTextWithMarkStyle:st];
}

- (void)showMarkDialog:(id)sender {
    // Simple sheet: text, match case, whole word, style selector, Mark All button.
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,380,150)
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    panel.title = @"Mark";
    [panel center];
    NSView *cv = panel.contentView;

    NSTextField *tf = [[NSTextField alloc] init];
    tf.translatesAutoresizingMaskIntoConstraints = NO;
    tf.placeholderString = @"Text to mark…";

    NSButton *mcBox = [NSButton checkboxWithTitle:@"Match case" target:nil action:nil];
    mcBox.translatesAutoresizingMaskIntoConstraints = NO;
    NSButton *wwBox = [NSButton checkboxWithTitle:@"Whole word" target:nil action:nil];
    wwBox.translatesAutoresizingMaskIntoConstraints = NO;

    NSPopUpButton *stylePop = [[NSPopUpButton alloc] init];
    stylePop.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSString *s in @[@"Style 1 (Cyan)", @"Style 2 (Yellow)", @"Style 3 (Green)",
                           @"Style 4 (Orange)", @"Style 5 (Violet)"])
        [stylePop addItemWithTitle:s];

    NSButton *markBtn   = [NSButton buttonWithTitle:@"Mark All" target:nil action:nil];
    markBtn.translatesAutoresizingMaskIntoConstraints = NO;
    markBtn.keyEquivalent = @"\r";
    NSButton *closeBtn  = [NSButton buttonWithTitle:@"Close" target:nil action:nil];
    closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    closeBtn.keyEquivalent = @"\033";

    [cv addSubview:tf]; [cv addSubview:mcBox]; [cv addSubview:wwBox];
    [cv addSubview:stylePop]; [cv addSubview:markBtn]; [cv addSubview:closeBtn];

    [NSLayoutConstraint activateConstraints:@[
        [tf.topAnchor constraintEqualToAnchor:cv.topAnchor constant:14],
        [tf.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:12],
        [tf.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-12],
        [mcBox.topAnchor constraintEqualToAnchor:tf.bottomAnchor constant:6],
        [mcBox.leadingAnchor constraintEqualToAnchor:tf.leadingAnchor],
        [wwBox.topAnchor constraintEqualToAnchor:mcBox.topAnchor],
        [wwBox.leadingAnchor constraintEqualToAnchor:mcBox.trailingAnchor constant:12],
        [stylePop.topAnchor constraintEqualToAnchor:mcBox.bottomAnchor constant:8],
        [stylePop.leadingAnchor constraintEqualToAnchor:tf.leadingAnchor],
        [stylePop.trailingAnchor constraintEqualToAnchor:tf.trailingAnchor],
        [markBtn.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-12],
        [markBtn.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-12],
        [closeBtn.trailingAnchor constraintEqualToAnchor:markBtn.leadingAnchor constant:-8],
        [closeBtn.bottomAnchor constraintEqualToAnchor:markBtn.bottomAnchor],
    ]];
    [panel makeFirstResponder:tf];

    __weak typeof(self) wSelf = self;
    __weak NSPanel *wPanel = panel;
    __weak NSTextField *wTF = tf;
    __weak NSButton *wMC = mcBox, *wWW = wwBox;
    __weak NSPopUpButton *wPop = stylePop;
    markBtn.target = [NSBlockOperation blockOperationWithBlock:^{
        NSString *text = wTF.stringValue;
        if (!text.length) return;
        NSInteger style = wPop.indexOfSelectedItem + 1;
        [[wSelf currentEditor] markStyle:style allOccurrencesOf:text
                               matchCase:wMC.state == NSControlStateValueOn
                               wholeWord:wWW.state == NSControlStateValueOn];
    }];
    markBtn.action = @selector(main);
    closeBtn.target = [NSBlockOperation blockOperationWithBlock:^{
        [NSApp stopModal]; [wPanel orderOut:nil];
    }];
    closeBtn.action = @selector(main);
    [NSApp runModalForWindow:panel];
}

- (void)pasteToBookmarkedLines:(id)sender { [[self currentEditor] pasteToBookmarkedLines:sender]; }

#pragma mark - Search Results Window (reuses Find in Files)

- (void)showSearchResultsWindow:(id)sender  { [self showFindInFiles:sender]; }
- (void)nextSearchResult:(id)sender         { /* navigated via FindInFilesPanel row selection */ }
- (void)previousSearchResult:(id)sender     { /* navigated via FindInFilesPanel row selection */ }

#pragma mark - Multi-select in all opened documents

- (void)multiSelectAllInAllDocuments:(id)sender {
    NSString *sel = [[self currentEditor] selectedText];
    if (!sel.length) return;
    for (TabManager *tm in @[_tabManager, _subTabManagerH, _subTabManagerV]) {
        for (EditorView *ed in tm.allEditors)
            [ed multiSelectAllInCurrentDocument:sender];
    }
}

- (void)multiSelectNextInAllDocuments:(id)sender {
    [[self currentEditor] multiSelectNextInCurrentDocument:sender];
}

#pragma mark - Plugins: Stubs

- (void)showPluginsAdmin:(id)sender {
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText    = @"Plugins Admin";
    a.informativeText = @"Plugin management is not yet supported in this port.";
    [a runModal];
}

- (void)openPluginsFolder:(id)sender {
    NSString *dir = [nppConfigDir() stringByAppendingPathComponent:@"plugins"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSWorkspace sharedWorkspace] openFile:dir];
}

- (void)showShortcutMapper:(id)sender {
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText     = @"Shortcut Mapper";
    a.informativeText = @"Shortcut mapping is not yet supported in this port.";
    [a runModal];
}

- (void)editPopupContextMenu:(id)sender {
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText     = @"Edit Popup Context Menu";
    a.informativeText = @"Context menu editing is not yet supported in this port.";
    [a runModal];
}

- (void)openUDLFolder:(id)sender {
    NSString *dir = [nppConfigDir() stringByAppendingPathComponent:@"userDefineLangs"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSWorkspace sharedWorkspace] openFile:dir];
}

- (void)showCLIHelp:(id)sender {
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText     = @"Command Line Arguments";
    a.informativeText = @"NotepadPlusPlusMac accepts file paths as arguments:\n\n"
                        @"  NotepadPlusPlusMac file1.txt file2.cpp …\n\n"
                        @"No additional CLI flags are currently supported.";
    [a runModal];
}

- (void)checkForUpdates:(id)sender {
    [[NSWorkspace sharedWorkspace]
     openURL:[NSURL URLWithString:@"https://github.com/notepad-plus-plus/notepad-plus-plus/releases"]];
}

- (void)showUpdaterProxyStub:(id)sender {
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText     = @"Set Updater Proxy";
    a.informativeText = @"Proxy configuration is not supported in this port.";
    [a runModal];
}

- (void)showMacroManager:(id)sender {
    // Build a list of saved macros and allow deletion.
    NSDictionary *macros = [NSDictionary dictionaryWithContentsOfFile:nppMacrosPath()];
    NSArray<NSString *> *names = macros ? [macros.allKeys sortedArrayUsingSelector:@selector(compare:)] : @[];
    if (!names.count) {
        NSAlert *a = [[NSAlert alloc] init];
        a.messageText = @"No Saved Macros";
        a.informativeText = @"Record and save a macro first.";
        [a runModal];
        return;
    }

    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,320,240)
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    panel.title = @"Macro Manager";
    [panel center];
    NSView *cv = panel.contentView;

    NSTableView *tv = [[NSTableView alloc] init];
    tv.allowsMultipleSelection = NO;
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    col.title = @"Macro Name"; col.resizingMask = NSTableColumnAutoresizingMask;
    [tv addTableColumn:col];
    NSScrollView *sv = [[NSScrollView alloc] init];
    sv.translatesAutoresizingMaskIntoConstraints = NO;
    sv.hasVerticalScroller = YES;
    sv.documentView = tv;
    [cv addSubview:sv];

    NSButton *delBtn  = [NSButton buttonWithTitle:@"Delete" target:nil action:nil];
    delBtn.translatesAutoresizingMaskIntoConstraints = NO;
    NSButton *doneBtn = [NSButton buttonWithTitle:@"Done" target:nil action:nil];
    doneBtn.translatesAutoresizingMaskIntoConstraints = NO;
    doneBtn.keyEquivalent = @"\r";
    [cv addSubview:delBtn]; [cv addSubview:doneBtn];
    [NSLayoutConstraint activateConstraints:@[
        [sv.topAnchor constraintEqualToAnchor:cv.topAnchor constant:8],
        [sv.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:8],
        [sv.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-8],
        [sv.bottomAnchor constraintEqualToAnchor:delBtn.topAnchor constant:-8],
        [doneBtn.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-8],
        [doneBtn.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-12],
        [delBtn.trailingAnchor constraintEqualToAnchor:doneBtn.leadingAnchor constant:-8],
        [delBtn.bottomAnchor constraintEqualToAnchor:doneBtn.bottomAnchor],
    ]];

    // Simple datasource
    NSMutableArray<NSString *> *mutableNames = [names mutableCopy];
    _NPPWindowsListHelper *helper = [[_NPPWindowsListHelper alloc] initWithRows:nil];
    __block NSMutableArray<NSString *> *macroNames = mutableNames;
    __block NSMutableDictionary *mutableMacros = [macros mutableCopy];

    helper.activateHandler = ^{
        NSInteger row = tv.selectedRow;
        if (row < 0 || row >= (NSInteger)macroNames.count) return;
        NSString *name = macroNames[row];
        [mutableMacros removeObjectForKey:name];
        [macroNames removeObjectAtIndex:row];
        [mutableMacros writeToFile:nppMacrosPath() atomically:YES];
        [tv reloadData];
    };

    // Reuse _NPPWindowsListHelper for simple string list
    tv.dataSource = (id<NSTableViewDataSource>)[NSObject new]; // placeholder
    tv.delegate   = (id<NSTableViewDelegate>)[NSObject new];

    // Use a block-based datasource
    _NPPWindowsListHelper *ds = [[_NPPWindowsListHelper alloc] initWithRows:nil];
    ds.rows = nil; // not used; override via blocks below
    objc_setAssociatedObject(panel, "ds",     ds,     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(panel, "names",  macroNames, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(panel, "macros", mutableMacros, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // Simpler approach: just use NSAlert for delete confirmation
    __weak NSPanel *wPanel = panel;
    __weak typeof(self) wSelf = self;
    delBtn.target = [NSBlockOperation blockOperationWithBlock:^{
        NSInteger row = tv.selectedRow;
        if (row < 0 || row >= (NSInteger)macroNames.count) return;
        NSString *name = macroNames[row];
        [mutableMacros removeObjectForKey:name];
        [macroNames removeObjectAtIndex:row];
        [mutableMacros writeToFile:nppMacrosPath() atomically:YES];
        [tv reloadData];
        [wSelf rebuildMacroMenu];
    }];
    delBtn.action = @selector(main);
    doneBtn.target = [NSBlockOperation blockOperationWithBlock:^{
        [NSApp stopModal]; [wPanel orderOut:nil];
    }];
    doneBtn.action = @selector(main);

    // Minimal tableview without subclassing — use raw datasource object
    // Since we can't easily set a block datasource, use a simple NSArray datasource
    // backed by the _NPPWindowsListHelper but with string rows
    NSMutableArray<NSDictionary *> *rowDicts = [NSMutableArray array];
    for (NSString *n in macroNames) [rowDicts addObject:@{@"name":n, @"path":@"", @"modified":@NO, @"mgr":@0, @"idx":@0}];
    _NPPWindowsListHelper *realDS = [[_NPPWindowsListHelper alloc] initWithRows:rowDicts];
    realDS.tableView = tv;
    tv.dataSource = realDS;
    tv.delegate = realDS;
    objc_setAssociatedObject(panel, "realDS", realDS, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [tv reloadData];

    [NSApp runModalForWindow:panel];
}

#pragma mark - Help / Debug

- (void)openNppHome:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://notepad-plus-plus.org/"]];
}
- (void)openNppProjectPage:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/notepad-plus-plus/notepad-plus-plus"]];
}
- (void)openNppManual:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://npp-user-manual.org/"]];
}
- (void)openNppForum:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://community.notepad-plus-plus.org/"]];
}

- (void)showDebugInfo:(id)sender {
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"dev";
    NSString *build   = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"?";
    NSString *os      = [[NSProcessInfo processInfo] operatingSystemVersionString];
    NSString *info    = [NSString stringWithFormat:@"Notepad++ for macOS\nVersion: %@ (build %@)\n%@", version, build, os];
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = @"Debug Info";
    a.informativeText = info;
    [a runModal];
}

#pragma mark - NSWindowDelegate

- (void)windowWillClose:(NSNotification *)n {
    [_autoSaveTimer invalidate];
    _autoSaveTimer = nil;
    [self saveWindowFrame];
    // Note: session already saved in windowShouldClose:
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    // 1. Back up all modified editors and write session.plist FIRST —
    //    before any editors are removed. This captures untitled tabs.
    [self saveSession];

    // 2. Prompt to save only named files with unsaved changes.
    for (EditorView *ed in _tabManager.allEditors.copy)
        if (ed.isModified && ed.filePath) [_tabManager closeEditor:ed];

    return YES;
}

#pragma mark - Helpers

- (void)updateTitle {
    EditorView *ed = [self currentEditor];
    NSString *name = ed ? ed.displayName : @"Notepad++";
    self.window.title = ed.isModified ? [name stringByAppendingString:@" •"] : name;
}

- (void)updateStatusBar {
    EditorView *ed = [self currentEditor];
    if (!ed) { _statusLeft.stringValue = _statusRight.stringValue = @""; return; }
    _statusLeft.stringValue  = [NSString stringWithFormat:@"Ln %ld, Col %ld  |  Lines: %ld",
                                 (long)ed.cursorLine, (long)ed.cursorColumn, (long)ed.lineCount];
    NSString *lang = ed.currentLanguage.length ? ed.currentLanguage : @"Plain Text";
    NSString *mode = ed.isOverwriteMode ? @"OVR" : @"INS";
    _statusRight.stringValue = [NSString stringWithFormat:@"%@  |  %@  |  %@  |  %@",
                                 lang, ed.encodingName, ed.eolName, mode];
}

- (void)refreshCurrentTab {
    [_tabManager refreshCurrentTabTitle];
    [self updateTitle];
}

- (void)saveWindowFrame {
    [[NSUserDefaults standardUserDefaults]
        setObject:NSStringFromRect(self.window.frame) forKey:kWindowFrameKey];
}

- (void)restoreWindowFrame {
    NSString *s = [[NSUserDefaults standardUserDefaults] stringForKey:kWindowFrameKey];
    if (s) [self.window setFrame:NSRectFromString(s) display:NO];
}

@end
