#import "FunctionListPanel.h"
#import "NppLocalizer.h"
#import "StyleConfiguratorWindowController.h"
#import "Scintilla.h"
#import "ScintillaMessages.h"

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
}

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
    }
    return self;
}

- (instancetype)init { return [self initWithFrame:NSZeroRect]; }

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

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
    _titleBar.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;
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
    _outlineView.target = self;
    _outlineView.action = @selector(_outlineClicked:);
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
    _titleBar.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;
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

    if (!editor) {
        [_outlineView reloadData];
        [self _updateEmptyState];
        return;
    }

    // Grab full text from Scintilla
    intptr_t len = [editor.scintillaView message:SCI_GETLENGTH];
    char *buf = (char *)malloc((size_t)len + 1);
    if (!buf) { [self _updateEmptyState]; return; }
    [editor.scintillaView message:SCI_GETTEXT wParam:(uptr_t)(len + 1) lParam:(sptr_t)buf];
    NSString *text = [[NSString alloc] initWithBytes:buf length:(NSUInteger)len
                                            encoding:NSUTF8StringEncoding];
    free(buf);
    if (!text) { [self _updateEmptyState]; return; }

    [self _scanText:text forLanguage:editor.currentLanguage];
    [self _rebuildFilteredItems];
    [_outlineView reloadData];
    [self _expandAllNodes];
    [self _updateEmptyState];
}

- (void)reload {
    EditorView *ed = _editor;
    if (ed) [self loadEditor:ed];
}

#pragma mark - Scanning (hierarchical: classes → methods)

- (void)_scanText:(NSString *)text forLanguage:(NSString *)lang {
    [_rootItems removeAllObjects];
    lang = lang.lowercaseString;

    // === Phase 1: Detect classes/structs/protocols ===
    NSMutableArray<_FuncItem *> *classNodes = [NSMutableArray array];

    NSString *classPattern = nil;
    if ([@[@"c", @"cpp", @"objc", @"swift", @"java", @"csharp", @"typescript"] containsObject:lang]) {
        classPattern = @"(?m)^[ \\t]*(?:public\\s+|private\\s+|protected\\s+|internal\\s+|abstract\\s+|final\\s+|static\\s+)*"
                       @"(?:class|struct|protocol|interface|enum)\\s+(\\w+)";
    } else if ([lang isEqualToString:@"python"]) {
        classPattern = @"(?m)^class\\s+(\\w+)";
    } else if ([lang isEqualToString:@"ruby"]) {
        classPattern = @"(?m)^[ \\t]*(?:class|module)\\s+(\\w+)";
    } else if ([lang isEqualToString:@"php"]) {
        classPattern = @"(?m)^[ \\t]*(?:abstract\\s+|final\\s+)?class\\s+(\\w+)";
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
                NSInteger line = [self _lineForPos:startPos inText:text];

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
        NSRange nameR = [m rangeAtIndex:1];
        if (nameR.location == NSNotFound) return;
        NSString *name = [text substringWithRange:nameR];

        // Dedup by name + position
        NSString *key = [NSString stringWithFormat:@"%@_%lu", name, (unsigned long)m.range.location];
        if ([addedNames containsObject:key]) return;
        [addedNames addObject:key];

        NSUInteger pos = m.range.location;
        NSInteger line = [self _lineForPos:pos inText:text];

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

- (NSString *)_funcPatternForLanguage:(NSString *)lang {
    if ([lang isEqualToString:@"python"])
        return @"(?m)^[ \\t]*(?:async\\s+)?def\\s+(\\w+)\\s*\\(";
    if ([lang isEqualToString:@"ruby"])
        return @"(?m)^[ \\t]*def\\s+(\\w+)";
    if ([lang isEqualToString:@"bash"])
        return @"(?m)^[ \\t]*(\\w+)\\s*\\(\\s*\\)";
    if ([@[@"javascript", @"typescript"] containsObject:lang]) {
        // Matches: function foo(, async foo(, foo: function(, foo = function(, foo( ...{
        return @"(?m)(?:function\\s+(\\w+)\\s*\\(|(?:async\\s+)?(\\w+)\\s*\\([^)]*\\)\\s*[:{])";
    }
    if ([@[@"c", @"cpp", @"objc", @"swift", @"java", @"csharp"] containsObject:lang]) {
        return @"(?m)^[\\t ]*(?:[\\w\\*<>\\[\\],\\s]+\\s+)(\\w+)\\s*\\([^;]*\\)\\s*(?:\\{|->|throws|where)";
    }
    if ([lang isEqualToString:@"php"])
        return @"(?m)^[ \\t]*(?:public\\s+|private\\s+|protected\\s+|static\\s+)*function\\s+(\\w+)\\s*\\(";
    if ([lang isEqualToString:@"go"])
        return @"(?m)^func\\s+(?:\\([^)]+\\)\\s+)?(\\w+)\\s*\\(";
    if ([lang isEqualToString:@"rust"])
        return @"(?m)^\\s*(?:pub\\s+)?(?:async\\s+)?fn\\s+(\\w+)";
    if ([lang isEqualToString:@"lua"])
        return @"(?m)(?:function\\s+(\\w[\\w.:]*)\\s*\\(|local\\s+function\\s+(\\w+)\\s*\\()";
    if ([lang isEqualToString:@"perl"])
        return @"(?m)^\\s*sub\\s+(\\w+)";
    if ([lang isEqualToString:@"haskell"])
        return @"(?m)^(\\w+)\\s+::";
    if ([lang isEqualToString:@"r"])
        return @"(?m)(\\w+)\\s*<-\\s*function\\s*\\(";
    // Generic: C-style function definitions
    return @"(?m)^[\\t ]*[\\w\\*]+(?:[\\s\\*]+)(\\w+)\\s*\\([^;]*\\)\\s*\\{";
}

#pragma mark - Helpers

- (NSInteger)_lineForPos:(NSUInteger)pos inText:(NSString *)text {
    NSUInteger nl = 0;
    NSUInteger limit = MIN(pos, text.length);
    const char *utf8 = text.UTF8String;
    for (NSUInteger i = 0; i < limit; i++) {
        if (utf8[i] == '\n') nl++;
    }
    return (NSInteger)(nl + 1);
}

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

- (void)_outlineClicked:(id)sender {
    _FuncItem *fi = [_outlineView itemAtRow:_outlineView.clickedRow];
    if (!fi) return;
    EditorView *ed = _editor;
    if (!ed) return;

    // Navigate to the function's line
    [ed goToLineNumber:fi.line];
    [ed.window makeFirstResponder:ed.scintillaView];
}

@end
