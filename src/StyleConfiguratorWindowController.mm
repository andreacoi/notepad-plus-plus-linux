#import "StyleConfiguratorWindowController.h"
#import "PreferencesWindowController.h"

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - NPPStyleEntry
// ─────────────────────────────────────────────────────────────────────────────

@implementation NPPStyleEntry
- (id)copyWithZone:(NSZone *)zone {
    NPPStyleEntry *c    = [NPPStyleEntry new];
    c.name              = [_name copy];
    c.styleID           = _styleID;
    c.fgColor           = [_fgColor copy];
    c.bgColor           = [_bgColor copy];
    c.fontName          = [_fontName copy];
    c.fontSize          = _fontSize;
    c.bold              = _bold;
    c.italic            = _italic;
    c.underline         = _underline;
    c.fontStyleExplicit = _fontStyleExplicit;
    return c;
}
@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - NPPLexer
// ─────────────────────────────────────────────────────────────────────────────

@implementation NPPLexer
- (instancetype)init { self = [super init]; _styles = [NSMutableArray new]; return self; }
- (nullable NPPStyleEntry *)styleForID:(int)sid {
    for (NPPStyleEntry *e in _styles) if (e.styleID == sid) return e;
    return nil;
}
- (nullable NPPStyleEntry *)styleForName:(NSString *)name {
    for (NPPStyleEntry *e in _styles) if ([e.name isEqualToString:name]) return e;
    return nil;
}
- (id)copyWithZone:(NSZone *)zone {
    NPPLexer *c     = [NPPLexer new];
    c.lexerID       = [_lexerID copy];
    c.displayName   = [_displayName copy];
    for (NPPStyleEntry *e in _styles) [c.styles addObject:[e copy]];
    return c;
}
@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Color helpers
// ─────────────────────────────────────────────────────────────────────────────

static NSColor * _Nullable colorFromRRGGBB(NSString * _Nullable hex) {
    if (!hex.length || hex.length < 6) return nil;
    unsigned int v = 0;
    [[NSScanner scannerWithString:hex] scanHexInt:&v];
    return [NSColor colorWithRed:((v >> 16) & 0xFF) / 255.0
                           green:((v >>  8) & 0xFF) / 255.0
                            blue:( v        & 0xFF) / 255.0
                           alpha:1.0];
}

static NSString *hexFromColor(NSColor *c) {
    NSColor *r = [c colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
    unsigned int rv = (unsigned int)(r.redComponent   * 255.0 + 0.5);
    unsigned int gv = (unsigned int)(r.greenComponent * 255.0 + 0.5);
    unsigned int bv = (unsigned int)(r.blueComponent  * 255.0 + 0.5);
    return [NSString stringWithFormat:@"%02X%02X%02X", rv, gv, bv];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - NPPStyleStore
// ─────────────────────────────────────────────────────────────────────────────

static NSString *const kNSDefaultsStyleKey  = @"NPPStyleOverrides";
static NSString *const kNSDefaultsThemeKey  = @"NPPActiveTheme";
static NSString *const kDefaultThemeName    = @"Default (stylers.xml)";

/// Mapping: theme/model lexer ID aliases.
/// Some theme XML files use "c" while the model uses "cpp"; merge into "cpp".
static NSString *modelLexerID(NSString *themeID) {
    NSDictionary<NSString *, NSString *> *aliases = @{
        @"c"          : @"cpp",
        @"hypertext"  : @"html",
        @"js"         : @"javascript",
        @"ts"         : @"typescript",
    };
    NSString *mapped = aliases[themeID.lowercaseString];
    return mapped ?: themeID.lowercaseString;
}

@implementation NPPStyleStore {
    NSMutableArray<NPPLexer *> *_lexers;
    NSDictionary<NSString *, NPPLexer *> *_lexerDict;
    NSString *_activeThemeName;
}

+ (NPPStyleStore *)sharedStore {
    static NPPStyleStore *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NPPStyleStore new]; });
    return s;
}

// ── XML parsing ──────────────────────────────────────────────────────────────

- (NPPStyleEntry *)_parseElement:(NSXMLElement *)el {
    NPPStyleEntry *s    = [NPPStyleEntry new];
    s.name              = [el attributeForName:@"name"].stringValue ?: @"";
    s.styleID           = [[el attributeForName:@"styleID"].stringValue intValue];
    s.fgColor           = colorFromRRGGBB([el attributeForName:@"fgColor"].stringValue);
    s.bgColor           = colorFromRRGGBB([el attributeForName:@"bgColor"].stringValue);
    s.fontName          = [el attributeForName:@"fontName"].stringValue ?: @"";
    NSString *fsSz      = [el attributeForName:@"fontSize"].stringValue;
    s.fontSize          = (fsSz.length > 0) ? fsSz.intValue : 0;
    NSString *fst       = [el attributeForName:@"fontStyle"].stringValue;
    s.fontStyleExplicit = (fst.length > 0);
    if (s.fontStyleExplicit) {
        int fstVal = fst.intValue;
        s.bold      = (fstVal & 1) != 0;
        s.italic    = (fstVal & 2) != 0;
        s.underline = (fstVal & 4) != 0;
    }
    return s;
}

