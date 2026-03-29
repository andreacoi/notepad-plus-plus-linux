#import "ShortcutMapperWindowController.h"
#import "NppPluginManager.h"

NSNotificationName const NPPShortcutsChangedNotification = @"NPPShortcutsChangedNotification";

// ═══════════════════════════════════════════════════════════════════════════════
// ShortcutEntry — one row in the table
// ═══════════════════════════════════════════════════════════════════════════════

@interface ShortcutEntry : NSObject
@property (copy)   NSString *name;
@property (copy)   NSString *shortcutDisplay;   // e.g. "Cmd+Shift+S"
@property (copy)   NSString *category;          // "File", "Edit", etc. (Main Menu only)
@property (copy)   NSString *pluginName;        // Plugin tab only
@property (assign) BOOL hasCtrl, hasAlt, hasShift, hasCmd;
@property (assign) NSUInteger keyCode;          // 0 = none
@property (assign) NSInteger  commandID;        // IDM_* or SCI_* or index
@property (copy, nullable) NSString *selectorName; // macOS selector string
@property (assign) BOOL isModified;             // user changed from default
@end

@implementation ShortcutEntry
- (void)updateDisplay {
    if (_keyCode == 0) { _shortcutDisplay = @""; return; }
    // macOS native symbol display: ⌃⌥⇧⌘ + key
    NSMutableString *s = [NSMutableString string];
    if (_hasCtrl)  [s appendString:@"\u2303"];  // ⌃
    if (_hasAlt)   [s appendString:@"\u2325"];  // ⌥
    if (_hasShift) [s appendString:@"\u21E7"];  // ⇧
    if (_hasCmd)   [s appendString:@"\u2318"];  // ⌘
    [s appendString:[ShortcutEntry keyNameForCode:_keyCode]];
    _shortcutDisplay = [s copy];
}

+ (NSString *)keyNameForCode:(NSUInteger)code {
    if (code >= 'A' && code <= 'Z') return [NSString stringWithFormat:@"%c", (char)code];
    if (code >= '0' && code <= '9') return [NSString stringWithFormat:@"%c", (char)code];
    // Windows VK function key codes (112-123 = F1-F12)
    if (code >= 112 && code <= 123) return [NSString stringWithFormat:@"F%lu", (unsigned long)(code - 111)];
    // macOS NSFunctionKey values (0xF704-0xF70F = F1-F12)
    if (code >= 0xF704 && code <= 0xF70F) return [NSString stringWithFormat:@"F%lu", (unsigned long)(code - 0xF704 + 1)];
    // macOS NSFunctionKey values (0xF710-0xF71B = F13-F24)
    if (code >= 0xF710 && code <= 0xF71B) return [NSString stringWithFormat:@"F%lu", (unsigned long)(code - 0xF710 + 13)];
    switch (code) {
        case 8:   return @"\u232B"; // ⌫ Backspace
        case 9:   return @"\u21E5"; // ⇥ Tab
        case 13:  return @"\u21A9"; // ↩ Enter
        case 27:  return @"\u238B"; // ⎋ Escape
        case 32:  return @"\u2423"; // ␣ Space
        case 33:  return @"\u21DE"; // ⇞ Page Up
        case 34:  return @"\u21DF"; // ⇟ Page Down
        case 35:  return @"\u2198"; // ↘ End
        case 36:  return @"\u2196"; // ↖ Home
        case 37:  return @"\u2190"; // ← Left
        case 38:  return @"\u2191"; // ↑ Up
        case 39:  return @"\u2192"; // → Right
        case 40:  return @"\u2193"; // ↓ Down
        case 45:  return @"Ins";
        case 46:  return @"\u2326"; // ⌦ Delete
        case 186: return @";";
        case 187: return @"=";
        case 188: return @",";
        case 189: return @"-";
        case 190: return @".";
        case 191: return @"/";
        case 192: return @"`";
        case 219: return @"[";
        case 220: return @"\\";
        case 221: return @"]";
        case 222: return @"'";
        // macOS special key unicodes
        case 0xF728: return @"\u2326"; // ⌦ Forward Delete
        case 0xF729: return @"\u2196"; // ↖ Home
        case 0xF72B: return @"\u2198"; // ↘ End
        case 0xF72C: return @"\u21DE"; // ⇞ Page Up
        case 0xF72D: return @"\u21DF"; // ⇟ Page Down
        case 0xF702: return @"\u2190"; // ← Left
        case 0xF703: return @"\u2192"; // → Right
        case 0xF700: return @"\u2191"; // ↑ Up
        case 0xF701: return @"\u2193"; // ↓ Down
        default:  return [NSString stringWithFormat:@"0x%lX", (unsigned long)code];
    }
}

+ (NSArray<NSString *> *)allKeyNames {
    NSMutableArray *keys = [NSMutableArray arrayWithObject:@"None"];
    for (unichar c = 'A'; c <= 'Z'; c++) [keys addObject:[NSString stringWithFormat:@"%c", c]];
    for (unichar c = '0'; c <= '9'; c++) [keys addObject:[NSString stringWithFormat:@"%c", c]];
    for (int i = 1; i <= 12; i++) [keys addObject:[NSString stringWithFormat:@"F%d", i]];
    [keys addObjectsFromArray:@[@"Backspace", @"Tab", @"Enter", @"Escape", @"Space",
        @"Page Up", @"Page Down", @"End", @"Home", @"Left", @"Up", @"Right", @"Down",
        @"Insert", @"Delete", @";", @"=", @",", @"-", @".", @"/", @"`", @"[", @"\\", @"]", @"'"]];
    return keys;
}

+ (NSUInteger)keyCodeForName:(NSString *)name {
    if ([name isEqualToString:@"None"] || name.length == 0) return 0;
    if (name.length == 1) return [name characterAtIndex:0];
    if ([name hasPrefix:@"F"] && name.length <= 3) return 111 + [name substringFromIndex:1].intValue;
    NSDictionary *map = @{@"Backspace":@8, @"Tab":@9, @"Enter":@13, @"Escape":@27, @"Space":@32,
        @"Page Up":@33, @"Page Down":@34, @"End":@35, @"Home":@36, @"Left":@37, @"Up":@38,
        @"Right":@39, @"Down":@40, @"Insert":@45, @"Delete":@46, @";":@186, @"=":@187,
        @",":@188, @"-":@189, @".":@190, @"/":@191, @"`":@192, @"[":@219, @"\\":@220,
        @"]":@221, @"'":@222};
    return [map[name] unsignedIntegerValue];
}
@end

// ═══════════════════════════════════════════════════════════════════════════════
// ShortcutMapperWindowController
// ═══════════════════════════════════════════════════════════════════════════════

@interface ShortcutMapperWindowController () <NSTableViewDataSource, NSTableViewDelegate, NSControlTextEditingDelegate, NSWindowDelegate>
@end

