#import "FunctionListPanel.h"
#import "NppLocalizer.h"
#import "StyleConfiguratorWindowController.h"
#import "PreferencesWindowController.h"
#import "Scintilla.h"
#import "ScintillaMessages.h"
#import "NppThemeManager.h"

// ── Data model: tree item (node = class/struct, leaf = function/method) ──────

@interface _FuncItem : NSObject
@property (nonatomic, copy)   NSString *name;
@property (nonatomic)         NSInteger line;      // 1-based
@property (nonatomic)         NSInteger pos;       // byte offset in document
@property (nonatomic)         BOOL isNode;         // YES = class/struct/protocol
@property (nonatomic, strong) NSMutableArray<_FuncItem *> *children;
@end

@implementation _FuncItem
- (instancetype)initWithName:(NSString *)name line:(NSInteger)line pos:(NSInteger)pos isNode:(BOOL)isNode {
    self = [super init];
    if (self) {
        _name = [name copy];
        _line = line;
        _pos  = pos;
        _isNode = isNode;
        _children = isNode ? [NSMutableArray array] : nil;
    }
    return self;
}
@end

// ── Panel button helper (same pattern as FolderTreePanel / GitPanel) ─────────

static NSButton *_flPanelBtn(NSString *iconName, NSString *subdir,
                              NSString *tip, CGFloat iconSize,
                              id target, SEL action) {
    NSButton *btn = [[NSButton alloc] init];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.bezelStyle = NSBezelStyleSmallSquare;
    btn.bordered   = NO;
    btn.toolTip    = tip;
    btn.target     = target;
    btn.action     = action;
    [btn.widthAnchor  constraintEqualToConstant:22].active = YES;
    [btn.heightAnchor constraintEqualToConstant:22].active = YES;
    NSURL *url = [[NSBundle mainBundle] URLForResource:iconName withExtension:@"png"
                                          subdirectory:subdir];
    NSImage *img = url ? [[NSImage alloc] initWithContentsOfURL:url] : nil;
    if (img) {
        img.size = NSMakeSize(iconSize, iconSize);
        btn.image = img;
        btn.imageScaling = NSImageScaleProportionallyDown;
    } else {
        btn.title = @"?";
    }
    return btn;
}

// ── FunctionListPanel ────────────────────────────────────────────────────────

@implementation FunctionListPanel {
    // Title bar
    NSView       *_titleBar;
    NSTextField  *_titleLabel;
    NSButton     *_sortButton;
    NSButton     *_reloadButton;
    NSButton     *_closeButton;

    // Search field
    NSTextField  *_searchField;

    // Tree
    NSScrollView   *_scrollView;
    NSOutlineView  *_outlineView;

    // Data
    NSMutableArray<_FuncItem *> *_rootItems;     // full tree
    NSMutableArray<_FuncItem *> *_filteredItems;  // search-filtered tree
    __weak EditorView *_editor;

    // State
    BOOL _sortAlpha;  // YES = alphabetical, NO = document order
    NSString *_searchText;

    // Icons
    NSImage *_leafIcon;
    NSImage *_nodeIcon;

    // Empty state
    NSTextField *_emptyLabel;

    // Background scanning
    NSUInteger _scanGeneration;         // incremented on each loadEditor, cancels stale scans

    // Line offset table (built once per scan, used for O(log n) line lookups)
    NSUInteger *_lineOffsets;           // array of byte offsets where each line starts
    NSUInteger  _lineOffsetCount;       // number of lines
}

// dealloc is below (after init) — _lineOffsets freed there

#pragma mark - Init

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _rootItems    = [NSMutableArray array];
        _filteredItems = [NSMutableArray array];
        _searchText   = @"";
        [self _loadIcons];
        [self _buildLayout];
        [self retranslateUI];
        [self _applyTheme];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_locChanged:)
                                                     name:NPPLocalizationChanged object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_themeChanged:)
                                                     name:@"NPPPreferencesChanged" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_darkModeChanged:) name:NPPDarkModeChangedNotification object:nil];
    }
    return self;
}

- (instancetype)init { return [self initWithFrame:NSZeroRect]; }