- (NSMutableArray<NPPLexer *> *)_parseXML:(NSXMLDocument *)doc {
    NSMutableArray<NPPLexer *> *result = [NSMutableArray new];

    // Global Styles first (use name matching, since WidgetStyle uses name not styleID for lookup)
    NPPLexer *globalLexer   = [NPPLexer new];
    globalLexer.lexerID     = @"global";
    globalLexer.displayName = @"Global Styles";
    NSArray *widgets = [doc nodesForXPath:@"//GlobalStyles/WidgetStyle" error:nil];
    for (NSXMLElement *el in widgets)
        [globalLexer.styles addObject:[self _parseElement:el]];
    [result addObject:globalLexer];

    // Per-language lexers
    NSArray *lexerTypes = [doc nodesForXPath:@"//LexerStyles/LexerType" error:nil];
    for (NSXMLElement *lt in lexerTypes) {
        NPPLexer *lex      = [NPPLexer new];
        lex.lexerID        = [lt attributeForName:@"name"].stringValue.lowercaseString ?: @"";
        lex.displayName    = [lt attributeForName:@"desc"].stringValue ?: lex.lexerID;
        NSArray *words     = [lt nodesForXPath:@"WordsStyle" error:nil];
        for (NSXMLElement *el in words)
            [lex.styles addObject:[self _parseElement:el]];
        if (lex.lexerID.length) [result addObject:lex];
    }
    return result;
}

- (NSMutableArray<NPPLexer *> *)_parseDefaultXML {
    // Read from ~/.notepad++/stylers.xml first (user-editable), fall back to bundle model.
    NSString *userStylers = [NSHomeDirectory() stringByAppendingPathComponent:@".notepad++/stylers.xml"];
    NSURL *url = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:userStylers]) {
        url = [NSURL fileURLWithPath:userStylers];
    } else {
        url = [[NSBundle mainBundle] URLForResource:@"stylers.model" withExtension:@"xml"];
    }
    if (!url) { NSLog(@"[NPPStyleStore] stylers.xml not found"); return [NSMutableArray new]; }
    NSData *data = [NSData dataWithContentsOfURL:url];
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:data options:0 error:nil];
    return doc ? [self _parseXML:doc] : [NSMutableArray new];
}

// ── Merge theme entry into target ─────────────────────────────────────────────

- (void)_mergeThemeEntry:(NPPStyleEntry *)src into:(NPPStyleEntry *)dst {
    if (src.fgColor)           dst.fgColor  = src.fgColor;
    if (src.bgColor)           dst.bgColor  = src.bgColor;
    if (src.fontName.length)   dst.fontName = src.fontName;
    if (src.fontSize > 0)      dst.fontSize = src.fontSize;
    if (src.fontStyleExplicit) {
        dst.bold      = src.bold;
        dst.italic    = src.italic;
        dst.underline = src.underline;
        dst.fontStyleExplicit = YES;
    }
}

// ── Load theme from XML ───────────────────────────────────────────────────────

- (NSArray<NPPLexer *> *)lexersForTheme:(NSString *)themeName {
    // Start from clean defaults
    NSMutableArray<NPPLexer *> *result = [self _parseDefaultXML];

    if ([themeName isEqualToString:kDefaultThemeName] || !themeName.length) {
        return result; // "Default (stylers.xml)" = pure model defaults
    }

    // Find theme XML: check user ~/.notepad++/themes/ first, then bundle
    NSURL *themeURL = nil;
    NSString *userPath = [_userThemesDir() stringByAppendingPathComponent:
                          [themeName stringByAppendingPathExtension:@"xml"]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:userPath]) {
        themeURL = [NSURL fileURLWithPath:userPath];
    } else {
        themeURL = [[NSBundle mainBundle] URLForResource:themeName
                                          withExtension:@"xml"
                                           subdirectory:@"themes"];
    }
    if (!themeURL) {
        NSLog(@"[NPPStyleStore] Theme not found: %@", themeName);
        return result;
    }
    NSData *data = [NSData dataWithContentsOfURL:themeURL];
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:data options:0 error:nil];
    if (!doc) return result;

    // Build quick lookup by lexerID
    NSMutableDictionary<NSString *, NPPLexer *> *lookup = [NSMutableDictionary new];
    for (NPPLexer *lex in result) lookup[lex.lexerID] = lex;

    // Merge GlobalStyles (match by name, not styleID)
    NPPLexer *globalLex = lookup[@"global"];
    NSArray<NSXMLElement *> *widgets = [doc nodesForXPath:@"//GlobalStyles/WidgetStyle" error:nil];
    for (NSXMLElement *el in widgets) {
        NPPStyleEntry *themeEntry = [self _parseElement:el];
        NPPStyleEntry *target = [globalLex styleForName:themeEntry.name];
        if (target) [self _mergeThemeEntry:themeEntry into:target];
    }

    // Merge per-language styles
    NSArray<NSXMLElement *> *lexerTypes = [doc nodesForXPath:@"//LexerStyles/LexerType" error:nil];
    for (NSXMLElement *lt in lexerTypes) {
        NSString *rawID = [lt attributeForName:@"name"].stringValue.lowercaseString ?: @"";
        NSString *lid   = modelLexerID(rawID); // e.g. "c" → "cpp"
        NPPLexer *lex   = lookup[lid];
        // If not found by alias, try original ID too
        if (!lex) lex   = lookup[rawID];
        if (!lex) continue;
        NSArray<NSXMLElement *> *words = [lt nodesForXPath:@"WordsStyle" error:nil];
        for (NSXMLElement *el in words) {
            NPPStyleEntry *themeEntry = [self _parseElement:el];
            NPPStyleEntry *target = [lex styleForID:themeEntry.styleID];
            if (target) [self _mergeThemeEntry:themeEntry into:target];
        }
    }
    return result;
}

// ── Available themes ──────────────────────────────────────────────────────────

/// Return path to ~/.notepad++/themes/ (user-installed themes directory).
static NSString *_userThemesDir(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@".notepad++/themes"];
}

