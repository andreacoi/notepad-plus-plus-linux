#import "StyleConfiguratorWindowController.h"
#import "PreferencesWindowController.h"

// ── Built-in theme presets ────────────────────────────────────────────────────
typedef struct {
    const char *name;
    const char *fg;        // default text
    const char *bg;        // editor background
    const char *comment;
    const char *keyword;
    const char *string;
    const char *number;
    const char *preproc;
    const char *fontName;
    int         fontSize;
} ThemePreset;

static const ThemePreset kPresets[] = {
    { "Default",       "#000000", "#FFFFFF", "#008000", "#0000FF", "#A31515", "#098658", "#800080", "Menlo", 11 },
    { "Monokai",       "#F8F8F2", "#272822", "#75715E", "#F92672", "#E6DB74", "#AE81FF", "#66D9EF", "Menlo", 11 },
    { "Obsidian",      "#E0E2E4", "#293134", "#66747B", "#93C763", "#EC7600", "#FFCD22", "#ACC0E7", "Menlo", 11 },
    { "Zenburn",       "#DCDCCC", "#3F3F3F", "#7F9F7F", "#F0DFAF", "#CC9393", "#8CD0D3", "#94BFF3", "Menlo", 11 },
    { "Solarized Dark","#839496", "#002B36", "#586E75", "#268BD2", "#2AA198", "#D33682", "#859900", "Menlo", 11 },
    { "GitHub Light",  "#24292E", "#FFFFFF", "#6A737D", "#D73A49", "#032F62", "#005CC5", "#E36209", "Menlo", 11 },
};
static const NSUInteger kPresetCount = sizeof(kPresets) / sizeof(kPresets[0]);

// ── Implementation ────────────────────────────────────────────────────────────

@interface StyleConfiguratorWindowController ()
@end

@implementation StyleConfiguratorWindowController {
    NSPopUpButton *_themePopup;
    // Color wells: fg, bg, comment, keyword, string, number, preproc
    NSColorWell   *_fgWell, *_bgWell, *_commentWell, *_keywordWell,
                  *_stringWell, *_numberWell, *_preprocWell;
    NSTextField   *_fontNameField;
    NSTextField   *_fontSizeField;
    BOOL           _suppressNotification;
}

+ (instancetype)sharedController {
    static StyleConfiguratorWindowController *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    NSWindow *win = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 480, 340)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    win.title = @"Style Configurator";
    win.releasedWhenClosed = NO;
    self = [super initWithWindow:win];
    if (self) [self buildUI];
    return self;
}

#pragma mark - UI Construction