- (void)dealloc {
    free(_lineOffsets);
    _lineOffsets = NULL;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Icons

- (void)_loadIcons {
    NSURL *leafURL = [[NSBundle mainBundle] URLForResource:@"funcList_leaf" withExtension:@"png"
                                              subdirectory:@"icons/standard/panels/treeview"];
    NSURL *nodeURL = [[NSBundle mainBundle] URLForResource:@"funcList_node" withExtension:@"png"
                                              subdirectory:@"icons/standard/panels/treeview"];
    _leafIcon = leafURL ? [[NSImage alloc] initWithContentsOfURL:leafURL] : nil;
    _nodeIcon = nodeURL ? [[NSImage alloc] initWithContentsOfURL:nodeURL] : nil;
    _leafIcon.size = NSMakeSize(14, 14);
    _nodeIcon.size = NSMakeSize(14, 14);
}

#pragma mark - Layout

- (void)_buildLayout {
    self.translatesAutoresizingMaskIntoConstraints = NO;

    // ── Title bar ────────────────────────────────────────────────────────────
    _titleBar = [[NSView alloc] init];
    _titleBar.translatesAutoresizingMaskIntoConstraints = NO;
    _titleBar.wantsLayer = YES;
    _titleBar.layer.backgroundColor = [NppThemeManager shared].panelBackground.CGColor;
    [self addSubview:_titleBar];

    _titleLabel = [NSTextField labelWithString:@"Function List"];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [NSFont boldSystemFontOfSize:11];
    _titleLabel.textColor = [NSColor labelColor];
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_titleBar addSubview:_titleLabel];

    _sortButton = _flPanelBtn(@"funclstSort", @"icons/standard/panels/toolbar",
                               @"Sort functions (A to Z)", 10, self, @selector(_toggleSort:));
    [_titleBar addSubview:_sortButton];

    _reloadButton = _flPanelBtn(@"funclstReload", @"icons/standard/panels/toolbar",
                                 @"Reload", 10, self, @selector(_reload:));
    [_titleBar addSubview:_reloadButton];

    _closeButton = [NSButton buttonWithTitle:@"✕" target:self action:@selector(_closePanel:)];
    _closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    _closeButton.bezelStyle = NSBezelStyleInline;
    _closeButton.bordered = NO;
    _closeButton.font = [NSFont systemFontOfSize:11];
    [_closeButton.widthAnchor constraintEqualToConstant:20].active = YES;
    [_closeButton.heightAnchor constraintEqualToConstant:20].active = YES;
    [_titleBar addSubview:_closeButton];

    [NSLayoutConstraint activateConstraints:@[
        [_titleBar.topAnchor      constraintEqualToAnchor:self.topAnchor],
        [_titleBar.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [_titleBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_titleBar.heightAnchor   constraintEqualToConstant:26],

        [_titleLabel.leadingAnchor  constraintEqualToAnchor:_titleBar.leadingAnchor constant:6],
        [_titleLabel.centerYAnchor  constraintEqualToAnchor:_titleBar.centerYAnchor],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_sortButton.leadingAnchor constant:-4],

        [_sortButton.trailingAnchor   constraintEqualToAnchor:_reloadButton.leadingAnchor constant:-2],
        [_sortButton.centerYAnchor    constraintEqualToAnchor:_titleBar.centerYAnchor],
        [_reloadButton.trailingAnchor constraintEqualToAnchor:_closeButton.leadingAnchor constant:-4],
        [_reloadButton.centerYAnchor  constraintEqualToAnchor:_titleBar.centerYAnchor],
        [_closeButton.trailingAnchor  constraintEqualToAnchor:_titleBar.trailingAnchor constant:-4],
        [_closeButton.centerYAnchor   constraintEqualToAnchor:_titleBar.centerYAnchor],
    ]];

    // ── Separator ────────────────────────────────────────────────────────────
    NSBox *sep = [[NSBox alloc] init];
    sep.boxType = NSBoxSeparator;
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:sep];

    // ── Search field ─────────────────────────────────────────────────────────
    _searchField = [[NSTextField alloc] init];
    _searchField.translatesAutoresizingMaskIntoConstraints = NO;
    _searchField.placeholderString = @"Search function...";
    _searchField.font = [NSFont systemFontOfSize:11];
    _searchField.delegate = self;
    _searchField.bezelStyle = NSTextFieldRoundedBezel;
    [[_searchField cell] setScrollable:YES];
    [self addSubview:_searchField];

    // ── Outline view (tree) ──────────────────────────────────────────────────
    _outlineView = [[NSOutlineView alloc] init];
    _outlineView.headerView = nil;
    _outlineView.rowHeight = 20;
    _outlineView.indentationPerLevel = 16;
    _outlineView.intercellSpacing = NSMakeSize(0, 1);
    _outlineView.allowsMultipleSelection = NO;
    _outlineView.dataSource = self;
    _outlineView.delegate = self;
    _outlineView.autoresizesOutlineColumn = YES;

    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"func"];
    col.resizingMask = NSTableColumnAutoresizingMask;
    [_outlineView addTableColumn:col];
    _outlineView.outlineTableColumn = col;

    _scrollView = [[NSScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.hasHorizontalScroller = NO;
    _scrollView.borderType = NSNoBorder;
    _scrollView.documentView = _outlineView;
    [self addSubview:_scrollView];

    // ── Empty label ──────────────────────────────────────────────────────────
    _emptyLabel = [NSTextField labelWithString:@"No functions found"];
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyLabel.textColor = [NSColor secondaryLabelColor];
    _emptyLabel.hidden = YES;
    [self addSubview:_emptyLabel];

    // ── Constraints ──────────────────────────────────────────────────────────
    [NSLayoutConstraint activateConstraints:@[
        [sep.topAnchor      constraintEqualToAnchor:_titleBar.bottomAnchor],
        [sep.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [sep.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [sep.heightAnchor   constraintEqualToConstant:1],

        [_searchField.topAnchor      constraintEqualToAnchor:sep.bottomAnchor constant:4],
        [_searchField.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor constant:6],
        [_searchField.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6],
        [_searchField.heightAnchor   constraintEqualToConstant:22],

        [_scrollView.topAnchor      constraintEqualToAnchor:_searchField.bottomAnchor constant:4],
        [_scrollView.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_scrollView.bottomAnchor   constraintEqualToAnchor:self.bottomAnchor],

        [_emptyLabel.centerXAnchor constraintEqualToAnchor:_scrollView.centerXAnchor],
        [_emptyLabel.centerYAnchor constraintEqualToAnchor:_scrollView.centerYAnchor],
    ]];
}

#pragma mark - Theme

- (void)_themeChanged:(NSNotification *)n { [self _applyTheme]; }

- (void)_applyTheme {
    // Follow the same theme as other panels (controlBackgroundColor adapts to dark mode).
    _titleBar.layer.backgroundColor = [NppThemeManager shared].panelBackground.CGColor;
    _titleLabel.textColor = [NSColor labelColor];
    _emptyLabel.textColor = [NSColor secondaryLabelColor];
    [_outlineView reloadData]; // colors may have changed
}

#pragma mark - Localization

- (void)_locChanged:(NSNotification *)n { [self retranslateUI]; }
- (void)retranslateUI {
    NppLocalizer *loc = [NppLocalizer shared];
    _titleLabel.stringValue = [loc translate:@"Function List"];
    _emptyLabel.stringValue = [loc translate:@"No functions found"];
    _sortButton.toolTip     = [loc translate:@"Sort functions (A to Z)"];
    _reloadButton.toolTip   = [loc translate:@"Reload"];
    _closeButton.toolTip    = [loc translate:@"Close"];
}

#pragma mark - Actions

- (void)_toggleSort:(id)sender {
    _sortAlpha = !_sortAlpha;
    [self _rebuildFilteredItems];
    [_outlineView reloadData];
    [self _expandAllNodes];
}

- (void)_reload:(id)sender {
    [self reload];
}

- (void)_closePanel:(id)sender {
    if ([_delegate respondsToSelector:@selector(functionListPanelDidRequestClose:)])
        [_delegate functionListPanelDidRequestClose:self];
}

#pragma mark - Search field delegate

- (void)controlTextDidChange:(NSNotification *)obj {
    if (obj.object != _searchField) return;
    _searchText = _searchField.stringValue ?: @"";
    [self _rebuildFilteredItems];
    [_outlineView reloadData];
    [self _expandAllNodes];
    [self _updateEmptyState];
}

#pragma mark - Public API

- (void)loadEditor:(EditorView *)editor {
    _editor = editor;
    [_rootItems removeAllObjects];
    [_filteredItems removeAllObjects];
    [_outlineView reloadData];
    [self _updateEmptyState];

    if (!editor) return;

    // Grab full text from Scintilla (must be on main thread — Scintilla is not thread-safe)
    intptr_t len = [editor.scintillaView message:SCI_GETLENGTH];
    char *buf = (char *)malloc((size_t)len + 1);
    if (!buf) return;
    [editor.scintillaView message:SCI_GETTEXT wParam:(uptr_t)(len + 1) lParam:(sptr_t)buf];
    NSString *text = [[NSString alloc] initWithBytes:buf length:(NSUInteger)len
                                            encoding:NSUTF8StringEncoding];
    if (!text) { free(buf); return; }

    // Build line offset table from raw UTF-8 (fast, single pass)
    [self _buildLineOffsetsFromUTF8:buf length:(NSUInteger)len];
    free(buf);

    NSString *lang = editor.currentLanguage;

    // Increment generation to cancel any in-flight background scan
    NSUInteger gen = ++_scanGeneration;

    // Dispatch scanning to background queue
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Check if this scan is still current
        if (gen != self->_scanGeneration) return;

        [self _scanText:text forLanguage:lang];

        if (gen != self->_scanGeneration) return;

        // Update UI on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            if (gen != self->_scanGeneration) return;
            [self _rebuildFilteredItems];
            [self->_outlineView reloadData];
            [self _expandAllNodes];
            [self _updateEmptyState];
        });
    });
}

