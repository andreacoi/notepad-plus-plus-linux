#import "DocumentListPanel.h"
#import "EditorView.h"
#import "NppLocalizer.h"
#import "StyleConfiguratorWindowController.h"
#import "NppThemeManager.h"

// ── Title-bar close button ───────────────────────────────────────────────────
// Mirrors _DMPCloseButton in DocumentMapPanel.mm / _FLPCloseButton in
// FunctionListPanel.mm: permanent 1px light-grey square border at rest,
// toolbar-style blue chrome on hover/press. Dark mode: only the border
// changes color on hover; the light-blue fill is skipped so it doesn't
// clash with the dark title strip.
@interface _DLPCloseButton : NSButton { BOOL _hovering; }
@end

@implementation _DLPCloseButton

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.bordered = NO;
        self.buttonType = NSButtonTypeMomentaryChange;
        self.title = @"";
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

- (void)mouseEntered:(NSEvent *)event { _hovering = YES; [self setNeedsDisplay:YES]; }
- (void)mouseExited:(NSEvent *)event  { _hovering = NO;  [self setNeedsDisplay:YES]; }

- (void)drawRect:(NSRect)dirtyRect {
    BOOL pressed = self.isHighlighted;
    BOOL active  = pressed || _hovering;
    BOOL isDark  = [NppThemeManager shared].isDark;

    if (active && !isDark) {
        NSColor *bg = pressed
            ? [NSColor colorWithRed:0xCC/255.0 green:0xE8/255.0 blue:0xFF/255.0 alpha:1.0]
            : [NSColor colorWithRed:0xE5/255.0 green:0xF3/255.0 blue:0xFF/255.0 alpha:1.0];
        [bg setFill];
        NSRectFill(self.bounds);
    }

    NSColor *bdr = active
        ? [NSColor colorWithRed:0xD0/255.0 green:0xEA/255.0 blue:0xFF/255.0 alpha:1.0]
        : [NSColor colorWithWhite:0.75 alpha:1.0];
    NSBezierPath *border = [NSBezierPath bezierPathWithRect:NSInsetRect(self.bounds, 0.5, 0.5)];
    border.lineWidth = 1.0;
    [bdr setStroke];
    [border stroke];

    NSString *glyph = @"✕";
    NSDictionary *attrs = @{
        NSFontAttributeName: self.font ?: [NSFont systemFontOfSize:11],
        NSForegroundColorAttributeName: [NSColor labelColor],
    };
    NSSize sz = [glyph sizeWithAttributes:attrs];
    NSPoint origin = NSMakePoint(NSMidX(self.bounds) - sz.width / 2.0,
                                 NSMidY(self.bounds) - sz.height / 2.0);
    [glyph drawAtPoint:origin withAttributes:attrs];
}

@end

@implementation DocumentListPanel {
    TabManager   *_tabManager;
    NSScrollView *_scrollView;
    NSTableView  *_tableView;
    NSArray<EditorView *> *_items;
    NSTextField  *_titleLabel;
    NSView       *_titleBar;
    CGFloat       _panelFontSize;
}

- (instancetype)initWithTabManager:(TabManager *)tabManager {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _tabManager = tabManager;
        _items = @[];
        { CGFloat z = [[NSUserDefaults standardUserDefaults] floatForKey:@"PanelZoom_DocumentList"]; _panelFontSize = z >= 8 ? z : 11; }
        [self _buildLayout];
        [self retranslateUI];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_locChanged:)
                                                     name:NPPLocalizationChanged object:nil];
    }
    return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)_locChanged:(NSNotification *)n { [self retranslateUI]; }
- (void)retranslateUI {
    _titleLabel.stringValue = [[NppLocalizer shared] translate:@"Document List"];
}

