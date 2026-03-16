#import "StyleConfiguratorWindowController.h"
#import "PreferencesWindowController.h"

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - NPPStyleEntry
// ─────────────────────────────────────────────────────────────────────────────

@implementation NPPStyleEntry
- (id)copyWithZone:(NSZone *)zone {
    NPPStyleEntry *c  = [NPPStyleEntry new];
    c.name            = [_name copy];
    c.styleID         = _styleID;
    c.fgColor         = [_fgColor copy];
    c.bgColor         = [_bgColor copy];
    c.fontName        = [_fontName copy];
    c.fontSize        = _fontSize;
    c.bold            = _bold;
    c.italic          = _italic;
    c.underline       = _underline;
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
- (id)copyWithZone:(NSZone *)zone {
    NPPLexer *c     = [NPPLexer new];
    c.lexerID       = [_lexerID copy];
    c.displayName   = [_displayName copy];
    for (NPPStyleEntry *e in _styles) [c.styles addObject:[e copy]];
    return c;
}
@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Helpers
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

static NSString *const kNSDefaultsStyleKey = @"NPPStyleOverrides";

@implementation NPPStyleStore {
    NSMutableArray<NPPLexer *> *_lexers;        // live state (published to EditorView)
    NSDictionary<NSString *, NPPLexer *> *_lexerDict;  // keyed by lexerID
}

+ (NPPStyleStore *)sharedStore {
    static NPPStyleStore *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NPPStyleStore new]; });
    return s;
}

// ── XML parsing ──────────────────────────────────────────────────────────────

- (NPPStyleEntry *)parseStyleElement:(NSXMLElement *)el {
    NPPStyleEntry *s  = [NPPStyleEntry new];
    s.name            = [el attributeForName:@"name"].stringValue ?: @"";
    s.styleID         = [[el attributeForName:@"styleID"].stringValue intValue];
    s.fgColor         = colorFromRRGGBB([el attributeForName:@"fgColor"].stringValue);
    s.bgColor         = colorFromRRGGBB([el attributeForName:@"bgColor"].stringValue);
    s.fontName        = [el attributeForName:@"fontName"].stringValue ?: @"";
    NSString *fsSz    = [el attributeForName:@"fontSize"].stringValue;
    s.fontSize        = (fsSz.length > 0) ? fsSz.intValue : 0;
    int fst           = [[el attributeForName:@"fontStyle"].stringValue intValue];
    s.bold            = (fst & 1) != 0;
    s.italic          = (fst & 2) != 0;
    s.underline       = (fst & 4) != 0;
    return s;
}

- (NSMutableArray<NPPLexer *> *)parseBundledXML {
    NSMutableArray<NPPLexer *> *result = [NSMutableArray new];
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"stylers.model" withExtension:@"xml"];
    if (!url) {
        NSLog(@"[NPPStyleStore] stylers.model.xml not found in bundle");
        return result;
    }
    NSData *data = [NSData dataWithContentsOfURL:url];
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:data options:0 error:nil];
    if (!doc) return result;

    // Global Styles first
    NPPLexer *globalLexer      = [NPPLexer new];
    globalLexer.lexerID        = @"global";
    globalLexer.displayName    = @"Global Styles";
    NSArray *widgets = [doc nodesForXPath:@"//GlobalStyles/WidgetStyle" error:nil];
    for (NSXMLElement *el in widgets)
        [globalLexer.styles addObject:[self parseStyleElement:el]];
    [result addObject:globalLexer];

    // Per-language lexers
    NSArray *lexerTypes = [doc nodesForXPath:@"//LexerStyles/LexerType" error:nil];
    for (NSXMLElement *lt in lexerTypes) {
        NPPLexer *lex      = [NPPLexer new];
        lex.lexerID        = [lt attributeForName:@"name"].stringValue ?: @"";
        lex.displayName    = [lt attributeForName:@"desc"].stringValue ?: lex.lexerID;
        NSArray *words = [lt nodesForXPath:@"WordsStyle" error:nil];
        for (NSXMLElement *el in words)
            [lex.styles addObject:[self parseStyleElement:el]];
        if (lex.lexerID.length) [result addObject:lex];
    }
    return result;
}

// ── Apply override dict ───────────────────────────────────────────────────────

