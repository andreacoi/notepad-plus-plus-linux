#import "PreferencesWindowController.h"

// ── NSUserDefaults keys (mirrors NPP settings) ────────────────────────────────
NSString *const kPrefTabWidth           = @"tabWidth";
NSString *const kPrefUseTabs            = @"useTabs";
NSString *const kPrefAutoIndent         = @"autoIndent";
NSString *const kPrefShowLineNumbers    = @"showLineNumbers";
NSString *const kPrefWordWrap           = @"wordWrap";
NSString *const kPrefHighlightCurrentLine = @"highlightCurrentLine";
NSString *const kPrefEOLType            = @"eolType";       // 0=CRLF 1=LF 2=CR
NSString *const kPrefEncoding           = @"encoding";      // 0=UTF-8 1=Latin-1
NSString *const kPrefAutoBackup         = @"autoBackup";
NSString *const kPrefBackupInterval     = @"backupInterval"; // seconds
NSString *const kPrefZoomLevel          = @"zoomLevel";

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

// ── PreferencesWindowController ───────────────────────────────────────────────

@interface PreferencesWindowController () <NSTabViewDelegate>
@end

@implementation PreferencesWindowController {
    NSTabView *_tabs;
}

+ (void)load {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        kPrefTabWidth:           @4,
        kPrefUseTabs:            @NO,
        kPrefAutoIndent:         @YES,
        kPrefShowLineNumbers:    @YES,
        kPrefWordWrap:           @NO,
        kPrefHighlightCurrentLine: @YES,
        kPrefEOLType:            @1,
        kPrefEncoding:           @0,
        kPrefAutoBackup:         @YES,
        kPrefBackupInterval:     @60,
        kPrefZoomLevel:          @0,
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
    }];
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
        initWithContentRect:NSMakeRect(0, 0, 560, 400)
                  styleMask:NSWindowStyleMaskTitled |
                            NSWindowStyleMaskClosable |
                            NSWindowStyleMaskMiniaturizable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    win.title = @"Preferences";
    self = [super initWithWindow:win];
    if (self) {
        [self registerDefaults];
        [self buildUI];
    }
    return self;
}

- (void)registerDefaults {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        kPrefTabWidth:           @4,
        kPrefUseTabs:            @NO,
        kPrefAutoIndent:         @YES,
        kPrefShowLineNumbers:    @YES,
        kPrefWordWrap:           @NO,
        kPrefHighlightCurrentLine: @YES,
        kPrefEOLType:            @1,    // LF
        kPrefEncoding:           @0,    // UTF-8
        kPrefAutoBackup:         @YES,
        kPrefBackupInterval:     @60,
    }];
}

- (void)buildUI {
    NSView *root = self.window.contentView;

    _tabs = [[NSTabView alloc] initWithFrame:NSMakeRect(10, 50, 540, 340)];
    _tabs.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    [_tabs addTabViewItem:[self buildEditorTab]];
    [_tabs addTabViewItem:[self buildNewDocTab]];
    [_tabs addTabViewItem:[self buildBackupTab]];

    [root addSubview:_tabs];

    NSButton *close = [NSButton buttonWithTitle:@"Close"
                                         target:self action:@selector(closePrefs:)];
    close.keyEquivalent = @"\033";
    close.frame = NSMakeRect(450, 12, 90, 28);
    [root addSubview:close];
}

// ── Editor tab ────────────────────────────────────────────────────────────────

- (NSTabViewItem *)buildEditorTab {
    NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:@"editor"];
    item.label = @"Editor";
    NSView *v = [[NSView alloc] init];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    CGFloat y = 270;

    // Tab size
    NSTextField *tabLabel = [NSTextField labelWithString:@"Tab size:"];
    tabLabel.frame = NSMakeRect(20, y, 80, 20);
    [v addSubview:tabLabel];

    NSTextField *tabField = [[NSTextField alloc] initWithFrame:NSMakeRect(110, y-2, 50, 22)];
    tabField.integerValue = [ud integerForKey:kPrefTabWidth];
    tabField.tag = 100;
    [v addSubview:tabField];
    y -= 30;

    // Use tabs
    NSButton *useTabs = [NSButton checkboxWithTitle:@"Use tabs (instead of spaces)"
                                             target:self action:@selector(prefChanged:)];
    useTabs.frame = NSMakeRect(20, y, 280, 20);
    useTabs.state = [ud boolForKey:kPrefUseTabs] ? NSControlStateValueOn : NSControlStateValueOff;
    useTabs.tag = 101;
    [v addSubview:useTabs];
    y -= 28;

    // Auto-indent
    NSButton *autoIndent = [NSButton checkboxWithTitle:@"Auto-indent"
                                                target:self action:@selector(prefChanged:)];
    autoIndent.frame = NSMakeRect(20, y, 280, 20);
    autoIndent.state = [ud boolForKey:kPrefAutoIndent] ? NSControlStateValueOn : NSControlStateValueOff;
    autoIndent.tag = 102;
    [v addSubview:autoIndent];
    y -= 28;

    // Show line numbers
    NSButton *lineNums = [NSButton checkboxWithTitle:@"Show line numbers"
                                              target:self action:@selector(prefChanged:)];
    lineNums.frame = NSMakeRect(20, y, 280, 20);
    lineNums.state = [ud boolForKey:kPrefShowLineNumbers] ? NSControlStateValueOn : NSControlStateValueOff;
    lineNums.tag = 103;
    [v addSubview:lineNums];
    y -= 28;

    // Word wrap
    NSButton *wordWrap = [NSButton checkboxWithTitle:@"Word wrap"
                                              target:self action:@selector(prefChanged:)];
    wordWrap.frame = NSMakeRect(20, y, 280, 20);
    wordWrap.state = [ud boolForKey:kPrefWordWrap] ? NSControlStateValueOn : NSControlStateValueOff;
    wordWrap.tag = 104;
    [v addSubview:wordWrap];
    y -= 28;

    // Highlight current line
    NSButton *hlLine = [NSButton checkboxWithTitle:@"Highlight current line"
                                            target:self action:@selector(prefChanged:)];
    hlLine.frame = NSMakeRect(20, y, 280, 20);
    hlLine.state = [ud boolForKey:kPrefHighlightCurrentLine] ? NSControlStateValueOn : NSControlStateValueOff;
    hlLine.tag = 105;
    [v addSubview:hlLine];

    item.view = v;
    return item;
}