- (NSArray<NSString *> *)availableThemeNames {
    NSMutableArray<NSString *> *names = [NSMutableArray new];
    [names addObject:kDefaultThemeName];

    NSMutableSet<NSString *> *seen = [NSMutableSet new]; // deduplicate by name

    // Scan user themes first (~/.notepad++/themes/) — user themes override bundled
    NSString *userDir = _userThemesDir();
    NSArray<NSString *> *userFiles = [[NSFileManager defaultManager]
        contentsOfDirectoryAtPath:userDir error:nil];
    for (NSString *f in userFiles) {
        if ([f.pathExtension.lowercaseString isEqualToString:@"xml"])
            [seen addObject:f.stringByDeletingPathExtension];
    }

    // Scan bundled themes (Resources/themes/)
    NSURL *bundleDir = [[NSBundle mainBundle] URLForResource:@"themes" withExtension:nil];
    if (bundleDir) {
        NSArray<NSURL *> *files = [[NSFileManager defaultManager]
            contentsOfDirectoryAtURL:bundleDir
            includingPropertiesForKeys:nil
            options:NSDirectoryEnumerationSkipsHiddenFiles
            error:nil];
        for (NSURL *u in files) {
            if ([u.pathExtension.lowercaseString isEqualToString:@"xml"])
                [seen addObject:u.URLByDeletingPathExtension.lastPathComponent];
        }
    }

    NSMutableArray<NSString *> *sorted = [seen.allObjects mutableCopy];
    [sorted sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    [names addObjectsFromArray:sorted];
    return [names copy];
}

// ── Apply overrides from NSUserDefaults ───────────────────────────────────────

- (void)_applyUserOverrides:(NSDictionary *)overrides to:(NSMutableArray<NPPLexer *> *)lexers {
    if (!overrides.count) return;
    NSMutableDictionary<NSString *, NPPLexer *> *dict = [NSMutableDictionary new];
    for (NPPLexer *lex in lexers) dict[lex.lexerID] = lex;
    for (NSString *key in overrides) {
        NSArray<NSString *> *parts = [key componentsSeparatedByString:@"|"];
        if (parts.count != 3) continue;
        NSString *lid  = parts[0];
        int       sid  = parts[1].intValue;
        NSString *prop = parts[2];
        NPPLexer  *lex = dict[lid];
        if (!lex) continue;
        NPPStyleEntry *entry = [lex styleForID:sid];
        if (!entry) continue;
        id val = overrides[key];
        if ([prop isEqualToString:@"fg"])         entry.fgColor   = colorFromRRGGBB(val);
        else if ([prop isEqualToString:@"bg"])     entry.bgColor   = colorFromRRGGBB(val);
        else if ([prop isEqualToString:@"fontName"])  entry.fontName  = val;
        else if ([prop isEqualToString:@"fontSize"])  entry.fontSize  = [val intValue];
        else if ([prop isEqualToString:@"bold"])      entry.bold      = [val boolValue];
        else if ([prop isEqualToString:@"italic"])    entry.italic    = [val boolValue];
        else if ([prop isEqualToString:@"underline"]) entry.underline = [val boolValue];
    }
}

// ── Public API ────────────────────────────────────────────────────────────────

- (void)loadFromDefaults {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *savedTheme = [ud stringForKey:kNSDefaultsThemeKey] ?: kDefaultThemeName;
    _activeThemeName = savedTheme;

    // Load theme (model + XML merge)
    NSMutableArray<NPPLexer *> *base = [[self lexersForTheme:savedTheme] mutableCopy];

    // Apply user overrides on top
    NSDictionary *saved = [ud dictionaryForKey:kNSDefaultsStyleKey];
    if (saved) [self _applyUserOverrides:saved to:base];

    _lexers = base;
    [self _buildDict];
}

- (void)_buildDict {
    NSMutableDictionary *d = [NSMutableDictionary new];
    for (NPPLexer *lex in _lexers) d[lex.lexerID] = lex;
    _lexerDict = [d copy];
}

- (nullable NSArray<NPPStyleEntry *> *)stylesForLexer:(NSString *)lexerID {
    if (!_lexers.count) [self loadFromDefaults];
    NSString *lid = lexerID.lowercaseString;
    if ([lid isEqualToString:@"c"] || [lid isEqualToString:@"objc"])  lid = @"cpp";
    else if ([lid isEqualToString:@"js"])   lid = @"javascript";
    else if ([lid isEqualToString:@"ts"])   lid = @"typescript";
    NPPLexer *lex = _lexerDict[lid];
    return lex ? lex.styles : nil;
}

- (NSArray<NPPLexer *> *)allLexers {
    if (!_lexers.count) [self loadFromDefaults];
    return _lexers;
}

- (NPPStyleEntry *)_globalDefaultEntry {
    if (!_lexers.count) [self loadFromDefaults];
    NPPLexer *g = _lexerDict[@"global"];
    NPPStyleEntry *e = [g styleForID:32];
    if (!e) e = [g styleForName:@"Default Style"];
    return e;
}
- (NSColor *)globalFg   { NPPStyleEntry *e = [self _globalDefaultEntry]; return e.fgColor ?: [NSColor blackColor]; }
- (NSColor *)globalBg   { NPPStyleEntry *e = [self _globalDefaultEntry]; return e.bgColor ?: [NSColor whiteColor]; }
- (NSString *)globalFontName { NPPStyleEntry *e = [self _globalDefaultEntry]; return (e.fontName.length) ? e.fontName : @"Menlo"; }
- (int)globalFontSize   { NPPStyleEntry *e = [self _globalDefaultEntry]; return e.fontSize > 0 ? e.fontSize : 11; }

- (nullable NPPStyleEntry *)globalStyleNamed:(NSString *)name {
    if (!_lexers.count) [self loadFromDefaults];
    NPPLexer *g = _lexerDict[@"global"];
    return g ? [g styleForName:name] : nil;
}

- (void)previewLexers:(NSArray<NPPLexer *> *)lexers {
    _lexers = [NSMutableArray new];
    for (NPPLexer *lex in lexers) [_lexers addObject:[lex copy]];
    [self _buildDict];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"NPPPreferencesChanged"
                      object:nil
                    userInfo:@{@"themeChanged": @YES}];
}