- (void)buildUI {
    NSView *v = self.window.contentView;
    CGFloat pad = 16, row = 28, y = NSHeight(v.bounds) - pad;

    // Theme label + popup
    y -= row;
    NSTextField *themeLabel = [self label:@"Theme:"];
    themeLabel.frame = NSMakeRect(pad, y, 80, 22);
    [v addSubview:themeLabel];

    _themePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(pad + 84, y, 200, 22) pullsDown:NO];
    for (NSUInteger i = 0; i < kPresetCount; i++)
        [_themePopup addItemWithTitle:@(kPresets[i].name)];
    [_themePopup addItemWithTitle:@"Custom"];
    [_themePopup setTarget:self];
    [_themePopup setAction:@selector(presetChanged:)];
    [v addSubview:_themePopup];

    // Separator
    y -= 10;
    NSBox *sep = [[NSBox alloc] initWithFrame:NSMakeRect(pad, y, NSWidth(v.bounds) - 2*pad, 1)];
    sep.boxType = NSBoxSeparator;
    [v addSubview:sep];
    y -= 10;

    // Color wells grid — 2 columns
    CGFloat colW = (NSWidth(v.bounds) - 2*pad) / 2.0;
    _fgWell      = [self addColorRow:@"Default text:"  x:pad       y:&y width:colW];
    _bgWell      = [self addColorRow:@"Background:"    x:pad+colW  y:&y width:colW offset:colW];

    y -= 6; // small gap between rows
    _commentWell = [self addColorRow:@"Comments:"      x:pad       y:&y width:colW];
    _keywordWell = [self addColorRow:@"Keywords:"      x:pad+colW  y:&y width:colW offset:colW];
    y -= 6;
    _stringWell  = [self addColorRow:@"Strings:"       x:pad       y:&y width:colW];
    _numberWell  = [self addColorRow:@"Numbers:"       x:pad+colW  y:&y width:colW offset:colW];
    y -= 6;
    _preprocWell = [self addColorRow:@"Preprocessor:"  x:pad       y:&y width:colW];

    // Font row
    y -= 14;
    NSTextField *fontLabel = [self label:@"Font:"];
    fontLabel.frame = NSMakeRect(pad, y, 60, 22);
    [v addSubview:fontLabel];

    _fontNameField = [NSTextField textFieldWithString:@"Menlo"];
    _fontNameField.frame = NSMakeRect(pad + 64, y, 140, 22);
    _fontNameField.target = self;
    _fontNameField.action = @selector(fontChanged:);
    [v addSubview:_fontNameField];

    NSTextField *sizeLabel = [self label:@"Size:"];
    sizeLabel.frame = NSMakeRect(pad + 220, y, 40, 22);
    [v addSubview:sizeLabel];

    _fontSizeField = [NSTextField textFieldWithString:@"11"];
    _fontSizeField.frame = NSMakeRect(pad + 264, y, 50, 22);
    _fontSizeField.target = self;
    _fontSizeField.action = @selector(fontChanged:);
    [v addSubview:_fontSizeField];

    // Buttons
    y -= 14;
    NSButton *importBtn = [NSButton buttonWithTitle:@"Import Theme…"
                                             target:self action:@selector(importTheme:)];
    importBtn.frame = NSMakeRect(pad, y - 6, 130, 28);
    [v addSubview:importBtn];

    NSButton *applyBtn = [NSButton buttonWithTitle:@"Apply"
                                            target:self action:@selector(applyTheme:)];
    applyBtn.frame = NSMakeRect(NSWidth(v.bounds) - pad - 80 - 90, y - 6, 80, 28);
    applyBtn.keyEquivalent = @"\r";
    [v addSubview:applyBtn];

    NSButton *closeBtn = [NSButton buttonWithTitle:@"Close"
                                            target:self action:@selector(closeWindow:)];
    closeBtn.frame = NSMakeRect(NSWidth(v.bounds) - pad - 80, y - 6, 80, 28);
    closeBtn.keyEquivalent = @"\033";
    [v addSubview:closeBtn];

    [self loadFromDefaults];
}

// Helper: add a label + color well row; returns the well. Shares y across columns.
- (NSColorWell *)addColorRow:(NSString *)label x:(CGFloat)x y:(CGFloat *)y
                       width:(CGFloat)width offset:(CGFloat)offset {
    (void)offset; // not used — both wells decrement y only once
    BOOL firstCol = (x < width + 16);
    if (firstCol) *y -= 32;
    NSTextField *lbl = [self label:label];
    lbl.frame = NSMakeRect(x, *y, 110, 22);
    [self.window.contentView addSubview:lbl];
    NSColorWell *well = [[NSColorWell alloc] initWithFrame:NSMakeRect(x + 114, *y, 44, 22)];
    well.target = self;
    well.action = @selector(colorWellChanged:);
    [self.window.contentView addSubview:well];
    return well;
}

// Simplified version for first column (no offset parameter)
- (NSColorWell *)addColorRow:(NSString *)label x:(CGFloat)x y:(CGFloat *)y width:(CGFloat)width {
    *y -= 32;
    NSTextField *lbl = [self label:label];
    lbl.frame = NSMakeRect(x, *y, 110, 22);
    [self.window.contentView addSubview:lbl];
    NSColorWell *well = [[NSColorWell alloc] initWithFrame:NSMakeRect(x + 114, *y, 44, 22)];
    well.target = self;
    well.action = @selector(colorWellChanged:);
    [self.window.contentView addSubview:well];
    return well;
}

- (NSTextField *)label:(NSString *)text {
    NSTextField *f = [NSTextField labelWithString:text];
    f.font = [NSFont systemFontOfSize:12];
    f.textColor = [NSColor secondaryLabelColor];
    return f;
}

#pragma mark - Load / Apply