- (void)reload {
    EditorView *ed = _editor;
    if (ed) [self loadEditor:ed];
}

#pragma mark - Line offset table (O(n) build, O(log n) lookup)

/// Build a table of byte offsets for the start of each line.
- (void)_buildLineOffsetsFromUTF8:(const char *)utf8 length:(NSUInteger)len {
    free(_lineOffsets);
    // Estimate: one line per 40 bytes on average
    NSUInteger cap = MAX(len / 40, 256);
    _lineOffsets = (NSUInteger *)malloc(cap * sizeof(NSUInteger));
    _lineOffsetCount = 0;

    _lineOffsets[_lineOffsetCount++] = 0; // line 1 starts at offset 0
    for (NSUInteger i = 0; i < len; i++) {
        if (utf8[i] == '\n') {
            if (_lineOffsetCount >= cap) {
                cap *= 2;
                _lineOffsets = (NSUInteger *)realloc(_lineOffsets, cap * sizeof(NSUInteger));
            }
            _lineOffsets[_lineOffsetCount++] = i + 1;
        }
    }
}

/// Fast O(log n) line lookup using the pre-built offset table. Returns 1-based line number.
- (NSInteger)_fastLineForPos:(NSUInteger)pos {
    if (!_lineOffsets || _lineOffsetCount == 0) return 1;
    // Binary search: find the last offset <= pos
    NSUInteger lo = 0, hi = _lineOffsetCount;
    while (lo < hi) {
        NSUInteger mid = (lo + hi) / 2;
        if (_lineOffsets[mid] <= pos) lo = mid + 1;
        else hi = mid;
    }
    return (NSInteger)lo; // lo is 1-based line number
}

#pragma mark - XML/regex cache

/// Cache parsed XML parser elements + compiled regexes per language.
/// Key = language name, Value = NSDictionary with parsed data.
static NSMutableDictionary<NSString *, NSDictionary *> *_xmlParserCache = nil;

static NSDictionary *_cachedParserForLanguage(NSString *lang) {
    if (!_xmlParserCache) _xmlParserCache = [NSMutableDictionary new];
    return _xmlParserCache[lang];
}

static void _cacheParser(NSString *lang, NSDictionary *entry) {
    if (!_xmlParserCache) _xmlParserCache = [NSMutableDictionary new];
    _xmlParserCache[lang] = entry;
}

#pragma mark - XML-based function list parser engine

/// Convert PCRE regex to ICU-compatible regex. Returns nil if unconvertible
/// (e.g. uses (?(DEFINE)...) or (?&name) subroutines).
static NSString *_pcreToICU(NSString *pcre) {
    if (!pcre.length) return nil;

    // Features that cannot be converted — bail out to hardcoded fallback
    if ([pcre containsString:@"(?(DEFINE)"] || [pcre containsString:@"(?&"])
        return nil;

    NSMutableString *s = [pcre mutableCopy];

    // \K (reset match start) — remove it; we'll match from the start and use nameExpr to extract
    [s replaceOccurrencesOfString:@"\\K" withString:@""
                          options:0 range:NSMakeRange(0, s.length)];

    // \h (horizontal whitespace) → [\\t ]
    [s replaceOccurrencesOfString:@"\\h" withString:@"[\\t\\x20]"
                          options:0 range:NSMakeRange(0, s.length)];

    // Named groups: (?'name'...) → (?<name>...)
    {
        NSRegularExpression *re = [NSRegularExpression
            regularExpressionWithPattern:@"\\(\\?'(\\w+)'" options:0 error:nil];
        if (re) {
            NSString *replaced = [re stringByReplacingMatchesInString:s options:0
                range:NSMakeRange(0, s.length) withTemplate:@"(?<$1>"];
            s = [replaced mutableCopy];
        }
    }

    // Named backrefs: \k'name' → \k<name>
    {
        NSRegularExpression *re = [NSRegularExpression
            regularExpressionWithPattern:@"\\\\k'(\\w+)'" options:0 error:nil];
        if (re) {
            NSString *replaced = [re stringByReplacingMatchesInString:s options:0
                range:NSMakeRange(0, s.length) withTemplate:@"\\k<$1>"];
            s = [replaced mutableCopy];
        }
    }

    // Scoped modifiers (?m-s:...) → strip the -s part (ICU doesn't support negated inline modifiers in groups)
    // Replace (?m-s: with (?m: and (?-s: with (?:
    {
        NSRegularExpression *re = [NSRegularExpression
            regularExpressionWithPattern:@"\\(\\?([a-z]*)-([a-z]+):" options:0 error:nil];
        if (re) {
            NSString *replaced = [re stringByReplacingMatchesInString:s options:0
                range:NSMakeRange(0, s.length) withTemplate:@"(?$1:"];
            s = [replaced mutableCopy];
        }
    }

    // XML entities that might appear in attributes: &lt; &gt; &amp;
    [s replaceOccurrencesOfString:@"&lt;" withString:@"<"
                          options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"&gt;" withString:@">"
                          options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"&amp;" withString:@"&"
                          options:0 range:NSMakeRange(0, s.length)];

    return s;
}