- (void)commitLexers:(NSArray<NPPLexer *> *)lexers themeName:(NSString *)themeName {
    [self previewLexers:lexers];
    _activeThemeName = themeName;

    // Serialize diffs against clean theme baseline (no user overrides)
    NSArray<NPPLexer *> *baseline = [self lexersForTheme:themeName];
    NSMutableDictionary<NSString *, NPPLexer *> *baseDict = [NSMutableDictionary new];
    for (NPPLexer *lex in baseline) baseDict[lex.lexerID] = lex;

    NSMutableDictionary *overrides = [NSMutableDictionary new];
    for (NPPLexer *lex in _lexers) {
        NPPLexer *baseLex = baseDict[lex.lexerID];
        for (NPPStyleEntry *e in lex.styles) {
            NPPStyleEntry *b = [baseLex styleForID:e.styleID];
            NSString *base = [NSString stringWithFormat:@"%@|%d|", lex.lexerID, e.styleID];
            NSString *bFg = b.fgColor ? hexFromColor(b.fgColor) : nil;
            NSString *eFg = e.fgColor ? hexFromColor(e.fgColor) : nil;
            if (eFg && ![eFg isEqualToString:bFg]) overrides[[base stringByAppendingString:@"fg"]] = eFg;
            NSString *bBg = b.bgColor ? hexFromColor(b.bgColor) : nil;
            NSString *eBg = e.bgColor ? hexFromColor(e.bgColor) : nil;
            if (eBg && ![eBg isEqualToString:bBg]) overrides[[base stringByAppendingString:@"bg"]] = eBg;
            if (e.fontName.length && ![e.fontName isEqualToString:b.fontName ?: @""])
                overrides[[base stringByAppendingString:@"fontName"]] = e.fontName;
            if (e.fontSize > 0 && e.fontSize != (b ? b.fontSize : 0))
                overrides[[base stringByAppendingString:@"fontSize"]] = @(e.fontSize);
            if (e.fontStyleExplicit) {
                if (e.bold != (b ? b.bold : NO))        overrides[[base stringByAppendingString:@"bold"]]    = @(e.bold);
                if (e.italic != (b ? b.italic : NO))    overrides[[base stringByAppendingString:@"italic"]]  = @(e.italic);
                if (e.underline != (b ? b.underline : NO)) overrides[[base stringByAppendingString:@"underline"]] = @(e.underline);
            }
        }
    }

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:overrides forKey:kNSDefaultsStyleKey];
    [ud setObject:themeName forKey:kNSDefaultsThemeKey];

    // Legacy keys for backward compat
    [ud setObject:[@"#" stringByAppendingString:hexFromColor(self.globalFg)] forKey:kPrefStyleFg];
    [ud setObject:[@"#" stringByAppendingString:hexFromColor(self.globalBg)] forKey:kPrefStyleBg];
    [ud setObject:self.globalFontName forKey:kPrefStyleFontName];
    [ud setInteger:self.globalFontSize forKey:kPrefStyleFontSize];
}

@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - _SCColorSwatch
// ─────────────────────────────────────────────────────────────────────────────

@interface _SCColorSwatch : NSButton
@property (nonatomic, strong) NSColor *swatchColor;
@property (nonatomic, weak)   id       colorTarget;
@property (nonatomic)         SEL      colorAction;
@end

@implementation _SCColorSwatch
- (instancetype)initWithFrame:(NSRect)f {
    self = [super initWithFrame:f];
    if (self) {
        self.bordered = NO;
        [self setButtonType:NSButtonTypeMomentaryPushIn];
        _swatchColor = [NSColor blackColor];
        [self setTarget:self];
        [self setAction:@selector(_clicked:)];
    }
    return self;
}
- (void)drawRect:(NSRect)dr {
    NSRect r = NSInsetRect(self.bounds, 0.5, 0.5);
    [_swatchColor setFill];
    NSRectFill(r);
    [[NSColor colorWithWhite:0.3 alpha:1] setStroke];
    [[NSBezierPath bezierPathWithRect:r] stroke];
}
- (void)_clicked:(id)s {
    NSColorPanel *cp = [NSColorPanel sharedColorPanel];
    [cp setTarget:self];
    [cp setAction:@selector(_colorPanelChanged:)];
    [cp setColor:_swatchColor];
    [cp orderFront:self];
}
- (void)_colorPanelChanged:(NSColorPanel *)cp {
    _swatchColor = cp.color;
    [self setNeedsDisplay:YES];
    if (_colorTarget && _colorAction)
        [NSApp sendAction:_colorAction to:_colorTarget from:self];
}
@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - StyleConfiguratorWindowController
// ─────────────────────────────────────────────────────────────────────────────

@interface StyleConfiguratorWindowController () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation StyleConfiguratorWindowController {
    NSPopUpButton        *_themePopup;
    NSPopUpButton        *_langPopup;
    NSTableView          *_styleTable;
    NSTextField          *_headerLabel;
    _SCColorSwatch       *_fgSwatch, *_bgSwatch;
    NSTextField          *_fgLabel, *_bgLabel;
    NSPopUpButton        *_fontNamePopup, *_fontSizePopup;
    NSButton             *_boldCheck, *_italicCheck, *_underlineCheck;

    // Working copy — edited by user; cancelled on Cancel; committed on Save
    NSMutableArray<NPPLexer *>  *_workingLexers;
    // Snapshot taken when window opens — restored on Cancel
    NSArray<NPPLexer *>         *_cancelBackup;
    NSString                    *_cancelTheme;
    // Currently displayed styles
    NSArray<NPPStyleEntry *>    *_currentStyles;
    int                          _selectedStyleID;
    // Active theme name in working copy
    NSString                    *_workingTheme;
    // Suppress feedback loops when populating UI
    BOOL                         _suppressActions;
}

+ (instancetype)sharedController {
    static StyleConfiguratorWindowController *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[self alloc] init]; });
    return s;
}