- (void)applyOverrides:(NSDictionary *)overrides to:(NSMutableArray<NPPLexer *> *)lexers {
    if (!overrides.count) return;
    // Build lookup: lexerID → lexer
    NSMutableDictionary<NSString *, NPPLexer *> *dict = [NSMutableDictionary new];
    for (NPPLexer *lex in lexers) dict[lex.lexerID] = lex;

    for (NSString *key in overrides) {
        // key format: "lexerID|styleID|prop"
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
        if ([prop isEqualToString:@"fg"])
            entry.fgColor   = colorFromRRGGBB(val);
        else if ([prop isEqualToString:@"bg"])
            entry.bgColor   = colorFromRRGGBB(val);
        else if ([prop isEqualToString:@"fontName"])
            entry.fontName  = val;
        else if ([prop isEqualToString:@"fontSize"])
            entry.fontSize  = [val intValue];
        else if ([prop isEqualToString:@"bold"])
            entry.bold      = [val boolValue];
        else if ([prop isEqualToString:@"italic"])
            entry.italic    = [val boolValue];
        else if ([prop isEqualToString:@"underline"])
            entry.underline = [val boolValue];
    }
}

// ── Public API ────────────────────────────────────────────────────────────────

- (void)loadFromDefaults {
    _lexers    = [self parseBundledXML];
    NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kNSDefaultsStyleKey];
    if (saved) {
        [self applyOverrides:saved to:_lexers];
    } else {
        // Migrate from old kPrefStyle* keys
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        NSString *fgHex  = [ud stringForKey:kPrefStyleFg];
        NSString *bgHex  = [ud stringForKey:kPrefStyleBg];
        NSString *fnName = [ud stringForKey:kPrefStyleFontName];
        NSInteger fnSize = [ud integerForKey:kPrefStyleFontSize];
        NPPLexer *global = [self _lexerForID:@"global"];
        NPPStyleEntry *def = [global styleForID:32]; // Default Style is 32
        if (!def) def = [global styleForID:0];
        if (def) {
            if (fgHex.length)   def.fgColor  = colorFromRRGGBB([fgHex hasPrefix:@"#"] ? [fgHex substringFromIndex:1] : fgHex);
            if (bgHex.length)   def.bgColor  = colorFromRRGGBB([bgHex hasPrefix:@"#"] ? [bgHex substringFromIndex:1] : bgHex);
            if (fnName.length)  def.fontName = fnName;
            if (fnSize > 0)     def.fontSize = (int)fnSize;
        }
    }
    [self _buildDict];
}

- (void)_buildDict {
    NSMutableDictionary *d = [NSMutableDictionary new];
    for (NPPLexer *lex in _lexers) d[lex.lexerID] = lex;
    _lexerDict = [d copy];
}

- (NPPLexer *)_lexerForID:(NSString *)lid {
    return _lexerDict[lid];
}

- (nullable NSArray<NPPStyleEntry *> *)stylesForLexer:(NSString *)lexerID {
    if (!_lexers.count) [self loadFromDefaults]; // lazy load on first use
    NSString *lid = lexerID.lowercaseString;
    // Aliases
    if ([lid isEqualToString:@"c"] || [lid isEqualToString:@"objc"])  lid = @"cpp";
    if ([lid isEqualToString:@"js"])    lid = @"javascript";
    if ([lid isEqualToString:@"ts"])    lid = @"typescript";
    NPPLexer *lex = _lexerDict[lid];
    return lex ? lex.styles : nil;
}

- (NSArray<NPPLexer *> *)allLexers { return _lexers; }

- (NPPStyleEntry *)_globalDefaultEntry {
    if (!_lexers.count) [self loadFromDefaults];
    NPPLexer *g = _lexerDict[@"global"];
    // styleID=32 is STYLE_DEFAULT in Scintilla; some themes use styleID=0
    NPPStyleEntry *e = [g styleForID:32];
    if (!e) e = [g styleForID:0];
    return e;
}

- (NSColor *)globalFg {
    NSColor *c = [self _globalDefaultEntry].fgColor;
    return c ?: [NSColor blackColor];
}
- (NSColor *)globalBg {
    NSColor *c = [self _globalDefaultEntry].bgColor;
    return c ?: [NSColor whiteColor];
}
- (NSString *)globalFontName {
    NSString *fn = [self _globalDefaultEntry].fontName;
    return (fn.length > 0) ? fn : @"Menlo";
}
- (int)globalFontSize {
    int fs = [self _globalDefaultEntry].fontSize;
    return (fs > 0) ? fs : 11;
}