/// Try to compile an ICU regex from a PCRE pattern. Returns nil on failure.
static NSRegularExpression *_compilePattern(NSString *pcre, NSRegularExpressionOptions opts) {
    NSString *icu = _pcreToICU(pcre);
    if (!icu) return nil;
    NSError *err = nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:icu options:opts error:&err];
    if (err) {
        NSLog(@"[FuncList] Regex compile failed: %@ — pattern: %.80s...", err.localizedDescription, icu.UTF8String);
        return nil;
    }
    return re;
}

/// Load a function list XML file. Returns the <parser> element or nil.
static NSXMLElement *_loadParserXML(NSString *lang) {
    NSFileManager *fm = [NSFileManager defaultManager];

    // 1. Check user override: ~/.notepad++/functionList/<lang>.xml
    NSString *userPath = [NSHomeDirectory() stringByAppendingPathComponent:
                          [NSString stringWithFormat:@".notepad++/functionList/%@.xml", lang]];
    NSData *data = [fm fileExistsAtPath:userPath] ? [NSData dataWithContentsOfFile:userPath] : nil;

    // 2. Fall back to bundled: Resources/functionList/<lang>.xml
    if (!data) {
        NSString *bundlePath = [[NSBundle mainBundle] pathForResource:lang ofType:@"xml"
                                                         inDirectory:@"functionList"];
        if (bundlePath) data = [NSData dataWithContentsOfFile:bundlePath];
    }
    if (!data) return nil;

    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:data options:0 error:nil];
    if (!doc) return nil;

    NSArray *parsers = [doc nodesForXPath:@"//functionList/parser" error:nil];
    return parsers.count ? (NSXMLElement *)parsers[0] : nil;
}