- (instancetype)init {
    NSWindow *win = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 780, 510)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    win.title = @"Style Configurator";
    win.releasedWhenClosed = NO;
    self = [super initWithWindow:win];
    if (self) {
        [self _buildUI];
        _selectedStyleID = -1;
    }
    return self;
}

// ── UI construction ───────────────────────────────────────────────────────────

- (void)_buildUI {
    NSView *cv = self.window.contentView;
    const CGFloat W = 780, H = 510;
    const CGFloat pad = 16;

    // Theme row
    CGFloat y = H - 30;
    NSTextField *themeLbl = [self _label:@"Select theme:"];
    themeLbl.frame = NSMakeRect(W - pad - 250 - 110, y - 3, 110, 20);
    [cv addSubview:themeLbl];

    _themePopup = [[NSPopUpButton alloc]
        initWithFrame:NSMakeRect(W - pad - 250, y - 3, 250, 25) pullsDown:NO];
    _themePopup.target = self;
    _themePopup.action = @selector(_themeChanged:);
    [cv addSubview:_themePopup];

    // Left panel – Language / Style
    NSBox *leftBox = [[NSBox alloc] initWithFrame:NSMakeRect(pad, 50, 245, 425)];
    leftBox.title = @"";
    leftBox.titlePosition = NSNoTitle;
    [cv addSubview:leftBox];
    NSView *lc = leftBox.contentView;
    CGFloat lcH = lc.bounds.size.height;
    CGFloat lcW = lc.bounds.size.width;

    NSTextField *langLbl = [self _label:@"Language:"];
    langLbl.frame = NSMakeRect(6, lcH - 24, lcW - 12, 18);
    [lc addSubview:langLbl];

    _langPopup = [[NSPopUpButton alloc]
        initWithFrame:NSMakeRect(6, lcH - 52, lcW - 12, 24) pullsDown:NO];
    _langPopup.target = self;
    _langPopup.action = @selector(_langChanged:);
    [lc addSubview:_langPopup];

    NSTextField *styleLbl = [self _label:@"Style:"];
    styleLbl.frame = NSMakeRect(6, lcH - 76, lcW - 12, 18);
    [lc addSubview:styleLbl];

    // Style list – allow horizontal scroll so no names are clipped
    NSScrollView *sv = [[NSScrollView alloc]
        initWithFrame:NSMakeRect(6, 6, lcW - 12, lcH - 84)];
    sv.hasVerticalScroller   = YES;
    sv.hasHorizontalScroller = YES;
    sv.autohidesScrollers    = YES;
    sv.borderType            = NSBezelBorder;
    _styleTable = [[NSTableView alloc] initWithFrame:sv.bounds];
    _styleTable.headerView = nil;
    _styleTable.rowHeight  = 18;
    _styleTable.font       = [NSFont systemFontOfSize:12];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"style"];
    col.width = 3000;  // wide enough that names are never truncated
    col.resizingMask = NSTableColumnNoResizing;
    [_styleTable addTableColumn:col];
    _styleTable.dataSource = self;
    _styleTable.delegate   = self;
    sv.documentView = _styleTable;
    [lc addSubview:sv];

    // Right panel
    CGFloat rx = pad + 245 + 12;
    CGFloat rw = W - rx - pad;
    CGFloat ry = 50;
    CGFloat rh = 425;

    _headerLabel = [NSTextField labelWithString:@""];
    _headerLabel.frame = NSMakeRect(rx, ry + rh - 26, rw, 22);
    _headerLabel.textColor = [NSColor systemBlueColor];
    _headerLabel.font = [NSFont boldSystemFontOfSize:13];
    [cv addSubview:_headerLabel];

    CGFloat boxY = ry + 4;
    CGFloat boxH = rh - 36;
    CGFloat csW  = rw * 0.45;
    CGFloat fsX  = rx + csW + 10;
    CGFloat fsW  = rw - csW - 10;

    NSBox *colourBox = [[NSBox alloc] initWithFrame:NSMakeRect(rx, boxY, csW, boxH)];
    colourBox.title = @"Colour Style";
    [cv addSubview:colourBox];
    [self _buildColourBox:colourBox];

    NSBox *fontBox = [[NSBox alloc] initWithFrame:NSMakeRect(fsX, boxY, fsW, boxH)];
    fontBox.title = @"Font Style";
    [cv addSubview:fontBox];
    [self _buildFontBox:fontBox];

    // Buttons
    NSButton *cancelBtn = [NSButton buttonWithTitle:@"Cancel"
                                             target:self action:@selector(_cancel:)];
    cancelBtn.frame = NSMakeRect(W - pad - 90, 14, 90, 28);
    cancelBtn.keyEquivalent = @"\033";
    [cv addSubview:cancelBtn];

    NSButton *saveBtn = [NSButton buttonWithTitle:@"Save && Close"
                                           target:self action:@selector(_saveAndClose:)];
    saveBtn.frame = NSMakeRect(W - pad - 90 - 120 - 8, 14, 120, 28);
    saveBtn.keyEquivalent = @"\r";
    saveBtn.bezelStyle = NSBezelStyleRounded;
    [cv addSubview:saveBtn];
}

- (void)_buildColourBox:(NSBox *)box {
    NSView *cv  = box.contentView;
    CGFloat cW  = cv.bounds.size.width;
    CGFloat cH  = cv.bounds.size.height;
    CGFloat midY = cH / 2.0;

    _fgLabel = [self _label:@"Foreground colour"];
    _fgLabel.frame = NSMakeRect(10, midY + 8, cW - 65, 18);
    [cv addSubview:_fgLabel];
    _fgSwatch = [[_SCColorSwatch alloc] initWithFrame:NSMakeRect(cW - 54, midY + 5, 42, 24)];
    _fgSwatch.colorTarget = self;
    _fgSwatch.colorAction = @selector(_fgColorChanged:);
    [cv addSubview:_fgSwatch];

    _bgLabel = [self _label:@"Background colour"];
    _bgLabel.frame = NSMakeRect(10, midY - 28, cW - 65, 18);
    [cv addSubview:_bgLabel];
    _bgSwatch = [[_SCColorSwatch alloc] initWithFrame:NSMakeRect(cW - 54, midY - 31, 42, 24)];
    _bgSwatch.colorTarget = self;
    _bgSwatch.colorAction = @selector(_bgColorChanged:);
    [cv addSubview:_bgSwatch];
}