- (void)loadFromDefaults {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *preset = [ud stringForKey:kPrefThemePreset] ?: @"Default";
    [_themePopup selectItemWithTitle:preset];

    _fgWell.color      = [self colorForKey:kPrefStyleFg      fallback:@"#000000"];
    _bgWell.color      = [self colorForKey:kPrefStyleBg      fallback:@"#FFFFFF"];
    _commentWell.color = [self colorForKey:kPrefStyleComment  fallback:@"#008000"];
    _keywordWell.color = [self colorForKey:kPrefStyleKeyword  fallback:@"#0000FF"];
    _stringWell.color  = [self colorForKey:kPrefStyleString   fallback:@"#A31515"];
    _numberWell.color  = [self colorForKey:kPrefStyleNumber   fallback:@"#098658"];
    _preprocWell.color = [self colorForKey:kPrefStylePreproc  fallback:@"#800080"];
    _fontNameField.stringValue = [ud stringForKey:kPrefStyleFontName] ?: @"Menlo";
    _fontSizeField.stringValue = [@([ud integerForKey:kPrefStyleFontSize] ?: 11) stringValue];
}

- (NSColor *)colorForKey:(NSString *)key fallback:(NSString *)fallback {
    NSString *hex = [[NSUserDefaults standardUserDefaults] stringForKey:key] ?: fallback;
    if ([hex hasPrefix:@"#"]) hex = [hex substringFromIndex:1];
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:hex] scanHexInt:&rgb];
    return [NSColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >>  8) & 0xFF) / 255.0
                            blue:( rgb        & 0xFF) / 255.0
                           alpha:1.0];
}

- (NSString *)hexFromColorWell:(NSColorWell *)well {
    NSColor *c = [well.color colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
    unsigned int r = (unsigned int)(c.redComponent   * 255);
    unsigned int g = (unsigned int)(c.greenComponent * 255);
    unsigned int b = (unsigned int)(c.blueComponent  * 255);
    return [NSString stringWithFormat:@"#%02X%02X%02X", r, g, b];
}

- (void)saveToDefaultsAndNotify {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:[_themePopup titleOfSelectedItem] forKey:kPrefThemePreset];
    [ud setObject:[self hexFromColorWell:_fgWell]      forKey:kPrefStyleFg];
    [ud setObject:[self hexFromColorWell:_bgWell]      forKey:kPrefStyleBg];
    [ud setObject:[self hexFromColorWell:_commentWell] forKey:kPrefStyleComment];
    [ud setObject:[self hexFromColorWell:_keywordWell] forKey:kPrefStyleKeyword];
    [ud setObject:[self hexFromColorWell:_stringWell]  forKey:kPrefStyleString];
    [ud setObject:[self hexFromColorWell:_numberWell]  forKey:kPrefStyleNumber];
    [ud setObject:[self hexFromColorWell:_preprocWell] forKey:kPrefStylePreproc];
    [ud setObject:_fontNameField.stringValue           forKey:kPrefStyleFontName];
    [ud setInteger:_fontSizeField.integerValue         forKey:kPrefStyleFontSize];

    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"NPPPreferencesChanged"
                      object:nil
                    userInfo:@{@"themeChanged": @YES}];
}

#pragma mark - Actions

- (void)presetChanged:(id)sender {
    NSString *title = [_themePopup titleOfSelectedItem];
    for (NSUInteger i = 0; i < kPresetCount; i++) {
        if ([title isEqualToString:@(kPresets[i].name)]) {
            const ThemePreset *p = &kPresets[i];
            _fgWell.color      = [self colorFromHex:@(p->fg)];
            _bgWell.color      = [self colorFromHex:@(p->bg)];
            _commentWell.color = [self colorFromHex:@(p->comment)];
            _keywordWell.color = [self colorFromHex:@(p->keyword)];
            _stringWell.color  = [self colorFromHex:@(p->string)];
            _numberWell.color  = [self colorFromHex:@(p->number)];
            _preprocWell.color = [self colorFromHex:@(p->preproc)];
            _fontNameField.stringValue = @(p->fontName);
            _fontSizeField.stringValue = [@(p->fontSize) stringValue];
            return;
        }
    }
    // "Custom" selected — keep current wells as-is
}