// ── New Document tab ──────────────────────────────────────────────────────────

- (NSTabViewItem *)buildNewDocTab {
    NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:@"newdoc"];
    item.label = @"New Document";
    NSView *v = [[NSView alloc] init];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    CGFloat y = 270;

    // EOL type
    NSTextField *eolLabel = [NSTextField labelWithString:@"Default EOL:"];
    eolLabel.frame = NSMakeRect(20, y, 100, 20);
    [v addSubview:eolLabel];

    NSPopUpButton *eolPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(130, y-2, 150, 26) pullsDown:NO];
    [eolPopup addItemsWithTitles:@[@"Windows (CRLF)", @"Unix (LF)", @"Mac (CR)"]];
    [eolPopup selectItemAtIndex:[ud integerForKey:kPrefEOLType]];
    eolPopup.tag = 200;
    eolPopup.target = self;
    eolPopup.action = @selector(prefChanged:);
    [v addSubview:eolPopup];
    y -= 36;

    // Encoding
    NSTextField *encLabel = [NSTextField labelWithString:@"Default encoding:"];
    encLabel.frame = NSMakeRect(20, y, 120, 20);
    [v addSubview:encLabel];

    NSPopUpButton *encPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(150, y-2, 150, 26) pullsDown:NO];
    [encPopup addItemsWithTitles:@[@"UTF-8", @"Latin-1 (ISO-8859-1)"]];
    [encPopup selectItemAtIndex:[ud integerForKey:kPrefEncoding]];
    encPopup.tag = 201;
    encPopup.target = self;
    encPopup.action = @selector(prefChanged:);
    [v addSubview:encPopup];

    item.view = v;
    return item;
}

// ── Backup tab ────────────────────────────────────────────────────────────────

- (NSTabViewItem *)buildBackupTab {
    NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:@"backup"];
    item.label = @"Backup";
    NSView *v = [[NSView alloc] init];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    CGFloat y = 270;

    NSButton *autoBackup = [NSButton checkboxWithTitle:@"Enable auto-backup"
                                                target:self action:@selector(prefChanged:)];
    autoBackup.frame = NSMakeRect(20, y, 280, 20);
    autoBackup.state = [ud boolForKey:kPrefAutoBackup] ? NSControlStateValueOn : NSControlStateValueOff;
    autoBackup.tag = 300;
    [v addSubview:autoBackup];
    y -= 30;

    NSTextField *intLabel = [NSTextField labelWithString:@"Backup interval (seconds):"];
    intLabel.frame = NSMakeRect(20, y, 180, 20);
    [v addSubview:intLabel];

    NSTextField *intField = [[NSTextField alloc] initWithFrame:NSMakeRect(210, y-2, 60, 22)];
    intField.integerValue = [ud integerForKey:kPrefBackupInterval];
    intField.tag = 301;
    [v addSubview:intField];
    y -= 36;

    NSTextField *backupDirLabel = [NSTextField labelWithString:@"Backup location:"];
    backupDirLabel.frame = NSMakeRect(20, y, 120, 20);
    [v addSubview:backupDirLabel];
    y -= 20;

    NSTextField *backupPath = [NSTextField labelWithString:
        [NSHomeDirectory() stringByAppendingPathComponent:@".notepad++/backup/"]];
    backupPath.frame = NSMakeRect(20, y, 500, 20);
    backupPath.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    [v addSubview:backupPath];

    item.view = v;
    return item;
}

// ── Actions ───────────────────────────────────────────────────────────────────

- (void)prefChanged:(id)sender {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSInteger tag = [(NSControl *)sender tag];

    switch (tag) {
        case 100: [ud setInteger:[(NSTextField *)sender integerValue] forKey:kPrefTabWidth]; break;
        case 101: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefUseTabs]; break;
        case 102: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefAutoIndent]; break;
        case 103: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefShowLineNumbers]; break;
        case 104: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefWordWrap]; break;
        case 105: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefHighlightCurrentLine]; break;
        case 200: [ud setInteger:[(NSPopUpButton *)sender indexOfSelectedItem] forKey:kPrefEOLType]; break;
        case 201: [ud setInteger:[(NSPopUpButton *)sender indexOfSelectedItem] forKey:kPrefEncoding]; break;
        case 300: [ud setBool:[(NSButton *)sender state] == NSControlStateValueOn forKey:kPrefAutoBackup]; break;
        case 301: [ud setInteger:[(NSTextField *)sender integerValue] forKey:kPrefBackupInterval]; break;
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:@"NPPPreferencesChanged" object:nil];
}

- (void)closePrefs:(id)sender {
    [self.window orderOut:nil];
}

@end