- (void)_buildFontBox:(NSBox *)box {
    NSView *cv = box.contentView;
    CGFloat cW = cv.bounds.size.width;
    CGFloat cH = cv.bounds.size.height;

    NSTextField *fnLbl = [self _label:@"Font name:"];
    fnLbl.frame = NSMakeRect(8, cH - 32, 72, 18);
    [cv addSubview:fnLbl];
    _fontNamePopup = [[NSPopUpButton alloc]
        initWithFrame:NSMakeRect(82, cH - 35, cW - 90, 22) pullsDown:NO];
    [_fontNamePopup addItemWithTitle:@"(inherit)"];
    NSArray<NSString *> *families = [[[NSFontManager sharedFontManager]
        availableFontFamilies] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *f in families) [_fontNamePopup addItemWithTitle:f];
    _fontNamePopup.target = self;
    _fontNamePopup.action = @selector(_fontNameChanged:);
    [cv addSubview:_fontNamePopup];

    CGFloat checkX = 8, checkY = cH - 68;
    _boldCheck = [NSButton checkboxWithTitle:@"Bold"      target:self action:@selector(_boldChanged:)];
    _boldCheck.frame = NSMakeRect(checkX, checkY, 80, 18);
    [cv addSubview:_boldCheck];
    checkY -= 22;
    _italicCheck = [NSButton checkboxWithTitle:@"Italic"  target:self action:@selector(_italicChanged:)];
    _italicCheck.frame = NSMakeRect(checkX, checkY, 80, 18);
    [cv addSubview:_italicCheck];
    checkY -= 22;
    _underlineCheck = [NSButton checkboxWithTitle:@"Underline" target:self action:@selector(_underlineChanged:)];
    _underlineCheck.frame = NSMakeRect(checkX, checkY, 90, 18);
    [cv addSubview:_underlineCheck];

    NSTextField *szLbl = [self _label:@"Font size:"];
    szLbl.frame = NSMakeRect(cW - 130, cH - 68, 70, 18);
    [cv addSubview:szLbl];
    _fontSizePopup = [[NSPopUpButton alloc]
        initWithFrame:NSMakeRect(cW - 58, cH - 71, 50, 22) pullsDown:NO];
    [_fontSizePopup addItemWithTitle:@"(inherit)"];
    for (NSNumber *sz in @[@6,@7,@8,@9,@10,@11,@12,@14,@16,@18,@20,@22,@24,@28,@36,@48,@72])
        [_fontSizePopup addItemWithTitle:[sz stringValue]];
    _fontSizePopup.target = self;
    _fontSizePopup.action = @selector(_fontSizeChanged:);
    [cv addSubview:_fontSizePopup];
}

- (NSTextField *)_label:(NSString *)text {
    NSTextField *f = [NSTextField labelWithString:text];
    f.font = [NSFont systemFontOfSize:12];
    return f;
}

// ── Populate theme popup from bundle ─────────────────────────────────────────

- (void)_populateThemePopup {
    [_themePopup removeAllItems];
    NSArray<NSString *> *themes = [[NPPStyleStore sharedStore] availableThemeNames];
    for (NSString *t in themes) [_themePopup addItemWithTitle:t];
}

// ── Working copy management ───────────────────────────────────────────────────

- (void)_resetWorkingCopyForTheme:(NSString *)themeName {
    NSArray<NPPLexer *> *base = [[NPPStyleStore sharedStore] lexersForTheme:themeName];
    _workingLexers = [NSMutableArray new];
    for (NPPLexer *lex in base) [_workingLexers addObject:[lex copy]];
    _workingTheme = themeName;
}

- (NPPLexer *)_workingLexerForID:(NSString *)lid {
    for (NPPLexer *lex in _workingLexers) if ([lex.lexerID isEqualToString:lid]) return lex;
    return nil;
}

- (void)_populateLangPopup {
    [_langPopup removeAllItems];
    for (NPPLexer *lex in _workingLexers)
        [_langPopup addItemWithTitle:lex.displayName];
}

- (void)_selectLangAtIndex:(NSInteger)idx {
    if (idx < 0 || idx >= (NSInteger)_workingLexers.count) return;
    _currentStyles = _workingLexers[idx].styles;
    [_styleTable reloadData];
    [_styleTable deselectAll:nil];
    _selectedStyleID = -1;
    [self _clearRightPanel];
}

- (void)_clearRightPanel {
    _headerLabel.stringValue = @"";
    _fgSwatch.swatchColor = [NSColor colorWithWhite:0.85 alpha:1];
    _bgSwatch.swatchColor = [NSColor colorWithWhite:0.85 alpha:1];
    [_fgSwatch setNeedsDisplay:YES];
    [_bgSwatch setNeedsDisplay:YES];
    _suppressActions = YES;
    [_fontNamePopup selectItemAtIndex:0];
    [_fontSizePopup selectItemAtIndex:0];
    _boldCheck.state      = NSControlStateValueOff;
    _italicCheck.state    = NSControlStateValueOff;
    _underlineCheck.state = NSControlStateValueOff;
    _suppressActions = NO;
    _fgLabel.textColor = [NSColor secondaryLabelColor];
    _bgLabel.textColor = [NSColor secondaryLabelColor];
}