@implementation ShortcutMapperWindowController {
    NSSegmentedControl *_segControl;
    NSTableView     *_tableView;
    NSScrollView    *_scrollView;
    NSTextField     *_filterField;
    NSTextField     *_conflictInfo;
    NSButton        *_modifyBtn, *_clearBtn, *_deleteBtn, *_closeBtn;

    // Data for each tab
    NSMutableArray<ShortcutEntry *> *_mainMenuEntries;
    NSMutableArray<ShortcutEntry *> *_macroEntries;
    NSMutableArray<ShortcutEntry *> *_runCmdEntries;
    NSMutableArray<ShortcutEntry *> *_pluginEntries;
    NSMutableArray<ShortcutEntry *> *_scintillaEntries;

    // Filtered view
    NSMutableArray<ShortcutEntry *> *_filteredEntries;
    ShortcutMapperTab _currentTab;
    BOOL _saved;
    BOOL _hasChanges;  // only save if user actually modified something
}

- (instancetype)init {
    NSWindow *win = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 820, 560)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    win.title = @"Shortcut Mapper";
    win.minSize = NSMakeSize(600, 400);
    [win center];

    self = [super initWithWindow:win];
    if (self) {
        win.delegate = self;
        [self _buildUI];
        [self _loadAllData];
        [self _switchToTab:ShortcutMapperTabMainMenu];
    }
    return self;
}

- (void)showWithTab:(ShortcutMapperTab)tab {
    [self _switchToTab:tab];
    [self showWindow:nil];
}

// ═══════════════════════════════════════════════════════════════════════════════
// UI Construction
// ═══════════════════════════════════════════════════════════════════════════════

