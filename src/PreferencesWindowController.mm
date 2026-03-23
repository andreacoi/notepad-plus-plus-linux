#import "PreferencesWindowController.h"
#import "NppLocalizer.h"

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
NSString *const kPrefSpellCheck         = @"spellCheck";
NSString *const kPrefAutoCompleteEnable  = @"autoCompleteEnable";
NSString *const kPrefAutoCompleteMinChars = @"autoCompleteMinChars";

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
    NSTabView   *_tabs;
    NSPopUpButton *_languagePopup;  // General tab — language selector
}

+ (void)load {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        kPrefTabWidth:           @4,
        kPrefUseTabs:            @YES,
        kPrefAutoIndent:         @YES,
        kPrefShowLineNumbers:    @YES,
        kPrefWordWrap:           @NO,
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
    }];
    // Force-upgrade any stale @NO value stored by earlier builds.
    // registerDefaults: only fills in missing keys, so previously-stored @NO
    // would silently override the new default. Remove the key so the
    // registered default (@YES) takes effect — users can still change it via Prefs.
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (![ud objectForKey:kPrefUseTabs]) {
        // Key absent — registered default will be used, nothing to do.
    } else if ([ud objectForKey:@"_useTabsDefaultApplied"] == nil) {
        // First run after default change: override stored value and mark done.
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
    // Tab labels
    NSArray *tabKeys = @[@"General", @"Editor", @"New Document", @"Backup"];
    for (NSUInteger i = 0; i < tabKeys.count && i < _tabs.numberOfTabViewItems; i++) {
        [_tabs tabViewItemAtIndex:i].label = [loc translate:tabKeys[i]];
    }
}

- (void)registerDefaults {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        kPrefTabWidth:           @4,
        kPrefUseTabs:            @YES,
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

    [_tabs addTabViewItem:[self buildGeneralTab]];
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

// ── General tab ───────────────────────────────────────────────────────────────

- (NSTabViewItem *)buildGeneralTab {
    NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:@"general"];
    item.label = @"General";
    NSView *v = [[NSView alloc] init];
    CGFloat y = 270;

    // ── Localization section ──────────────────────────────────────────────────
    NSTextField *sectionLabel = [NSTextField labelWithString:@"Localization"];
    sectionLabel.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
    sectionLabel.frame = NSMakeRect(20, y, 200, 20);
    [v addSubview:sectionLabel];
    y -= 30;

    NSTextField *langLabel = [NSTextField labelWithString:@"Language:"];
    langLabel.frame = NSMakeRect(20, y, 90, 20);
    [v addSubview:langLabel];

    _languagePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(120, y - 2, 250, 26)
                                               pullsDown:NO];
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
    hint.frame = NSMakeRect(20, y - 16, 500, 44);
    [v addSubview:hint];

    item.view = v;
    return item;
}

/// Populate _languagePopup from all available language names, selecting the
/// currently active language.
- (void)_rebuildLanguagePopup {
    if (!_languagePopup) return;

    NSDictionary<NSString *, NSString *> *langMap = [NppLocalizer availableLanguagesMap];
    NSArray<NSString *> *names = [[langMap allKeys]
        sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

    [_languagePopup removeAllItems];
    [_languagePopup addItemsWithTitles:names];

    // Select the current language.
    NSString *currentFile = [NppLocalizer shared].currentLanguageFile;
    for (NSString *name in names) {
        if ([langMap[name].lowercaseString isEqualToString:currentFile.lowercaseString]) {
            [_languagePopup selectItemWithTitle:name];
            break;
        }
    }
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
        case 400: {
            // Language / localization change.
            NSPopUpButton *popup = (NSPopUpButton *)sender;
            NSString *selectedName = popup.selectedItem.title;
            if (selectedName.length > 0) {
                NSDictionary *langMap = [NppLocalizer availableLanguagesMap];
                NSString *stem = langMap[selectedName];
                if (stem) {
                    [[NppLocalizer shared] loadLanguageNamed:stem];
                    // NppLocalizer saves kPrefLanguage and posts NPPLocalizationChanged.
                }
            }
            return; // NppLocalizer already posts NPPPreferencesChanged via NPPLocalizationChanged
        }
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:@"NPPPreferencesChanged" object:nil];
}

- (void)closePrefs:(id)sender {
    [self.window orderOut:nil];
}

@end