- (void)colorWellChanged:(id)sender {
    // Mark preset as "Custom" when user manually edits a color
    [_themePopup selectItemWithTitle:@"Custom"];
}

- (void)fontChanged:(id)sender {
    [_themePopup selectItemWithTitle:@"Custom"];
}

- (void)applyTheme:(id)sender {
    [self saveToDefaultsAndNotify];
}

- (void)closeWindow:(id)sender {
    [self.window close];
}

- (void)importTheme:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"Import Style Theme";
    panel.allowedFileTypes = @[@"xml"];
    panel.message = @"Select a Notepad++ theme XML file";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;
        NSURL *url = panel.URL;
        [self loadNppThemeXML:url];
    }];
}

#pragma mark - NPP XML Theme Parsing

- (void)loadNppThemeXML:(NSURL *)url {
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (!data) return;

    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:data options:0 error:nil];
    if (!doc) return;

    // Extract GlobalStyles → Default Style (fgColor, bgColor, fontName, fontSize)
    NSArray<NSXMLElement *> *globalStyles =
        [doc nodesForXPath:@"//GlobalStyles/WidgetStyle[@name='Default Style']" error:nil];
    if (globalStyles.count > 0) {
        NSXMLElement *e = globalStyles[0];
        NSString *fg = [e attributeForName:@"fgColor"].stringValue;
        NSString *bg = [e attributeForName:@"bgColor"].stringValue;
        NSString *fn = [e attributeForName:@"fontName"].stringValue;
        NSString *fs = [e attributeForName:@"fontSize"].stringValue;
        if (fg.length == 6) {
            _fgWell.color = [self colorFromHex:[@"#" stringByAppendingString:fg]];
        }
        if (bg.length == 6) {
            _bgWell.color = [self colorFromHex:[@"#" stringByAppendingString:bg]];
        }
        if (fn.length) _fontNameField.stringValue = fn;
        if (fs.integerValue > 0) _fontSizeField.stringValue = fs;
    }

    // Extract per-language token colors — use CPP as canonical source
    NSDictionary<NSString *, NSString *> *tokenMap = @{
        @"COMMENT":           @"comment",
        @"COMMENT LINE":      @"comment",
        @"COMMENTLINE":       @"comment",
        @"INSTRUCTION WORD":  @"keyword",
        @"KEYWORD":           @"keyword",
        @"STRING":            @"string",
        @"CHARACTER":         @"string",
        @"NUMBER":            @"number",
        @"PREPROCESSOR":      @"preproc",
    };

    NSMutableDictionary<NSString *, NSColorWell *> *wellMap = [@{
        @"comment": _commentWell,
        @"keyword": _keywordWell,
        @"string":  _stringWell,
        @"number":  _numberWell,
        @"preproc": _preprocWell,
    } mutableCopy];
    NSMutableSet<NSString *> *found = [NSMutableSet set];

    // Walk all WordsStyle elements in the document
    NSArray<NSXMLElement *> *styles =
        [doc nodesForXPath:@"//WordsStyle" error:nil];
    for (NSXMLElement *el in styles) {
        NSString *name = [el attributeForName:@"name"].stringValue.uppercaseString;
        NSString *fg   = [el attributeForName:@"fgColor"].stringValue;
        if (!fg.length || fg.length != 6) continue;

        for (NSString *token in tokenMap) {
            if ([name containsString:token] && ![found containsObject:tokenMap[token]]) {
                NSColorWell *well = wellMap[tokenMap[token]];
                if (well) {
                    well.color = [self colorFromHex:[@"#" stringByAppendingString:fg]];
                    [found addObject:tokenMap[token]];
                }
            }
        }
        if (found.count == wellMap.count) break;
    }

    [_themePopup selectItemWithTitle:@"Custom"];
}

- (NSColor *)colorFromHex:(NSString *)hex {
    if ([hex hasPrefix:@"#"]) hex = [hex substringFromIndex:1];
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:hex] scanHexInt:&rgb];
    return [NSColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >>  8) & 0xFF) / 255.0
                            blue:( rgb        & 0xFF) / 255.0
                           alpha:1.0];
}

@end