- (void)commitLexers:(NSArray<NPPLexer *> *)lexers {
    // Deep copy into _lexers
    _lexers = [NSMutableArray new];
    for (NPPLexer *lex in lexers) [_lexers addObject:[lex copy]];
    [self _buildDict];

    // Serialize to NSUserDefaults
    // Re-parse XML to get defaults; only store diffs (or just store everything)
    NSMutableDictionary *overrides = [NSMutableDictionary new];
    NSMutableArray<NPPLexer *> *xmlDefaults = [self parseBundledXML];
    NSMutableDictionary<NSString *, NPPLexer *> *xmlDict = [NSMutableDictionary new];
    for (NPPLexer *lex in xmlDefaults) xmlDict[lex.lexerID] = lex;

    for (NPPLexer *lex in _lexers) {
        NPPLexer *xmlLex = xmlDict[lex.lexerID];
        for (NPPStyleEntry *e in lex.styles) {
            NPPStyleEntry *xmlE = [xmlLex styleForID:e.styleID];
            NSString *base = [NSString stringWithFormat:@"%@|%d|", lex.lexerID, e.styleID];
            // Store fg if changed
            NSString *xmlFgHex = xmlE ? (xmlE.fgColor ? hexFromColor(xmlE.fgColor) : nil) : nil;
            NSString *curFgHex = e.fgColor ? hexFromColor(e.fgColor) : nil;
            if (curFgHex && ![curFgHex isEqualToString:xmlFgHex])
                overrides[[base stringByAppendingString:@"fg"]] = curFgHex;
            // Store bg if changed
            NSString *xmlBgHex = xmlE ? (xmlE.bgColor ? hexFromColor(xmlE.bgColor) : nil) : nil;
            NSString *curBgHex = e.bgColor ? hexFromColor(e.bgColor) : nil;
            if (curBgHex && ![curBgHex isEqualToString:xmlBgHex])
                overrides[[base stringByAppendingString:@"bg"]] = curBgHex;
            // fontName
            if (e.fontName.length && ![e.fontName isEqualToString:xmlE.fontName ?: @""])
                overrides[[base stringByAppendingString:@"fontName"]] = e.fontName;
            // fontSize
            if (e.fontSize != (xmlE ? xmlE.fontSize : 0) && e.fontSize > 0)
                overrides[[base stringByAppendingString:@"fontSize"]] = @(e.fontSize);
            // bold/italic/underline
            if (e.bold    != (xmlE ? xmlE.bold    : NO)) overrides[[base stringByAppendingString:@"bold"]]    = @(e.bold);
            if (e.italic  != (xmlE ? xmlE.italic  : NO)) overrides[[base stringByAppendingString:@"italic"]]  = @(e.italic);
            if (e.underline != (xmlE ? xmlE.underline : NO)) overrides[[base stringByAppendingString:@"underline"]] = @(e.underline);
        }
    }
    [[NSUserDefaults standardUserDefaults] setObject:overrides forKey:kNSDefaultsStyleKey];

    // Also write legacy kPrefStyle* keys for EditorView compat
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSColor *fg = self.globalFg, *bg = self.globalBg;
    [ud setObject:[@"#" stringByAppendingString:hexFromColor(fg)] forKey:kPrefStyleFg];
    [ud setObject:[@"#" stringByAppendingString:hexFromColor(bg)] forKey:kPrefStyleBg];
    [ud setObject:self.globalFontName forKey:kPrefStyleFontName];
    [ud setInteger:self.globalFontSize forKey:kPrefStyleFontSize];

    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"NPPPreferencesChanged"
                      object:nil
                    userInfo:@{@"themeChanged": @YES}];
}

@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Built-in themes (stored as category-level overrides)
// ─────────────────────────────────────────────────────────────────────────────

typedef struct {
    const char *name;
    const char *fg, *bg;
    const char *comment, *keyword, *string, *number, *preproc;
    const char *fontName; int fontSize;
} _BuiltinTheme;

static const _BuiltinTheme kBuiltinThemes[] = {
    { "Default",        "000000","FFFFFF","008000","0000FF","A31515","098658","800080","",0 },
    { "Monokai",        "F8F8F2","272822","75715E","F92672","E6DB74","AE81FF","66D9EF","",0 },
    { "Obsidian",       "E0E2E4","293134","66747B","93C763","EC7600","FFCD22","ACC0E7","",0 },
    { "Zenburn",        "DCDCCC","3F3F3F","7F9F7F","F0DFAF","CC9393","8CD0D3","94BFF3","",0 },
    { "Solarized Dark", "839496","002B36","586E75","268BD2","2AA198","D33682","859900","",0 },
    { "GitHub Light",   "24292E","FFFFFF","6A737D","D73A49","032F62","005CC5","E36209","",0 },
};
static const int kBuiltinThemeCount = sizeof(kBuiltinThemes) / sizeof(kBuiltinThemes[0]);