- (void)_buildUI {
    NSView *cv = self.window.contentView;

    // Segmented control for tabs (matching Windows tab bar appearance)
    NSSegmentedControl *seg = [NSSegmentedControl segmentedControlWithLabels:
        @[@"Main menu", @"Macros", @"Run commands", @"Plugin commands", @"Scintilla commands"]
        trackingMode:NSSegmentSwitchTrackingSelectOne
        target:self action:@selector(_tabSegmentChanged:)];
    seg.translatesAutoresizingMaskIntoConstraints = NO;
    seg.selectedSegment = 0;
    seg.segmentStyle = NSSegmentStyleTexturedSquare;
    [cv addSubview:seg];
    _segControl = seg;

    // Table view inside scroll view
    _tableView = [[NSTableView alloc] init];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = 20;
    _tableView.allowsMultipleSelection = NO;
    _tableView.usesAlternatingRowBackgroundColors = YES;
    _tableView.target = self;
    _tableView.doubleAction = @selector(_modifyShortcut:);
    _tableView.gridStyleMask = NSTableViewSolidHorizontalGridLineMask | NSTableViewSolidVerticalGridLineMask;

    // Row number column
    NSTableColumn *numCol = [[NSTableColumn alloc] initWithIdentifier:@"num"];
    numCol.title = @"";
    numCol.width = 30;
    numCol.minWidth = 30;
    numCol.maxWidth = 40;
    [_tableView addTableColumn:numCol];

    NSTableColumn *nameCol = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameCol.title = @"Name";
    nameCol.width = 350;
    nameCol.resizingMask = NSTableColumnAutoresizingMask;
    [nameCol.headerCell setFont:[NSFont boldSystemFontOfSize:13]];
    [_tableView addTableColumn:nameCol];

    NSTableColumn *shortcutCol = [[NSTableColumn alloc] initWithIdentifier:@"shortcut"];
    shortcutCol.title = @"Shortcut";
    shortcutCol.width = 180;
    [shortcutCol.headerCell setFont:[NSFont boldSystemFontOfSize:13]];
    [_tableView addTableColumn:shortcutCol];

    NSTableColumn *catCol = [[NSTableColumn alloc] initWithIdentifier:@"category"];
    catCol.title = @"Category";
    catCol.width = 150;
    [catCol.headerCell setFont:[NSFont boldSystemFontOfSize:13]];
    [_tableView addTableColumn:catCol];

    _scrollView = [[NSScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.borderType = NSBezelBorder;
    _scrollView.documentView = _tableView;
    [cv addSubview:_scrollView];

    // Conflict info
    _conflictInfo = [[NSTextField alloc] init];
    _conflictInfo.translatesAutoresizingMaskIntoConstraints = NO;
    _conflictInfo.editable = NO;
    _conflictInfo.bordered = YES;
    _conflictInfo.bezeled = YES;
    _conflictInfo.bezelStyle = NSTextFieldSquareBezel;
    _conflictInfo.font = [NSFont systemFontOfSize:11];
    _conflictInfo.stringValue = @"No shortcut conflicts for this item.";
    [cv addSubview:_conflictInfo];

    // Filter
    NSTextField *filterLabel = [NSTextField labelWithString:@"Filter:"];
    filterLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [cv addSubview:filterLabel];

    _filterField = [[NSTextField alloc] init];
    _filterField.translatesAutoresizingMaskIntoConstraints = NO;
    _filterField.placeholderString = @"Type to filter...";
    _filterField.delegate = (id<NSTextFieldDelegate>)self;
    [cv addSubview:_filterField];

    // Buttons
    _modifyBtn = [NSButton buttonWithTitle:@"Modify" target:self action:@selector(_modifyShortcut:)];
    _clearBtn  = [NSButton buttonWithTitle:@"Clear"  target:self action:@selector(_clearShortcut:)];
    _deleteBtn = [NSButton buttonWithTitle:@"Delete" target:self action:@selector(_deleteShortcut:)];
    _closeBtn  = [NSButton buttonWithTitle:@"Close"  target:self action:@selector(_close:)];
    _closeBtn.keyEquivalent = @"\r";
    for (NSButton *b in @[_modifyBtn, _clearBtn, _deleteBtn, _closeBtn]) {
        b.translatesAutoresizingMaskIntoConstraints = NO;
        b.bezelStyle = NSBezelStyleRounded;
        [cv addSubview:b];
    }

    // Layout
    [NSLayoutConstraint activateConstraints:@[
        [seg.topAnchor constraintEqualToAnchor:cv.topAnchor constant:10],
        [seg.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:10],

        [_scrollView.topAnchor constraintEqualToAnchor:seg.bottomAnchor constant:6],
        [_scrollView.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:10],
        [_scrollView.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-10],
        [_scrollView.bottomAnchor constraintEqualToAnchor:_conflictInfo.topAnchor constant:-8],

        [_conflictInfo.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:10],
        [_conflictInfo.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-10],
        [_conflictInfo.heightAnchor constraintEqualToConstant:40],
        [_conflictInfo.bottomAnchor constraintEqualToAnchor:filterLabel.topAnchor constant:-6],

        [filterLabel.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:10],
        [filterLabel.centerYAnchor constraintEqualToAnchor:_filterField.centerYAnchor],
        [_filterField.leadingAnchor constraintEqualToAnchor:filterLabel.trailingAnchor constant:4],
        [_filterField.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-10],
        [_filterField.bottomAnchor constraintEqualToAnchor:_modifyBtn.topAnchor constant:-10],
        [_filterField.heightAnchor constraintEqualToConstant:22],

        [_closeBtn.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-10],
        [_closeBtn.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-10],
        [_closeBtn.widthAnchor constraintEqualToConstant:80],
        [_deleteBtn.trailingAnchor constraintEqualToAnchor:_closeBtn.leadingAnchor constant:-8],
        [_deleteBtn.bottomAnchor constraintEqualToAnchor:_closeBtn.bottomAnchor],
        [_deleteBtn.widthAnchor constraintEqualToConstant:80],
        [_clearBtn.trailingAnchor constraintEqualToAnchor:_deleteBtn.leadingAnchor constant:-8],
        [_clearBtn.bottomAnchor constraintEqualToAnchor:_closeBtn.bottomAnchor],
        [_clearBtn.widthAnchor constraintEqualToConstant:80],
        [_modifyBtn.trailingAnchor constraintEqualToAnchor:_clearBtn.leadingAnchor constant:-8],
        [_modifyBtn.bottomAnchor constraintEqualToAnchor:_closeBtn.bottomAnchor],
        [_modifyBtn.widthAnchor constraintEqualToConstant:80],
    ]];
}

- (void)_tabSegmentChanged:(NSSegmentedControl *)seg {
    [self _switchToTab:(ShortcutMapperTab)seg.selectedSegment];
}

// ═══════════════════════════════════════════════════════════════════════════════
// Data Loading
// ═══════════════════════════════════════════════════════════════════════════════

- (void)_loadAllData {
    [self _loadMainMenuEntries];
    [self _loadMacroEntries];
    [self _loadRunCommandEntries];
    [self _loadPluginEntries];
    [self _loadScintillaEntries];
}

/// Walk the live application menu recursively to build the Main Menu tab data.
- (void)_loadMainMenuEntries {
    _mainMenuEntries = [NSMutableArray array];
    NSMenu *mainMenu = [NSApp mainMenu];
    NSLog(@"[ShortcutMapper] Main menu top-level items: %ld", (long)mainMenu.numberOfItems);

    for (NSUInteger i = 0; i < mainMenu.itemArray.count; i++) {
        NSMenuItem *topItem = mainMenu.itemArray[i];
        // Skip the Apple/App menu (always index 0)
        if (i == 0) continue;
        if (!topItem.submenu) continue;

        // The menu name is the submenu's title (topItem.title may return class name)
        NSString *category = topItem.submenu.title;
        if (!category.length) category = topItem.title;
        if (!category.length || [category isEqualToString:@"NSMenuItem"]) category = @"Other";

        @try {
            // Force the submenu to populate
            [topItem.submenu update];
            NSUInteger before = _mainMenuEntries.count;
            [self _walkMenu:topItem.submenu category:category];
            NSLog(@"[ShortcutMapper]   %@ (%lu → %lu items, submenu has %ld items)",
                  category, (unsigned long)before, (unsigned long)_mainMenuEntries.count,
                  (long)topItem.submenu.numberOfItems);
        } @catch (NSException *ex) {
            NSLog(@"[ShortcutMapper] EXCEPTION walking %@: %@", category, ex);
        }
    }
    // Mark entries that have overrides in shortcuts.xml as isModified
    // so they'll be preserved on save
    NSString *scPath = [NSHomeDirectory() stringByAppendingPathComponent:@".notepad++/shortcuts.xml"];
    NSData *scData = [NSData dataWithContentsOfFile:scPath];
    if (scData) {
        NSXMLDocument *scDoc = [[NSXMLDocument alloc] initWithData:scData options:0 error:nil];
        if (scDoc) {
            NSArray *overrides = [scDoc nodesForXPath:@"//InternalCommands/Shortcut" error:nil];
            NSMutableSet *overriddenSelectors = [NSMutableSet set];
            for (NSXMLElement *sc in overrides) {
                NSString *selId = [[sc attributeForName:@"id"] stringValue];
                if (selId.length) [overriddenSelectors addObject:selId];
            }
            for (ShortcutEntry *e in _mainMenuEntries) {
                if (e.selectorName && [overriddenSelectors containsObject:e.selectorName]) {
                    e.isModified = YES;
                }
            }
            NSLog(@"[ShortcutMapper] Marked %lu entries as having overrides", (unsigned long)overriddenSelectors.count);
        }
    }

    NSLog(@"[ShortcutMapper] Main menu total: %lu entries", (unsigned long)_mainMenuEntries.count);
}

- (void)_walkMenu:(NSMenu *)menu category:(NSString *)category {
    // Selectors to skip (dynamic/non-command items)
    static NSSet *skipSelectors;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        skipSelectors = [NSSet setWithObjects:
            @"openRecentFile:", @"runSavedMacro:", @"pluginMenuAction:",
            @"pluginToolbarAction:", @"submenuAction:", @"_showAllCharsDropdown:",
            @"orderFrontStandardAboutPanel:", @"hide:", @"hideOtherApplications:",
            @"unhideAllApplications:", @"terminate:", @"performMiniaturize:",
            @"performZoom:", @"toggleFullScreen:", @"arrangeInFront:",
            nil];
    });

    for (NSMenuItem *mi in menu.itemArray) {
        if (mi.isSeparatorItem) continue;
        if (mi.submenu) {
            [mi.submenu update]; // force populate lazy submenus
            [self _walkMenu:mi.submenu category:category];
            continue;
        }
        if (!mi.action) continue;

        // Skip dynamic/system items
        NSString *selName = NSStringFromSelector(mi.action);
        if ([skipSelectors containsObject:selName]) continue;
        // Skip empty-titled items
        if (mi.title.length == 0) continue;

        ShortcutEntry *e = [[ShortcutEntry alloc] init];
        e.name = mi.title;
        e.category = category;
        e.selectorName = NSStringFromSelector(mi.action);
        e.commandID = mi.tag;

        // Extract current key equivalent
        NSString *key = mi.keyEquivalent;
        NSEventModifierFlags mods = mi.keyEquivalentModifierMask;
        if (key.length > 0 && [key characterAtIndex:0] > 32) {
            e.hasCmd   = (mods & NSEventModifierFlagCommand) != 0;
            e.hasCtrl  = (mods & NSEventModifierFlagControl) != 0;
            e.hasAlt   = (mods & NSEventModifierFlagOption)  != 0;
            e.hasShift = (mods & NSEventModifierFlagShift)   != 0;
            unichar c = [key.uppercaseString characterAtIndex:0];
            e.keyCode = c;
        } else if (key.length > 0) {
            // Function keys and special keys
            unichar c = [key characterAtIndex:0];
            e.hasCmd   = (mods & NSEventModifierFlagCommand) != 0;
            e.hasCtrl  = (mods & NSEventModifierFlagControl) != 0;
            e.hasAlt   = (mods & NSEventModifierFlagOption)  != 0;
            e.hasShift = (mods & NSEventModifierFlagShift)   != 0;
            // Map NSFunctionKey characters to Windows VK codes
            if (c >= NSF1FunctionKey && c <= NSF12FunctionKey)
                e.keyCode = 112 + (c - NSF1FunctionKey);
            else
                e.keyCode = c;
        }
        [e updateDisplay];
        [_mainMenuEntries addObject:e];
    }
}