/// Extract name from text using a chain of nameExpr elements (last one refines).
static NSString *_extractName(NSString *matchedText, NSArray<NSXMLElement *> *nameExprs) {
    NSString *result = matchedText;
    for (NSXMLElement *ne in nameExprs) {
        NSString *pattern = [[ne attributeForName:@"expr"] stringValue];
        if (!pattern.length) continue;
        NSRegularExpression *re = _compilePattern(pattern, 0);
        if (!re) continue;
        NSTextCheckingResult *m = [re firstMatchInString:result options:0
                                                   range:NSMakeRange(0, result.length)];
        if (m) result = [result substringWithRange:m.range];
    }
    return [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

/// Build an NSIndexSet of comment ranges (excluded from function matching).
/// No string mutation — just tracks which byte ranges are comments.
static NSIndexSet *_commentRanges(NSString *text, NSString *commentExpr) {
    if (!commentExpr.length) return nil;
    NSRegularExpression *re = _compilePattern(commentExpr,
        NSRegularExpressionAnchorsMatchLines | NSRegularExpressionDotMatchesLineSeparators);
    if (!re) return nil;

    NSMutableIndexSet *ranges = [NSMutableIndexSet new];
    [re enumerateMatchesInString:text options:0 range:NSMakeRange(0, text.length)
                      usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
        [ranges addIndexesInRange:m.range];
    }];
    return ranges.count ? ranges : nil;
}

/// Check if a match range overlaps with comment ranges.
static BOOL _isInComment(NSRange range, NSIndexSet *commentRanges) {
    if (!commentRanges) return NO;
    return [commentRanges intersectsIndexesInRange:range];
}

/// XML-based scan: parse a function list XML and populate _rootItems.
/// Returns YES if successful, NO if XML not found or unconvertible (fall back to hardcoded).
- (BOOL)_scanTextWithXML:(NSString *)text forLanguage:(NSString *)lang {
    // ── Load parser (cached) ──────────────────────────────────────────
    NSDictionary *cached = _cachedParserForLanguage(lang);
    NSXMLElement *parser = nil;
    NSRegularExpression *commentRE = nil;

    if (cached) {
        parser = cached[@"parser"];
        commentRE = cached[@"commentRE"]; // may be [NSNull null]
    } else {
        parser = _loadParserXML(lang);
        if (!parser) return NO;

        NSString *commentExpr = [[parser attributeForName:@"commentExpr"] stringValue];
        commentRE = commentExpr.length ? _compilePattern(commentExpr,
            NSRegularExpressionAnchorsMatchLines | NSRegularExpressionDotMatchesLineSeparators) : nil;

        _cacheParser(lang, @{
            @"parser": parser,
            @"commentRE": commentRE ?: [NSNull null]
        });
    }
    if (!parser) return NO;
    if ([commentRE isEqual:[NSNull null]]) commentRE = nil;

    // ── Build comment exclusion ranges ────────────────────────────────
    NSIndexSet *commentRanges = nil;
    if (commentRE) {
        NSMutableIndexSet *cRanges = [NSMutableIndexSet new];
        [commentRE enumerateMatchesInString:text options:0 range:NSMakeRange(0, text.length)
                                 usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
            [cRanges addIndexesInRange:m.range];
        }];
        if (cRanges.count) commentRanges = cRanges;
    }

    // ── Collect parser elements ───────────────────────────────────────
    NSArray<NSXMLElement *> *classRangeEls = [parser nodesForXPath:@"classRange" error:nil];
    NSArray<NSXMLElement *> *topFuncEls = [parser nodesForXPath:@"function" error:nil];
    NSMutableArray<NSXMLElement *> *topLevelFuncs = [NSMutableArray array];
    for (NSXMLElement *fe in topFuncEls) {
        if (![fe.parent.name isEqualToString:@"classRange"])
            [topLevelFuncs addObject:fe];
    }

    BOOL didParse = NO;

    // ── Process classRange elements ───────────────────────────────────
    for (NSXMLElement *crEl in classRangeEls) {
        NSString *crMainExpr = [[crEl attributeForName:@"mainExpr"] stringValue];
        NSRegularExpression *crRE = _compilePattern(crMainExpr,
            NSRegularExpressionAnchorsMatchLines | NSRegularExpressionDotMatchesLineSeparators);
        if (!crRE) continue;
        didParse = YES;

        NSArray<NSXMLElement *> *classNameExprs = [crEl nodesForXPath:@"className/nameExpr" error:nil];
        NSArray<NSXMLElement *> *nestedFuncEls = [crEl nodesForXPath:@"function" error:nil];

        [crRE enumerateMatchesInString:text options:0
                                 range:NSMakeRange(0, text.length)
                            usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
            if (_isInComment(m.range, commentRanges)) return;

            NSString *matchedText = [text substringWithRange:m.range];
            NSString *className = classNameExprs.count
                ? _extractName(matchedText, classNameExprs)
                : [matchedText componentsSeparatedByCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]][0];
            if (!className.length) return;

            NSInteger classLine = [self _fastLineForPos:m.range.location];
            _FuncItem *classNode = [[_FuncItem alloc] initWithName:className line:classLine
                                                               pos:(NSInteger)m.range.location isNode:YES];

            for (NSXMLElement *funcEl in nestedFuncEls) {
                NSString *funcMainExpr = [[funcEl attributeForName:@"mainExpr"] stringValue];
                NSRegularExpression *funcRE = _compilePattern(funcMainExpr,
                    NSRegularExpressionAnchorsMatchLines);
                if (!funcRE) continue;

                NSArray<NSXMLElement *> *funcNameExprs = [funcEl nodesForXPath:@"functionName/funcNameExpr" error:nil];
                if (!funcNameExprs.count)
                    funcNameExprs = [funcEl nodesForXPath:@"functionName/nameExpr" error:nil];

                [funcRE enumerateMatchesInString:matchedText options:0
                                           range:NSMakeRange(0, matchedText.length)
                                      usingBlock:^(NSTextCheckingResult *fm2, NSMatchingFlags f2, BOOL *stop2) {
                    NSString *funcMatch = [matchedText substringWithRange:fm2.range];
                    NSString *funcName = funcNameExprs.count
                        ? _extractName(funcMatch, funcNameExprs) : funcMatch;
                    if (!funcName.length) return;

                    NSUInteger absPos = m.range.location + fm2.range.location;
                    NSInteger funcLine = [self _fastLineForPos:absPos];
                    _FuncItem *leaf = [[_FuncItem alloc] initWithName:funcName line:funcLine
                                                                 pos:(NSInteger)absPos isNode:NO];
                    [classNode.children addObject:leaf];
                }];
            }

            [self->_rootItems addObject:classNode];
        }];
    }

    // ── Process top-level function elements ───────────────────────────
    for (NSXMLElement *funcEl in topLevelFuncs) {
        NSString *funcMainExpr = [[funcEl attributeForName:@"mainExpr"] stringValue];
        NSRegularExpression *funcRE = _compilePattern(funcMainExpr,
            NSRegularExpressionAnchorsMatchLines);
        if (!funcRE) continue;
        didParse = YES;

        NSArray<NSXMLElement *> *funcNameExprs = [funcEl nodesForXPath:@"functionName/funcNameExpr" error:nil];
        if (!funcNameExprs.count)
            funcNameExprs = [funcEl nodesForXPath:@"functionName/nameExpr" error:nil];
        NSArray<NSXMLElement *> *topClassExprs = [funcEl nodesForXPath:@"className/nameExpr" error:nil];

        [funcRE enumerateMatchesInString:text options:0
                                   range:NSMakeRange(0, text.length)
                              usingBlock:^(NSTextCheckingResult *fm3, NSMatchingFlags f3, BOOL *stop3) {
            if (_isInComment(fm3.range, commentRanges)) return;

            NSString *funcMatch = [text substringWithRange:fm3.range];
            NSString *funcName = funcNameExprs.count
                ? _extractName(funcMatch, funcNameExprs) : funcMatch;
            if (!funcName.length) return;

            NSInteger funcLine = [self _fastLineForPos:fm3.range.location];
            _FuncItem *leaf = [[_FuncItem alloc] initWithName:funcName line:funcLine
                                                         pos:(NSInteger)fm3.range.location isNode:NO];

            if (topClassExprs.count) {
                NSString *clsName = _extractName(funcMatch, topClassExprs);
                if (clsName.length) {
                    _FuncItem *parent = nil;
                    for (_FuncItem *existing in self->_rootItems) {
                        if (existing.isNode && [existing.name isEqualToString:clsName]) {
                            parent = existing;
                            break;
                        }
                    }
                    if (!parent) {
                        parent = [[_FuncItem alloc] initWithName:clsName line:funcLine
                                                             pos:(NSInteger)fm3.range.location isNode:YES];
                        [self->_rootItems addObject:parent];
                    }
                    [parent.children addObject:leaf];
                    return;
                }
            }

            [self->_rootItems addObject:leaf];
        }];
    }

    return didParse;
}

#pragma mark - Scanning (hierarchical: classes → methods)