- (void)_buildLayout {
    // ── Title bar ─────────────────────────────────────────────────────────────
        _titleBar = [[NSView alloc] init];
    _titleBar.translatesAutoresizingMaskIntoConstraints = NO;
    _titleBar.wantsLayer = YES;
    _titleBar.layer.backgroundColor = [NppThemeManager shared].tabBarBackground.CGColor;
    [self addSubview:_titleBar];

    _titleLabel = [NSTextField labelWithString:[[NppLocalizer shared] translate:@"Document List"]];
    NSTextField *titleLabel = _titleLabel;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [NSFont systemFontOfSize:11];
    titleLabel.textColor = [NSColor labelColor];
    titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_titleBar addSubview:titleLabel];

    _DLPCloseButton *closeBtn = [[_DLPCloseButton alloc] initWithFrame:NSZeroRect];
    closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    closeBtn.target = self;
    closeBtn.action = @selector(_closePanel:);
    closeBtn.font = [NSFont systemFontOfSize:11];
    [_titleBar addSubview:closeBtn];

    [NSLayoutConstraint activateConstraints:@[
        [_titleBar.topAnchor      constraintEqualToAnchor:self.topAnchor],
        [_titleBar.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [_titleBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_titleBar.heightAnchor   constraintEqualToConstant:24],

        [titleLabel.leadingAnchor  constraintEqualToAnchor:_titleBar.leadingAnchor constant:6],
        [titleLabel.centerYAnchor  constraintEqualToAnchor:_titleBar.centerYAnchor],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:closeBtn.leadingAnchor constant:-4],

        [closeBtn.trailingAnchor constraintEqualToAnchor:_titleBar.trailingAnchor constant:-6],
        [closeBtn.centerYAnchor  constraintEqualToAnchor:_titleBar.centerYAnchor],
        [closeBtn.widthAnchor    constraintEqualToConstant:16],
        [closeBtn.heightAnchor   constraintEqualToConstant:16],
    ]];

    // ── Separator ─────────────────────────────────────────────────────────────
    NSBox *sep = [[NSBox alloc] init];
    sep.boxType = NSBoxSeparator;
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:sep];
    [NSLayoutConstraint activateConstraints:@[
        [sep.topAnchor      constraintEqualToAnchor:_titleBar.bottomAnchor],
        [sep.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [sep.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [sep.heightAnchor   constraintEqualToConstant:1],
    ]];

    // ── Table ─────────────────────────────────────────────────────────────────
    _scrollView = [[NSScrollView alloc] init];
    NSScrollView *scroll = _scrollView;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.autohidesScrollers = YES;

    _tableView = [[NSTableView alloc] init];
    _tableView.headerView = nil;
    _tableView.rowHeight = 18;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.allowsEmptySelection = YES;
    _tableView.allowsMultipleSelection = NO;
    _tableView.usesAlternatingRowBackgroundColors = NO;

    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    col.resizingMask = NSTableColumnAutoresizingMask;
    [_tableView addTableColumn:col];
    [_tableView sizeLastColumnToFit];

    scroll.documentView = _tableView;
    [self addSubview:scroll];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor      constraintEqualToAnchor:sep.bottomAnchor],
        [scroll.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [scroll.bottomAnchor   constraintEqualToAnchor:self.bottomAnchor],
    ]];

    _tableView.target = self;
    _tableView.action = @selector(_rowClicked:);

    [self _applyTheme];
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(_themeChanged:)
               name:@"NPPPreferencesChanged" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_darkModeChanged:) name:NPPDarkModeChangedNotification object:nil];
}

- (void)_applyTheme {
    NSColor *bg = [[NPPStyleStore sharedStore] globalBg];
    _scrollView.backgroundColor = bg;
    _tableView.backgroundColor  = bg;
    [_tableView reloadData];   // refresh cell text colors
}

- (void)_themeChanged:(NSNotification *)note {
    [self _applyTheme];
}

- (void)_closePanel:(id)sender {
    [_delegate documentListPanelDidRequestClose:self];
}

- (void)reloadData {
    NSInteger prevSel = _tableView.selectedRow;
    _items = [_tabManager.allEditors copy];

    NSInteger currentIdx = NSNotFound;
    EditorView *current = _tabManager.currentEditor;
    for (NSUInteger i = 0; i < _items.count; i++) {
        if (_items[i] == current) { currentIdx = (NSInteger)i; break; }
    }

    [_tableView reloadData];

    if (currentIdx != NSNotFound) {
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)currentIdx]
                byExtendingSelection:NO];
        [_tableView scrollRowToVisible:currentIdx];
    } else if (prevSel >= 0) {
        [_tableView deselectAll:nil];
    }
}

// ── NSTableViewDataSource ─────────────────────────────────────────────────────

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)_items.count;
}

// ── NSTableViewDelegate ───────────────────────────────────────────────────────

- (nullable NSView *)tableView:(NSTableView *)tableView
            viewForTableColumn:(nullable NSTableColumn *)tableColumn
                           row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_items.count) return nil;
    EditorView *ed = _items[row];
    NSString *display = ed.isModified
        ? [NSString stringWithFormat:@"• %@", ed.displayName]
        : ed.displayName;

    NSTextField *cell = [tableView makeViewWithIdentifier:@"DocCell" owner:nil];
    if (!cell) {
        cell = [[NSTextField alloc] init];
        cell.identifier = @"DocCell";
        cell.editable = NO;
        cell.bordered = NO;
        cell.drawsBackground = NO;
        cell.font = [NSFont systemFontOfSize:12];
    }
    cell.stringValue = display;
    cell.textColor = [[NPPStyleStore sharedStore] globalFg];
    cell.font = [NSFont systemFontOfSize:_panelFontSize];
    return cell;
}

// ── Row click ─────────────────────────────────────────────────────────────────

- (void)_rowClicked:(id)sender {
    NSInteger row = _tableView.clickedRow;
    if (row >= 0 && row < (NSInteger)_items.count) {
        [_tabManager selectTabAtIndex:row];
    }
}


- (void)_darkModeChanged:(NSNotification *)n {
    _titleBar.layer.backgroundColor = [NppThemeManager shared].tabBarBackground.CGColor;
}

#pragma mark - Panel Zoom

- (void)_saveZoom { [[NSUserDefaults standardUserDefaults] setFloat:_panelFontSize forKey:@"PanelZoom_DocumentList"]; }
- (void)panelZoomIn    { _panelFontSize = MIN(_panelFontSize + 1, 28); _tableView.rowHeight = _panelFontSize + 8; [_tableView reloadData]; [self _saveZoom]; }
- (void)panelZoomOut   { _panelFontSize = MAX(_panelFontSize - 1, 8);  _tableView.rowHeight = _panelFontSize + 8; [_tableView reloadData]; [self _saveZoom]; }
- (void)panelZoomReset { _panelFontSize = 11; _tableView.rowHeight = 19; [_tableView reloadData]; [self _saveZoom]; }
@end