- (void)_loadMacroEntries {
    _macroEntries = [NSMutableArray array];
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@".notepad++/shortcuts.xml"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return;
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:data options:0 error:nil];
    if (!doc) return;
    for (NSXMLElement *el in [doc nodesForXPath:@"//Macros/Macro" error:nil]) {
        ShortcutEntry *e = [[ShortcutEntry alloc] init];
        e.name = [[el attributeForName:@"name"] stringValue] ?: @"";
        e.hasCtrl  = [[[el attributeForName:@"Ctrl"]  stringValue] isEqualToString:@"yes"];
        e.hasAlt   = [[[el attributeForName:@"Alt"]   stringValue] isEqualToString:@"yes"];
        e.hasShift = [[[el attributeForName:@"Shift"] stringValue] isEqualToString:@"yes"];
        e.keyCode  = [[[el attributeForName:@"Key"]   stringValue] integerValue];
        // Map Windows Ctrl to macOS Cmd for display
        if (e.hasCtrl) { e.hasCmd = YES; e.hasCtrl = NO; }
        [e updateDisplay];
        [_macroEntries addObject:e];
    }
    NSLog(@"[ShortcutMapper] Macros: %lu entries", (unsigned long)_macroEntries.count);
}

- (void)_loadRunCommandEntries {
    _runCmdEntries = [NSMutableArray array];

    // Load from shortcuts.xml <UserDefinedCommands> only (matches Windows behavior)
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@".notepad++/shortcuts.xml"];
    NSData *data = [NSData dataWithContentsOfFile:path];

    // If no UserDefinedCommands exist in shortcuts.xml, create defaults
    BOOL hasUserCmds = NO;
    if (data) {
        NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:data options:0 error:nil];
        if (doc) {
            NSArray *cmds = [doc nodesForXPath:@"//UserDefinedCommands/Command" error:nil];
            hasUserCmds = (cmds.count > 0);
            for (NSXMLElement *el in cmds) {
                ShortcutEntry *e = [[ShortcutEntry alloc] init];
                e.name = [[el attributeForName:@"name"] stringValue] ?: @"";
                e.hasCtrl  = [[[el attributeForName:@"Ctrl"]  stringValue] isEqualToString:@"yes"];
                e.hasAlt   = [[[el attributeForName:@"Alt"]   stringValue] isEqualToString:@"yes"];
                e.hasShift = [[[el attributeForName:@"Shift"] stringValue] isEqualToString:@"yes"];
                e.keyCode  = [[[el attributeForName:@"Key"]   stringValue] integerValue];
                if (e.hasCtrl) { e.hasCmd = YES; e.hasCtrl = NO; }
                [e updateDisplay];
                [_runCmdEntries addObject:e];
            }
        }
    }

    // Default entries come from the bundled shortcuts.xml (copied to ~/.notepad++/ on first run)
    NSLog(@"[ShortcutMapper] Run commands: %lu entries", (unsigned long)_runCmdEntries.count);
}

- (void)_loadPluginEntries {
    _pluginEntries = [NSMutableArray array];
    // Walk the Plugins menu to extract plugin commands
    NSMenu *mainMenu = [NSApp mainMenu];
    for (NSMenuItem *topItem in mainMenu.itemArray) {
        NSString *menuTitle = topItem.submenu.title ?: topItem.title;
        if (![menuTitle isEqualToString:@"Plugins"]) continue;
        [topItem.submenu update];
        for (NSMenuItem *pluginItem in topItem.submenu.itemArray) {
            if (pluginItem.isSeparatorItem) continue;
            if (!pluginItem.submenu) continue;
            NSString *plugName = pluginItem.title;
            if (!plugName.length) continue;
            [pluginItem.submenu update];
            for (NSMenuItem *cmdItem in pluginItem.submenu.itemArray) {
                if (cmdItem.isSeparatorItem || !cmdItem.action) continue;
                if (!cmdItem.title.length) continue;
                // Skip separator-like items (some plugins use "-" as menu item title)
                // Skip separator-like items (plugins use "-" as title for separators)
                NSString *trimmed = [cmdItem.title stringByTrimmingCharactersInSet:
                    [NSCharacterSet characterSetWithCharactersInString:@"- "]];
                if (trimmed.length == 0) continue;
                ShortcutEntry *e = [[ShortcutEntry alloc] init];
                e.name = cmdItem.title;
                e.pluginName = plugName;
                e.commandID = cmdItem.tag;
                e.selectorName = NSStringFromSelector(cmdItem.action);
                // Extract key
                NSString *key = cmdItem.keyEquivalent;
                NSEventModifierFlags mods = cmdItem.keyEquivalentModifierMask;
                if (key.length > 0 && [key characterAtIndex:0] > 32) {
                    e.hasCmd   = (mods & NSEventModifierFlagCommand) != 0;
                    e.hasCtrl  = (mods & NSEventModifierFlagControl) != 0;
                    e.hasAlt   = (mods & NSEventModifierFlagOption)  != 0;
                    e.hasShift = (mods & NSEventModifierFlagShift)   != 0;
                    e.keyCode  = [key.uppercaseString characterAtIndex:0];
                }
                [e updateDisplay];
                [_pluginEntries addObject:e];
            }
        }
        break;
    }
    NSLog(@"[ShortcutMapper] Plugin commands: %lu entries", (unsigned long)_pluginEntries.count);
}