- (void)_scanText:(NSString *)text forLanguage:(NSString *)lang {
    [_rootItems removeAllObjects];
    lang = lang.lowercaseString;

    // If XML-based parsing is enabled, try the multi-stage XML parser first.
    // Falls back to hardcoded regex if XML not found or patterns are unconvertible.
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kPrefFuncListUseXML]) {
        if ([self _scanTextWithXML:text forLanguage:lang])
            return; // XML parser succeeded
    }

    // ═══════════════════════════════════════════════════════════════════
    // Hardcoded regex fallback (original approach)
    // ═══════════════════════════════════════════════════════════════════

    // === Phase 1: Detect classes/structs/protocols ===
    NSMutableArray<_FuncItem *> *classNodes = [NSMutableArray array];

    // Check user override for class pattern
    NSString *userClassPattern = nil;
    _userFuncPatternForLanguage(lang, &userClassPattern);

    NSString *classPattern = userClassPattern; // nil if no user override
    if (!classPattern) {
        if ([@[@"c", @"cpp", @"objc", @"swift", @"java", @"cs", @"typescript", @"javascript",
               @"javascript.js", @"go", @"d", @"rust", @"kotlin"] containsObject:lang]) {
            classPattern = @"(?m)^[ \\t]*(?:public\\s+|private\\s+|protected\\s+|internal\\s+|abstract\\s+|final\\s+|static\\s+)*"
                           @"(?:class|struct|protocol|interface|enum)\\s+(\\w+)";
        } else if ([lang isEqualToString:@"python"]) {
            classPattern = @"(?m)^class\\s+(\\w+)";
        } else if ([lang isEqualToString:@"ruby"]) {
            classPattern = @"(?m)^[ \\t]*(?:class|module)\\s+(\\w+)";
        } else if ([lang isEqualToString:@"php"]) {
            classPattern = @"(?m)^[ \\t]*(?:abstract\\s+|final\\s+)?class\\s+(\\w+)";
        }
    }

    // Build a list of class ranges: {name, startLine, startPos, endPos}
    NSMutableArray *classRanges = [NSMutableArray array]; // @[@{name, start, end, node}]

    if (classPattern) {
        NSRegularExpression *classRE = [NSRegularExpression
            regularExpressionWithPattern:classPattern
                                 options:NSRegularExpressionAnchorsMatchLines error:nil];
        if (classRE) {
            [classRE enumerateMatchesInString:text options:0 range:NSMakeRange(0, text.length)
                                  usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
                NSRange nameR = [m rangeAtIndex:1];
                if (nameR.location == NSNotFound) return;
                NSString *name = [text substringWithRange:nameR];
                NSUInteger startPos = m.range.location;
                NSInteger line = [self _fastLineForPos:startPos];

                _FuncItem *node = [[_FuncItem alloc] initWithName:name line:line pos:(NSInteger)startPos isNode:YES];
                [classNodes addObject:node];

                // Find the class body end (brace counting)
                NSUInteger bodyStart = [self _findBraceOpen:text from:NSMaxRange(m.range)];
                NSUInteger bodyEnd   = [self _findBraceClose:text from:bodyStart];

                [classRanges addObject:@{@"name": name, @"start": @(bodyStart),
                                         @"end": @(bodyEnd), @"node": node}];
            }];
        }
    }

    // === Phase 2: Detect functions/methods ===
    NSString *funcPattern = [self _funcPatternForLanguage:lang];
    if (!funcPattern) return;

    NSRegularExpression *funcRE = [NSRegularExpression
        regularExpressionWithPattern:funcPattern
                             options:NSRegularExpressionAnchorsMatchLines error:nil];
    if (!funcRE) return;

    NSMutableSet *addedNames = [NSMutableSet set]; // dedup

    [funcRE enumerateMatchesInString:text options:0 range:NSMakeRange(0, text.length)
                          usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
        // Try capture group 1, fall back to group 2 (for patterns with alternation)
        NSRange nameR = [m rangeAtIndex:1];
        if (nameR.location == NSNotFound && m.numberOfRanges > 2)
            nameR = [m rangeAtIndex:2];
        if (nameR.location == NSNotFound) return;
        NSString *name = [text substringWithRange:nameR];

        // Truncate long names (e.g. full XML tags) and collapse whitespace
        if (name.length > 50) name = [[name substringToIndex:50] stringByAppendingString:@"…"];
        name = [[name componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]
                componentsJoinedByString:@" "];

        // Dedup by name + position
        NSString *key = [NSString stringWithFormat:@"%@_%lu", name, (unsigned long)m.range.location];
        if ([addedNames containsObject:key]) return;
        [addedNames addObject:key];

        // Use the position of the captured NAME (not the full match start)
        // to get the exact line the function name appears on
        NSUInteger pos = nameR.location;
        NSInteger line = [self _fastLineForPos:pos];

        _FuncItem *leaf = [[_FuncItem alloc] initWithName:name line:line pos:(NSInteger)pos isNode:NO];

        // Check if this function is inside a class range
        BOOL nested = NO;
        for (NSDictionary *cr in classRanges) {
            NSUInteger cStart = [cr[@"start"] unsignedIntegerValue];
            NSUInteger cEnd   = [cr[@"end"] unsignedIntegerValue];
            if (pos > cStart && pos < cEnd) {
                _FuncItem *parentNode = cr[@"node"];
                [parentNode.children addObject:leaf];
                nested = YES;
                break;
            }
        }
        if (!nested) {
            [self->_rootItems addObject:leaf];
        }
    }];

    // Add class nodes (that have children) to root
    for (_FuncItem *node in classNodes) {
        if (node.children.count > 0) {
            // Sort children by line
            [node.children sortUsingComparator:^NSComparisonResult(_FuncItem *a, _FuncItem *b) {
                return a.line < b.line ? NSOrderedAscending : (a.line > b.line ? NSOrderedDescending : NSOrderedSame);
            }];
            [_rootItems addObject:node];
        }
    }

    // Sort root by line number (document order)
    [_rootItems sortUsingComparator:^NSComparisonResult(_FuncItem *a, _FuncItem *b) {
        return a.line < b.line ? NSOrderedAscending : (a.line > b.line ? NSOrderedDescending : NSOrderedSame);
    }];
}

/// Check ~/.notepad++/functionList/<lang>.xml for a user-defined pattern override.
/// Expected format:
///   <NotepadPlus><functionList><parser>
///     <function mainExpr="regex-with-capture-group-1-for-name" />
///     <classRange mainExpr="regex-with-capture-group-1-for-name" />  (optional)
///   </parser></functionList></NotepadPlus>
/// Returns nil if no user override exists or the file can't be parsed.
static NSString *_userFuncPatternForLanguage(NSString *lang, NSString * __autoreleasing *outClassPattern) {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@".notepad++/functionList/%@.xml", lang.lowercaseString]];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;

    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:data options:0 error:nil];
    if (!doc) return nil;

    // Extract function mainExpr
    NSArray *funcNodes = [doc nodesForXPath:@"//functionList/parser/function" error:nil];
    NSString *funcExpr = nil;
    if (funcNodes.count) {
        funcExpr = [[(NSXMLElement *)funcNodes[0] attributeForName:@"mainExpr"] stringValue];
    }

    // Extract optional classRange mainExpr
    if (outClassPattern) {
        NSArray *classNodes = [doc nodesForXPath:@"//functionList/parser/classRange" error:nil];
        if (classNodes.count) {
            *outClassPattern = [[(NSXMLElement *)classNodes[0] attributeForName:@"mainExpr"] stringValue];
        }
    }

    return funcExpr;
}