- (void)_updateRightPanelForStyle:(NPPStyleEntry *)entry lang:(NPPLexer *)lex {
    _selectedStyleID = entry.styleID;
    _headerLabel.stringValue = [NSString stringWithFormat:@"%@: %@",
                                  lex.displayName, entry.name];
    BOOL hasFg = (entry.fgColor != nil);
    BOOL hasBg = (entry.bgColor != nil);
    _fgLabel.textColor = hasFg ? [NSColor labelColor] : [NSColor secondaryLabelColor];
    _bgLabel.textColor = hasBg ? [NSColor labelColor] : [NSColor secondaryLabelColor];
    _fgSwatch.swatchColor = hasFg ? entry.fgColor : [NSColor colorWithWhite:0.85 alpha:1];
    _bgSwatch.swatchColor = hasBg ? entry.bgColor : [NSColor colorWithWhite:0.85 alpha:1];
    [_fgSwatch setNeedsDisplay:YES];
    [_bgSwatch setNeedsDisplay:YES];

    _suppressActions = YES;
    if (entry.fontName.length > 0) [_fontNamePopup selectItemWithTitle:entry.fontName];
    else                            [_fontNamePopup selectItemAtIndex:0];
    if (entry.fontSize > 0) [_fontSizePopup selectItemWithTitle:[@(entry.fontSize) stringValue]];
    else                    [_fontSizePopup selectItemAtIndex:0];
    _boldCheck.state      = entry.bold      ? NSControlStateValueOn : NSControlStateValueOff;
    _italicCheck.state    = entry.italic    ? NSControlStateValueOn : NSControlStateValueOff;
    _underlineCheck.state = entry.underline ? NSControlStateValueOn : NSControlStateValueOff;
    _suppressActions = NO;
}

// ── NSTableViewDataSource ─────────────────────────────────────────────────────

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv {
    return (NSInteger)_currentStyles.count;
}
- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_currentStyles.count) return @"";
    return _currentStyles[row].name;
}
- (void)tableViewSelectionDidChange:(NSNotification *)n {
    NSInteger row = _styleTable.selectedRow;
    if (row < 0 || row >= (NSInteger)_currentStyles.count) { [self _clearRightPanel]; return; }
    NSInteger langIdx = _langPopup.indexOfSelectedItem;
    if (langIdx < 0 || langIdx >= (NSInteger)_workingLexers.count) return;
    [self _updateRightPanelForStyle:_currentStyles[row] lang:_workingLexers[langIdx]];
}

// ── Current working entry ─────────────────────────────────────────────────────

- (nullable NPPStyleEntry *)_currentEntry {
    if (_selectedStyleID < 0) return nil;
    NSInteger langIdx = _langPopup.indexOfSelectedItem;
    if (langIdx < 0 || langIdx >= (NSInteger)_workingLexers.count) return nil;
    return [_workingLexers[langIdx] styleForID:_selectedStyleID];
}

// ── Actions ───────────────────────────────────────────────────────────────────

- (void)_themeChanged:(id)sender {
    if (_suppressActions) return;
    NSString *name = [_themePopup titleOfSelectedItem];
    [self _resetWorkingCopyForTheme:name];
    // Refresh lang popup (keep same language selected if possible)
    NSInteger prevLangIdx = _langPopup.indexOfSelectedItem;
    [self _populateLangPopup];
    NSInteger newIdx = (prevLangIdx >= 0 && prevLangIdx < (NSInteger)_workingLexers.count)
                       ? prevLangIdx : 0;
    [_langPopup selectItemAtIndex:newIdx];
    [self _selectLangAtIndex:newIdx];
    // Live preview — immediately apply to all editors
    [NPPStyleStore sharedStore].activeThemeName = _workingTheme ?: kDefaultThemeName;
    [[NPPStyleStore sharedStore] previewLexers:_workingLexers];
}

- (void)_langChanged:(id)sender {
    if (_suppressActions) return;
    [self _selectLangAtIndex:_langPopup.indexOfSelectedItem];
}

- (void)_fgColorChanged:(_SCColorSwatch *)swatch {
    if (_suppressActions) return;
    NPPStyleEntry *e = [self _currentEntry];
    if (!e) return;
    e.fgColor = swatch.swatchColor;
}
- (void)_bgColorChanged:(_SCColorSwatch *)swatch {
    if (_suppressActions) return;
    NPPStyleEntry *e = [self _currentEntry];
    if (!e) return;
    e.bgColor = swatch.swatchColor;
}
- (void)_fontNameChanged:(id)sender {
    if (_suppressActions) return;
    NPPStyleEntry *e = [self _currentEntry];
    if (!e) return;
    NSString *title = [_fontNamePopup titleOfSelectedItem];
    e.fontName = [title isEqualToString:@"(inherit)"] ? @"" : title;
}
- (void)_fontSizeChanged:(id)sender {
    if (_suppressActions) return;
    NPPStyleEntry *e = [self _currentEntry];
    if (!e) return;
    NSString *t = [_fontSizePopup titleOfSelectedItem];
    e.fontSize = [t isEqualToString:@"(inherit)"] ? 0 : t.intValue;
}
- (void)_boldChanged:(id)sender {
    if (_suppressActions) return;
    NPPStyleEntry *e = [self _currentEntry];
    if (e) { e.bold = (_boldCheck.state == NSControlStateValueOn); e.fontStyleExplicit = YES; }
}
- (void)_italicChanged:(id)sender {
    if (_suppressActions) return;
    NPPStyleEntry *e = [self _currentEntry];
    if (e) { e.italic = (_italicCheck.state == NSControlStateValueOn); e.fontStyleExplicit = YES; }
}
- (void)_underlineChanged:(id)sender {
    if (_suppressActions) return;
    NPPStyleEntry *e = [self _currentEntry];
    if (e) { e.underline = (_underlineCheck.state == NSControlStateValueOn); e.fontStyleExplicit = YES; }
}