- (void)_loadScintillaEntries {
    _scintillaEntries = [NSMutableArray array];
    // Hardcoded Scintilla command definitions matching Windows scintKeyDefs[]
    struct SciKeyDef { const char *name; int sciID; BOOL ctrl; BOOL alt; BOOL shift; int key; };
    static const struct SciKeyDef defs[] = {
        {"SCI_SELECTALL",            2013, YES, NO,  NO,  'A'},
        {"SCI_CLEAR",                2180, NO,  NO,  NO,  46},  // Delete
        {"SCI_CLEARALL",             2004, NO,  NO,  NO,  0},
        {"SCI_UNDO",                 2176, YES, NO,  NO,  'Z'},
        {"SCI_REDO",                 2011, YES, NO,  YES, 'Z'},
        {"SCI_NEWLINE",              2329, NO,  NO,  NO,  13},  // Enter
        {"SCI_TAB",                  2327, NO,  NO,  NO,  9},
        {"SCI_BACKTAB",              2328, NO,  NO,  YES, 9},
        {"SCI_FORMFEED",             2330, NO,  NO,  NO,  0},
        {"SCI_ZOOMIN",               2333, YES, NO,  NO,  187}, // =
        {"SCI_ZOOMOUT",              2334, YES, NO,  NO,  189}, // -
        {"SCI_SETZOOM",              2373, YES, NO,  NO,  191}, // /
        {"SCI_SELECTIONDUPLICATE",   2469, YES, NO,  NO,  'D'},
        {"SCI_LINESJOIN",            2288, NO,  NO,  NO,  0},
        {"SCI_SCROLLCARET",          2169, NO,  NO,  NO,  0},
        {"SCI_EDITTOGGLEOVERTYPE",   2324, NO,  NO,  NO,  45},  // Insert
        {"SCI_MOVECARETINSIDEVIEW",  2401, NO,  NO,  NO,  0},
        {"SCI_LINEDOWN",             2300, NO,  NO,  NO,  40},  // Down
        {"SCI_LINEDOWNEXTEND",       2301, NO,  NO,  YES, 40},
        {"SCI_LINESCROLLDOWN",       2342, YES, NO,  NO,  40},
        {"SCI_LINEUP",               2302, NO,  NO,  NO,  38},  // Up
        {"SCI_LINEUPEXTEND",         2303, NO,  NO,  YES, 38},
        {"SCI_LINESCROLLUP",         2343, YES, NO,  NO,  38},
        {"SCI_PARADOWN",             2413, YES, NO,  NO,  221}, // ]
        {"SCI_PARADOWNEXTEND",       2414, YES, NO,  YES, 221},
        {"SCI_PARAUP",               2415, YES, NO,  NO,  219}, // [
        {"SCI_PARAUPEXTEND",         2416, YES, NO,  YES, 219},
        {"SCI_CHARLEFT",             2304, NO,  NO,  NO,  37},  // Left
        {"SCI_CHARLEFTEXTEND",       2305, NO,  NO,  YES, 37},
        {"SCI_CHARRIGHT",            2306, NO,  NO,  NO,  39},  // Right
        {"SCI_CHARRIGHTEXTEND",      2307, NO,  NO,  YES, 39},
        {"SCI_WORDLEFT",             2308, YES, NO,  NO,  37},
        {"SCI_WORDLEFTEXTEND",       2309, YES, NO,  YES, 37},
        {"SCI_WORDRIGHT",            2310, YES, NO,  NO,  39},
        {"SCI_WORDRIGHTEXTEND",      2311, YES, NO,  YES, 39},
        {"SCI_WORDPARTLEFT",         2390, YES, NO,  NO,  191},
        {"SCI_WORDPARTLEFTEXTEND",   2391, YES, NO,  YES, 191},
        {"SCI_WORDPARTRIGHT",        2392, YES, NO,  NO,  220},
        {"SCI_WORDPARTRIGHTEXTEND",  2393, YES, NO,  YES, 220},
        {"SCI_HOME",                 2312, NO,  NO,  NO,  36},
        {"SCI_HOMEEXTEND",           2313, NO,  NO,  YES, 36},
        {"SCI_VCHOME",               2331, NO,  NO,  NO,  0},
        {"SCI_VCHOMEEXTEND",         2332, NO,  NO,  NO,  0},
        {"SCI_LINEEND",              2314, NO,  NO,  NO,  35},
        {"SCI_LINEENDEXTEND",        2315, NO,  NO,  YES, 35},
        {"SCI_DOCUMENTSTART",        2316, YES, NO,  NO,  36},
        {"SCI_DOCUMENTSTARTEXTEND",  2317, YES, NO,  YES, 36},
        {"SCI_DOCUMENTEND",          2318, YES, NO,  NO,  35},
        {"SCI_DOCUMENTENDEXTEND",    2319, YES, NO,  YES, 35},
        {"SCI_PAGEUP",               2320, NO,  NO,  NO,  33},
        {"SCI_PAGEUPEXTEND",         2321, NO,  NO,  YES, 33},
        {"SCI_PAGEDOWN",             2322, NO,  NO,  NO,  34},
        {"SCI_PAGEDOWNEXTEND",       2323, NO,  NO,  YES, 34},
        {"SCI_DELETEBACK",           2326, NO,  NO,  NO,  8},
        {"SCI_DELETEBACKNOTLINE",    2344, NO,  NO,  NO,  0},
        {"SCI_DELWORDLEFT",          2335, YES, NO,  NO,  8},
        {"SCI_DELWORDRIGHT",         2336, YES, NO,  NO,  46},
        {"SCI_DELLINELEFT",          2395, YES, NO,  YES, 8},
        {"SCI_DELLINERIGHT",         2396, YES, NO,  YES, 46},
        {"SCI_LINEDELETE",           2338, YES, NO,  YES, 'L'},
        {"SCI_LINECUT",              2337, YES, NO,  NO,  'L'},
        {"SCI_LINECOPY",             2455, YES, NO,  YES, 'X'},
        {"SCI_LINETRANSPOSE",        2339, YES, NO,  NO,  'T'},
        {"SCI_CUT",                  2177, YES, NO,  NO,  'X'},
        {"SCI_COPY",                 2178, YES, NO,  NO,  'C'},
        {"SCI_PASTE",                2179, YES, NO,  NO,  'V'},
        {"SCI_CANCEL",               2325, NO,  NO,  NO,  27},
        {"SCI_STUTTEREDPAGEUP",      2435, NO,  NO,  NO,  0},
        {"SCI_STUTTEREDPAGEUPEXTEND",2436, NO,  NO,  NO,  0},
        {"SCI_STUTTEREDPAGEDOWN",    2437, NO,  NO,  NO,  0},
        {"SCI_STUTTEREDPAGEDOWNEXTEND",2438,NO, NO,  NO,  0},
    };
    for (size_t i = 0; i < sizeof(defs)/sizeof(defs[0]); i++) {
        ShortcutEntry *e = [[ShortcutEntry alloc] init];
        e.name = [NSString stringWithUTF8String:defs[i].name];
        e.commandID = defs[i].sciID;
        // Map Windows Ctrl to macOS Cmd
        e.hasCmd   = defs[i].ctrl;
        e.hasAlt   = defs[i].alt;
        e.hasShift = defs[i].shift;
        e.keyCode  = defs[i].key;
        [e updateDisplay];
        [_scintillaEntries addObject:e];
    }
    NSLog(@"[ShortcutMapper] Scintilla commands: %lu entries", (unsigned long)_scintillaEntries.count);
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tab Switching
// ═══════════════════════════════════════════════════════════════════════════════

- (void)_switchToTab:(ShortcutMapperTab)tab {
    _currentTab = tab;
    _segControl.selectedSegment = tab;

    // Show/hide Category column based on tab
    NSTableColumn *catCol = [_tableView tableColumnWithIdentifier:@"category"];
    catCol.hidden = (tab != ShortcutMapperTabMainMenu);
    catCol.title = (tab == ShortcutMapperTabPluginCommands) ? @"Plugin" : @"Category";
    if (tab == ShortcutMapperTabPluginCommands) catCol.hidden = NO;

    // Enable/disable Delete button
    _deleteBtn.enabled = (tab == ShortcutMapperTabMacros || tab == ShortcutMapperTabRunCommands);

    [self _applyFilter];
}

// Tab switching handled by _tabSegmentChanged:

// ═══════════════════════════════════════════════════════════════════════════════
// Filtering
// ═══════════════════════════════════════════════════════════════════════════════

- (NSMutableArray<ShortcutEntry *> *)_entriesForCurrentTab {
    switch (_currentTab) {
        case ShortcutMapperTabMainMenu:        return _mainMenuEntries;
        case ShortcutMapperTabMacros:          return _macroEntries;
        case ShortcutMapperTabRunCommands:     return _runCmdEntries;
        case ShortcutMapperTabPluginCommands:  return _pluginEntries;
        case ShortcutMapperTabScintillaCommands: return _scintillaEntries;
    }
    return _mainMenuEntries;
}

- (void)_applyFilter {
    NSString *filter = _filterField.stringValue;
    NSMutableArray *source = [self _entriesForCurrentTab];

    if (filter.length == 0) {
        _filteredEntries = source;
    } else {
        _filteredEntries = [NSMutableArray array];
        for (ShortcutEntry *e in source) {
            if ([e.name rangeOfString:filter options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [e.shortcutDisplay rangeOfString:filter options:NSCaseInsensitiveSearch].location != NSNotFound ||
                (e.category && [e.category rangeOfString:filter options:NSCaseInsensitiveSearch].location != NSNotFound)) {
                [_filteredEntries addObject:e];
            }
        }
    }
    [_tableView reloadData];
    _conflictInfo.stringValue = @"No shortcut conflicts for this item.";
}

- (void)_filterChanged:(id)sender {
    [self _applyFilter];
}

// Live filtering as user types (no need to hit Enter)
- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object == _filterField) {
        [self _applyFilter];
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NSTableViewDataSource / Delegate
// ═══════════════════════════════════════════════════════════════════════════════

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)_filteredEntries.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_filteredEntries.count) return nil;
    ShortcutEntry *e = _filteredEntries[row];
    NSString *colID = tableColumn.identifier;

    // Determine text for this cell
    NSString *text = @"";
    if ([colID isEqualToString:@"num"])
        text = [NSString stringWithFormat:@"%ld", (long)(row + 1)];
    else if ([colID isEqualToString:@"name"])
        text = e.name ?: @"";
    else if ([colID isEqualToString:@"shortcut"])
        text = e.shortcutDisplay ?: @"";
    else if ([colID isEqualToString:@"category"])
        text = (_currentTab == ShortcutMapperTabPluginCommands)
            ? (e.pluginName ?: @"") : (e.category ?: @"");

    // Use a single identifier for all cells (same as DocumentListPanel pattern)
    NSTextField *cell = [tableView makeViewWithIdentifier:@"SCell" owner:nil];
    if (!cell) {
        cell = [[NSTextField alloc] init];
        cell.identifier = @"SCell";
        cell.editable = NO;
        cell.bordered = NO;
        cell.drawsBackground = NO;
    }
    cell.stringValue = text;
    cell.font = [NSFont systemFontOfSize:12];
    cell.textColor = [NSColor labelColor];
    cell.alignment = [colID isEqualToString:@"num"] ? NSTextAlignmentRight : NSTextAlignmentLeft;
    if ([colID isEqualToString:@"num"]) {
        cell.textColor = [NSColor secondaryLabelColor];
        cell.font = [NSFont systemFontOfSize:11];
    }
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = _tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)_filteredEntries.count) {
        _conflictInfo.stringValue = @"No shortcut conflicts for this item.";
        return;
    }
    ShortcutEntry *e = _filteredEntries[row];
    if (e.keyCode == 0) {
        _conflictInfo.stringValue = @"No shortcut conflicts for this item.";
        return;
    }
    // Check for conflicts
    NSString *conflicts = [self _findConflictsFor:e];
    _conflictInfo.stringValue = conflicts.length ? conflicts : @"No shortcut conflicts for this item.";
}