/// Category classifier for style names
static NSString *_categoryForStyleName(NSString *name) {
    NSString *u = name.uppercaseString;
    if ([u containsString:@"COMMENT"])     return @"comment";
    if ([u containsString:@"INSTRUCTION WORD"] || [u isEqualToString:@"WORD"] ||
        [u containsString:@"KEYWORD"] || [u hasSuffix:@" WORD"] ||
        [u isEqualToString:@"OPERATOR"] == NO && [u containsString:@"WORD"])
        return nil; // handled below
    if ([u containsString:@"STRING"] || [u containsString:@"CHARACTER"] ||
        [u containsString:@"LITERAL"])     return @"string";
    if ([u isEqualToString:@"NUMBER"])     return @"number";
    if ([u containsString:@"PREPROCESSOR"])return @"preproc";
    return nil;
}

/// Returns the category for a style name (comment/keyword/string/number/preproc)
static NSString * _Nullable categoryFor(NSString *name) {
    NSString *u = name.uppercaseString;
    if ([u containsString:@"COMMENT"])      return @"comment";
    if ([u containsString:@"PREPROC"] || [u containsString:@"PREPROCESSOR"]) return @"preproc";
    if ([u containsString:@"STRING"] || [u containsString:@"CHARACTER"] ||
        [u containsString:@"LITERAL"])      return @"string";
    if ([u isEqualToString:@"NUMBER"])      return @"number";
    // keyword: "INSTRUCTION WORD", "WORD", "KEYWORD", "KEYWORDS", "FUNCTION WORD"
    if ([u isEqualToString:@"WORD"] || [u isEqualToString:@"KEYWORD"] ||
        [u isEqualToString:@"KEYWORDS"] || [u containsString:@"INSTRUCTION WORD"] ||
        [u hasSuffix:@"WORD"])              return @"keyword";
    return nil;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - StyleConfiguratorWindowController
// ─────────────────────────────────────────────────────────────────────────────

/// Private color-swatch button: draws a filled rect with 1px border; click opens NSColorPanel.
@interface _SCColorSwatch : NSButton
@property (nonatomic, strong) NSColor *swatchColor;
@property (nonatomic, weak)   id       colorTarget;
@property (nonatomic)         SEL      colorAction;
@end

@implementation _SCColorSwatch {
    BOOL _panelOpen;
}
- (instancetype)initWithFrame:(NSRect)f {
    self = [super initWithFrame:f];
    if (self) {
        self.bordered = NO;
        self.bezelStyle = NSBezelStyleShadowlessSquare;
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
    [cp orderFront:self];
    [cp setColor:_swatchColor];
    [cp setTarget:self];
    [cp setAction:@selector(_colorPanelDidChange:)];
    _panelOpen = YES;
}
- (void)_colorPanelDidChange:(NSColorPanel *)cp {
    _swatchColor = cp.color;
    [self setNeedsDisplay:YES];
    if (_colorTarget && _colorAction)
        [NSApp sendAction:_colorAction to:_colorTarget from:self];
}
@end

// ── Main controller ───────────────────────────────────────────────────────────

@interface StyleConfiguratorWindowController () <NSTableViewDataSource, NSTableViewDelegate,
                                                  NSOutlineViewDataSource, NSOutlineViewDelegate>
@end

@implementation StyleConfiguratorWindowController {
    // Theme
    NSPopUpButton        *_themePopup;

    // Left panel
    NSPopUpButton        *_langPopup;
    NSTableView          *_styleTable;

    // Right panel header
    NSTextField          *_headerLabel;

    // Colour Style box
    _SCColorSwatch       *_fgSwatch, *_bgSwatch;
    NSTextField          *_fgLabel, *_bgLabel;

    // Font Style box
    NSPopUpButton        *_fontNamePopup, *_fontSizePopup;
    NSButton             *_boldCheck, *_italicCheck, *_underlineCheck;

    // Working copy (deep-copied from store on show; committed on Save)
    NSMutableArray<NPPLexer *>  *_workingLexers;
    NSArray<NPPStyleEntry *>    *_currentStyles;   // styles for selected lang
    int                          _selectedStyleID; // -1 = none
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

    // ── Theme row ────────────────────────────────────────────────────────────
    CGFloat y = H - 20;
    NSTextField *themeLbl = [self _label:@"Select theme:"];
    themeLbl.frame = NSMakeRect(W - pad - 230 - 110, y - 3, 110, 20);
    [cv addSubview:themeLbl];

    _themePopup = [[NSPopUpButton alloc]
        initWithFrame:NSMakeRect(W - pad - 230, y - 3, 230, 25) pullsDown:NO];
    for (int i = 0; i < kBuiltinThemeCount; i++)
        [_themePopup addItemWithTitle:@(kBuiltinThemes[i].name)];
    [_themePopup addItemWithTitle:@"Custom"];
    _themePopup.target = self;
    _themePopup.action = @selector(_themeChanged:);
    [cv addSubview:_themePopup];

    // ── Left panel – Language / Style ────────────────────────────────────────
    NSBox *leftBox = [[NSBox alloc] initWithFrame:NSMakeRect(pad, 55, 245, 415)];
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

    NSScrollView *sv = [[NSScrollView alloc]
        initWithFrame:NSMakeRect(6, 6, lcW - 12, lcH - 84)];
    sv.hasVerticalScroller = YES;
    sv.autohidesScrollers = YES;
    sv.borderType = NSBezelBorder;
    _styleTable = [[NSTableView alloc] initWithFrame:sv.bounds];
    _styleTable.headerView = nil;
    _styleTable.rowHeight = 18;
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"style"];
    col.resizingMask = NSTableColumnAutoresizingMask;
    [_styleTable addTableColumn:col];
    _styleTable.dataSource = self;
    _styleTable.delegate   = self;
    sv.documentView = _styleTable;
    [lc addSubview:sv];

    // ── Right panel ──────────────────────────────────────────────────────────
    CGFloat rx = pad + 245 + 12;
    CGFloat rw = W - rx - pad;
    CGFloat ry = 55;
    CGFloat rh = 415;

    _headerLabel = [NSTextField labelWithString:@""];
    _headerLabel.frame = NSMakeRect(rx, ry + rh - 26, rw, 22);
    _headerLabel.textColor = [NSColor systemBlueColor];
    _headerLabel.font = [NSFont boldSystemFontOfSize:13];
    [cv addSubview:_headerLabel];

    // Two boxes side by side
    CGFloat boxY   = ry + 4;
    CGFloat boxH   = rh - 36;
    CGFloat csBx   = rx;
    CGFloat csW    = rw * 0.45;
    CGFloat fsX    = rx + csW + 10;
    CGFloat fsW    = rw - csW - 10;

    NSBox *colourBox = [[NSBox alloc] initWithFrame:NSMakeRect(csBx, boxY, csW, boxH)];
    colourBox.title = @"Colour Style";
    [cv addSubview:colourBox];
    [self _buildColourStyleBox:colourBox];

    NSBox *fontBox = [[NSBox alloc] initWithFrame:NSMakeRect(fsX, boxY, fsW, boxH)];
    fontBox.title = @"Font Style";
    [cv addSubview:fontBox];
    [self _buildFontStyleBox:fontBox];

    // ── Bottom buttons ────────────────────────────────────────────────────────
    NSButton *cancelBtn = [NSButton buttonWithTitle:@"Cancel"
                                             target:self action:@selector(_cancel:)];
    cancelBtn.frame = NSMakeRect(W - pad - 90, 16, 90, 28);
    cancelBtn.keyEquivalent = @"\033";
    [cv addSubview:cancelBtn];

    NSButton *saveBtn = [NSButton buttonWithTitle:@"Save && Close"
                                           target:self action:@selector(_saveAndClose:)];
    saveBtn.frame = NSMakeRect(W - pad - 90 - 120 - 8, 16, 120, 28);
    saveBtn.keyEquivalent = @"\r";
    saveBtn.bezelStyle = NSBezelStyleRounded;
    [cv addSubview:saveBtn];
}

- (void)_buildColourStyleBox:(NSBox *)box {
    NSView *cv   = box.contentView;
    CGFloat cW   = cv.bounds.size.width;
    CGFloat cH   = cv.bounds.size.height;
    CGFloat midY = cH / 2.0;

    // Foreground colour
    _fgLabel = [self _label:@"Foreground colour"];
    _fgLabel.frame = NSMakeRect(10, midY + 8, cW - 80, 18);
    [cv addSubview:_fgLabel];

    _fgSwatch = [[_SCColorSwatch alloc] initWithFrame:NSMakeRect(cW - 56, midY + 5, 44, 24)];
    _fgSwatch.swatchColor  = [NSColor blackColor];
    _fgSwatch.colorTarget  = self;
    _fgSwatch.colorAction  = @selector(_fgColorChanged:);
    [cv addSubview:_fgSwatch];

    // Background colour
    _bgLabel = [self _label:@"Background colour"];
    _bgLabel.frame = NSMakeRect(10, midY - 28, cW - 80, 18);
    [cv addSubview:_bgLabel];

    _bgSwatch = [[_SCColorSwatch alloc] initWithFrame:NSMakeRect(cW - 56, midY - 31, 44, 24)];
    _bgSwatch.swatchColor  = [NSColor whiteColor];
    _bgSwatch.colorTarget  = self;
    _bgSwatch.colorAction  = @selector(_bgColorChanged:);
    [cv addSubview:_bgSwatch];
}

- (void)_buildFontStyleBox:(NSBox *)box {
    NSView *cv = box.contentView;
    CGFloat cW = cv.bounds.size.width;
    CGFloat cH = cv.bounds.size.height;

    // Font name (full width, upper half)
    NSTextField *fnLbl = [self _label:@"Font name:"];
    fnLbl.frame = NSMakeRect(8, cH - 32, 72, 18);
    [cv addSubview:fnLbl];

    _fontNamePopup = [[NSPopUpButton alloc]
        initWithFrame:NSMakeRect(82, cH - 35, cW - 90, 22) pullsDown:NO];
    NSArray<NSString *> *families = [[[NSFontManager sharedFontManager]
        availableFontFamilies] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    // Add empty entry for "inherit"
    [_fontNamePopup addItemWithTitle:@"(inherit)"];
    for (NSString *f in families) [_fontNamePopup addItemWithTitle:f];
    _fontNamePopup.target = self;
    _fontNamePopup.action = @selector(_fontNameChanged:);
    [cv addSubview:_fontNamePopup];

    // Bold / Italic / Underline checkboxes (left column, lower half)
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

    // Font size (right column, lower half)
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

// ── Helpers ───────────────────────────────────────────────────────────────────

- (NSTextField *)_label:(NSString *)text {
    NSTextField *f = [NSTextField labelWithString:text];
    f.font = [NSFont systemFontOfSize:12];
    return f;
}

// ── Populate from working copy ────────────────────────────────────────────────

- (void)_loadWorkingCopy {
    NSArray<NPPLexer *> *src = [NPPStyleStore sharedStore].allLexers;
    _workingLexers = [NSMutableArray new];
    for (NPPLexer *lex in src) [_workingLexers addObject:[lex copy]];
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

- (void)_selectLang:(NSInteger)idx {
    if (idx < 0 || idx >= (NSInteger)_workingLexers.count) return;
    NPPLexer *lex = _workingLexers[idx];
    _currentStyles = lex.styles;
    [_styleTable reloadData];
    [_styleTable deselectAll:nil];
    _selectedStyleID = -1;
    [self _clearRightPanel];
}

- (void)_clearRightPanel {
    _headerLabel.stringValue = @"";
    _fgSwatch.swatchColor    = [NSColor colorWithWhite:0.5 alpha:1];
    [_fgSwatch setNeedsDisplay:YES];
    _bgSwatch.swatchColor    = [NSColor colorWithWhite:0.5 alpha:1];
    [_bgSwatch setNeedsDisplay:YES];
    [_fontNamePopup selectItemAtIndex:0];
    [_fontSizePopup selectItemAtIndex:0];
    _boldCheck.state      = NSControlStateValueOff;
    _italicCheck.state    = NSControlStateValueOff;
    _underlineCheck.state = NSControlStateValueOff;
    _fgLabel.textColor    = [NSColor secondaryLabelColor];
    _bgLabel.textColor    = [NSColor secondaryLabelColor];
}

- (void)_updateRightPanelForStyle:(NPPStyleEntry *)entry lang:(NPPLexer *)lex {
    _selectedStyleID = entry.styleID;
    _headerLabel.stringValue = [NSString stringWithFormat:@"%@: %@",
                                  lex.displayName, entry.name];
    // Colors
    BOOL hasFg = (entry.fgColor != nil);
    BOOL hasBg = (entry.bgColor != nil);
    _fgLabel.textColor = hasFg ? [NSColor labelColor] : [NSColor secondaryLabelColor];
    _bgLabel.textColor = hasBg ? [NSColor labelColor] : [NSColor secondaryLabelColor];
    _fgSwatch.swatchColor = hasFg ? entry.fgColor : [NSColor colorWithWhite:0.85 alpha:1];
    _bgSwatch.swatchColor = hasBg ? entry.bgColor : [NSColor colorWithWhite:0.85 alpha:1];
    [_fgSwatch setNeedsDisplay:YES];
    [_bgSwatch setNeedsDisplay:YES];
    // Font name
    if (entry.fontName.length > 0)
        [_fontNamePopup selectItemWithTitle:entry.fontName];
    else
        [_fontNamePopup selectItemAtIndex:0]; // (inherit)
    // Font size
    if (entry.fontSize > 0)
        [_fontSizePopup selectItemWithTitle:[@(entry.fontSize) stringValue]];
    else
        [_fontSizePopup selectItemAtIndex:0];
    // Font style
    _boldCheck.state      = entry.bold      ? NSControlStateValueOn : NSControlStateValueOff;
    _italicCheck.state    = entry.italic    ? NSControlStateValueOn : NSControlStateValueOff;
    _underlineCheck.state = entry.underline ? NSControlStateValueOn : NSControlStateValueOff;
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
    NPPLexer *lex = _workingLexers[langIdx];
    [self _updateRightPanelForStyle:_currentStyles[row] lang:lex];
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
    NSString *title = [_themePopup titleOfSelectedItem];
    for (int i = 0; i < kBuiltinThemeCount; i++) {
        if ([title isEqualToString:@(kBuiltinThemes[i].name)]) {
            [self _applyBuiltinTheme:&kBuiltinThemes[i]];
            return;
        }
    }
    // "Custom" selected — do nothing
}

- (void)_applyBuiltinTheme:(const _BuiltinTheme *)t {
    NSColor *fg      = colorFromRRGGBB(@(t->fg));
    NSColor *bg      = colorFromRRGGBB(@(t->bg));
    NSColor *comment = colorFromRRGGBB(@(t->comment));
    NSColor *keyword = colorFromRRGGBB(@(t->keyword));
    NSColor *string  = colorFromRRGGBB(@(t->string));
    NSColor *number  = colorFromRRGGBB(@(t->number));
    NSColor *preproc = colorFromRRGGBB(@(t->preproc));

    for (NPPLexer *lex in _workingLexers) {
        BOOL isGlobal = [lex.lexerID isEqualToString:@"global"];
        for (NPPStyleEntry *e in lex.styles) {
            if (isGlobal && [e.name isEqualToString:@"Default Style"]) {
                if (fg) e.fgColor = fg;
                if (bg) e.bgColor = bg;
                if (strlen(t->fontName) > 0) e.fontName = @(t->fontName);
                if (t->fontSize > 0) e.fontSize = t->fontSize;
                continue;
            }
            NSString *cat = categoryFor(e.name);
            if (!cat) continue;
            NSColor *c = nil;
            if ([cat isEqualToString:@"comment"]) c = comment;
            else if ([cat isEqualToString:@"keyword"]) c = keyword;
            else if ([cat isEqualToString:@"string"])  c = string;
            else if ([cat isEqualToString:@"number"])  c = number;
            else if ([cat isEqualToString:@"preproc"]) c = preproc;
            if (c && e.fgColor) e.fgColor = c; // only override if style had a fg color
        }
    }
    // Refresh right panel
    NSInteger row = _styleTable.selectedRow;
    if (row >= 0 && row < (NSInteger)_currentStyles.count) {
        NSInteger langIdx = _langPopup.indexOfSelectedItem;
        if (langIdx >= 0 && langIdx < (NSInteger)_workingLexers.count) {
            // Refresh _currentStyles from updated working copy
            _currentStyles = _workingLexers[langIdx].styles;
            [self _updateRightPanelForStyle:_currentStyles[row] lang:_workingLexers[langIdx]];
        }
    }
    [_styleTable reloadData];
}

- (void)_langChanged:(id)sender {
    NSInteger idx = _langPopup.indexOfSelectedItem;
    [self _selectLang:idx];
}

- (void)_fgColorChanged:(_SCColorSwatch *)swatch {
    NPPStyleEntry *e = [self _currentEntry];
    if (!e) return;
    e.fgColor = swatch.swatchColor;
    [_themePopup selectItemWithTitle:@"Custom"];
}

- (void)_bgColorChanged:(_SCColorSwatch *)swatch {
    NPPStyleEntry *e = [self _currentEntry];
    if (!e) return;
    e.bgColor = swatch.swatchColor;
    [_themePopup selectItemWithTitle:@"Custom"];
}

- (void)_fontNameChanged:(id)sender {
    NPPStyleEntry *e = [self _currentEntry];
    if (!e) return;
    NSString *title = [_fontNamePopup titleOfSelectedItem];
    e.fontName = [title isEqualToString:@"(inherit)"] ? @"" : title;
    [_themePopup selectItemWithTitle:@"Custom"];
}

- (void)_fontSizeChanged:(id)sender {
    NPPStyleEntry *e = [self _currentEntry];
    if (!e) return;
    NSString *title = [_fontSizePopup titleOfSelectedItem];
    e.fontSize = [title isEqualToString:@"(inherit)"] ? 0 : title.intValue;
    [_themePopup selectItemWithTitle:@"Custom"];
}

- (void)_boldChanged:(id)sender {
    NPPStyleEntry *e = [self _currentEntry];
    if (e) { e.bold = (_boldCheck.state == NSControlStateValueOn); [_themePopup selectItemWithTitle:@"Custom"]; }
}
- (void)_italicChanged:(id)sender {
    NPPStyleEntry *e = [self _currentEntry];
    if (e) { e.italic = (_italicCheck.state == NSControlStateValueOn); [_themePopup selectItemWithTitle:@"Custom"]; }
}
- (void)_underlineChanged:(id)sender {
    NPPStyleEntry *e = [self _currentEntry];
    if (e) { e.underline = (_underlineCheck.state == NSControlStateValueOn); [_themePopup selectItemWithTitle:@"Custom"]; }
}

- (void)_saveAndClose:(id)sender {
    [[NPPStyleStore sharedStore] commitLexers:_workingLexers];
    [[NSUserDefaults standardUserDefaults] setObject:[_themePopup titleOfSelectedItem]
                                              forKey:kPrefThemePreset];
    [self.window close];
}

- (void)_cancel:(id)sender {
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

    // Apply Default Style fg/bg/font
    NSArray<NSXMLElement *> *globalDef =
        [doc nodesForXPath:@"//GlobalStyles/WidgetStyle[@name='Default Style']" error:nil];
    if (globalDef.count > 0) {
        NSXMLElement *e = globalDef[0];
        NSString *fgHex = [e attributeForName:@"fgColor"].stringValue;
        NSString *bgHex = [e attributeForName:@"bgColor"].stringValue;
        NSString *fn    = [e attributeForName:@"fontName"].stringValue;
        NSString *fs    = [e attributeForName:@"fontSize"].stringValue;
        NPPLexer *global = nil;
        for (NPPLexer *lex in _workingLexers) if ([lex.lexerID isEqualToString:@"global"]) { global = lex; break; }
        NPPStyleEntry *def = [global styleForID:32] ?: [global styleForID:0];
        if (def) {
            if (fgHex.length == 6) def.fgColor = colorFromRRGGBB(fgHex);
            if (bgHex.length == 6) def.bgColor = colorFromRRGGBB(bgHex);
            if (fn.length)  def.fontName = fn;
            if (fs.intValue > 0) def.fontSize = fs.intValue;
        }
    }

    // Apply per-language style colors from the XML
    // Build a map: lexerName → (styleID → fgColor)
    NSArray<NSXMLElement *> *lexerTypes = [doc nodesForXPath:@"//LexerStyles/LexerType" error:nil];
    NSMutableDictionary<NSString *, NSMutableDictionary<NSNumber *, NSColor *> *> *xmlMap = [NSMutableDictionary new];
    for (NSXMLElement *lt in lexerTypes) {
        NSString *lname = [lt attributeForName:@"name"].stringValue;
        if (!lname) continue;
        NSMutableDictionary<NSNumber *, NSColor *> *smap = [NSMutableDictionary new];
        NSArray<NSXMLElement *> *words = [lt nodesForXPath:@"WordsStyle" error:nil];
        for (NSXMLElement *ws in words) {
            int sid = [[ws attributeForName:@"styleID"].stringValue intValue];
            NSString *fg = [ws attributeForName:@"fgColor"].stringValue;
            NSString *bg = [ws attributeForName:@"bgColor"].stringValue;
            if (fg.length == 6) smap[@(sid)] = colorFromRRGGBB(fg);
            (void)bg;  // bg overlay can be added similarly if needed
        }
        xmlMap[lname] = smap;
    }

    // Apply to working lexers
    for (NPPLexer *lex in _workingLexers) {
        NSMutableDictionary<NSNumber *, NSColor *> *smap = xmlMap[lex.lexerID];
        if (!smap) continue;
        for (NPPStyleEntry *e in lex.styles) {
            NSColor *c = smap[@(e.styleID)];
            if (c && e.fgColor) e.fgColor = c;  // only override if style had fg
        }
    }

    [_themePopup selectItemWithTitle:@"Custom"];
    [_styleTable reloadData];
    // Refresh right panel
    NSInteger row = _styleTable.selectedRow;
    if (row >= 0 && row < (NSInteger)_currentStyles.count) {
        NSInteger langIdx = _langPopup.indexOfSelectedItem;
        if (langIdx >= 0 && langIdx < (NSInteger)_workingLexers.count) {
            _currentStyles = _workingLexers[langIdx].styles;
            [self _updateRightPanelForStyle:_currentStyles[row] lang:_workingLexers[langIdx]];
        }
    }
}

// ── Show window ───────────────────────────────────────────────────────────────

- (void)showWindow:(id)sender {
    [super showWindow:sender];
    NPPStyleStore *store = [NPPStyleStore sharedStore];
    if (!store.allLexers.count) [store loadFromDefaults];
    [self _loadWorkingCopy];
    [self _populateLangPopup];
    if (_workingLexers.count) {
        [_langPopup selectItemAtIndex:0];
        [self _selectLang:0];
    }
    // Set theme popup
    NSString *savedTheme = [[NSUserDefaults standardUserDefaults] stringForKey:kPrefThemePreset];
    if (savedTheme) [_themePopup selectItemWithTitle:savedTheme];
    [self.window center];
}

@end