- (void)_saveAndClose:(id)sender {
    [[NPPStyleStore sharedStore] commitLexers:_workingLexers themeName:_workingTheme ?: kDefaultThemeName];
    [self.window close];
}

- (void)_cancel:(id)sender {
    // Restore state that was active when window was opened
    if (_cancelBackup) {
        [NPPStyleStore sharedStore].activeThemeName = _cancelTheme ?: kDefaultThemeName;
        [[NPPStyleStore sharedStore] previewLexers:_cancelBackup];
    }
    [self.window close];
}

// ── Import NPP theme XML ──────────────────────────────────────────────────────

- (void)importTheme:(id)sender {
    if (!self.window.isVisible) [self showWindow:nil];
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"Import Style Theme";
    panel.allowedFileTypes = @[@"xml"];
    panel.message = @"Select a Notepad++ theme XML file to apply";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;
        [self _loadNppThemeXML:panel.URL];
    }];
}

- (void)_loadNppThemeXML:(NSURL *)url {
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (!data) return;
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:data options:0 error:nil];
    if (!doc) return;

    // Apply GlobalStyles Default Style fg/bg/font
    NSArray<NSXMLElement *> *widgets = [doc nodesForXPath:@"//GlobalStyles/WidgetStyle" error:nil];
    NPPLexer *global = [self _workingLexerForID:@"global"];
    for (NSXMLElement *el in widgets) {
        NSString *name = [el attributeForName:@"name"].stringValue;
        NPPStyleEntry *target = [global styleForName:name];
        if (target) {
            NPPStyleStore *s = [NPPStyleStore sharedStore];
            NPPStyleEntry *te = [s _parseElement:el];
            [s _mergeThemeEntry:te into:target];
        }
    }

    // Apply per-language styles
    NSArray<NSXMLElement *> *lexerTypes = [doc nodesForXPath:@"//LexerStyles/LexerType" error:nil];
    for (NSXMLElement *lt in lexerTypes) {
        NSString *rawID = [lt attributeForName:@"name"].stringValue.lowercaseString ?: @"";
        NSString *lid = modelLexerID(rawID);
        NPPLexer *lex = [self _workingLexerForID:lid] ?: [self _workingLexerForID:rawID];
        if (!lex) continue;
        NSArray<NSXMLElement *> *words = [lt nodesForXPath:@"WordsStyle" error:nil];
        NPPStyleStore *s = [NPPStyleStore sharedStore];
        for (NSXMLElement *el in words) {
            NPPStyleEntry *te = [s _parseElement:el];
            NPPStyleEntry *target = [lex styleForID:te.styleID];
            if (target) [s _mergeThemeEntry:te into:target];
        }
    }

    [_themePopup selectItemWithTitle:@"Custom"];
    [_styleTable reloadData];
    NSInteger row = _styleTable.selectedRow;
    NSInteger langIdx = _langPopup.indexOfSelectedItem;
    if (row >= 0 && langIdx >= 0 && langIdx < (NSInteger)_workingLexers.count) {
        _currentStyles = _workingLexers[langIdx].styles;
        if (row < (NSInteger)_currentStyles.count)
            [self _updateRightPanelForStyle:_currentStyles[row] lang:_workingLexers[langIdx]];
    }
    // Live preview
    [[NPPStyleStore sharedStore] previewLexers:_workingLexers];
}

// ── Show window ───────────────────────────────────────────────────────────────

- (void)showWindow:(id)sender {
    [super showWindow:sender];
    NPPStyleStore *store = [NPPStyleStore sharedStore];
    if (!store.allLexers.count) [store loadFromDefaults];

    // Save cancel backup — snapshot of current live store state
    NSMutableArray *backup = [NSMutableArray new];
    for (NPPLexer *lex in store.allLexers) [backup addObject:[lex copy]];
    _cancelBackup = [backup copy];
    _cancelTheme  = store.activeThemeName ?: kDefaultThemeName;

    // Populate theme popup
    [self _populateThemePopup];

    // Figure out active theme
    NSString *activeName = [[NSUserDefaults standardUserDefaults] stringForKey:kNSDefaultsThemeKey]
                            ?: kDefaultThemeName;
    // Load fresh working copy for active theme
    [self _resetWorkingCopyForTheme:activeName];

    // Apply any user overrides on top
    NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kNSDefaultsStyleKey];
    if (saved.count) {
        // Build lookup for overrides application
        NSMutableDictionary<NSString *, NPPLexer *> *lookup = [NSMutableDictionary new];
        for (NPPLexer *lex in _workingLexers) lookup[lex.lexerID] = lex;
        for (NSString *key in saved) {
            NSArray<NSString *> *parts = [key componentsSeparatedByString:@"|"];
            if (parts.count != 3) continue;
            NPPLexer *lex = lookup[parts[0]];
            NPPStyleEntry *e = [lex styleForID:parts[1].intValue];
            if (!e) continue;
            id val = saved[key];
            NSString *prop = parts[2];
            if ([prop isEqualToString:@"fg"]) e.fgColor = colorFromRRGGBB(val);
            else if ([prop isEqualToString:@"bg"]) e.bgColor = colorFromRRGGBB(val);
            else if ([prop isEqualToString:@"fontName"]) e.fontName = val;
            else if ([prop isEqualToString:@"fontSize"]) e.fontSize = [val intValue];
            else if ([prop isEqualToString:@"bold"]) e.bold = [val boolValue];
            else if ([prop isEqualToString:@"italic"]) e.italic = [val boolValue];
            else if ([prop isEqualToString:@"underline"]) e.underline = [val boolValue];
        }
    }

    // Select theme in popup
    [_themePopup selectItemWithTitle:activeName];

    // Populate lang popup and select first item
    [self _populateLangPopup];
    if (_workingLexers.count) {
        [_langPopup selectItemAtIndex:0];
        [self _selectLangAtIndex:0];
    }

    [self.window center];
}

@end