// ═══════════════════════════════════════════════════════════════════════════════
// Conflict Detection
// ═══════════════════════════════════════════════════════════════════════════════

- (NSString *)_findConflictsFor:(ShortcutEntry *)entry {
    if (entry.keyCode == 0) return @"";
    NSMutableArray<NSString *> *conflicts = [NSMutableArray array];

    NSArray *allTabs = @[
        @[@"Main menu", _mainMenuEntries ?: @[]],
        @[@"Macros", _macroEntries ?: @[]],
        @[@"Run commands", _runCmdEntries ?: @[]],
        @[@"Plugin commands", _pluginEntries ?: @[]],
        @[@"Scintilla commands", _scintillaEntries ?: @[]],
    ];

    for (NSArray *tabInfo in allTabs) {
        NSString *tabName = tabInfo[0];
        NSArray<ShortcutEntry *> *entries = tabInfo[1];
        for (NSUInteger i = 0; i < entries.count; i++) {
            ShortcutEntry *other = entries[i];
            if (other == entry) continue;
            if (other.keyCode == 0) continue;
            if (other.keyCode == entry.keyCode &&
                other.hasCmd == entry.hasCmd &&
                other.hasCtrl == entry.hasCtrl &&
                other.hasAlt == entry.hasAlt &&
                other.hasShift == entry.hasShift) {
                [conflicts addObject:[NSString stringWithFormat:@"%@ | %lu  %@  ( %@ )",
                    tabName, (unsigned long)(i+1), other.name, other.shortcutDisplay]];
            }
        }
    }
    return conflicts.count ? [conflicts componentsJoinedByString:@"\n"] : @"";
}

// ═══════════════════════════════════════════════════════════════════════════════
// Actions: Modify / Clear / Delete / Close
// ═══════════════════════════════════════════════════════════════════════════════