- (NSString *)_funcPatternForLanguage:(NSString *)lang {
    // Check user override first
    NSString *userPattern = _userFuncPatternForLanguage(lang, nil);
    if (userPattern.length) return userPattern;

    if ([lang isEqualToString:@"python"])
        return @"(?m)^[ \\t]*(?:async\\s+)?def\\s+(\\w+)\\s*\\(";
    if ([lang isEqualToString:@"ruby"])
        return @"(?m)^[ \\t]*def\\s+(\\w+)";
    if ([lang isEqualToString:@"bash"])
        return @"(?m)^[ \\t]*(\\w+)\\s*\\(\\s*\\)";
    if ([@[@"javascript", @"javascript.js", @"typescript"] containsObject:lang]) {
        return @"(?m)(?:function\\s+(\\w+)\\s*\\(|(?:async\\s+)?(\\w+)\\s*\\([^)]*\\)\\s*[:{])";
    }
    // Swift: func keyword required
    if ([lang isEqualToString:@"swift"]) {
        return @"(?m)^[ \\t]*(?:@\\w+\\s+)*(?:(?:public|private|internal|fileprivate|open|static|class|override|mutating|final)\\s+)*func\\s+(\\w+)";
    }
    // C/C++/ObjC/Java/C#: return-type + name + params + opening brace
    if ([@[@"c", @"cpp", @"objc", @"java", @"cs", @"go", @"d", @"actionscript", @"rc"] containsObject:lang]) {
        // [^)]* matches until closing paren (NOT [^;]* which crosses function boundaries)
        return @"(?m)^[\\t ]*(?:[\\w\\*<>\\[\\],&:\\s]+\\s+)(\\w+)\\s*\\([^)]*\\)\\s*(?:const\\s*)?(?:override\\s*)?(?:noexcept\\s*)?\\{";
    }
    if ([lang isEqualToString:@"php"])
        return @"(?m)^[ \\t]*(?:public\\s+|private\\s+|protected\\s+|static\\s+)*function\\s+(\\w+)\\s*\\(";
    if ([lang isEqualToString:@"go"])
        return @"(?m)^func\\s+(?:\\([^)]+\\)\\s+)?(\\w+)\\s*\\(";
    if ([lang isEqualToString:@"rust"])
        return @"(?m)^\\s*(?:pub(?:\\([^)]*\\))?\\s+)?(?:async\\s+)?fn\\s+(\\w+)";
    if ([lang isEqualToString:@"lua"])
        return @"(?m)(?:function\\s+(\\w[\\w.:]*)\\s*\\(|local\\s+function\\s+(\\w+)\\s*\\()";
    if ([lang isEqualToString:@"perl"])
        return @"(?m)^\\s*sub\\s+(\\w+)";
    if ([lang isEqualToString:@"haskell"])
        return @"(?m)^(\\w+)\\s+::";
    if ([lang isEqualToString:@"r"])
        return @"(?m)(\\w+)\\s*<-\\s*function\\s*\\(";
    if ([lang isEqualToString:@"powershell"])
        return @"(?m)^\\s*function\\s+(\\w[\\w-]*)";
    if ([lang isEqualToString:@"pascal"])
        return @"(?m)^\\s*(?:procedure|function)\\s+(\\w+)";
    if ([@[@"fortran", @"fortran77"] containsObject:lang])
        return @"(?mi)^\\s*(?:(?:integer|real|double\\s+precision|complex|logical|character|subroutine|function|program)\\s+)(\\w+)";
    if ([lang isEqualToString:@"ada"])
        return @"(?m)^\\s*(?:procedure|function)\\s+(\\w+)";
    if ([lang isEqualToString:@"vb"])
        return @"(?mi)^\\s*(?:public\\s+|private\\s+|friend\\s+)?(?:sub|function|property)\\s+(\\w+)";
    if ([lang isEqualToString:@"sql"] || [lang isEqualToString:@"mssql"])
        return @"(?mi)^\\s*create\\s+(?:or\\s+replace\\s+)?(?:function|procedure|trigger)\\s+(\\w+)";
    if ([lang isEqualToString:@"latex"])
        return @"(?m)\\\\(?:section|subsection|subsubsection|chapter|part)\\{([^}]+)\\}";
    if ([lang isEqualToString:@"makefile"])
        return @"(?m)^([\\w][\\w.-]*)\\s*:";
    if ([lang isEqualToString:@"cmake"])
        return @"(?mi)^\\s*(?:function|macro)\\s*\\(\\s*(\\w+)";
    if ([lang isEqualToString:@"nim"])
        return @"(?m)^\\s*(?:proc|func|method|iterator|template|macro)\\s+(\\w+)";
    if ([lang isEqualToString:@"erlang"])
        return @"(?m)^(\\w+)\\s*\\(";
    if ([lang isEqualToString:@"asm"])
        return @"(?m)^(\\w+):";
    if ([lang isEqualToString:@"vhdl"])
        return @"(?mi)^\\s*(?:procedure|function)\\s+(\\w+)";
    if ([lang isEqualToString:@"verilog"])
        return @"(?m)^\\s*(?:module|task|function)\\s+(\\w+)";
    if ([lang isEqualToString:@"css"])
        return @"(?m)^([.#]?[\\w][\\w.#>~+\\-\\s,:]*)\\s*\\{";
    if ([lang isEqualToString:@"ini"] || [lang isEqualToString:@"props"])
        return @"(?m)^\\[([^\\]]+)\\]";
    if ([lang isEqualToString:@"yaml"])
        return @"(?m)^(\\w[\\w-]*)\\s*:";
    if ([lang isEqualToString:@"toml"])
        return @"(?m)^\\[([^\\]]+)\\]";
    if ([lang isEqualToString:@"batch"])
        return @"(?mi)^\\s*:(\\w+)";
    if ([lang isEqualToString:@"coffeescript"])
        return @"(?m)^\\s*(\\w+)\\s*[=:]\\s*(?:\\([^)]*\\))?\\s*[-=]>";
    // XML/HTML: capture full opening tag (truncated to 50 chars in display)
    if ([lang isEqualToString:@"xml"] || [lang isEqualToString:@"html"] || [lang isEqualToString:@"asp"])
        return @"(?m)(<\\w+(?:\\s+[\\w:-]+\\s*=\\s*\"[^\"]*\")*\\s*/?>)";
    // JSON: top-level keys
    if ([lang isEqualToString:@"json"])
        return @"(?m)^\\s*\"(\\w[\\w\\s]*)\"\\s*:";
    // Generic fallback: C-style function definitions
    return @"(?m)^[\\t ]*[\\w\\*]+(?:[\\s\\*]+)(\\w+)\\s*\\([^)]*\\)\\s*\\{";
}