- (void)_modifyShortcut:(id)sender {
    NSInteger row = _tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)_filteredEntries.count) return;
    ShortcutEntry *e = _filteredEntries[row];

    // Reuse the Shortcut dialog pattern
    NSPanel *panel = [[NSPanel alloc]
        initWithContentRect:NSMakeRect(0, 0, 340, 200)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                    backing:NSBackingStoreBuffered defer:NO];
    panel.title = @"Shortcut";
    [panel center];
    NSView *cv = panel.contentView;

    NSTextField *nameLbl = [NSTextField labelWithString:@"Name:"];
    nameLbl.frame = NSMakeRect(20, 162, 50, 16);
    [cv addSubview:nameLbl];
    NSTextField *nameVal = [NSTextField labelWithString:e.name];
    nameVal.frame = NSMakeRect(75, 162, 240, 16);
    nameVal.font = [NSFont boldSystemFontOfSize:13];
    [cv addSubview:nameVal];

    NSButton *chkCmd = [NSButton checkboxWithTitle:@"\u2318 Command" target:nil action:nil];
    chkCmd.frame = NSMakeRect(20, 125, 140, 20);
    chkCmd.state = e.hasCmd ? NSControlStateValueOn : NSControlStateValueOff;
    [cv addSubview:chkCmd];

    NSButton *chkCtrl = [NSButton checkboxWithTitle:@"\u2303 Control" target:nil action:nil];
    chkCtrl.frame = NSMakeRect(170, 125, 140, 20);
    chkCtrl.state = e.hasCtrl ? NSControlStateValueOn : NSControlStateValueOff;
    [cv addSubview:chkCtrl];

    NSButton *chkOpt = [NSButton checkboxWithTitle:@"\u2325 Option" target:nil action:nil];
    chkOpt.frame = NSMakeRect(20, 98, 140, 20);
    chkOpt.state = e.hasAlt ? NSControlStateValueOn : NSControlStateValueOff;
    [cv addSubview:chkOpt];

    NSButton *chkShift = [NSButton checkboxWithTitle:@"\u21E7 Shift" target:nil action:nil];
    chkShift.frame = NSMakeRect(170, 98, 100, 20);
    chkShift.state = e.hasShift ? NSControlStateValueOn : NSControlStateValueOff;
    [cv addSubview:chkShift];

    NSTextField *plusKey = [NSTextField labelWithString:@"+"];
    plusKey.frame = NSMakeRect(265, 100, 15, 16);
    [cv addSubview:plusKey];

    NSPopUpButton *keyPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(278, 96, 42, 25) pullsDown:NO];
    [keyPopup addItemsWithTitles:[ShortcutEntry allKeyNames]];
    if (e.keyCode > 0) {
        NSString *current = [ShortcutEntry keyNameForCode:e.keyCode];
        [keyPopup selectItemWithTitle:current];
    }
    [cv addSubview:keyPopup];

    NSButton *btnOK = [[NSButton alloc] initWithFrame:NSMakeRect(120, 12, 90, 28)];
    btnOK.title = @"OK"; btnOK.bezelStyle = NSBezelStyleRounded;
    btnOK.keyEquivalent = @"\r"; btnOK.target = NSApp; btnOK.action = @selector(stopModal);
    [cv addSubview:btnOK];

    NSButton *btnCancel = [[NSButton alloc] initWithFrame:NSMakeRect(220, 12, 90, 28)];
    btnCancel.title = @"Cancel"; btnCancel.bezelStyle = NSBezelStyleRounded;
    btnCancel.keyEquivalent = @"\033"; btnCancel.target = NSApp; btnCancel.action = @selector(abortModal);
    [cv addSubview:btnCancel];

    NSModalResponse resp = [NSApp runModalForWindow:panel];
    [panel orderOut:nil];
    if (resp != NSModalResponseStop) return;

    // Apply changes
    e.hasCmd   = (chkCmd.state == NSControlStateValueOn);
    e.hasCtrl  = (chkCtrl.state == NSControlStateValueOn);
    e.hasAlt   = (chkOpt.state == NSControlStateValueOn);
    e.hasShift = (chkShift.state == NSControlStateValueOn);
    e.keyCode  = [ShortcutEntry keyCodeForName:keyPopup.titleOfSelectedItem];
    e.isModified = YES;
    _hasChanges = YES;
    [e updateDisplay];
    [_tableView reloadData];

    // Update conflict info
    NSString *conflicts = [self _findConflictsFor:e];
    _conflictInfo.stringValue = conflicts.length ? conflicts : @"No shortcut conflicts for this item.";
}

- (void)_clearShortcut:(id)sender {
    NSInteger row = _tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)_filteredEntries.count) return;
    ShortcutEntry *e = _filteredEntries[row];
    e.hasCmd = e.hasCtrl = e.hasAlt = e.hasShift = NO;
    e.keyCode = 0;
    e.isModified = YES;
    _hasChanges = YES;
    [e updateDisplay];
    [_tableView reloadData];
    _conflictInfo.stringValue = @"No shortcut conflicts for this item.";
}

- (void)_deleteShortcut:(id)sender {
    if (_currentTab != ShortcutMapperTabMacros && _currentTab != ShortcutMapperTabRunCommands) return;
    NSInteger row = _tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)_filteredEntries.count) return;

    ShortcutEntry *e = _filteredEntries[row];
    NSAlert *confirm = [[NSAlert alloc] init];
    confirm.messageText = @"Delete Shortcut";
    confirm.informativeText = [NSString stringWithFormat:@"Delete \"%@\"?", e.name];
    [confirm addButtonWithTitle:@"Delete"];
    [confirm addButtonWithTitle:@"Cancel"];
    if ([confirm runModal] != NSAlertFirstButtonReturn) return;

    NSMutableArray *source = [self _entriesForCurrentTab];
    [source removeObject:e];
    _hasChanges = YES;
    [self _applyFilter];
}

- (void)_close:(id)sender {
    [self _saveIfNeeded];
    [self.window close];
}

- (void)windowWillClose:(NSNotification *)notification {
    [self _saveIfNeeded];
}

- (void)_saveIfNeeded {
    if (_saved) { NSLog(@"[ShortcutMapper] _saveIfNeeded: already saved, skipping"); return; }
    _saved = YES;
    if (!_hasChanges) {
        NSLog(@"[ShortcutMapper] _saveIfNeeded: no changes, skipping save");
        return;
    }
    NSLog(@"[ShortcutMapper] _saveIfNeeded: saving now...");
    [self _saveChanges];
}

// ═══════════════════════════════════════════════════════════════════════════════
// Save Changes to shortcuts.xml and live menus
// ═══════════════════════════════════════════════════════════════════════════════

- (void)_saveChanges {
    NSInteger modCount = 0;

    // Apply Main Menu shortcut changes to live menu items
    for (ShortcutEntry *e in _mainMenuEntries) {
        if (!e.isModified) continue;
        if (!e.selectorName) continue;
        SEL sel = NSSelectorFromString(e.selectorName);
        NSMenuItem *mi = [self _findMenuItemWithAction:sel inMenu:[NSApp mainMenu]];
        if (!mi) continue;
        [self _applyShortcutEntry:e toMenuItem:mi];
        modCount++;
    }

    // Save ALL changes to shortcuts.xml
    [self _saveToShortcutsXML];

    NSLog(@"[ShortcutMapper] Saved %ld modified shortcuts", (long)modCount);

    // Post notification for other parts of the app
    [[NSNotificationCenter defaultCenter] postNotificationName:NPPShortcutsChangedNotification object:nil];
}

- (void)_applyShortcutEntry:(ShortcutEntry *)e toMenuItem:(NSMenuItem *)mi {
    if (e.keyCode == 0) {
        mi.keyEquivalent = @"";
        mi.keyEquivalentModifierMask = 0;
        return;
    }
    NSEventModifierFlags mods = 0;
    if (e.hasCmd)   mods |= NSEventModifierFlagCommand;
    if (e.hasCtrl)  mods |= NSEventModifierFlagControl;
    if (e.hasAlt)   mods |= NSEventModifierFlagOption;
    if (e.hasShift) mods |= NSEventModifierFlagShift;

    NSString *key = @"";
    if (e.keyCode >= 'A' && e.keyCode <= 'Z') {
        key = [[NSString stringWithFormat:@"%c", (char)e.keyCode] lowercaseString];
    } else if (e.keyCode >= '0' && e.keyCode <= '9') {
        key = [NSString stringWithFormat:@"%c", (char)e.keyCode];
    } else if (e.keyCode >= 112 && e.keyCode <= 123) {
        unichar fk = NSF1FunctionKey + (e.keyCode - 112);
        key = [NSString stringWithCharacters:&fk length:1];
        mods &= ~NSEventModifierFlagCommand; // function keys don't need Cmd implicit
    } else {
        // Special keys
        switch (e.keyCode) {
            case 8:  key = [NSString stringWithFormat:@"%C", (unichar)NSBackspaceCharacter]; break;
            case 9:  key = @"\t"; break;
            case 13: key = @"\r"; break;
            case 27: key = [NSString stringWithFormat:@"%C", (unichar)0x1B]; break;
            case 46: key = [NSString stringWithFormat:@"%C", (unichar)NSDeleteCharacter]; break;
            default: key = [[NSString stringWithFormat:@"%c", (char)e.keyCode] lowercaseString]; break;
        }
    }
    mi.keyEquivalent = key;
    mi.keyEquivalentModifierMask = mods;
}

- (nullable NSMenuItem *)_findMenuItemWithAction:(SEL)action inMenu:(NSMenu *)menu {
    for (NSMenuItem *mi in menu.itemArray) {
        if (mi.action == action) return mi;
        if (mi.submenu) {
            NSMenuItem *found = [self _findMenuItemWithAction:action inMenu:mi.submenu];
            if (found) return found;
        }
    }
    return nil;
}

- (void)_saveToShortcutsXML {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@".notepad++/shortcuts.xml"];

    // Read existing shortcuts.xml — modify in-place to preserve comments and structure
    NSData *existingData = [NSData dataWithContentsOfFile:path];
    if (!existingData) {
        NSLog(@"[ShortcutMapper] ERROR: shortcuts.xml not found at %@", path);
        return;
    }
    NSError *parseErr = nil;
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:existingData
                                                     options:NSXMLNodePreserveAll
                                                       error:&parseErr];
    if (!doc) {
        NSLog(@"[ShortcutMapper] ERROR parsing shortcuts.xml: %@", parseErr);
        return;
    }

    NSXMLElement *root = doc.rootElement;

    // ── Update InternalCommands in-place ──
    // Remove existing InternalCommands element and replace with new one
    NSArray *intCmdNodes = [root elementsForName:@"InternalCommands"];
    for (NSXMLElement *old in intCmdNodes) {
        [old detach];
    }
    NSXMLElement *intCmdsEl = [NSXMLElement elementWithName:@"InternalCommands"];
    NSInteger intCmdCount = 0;
    for (ShortcutEntry *e in _mainMenuEntries) {
        if (!e.isModified) continue;
        intCmdCount++;
        NSLog(@"[ShortcutMapper] Saving InternalCommand: %@ sel=%@ key=%lu", e.name, e.selectorName, (unsigned long)e.keyCode);
        NSXMLElement *sc = [NSXMLElement elementWithName:@"Shortcut"];
        [sc addAttribute:[NSXMLNode attributeWithName:@"id" stringValue:e.selectorName ?: @""]];
        [sc addAttribute:[NSXMLNode attributeWithName:@"Ctrl" stringValue:e.hasCmd ? @"yes" : @"no"]];
        [sc addAttribute:[NSXMLNode attributeWithName:@"Alt" stringValue:e.hasAlt ? @"yes" : @"no"]];
        [sc addAttribute:[NSXMLNode attributeWithName:@"Shift" stringValue:e.hasShift ? @"yes" : @"no"]];
        [sc addAttribute:[NSXMLNode attributeWithName:@"Key"
                                          stringValue:[NSString stringWithFormat:@"%lu", (unsigned long)e.keyCode]]];
        [intCmdsEl addChild:sc];
    }
    // Insert InternalCommands as first child of root
    if (root.childCount > 0)
        [root insertChild:intCmdsEl atIndex:0];
    else
        [root addChild:intCmdsEl];
    NSLog(@"[ShortcutMapper] InternalCommands: %ld entries saved", (long)intCmdCount);

    // ── Update Macros in-place (only shortcut attributes, preserve Action children) ──
    NSArray *macroNodes = [doc nodesForXPath:@"//Macros/Macro" error:nil];
    for (NSXMLElement *macroEl in macroNodes) {
        NSString *macroName = [[macroEl attributeForName:@"name"] stringValue];
        for (ShortcutEntry *e in _macroEntries) {
            if ([e.name isEqualToString:macroName] && e.isModified) {
                [macroEl removeAttributeForName:@"Ctrl"];
                [macroEl removeAttributeForName:@"Alt"];
                [macroEl removeAttributeForName:@"Shift"];
                [macroEl removeAttributeForName:@"Key"];
                [macroEl addAttribute:[NSXMLNode attributeWithName:@"Ctrl" stringValue:e.hasCmd ? @"yes" : @"no"]];
                [macroEl addAttribute:[NSXMLNode attributeWithName:@"Alt" stringValue:e.hasAlt ? @"yes" : @"no"]];
                [macroEl addAttribute:[NSXMLNode attributeWithName:@"Shift" stringValue:e.hasShift ? @"yes" : @"no"]];
                [macroEl addAttribute:[NSXMLNode attributeWithName:@"Key"
                                                       stringValue:[NSString stringWithFormat:@"%lu", (unsigned long)e.keyCode]]];
                break;
            }
        }
    }

    // Write back — preserves comments and structure
    NSData *xmlData = [doc XMLDataWithOptions:NSXMLNodePrettyPrint | NSXMLNodePreserveAll];
    if (!xmlData) {
        NSLog(@"[ShortcutMapper] ERROR: failed to generate XML data");
        return;
    }
    NSError *writeErr = nil;
    BOOL ok = [xmlData writeToFile:path options:NSDataWritingAtomic error:&writeErr];
    if (ok) {
        NSLog(@"[ShortcutMapper] Saved shortcuts.xml (%lu bytes) to %@", (unsigned long)xmlData.length, path);
    } else {
        NSLog(@"[ShortcutMapper] ERROR writing shortcuts.xml: %@", writeErr);
    }
}

@end