#pragma mark - Helpers

// _lineForPos:inText: removed — replaced by _fastLineForPos: (O(log n) binary search)

- (NSUInteger)_findBraceOpen:(NSString *)text from:(NSUInteger)start {
    NSUInteger len = text.length;
    for (NSUInteger i = start; i < len; i++) {
        unichar c = [text characterAtIndex:i];
        if (c == '{') return i;
        if (c == ';') return len; // declaration only, no body
    }
    return len;
}

- (NSUInteger)_findBraceClose:(NSString *)text from:(NSUInteger)start {
    NSUInteger len = text.length;
    NSInteger depth = 0;
    for (NSUInteger i = start; i < len; i++) {
        unichar c = [text characterAtIndex:i];
        if (c == '{') depth++;
        else if (c == '}') { depth--; if (depth <= 0) return i; }
    }
    return len;
}

#pragma mark - Filtering & sorting

- (void)_rebuildFilteredItems {
    [_filteredItems removeAllObjects];

    BOOL hasSearch = (_searchText.length > 0);
    NSString *lowerSearch = _searchText.lowercaseString;

    for (_FuncItem *item in _rootItems) {
        if (item.isNode) {
            // Filter children, keep node if any child matches
            _FuncItem *filteredNode = nil;
            for (_FuncItem *child in item.children) {
                if (!hasSearch || [child.name.lowercaseString containsString:lowerSearch]) {
                    if (!filteredNode) {
                        filteredNode = [[_FuncItem alloc] initWithName:item.name
                                                                  line:item.line pos:item.pos isNode:YES];
                    }
                    [filteredNode.children addObject:child];
                }
            }
            // Also match the node name itself
            if (!filteredNode && hasSearch && [item.name.lowercaseString containsString:lowerSearch]) {
                filteredNode = item; // include all children
            }
            if (filteredNode) [_filteredItems addObject:filteredNode];
            else if (!hasSearch) [_filteredItems addObject:item];
        } else {
            // Leaf at root level
            if (!hasSearch || [item.name.lowercaseString containsString:lowerSearch]) {
                [_filteredItems addObject:item];
            }
        }
    }

    // Sort
    if (_sortAlpha) {
        [self _sortAlphabetically:_filteredItems];
    }
}

- (void)_sortAlphabetically:(NSMutableArray<_FuncItem *> *)items {
    [items sortUsingComparator:^NSComparisonResult(_FuncItem *a, _FuncItem *b) {
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];
    for (_FuncItem *item in items) {
        if (item.isNode && item.children.count > 0) {
            [self _sortAlphabetically:item.children];
        }
    }
}

- (void)_expandAllNodes {
    for (_FuncItem *item in _filteredItems) {
        if (item.isNode) [_outlineView expandItem:item];
    }
}

- (void)_updateEmptyState {
    _emptyLabel.hidden = (_filteredItems.count > 0);
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(nullable id)item {
    if (!item) return (NSInteger)_filteredItems.count;
    _FuncItem *fi = (_FuncItem *)item;
    return fi.isNode ? (NSInteger)fi.children.count : 0;
}

- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)index ofItem:(nullable id)item {
    if (!item) return _filteredItems[index];
    return ((_FuncItem *)item).children[index];
}

- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item {
    return ((_FuncItem *)item).isNode;
}

#pragma mark - NSOutlineViewDelegate

- (NSView *)outlineView:(NSOutlineView *)ov viewForTableColumn:(NSTableColumn *)col item:(id)item {
    _FuncItem *fi = (_FuncItem *)item;

    NSTableCellView *cell = [ov makeViewWithIdentifier:@"FLCell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] init];
        cell.identifier = @"FLCell";

        NSImageView *iv = [[NSImageView alloc] init];
        iv.translatesAutoresizingMaskIntoConstraints = NO;
        iv.imageScaling = NSImageScaleProportionallyDown;
        [cell addSubview:iv];
        cell.imageView = iv;

        NSTextField *tf = [NSTextField labelWithString:@""];
        tf.translatesAutoresizingMaskIntoConstraints = NO;
        tf.font = [NSFont systemFontOfSize:12];
        tf.lineBreakMode = NSLineBreakByTruncatingTail;
        [cell addSubview:tf];
        cell.textField = tf;

        [NSLayoutConstraint activateConstraints:@[
            [iv.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
            [iv.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [iv.widthAnchor constraintEqualToConstant:14],
            [iv.heightAnchor constraintEqualToConstant:14],
            [tf.leadingAnchor constraintEqualToAnchor:iv.trailingAnchor constant:4],
            [tf.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
            [tf.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    }

    cell.imageView.image = fi.isNode ? _nodeIcon : _leafIcon;
    cell.textField.stringValue = fi.name;
    return cell;
}

#pragma mark - Click handler

- (void)outlineViewSelectionDidChange:(NSNotification *)n {
    NSInteger row = _outlineView.selectedRow;
    if (row < 0) return;
    _FuncItem *fi = [_outlineView itemAtRow:row];
    if (!fi) return;
    EditorView *ed = _editor;
    if (!ed) return;

    NSInteger line = fi.line;
    // Give focus to Scintilla's inner content view (SCIContentView), then navigate.
    // Must target the content view — not ScintillaView itself — for selection to render.
    NSView *contentView = [ed.scintillaView content];
    [ed.window makeFirstResponder:contentView];

    // Use performSelector with delay so the focus change fully settles
    // before we set the selection (otherwise the focus-in event clears it).
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [ed goToLineNumber:line];
    });
}


- (void)_darkModeChanged:(NSNotification *)n {
    _titleBar.layer.backgroundColor = [NppThemeManager shared].panelBackground.CGColor;
}
@end
