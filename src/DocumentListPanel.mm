#import "DocumentListPanel.h"
#import "EditorView.h"
#import "NppLocalizer.h"
#import "StyleConfiguratorWindowController.h"
#import "NppThemeManager.h"

@implementation DocumentListPanel {
    TabManager   *_tabManager;
    NSScrollView *_scrollView;
    NSTableView  *_tableView;
    NSArray<EditorView *> *_items;
    NSTextField  *_titleLabel;
    NSView       *_titleBar;
}

- (instancetype)initWithTabManager:(TabManager *)tabManager {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _tabManager = tabManager;
        _items = @[];
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
    _titleBar.layer.backgroundColor = [NppThemeManager shared].panelBackground.CGColor;
    [self addSubview:_titleBar];

    _titleLabel = [NSTextField labelWithString:[[NppLocalizer shared] translate:@"Document List"]];
    NSTextField *titleLabel = _titleLabel;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [NSFont boldSystemFontOfSize:11];
    titleLabel.textColor = [NSColor labelColor];
    titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_titleBar addSubview:titleLabel];

    NSButton *closeBtn = [NSButton buttonWithTitle:@"✕" target:self action:@selector(_closePanel:)];
    closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    closeBtn.bezelStyle = NSBezelStyleInline;
    closeBtn.bordered = NO;
    closeBtn.font = [NSFont systemFontOfSize:11];
    [_titleBar addSubview:closeBtn];

    [NSLayoutConstraint activateConstraints:@[
        [_titleBar.topAnchor      constraintEqualToAnchor:self.topAnchor],
        [_titleBar.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [_titleBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_titleBar.heightAnchor   constraintEqualToConstant:26],

        [titleLabel.leadingAnchor  constraintEqualToAnchor:_titleBar.leadingAnchor constant:6],
        [titleLabel.centerYAnchor  constraintEqualToAnchor:_titleBar.centerYAnchor],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:closeBtn.leadingAnchor constant:-4],

        [closeBtn.trailingAnchor constraintEqualToAnchor:_titleBar.trailingAnchor constant:-6],
        [closeBtn.centerYAnchor  constraintEqualToAnchor:_titleBar.centerYAnchor],
        [closeBtn.widthAnchor    constraintEqualToConstant:20],
        [closeBtn.heightAnchor   constraintEqualToConstant:20],
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
    _titleBar.layer.backgroundColor = [NppThemeManager shared].panelBackground.CGColor;
}

#pragma mark - Panel Zoom

- (void)panelZoomIn {
    NSFont *f = _tableView.font ?: [NSFont systemFontOfSize:12];
    _tableView.font = [NSFont fontWithName:f.fontName size:f.pointSize + 1];
    _tableView.rowHeight = f.pointSize + 1 + 8;
    [_tableView reloadData];
}
- (void)panelZoomOut {
    NSFont *f = _tableView.font ?: [NSFont systemFontOfSize:12];
    if (f.pointSize <= 6) return;
    _tableView.font = [NSFont fontWithName:f.fontName size:f.pointSize - 1];
    _tableView.rowHeight = f.pointSize - 1 + 8;
    [_tableView reloadData];
}
- (void)panelZoomReset {
    _tableView.font = [NSFont systemFontOfSize:12];
    _tableView.rowHeight = 20;
    [_tableView reloadData];
}
@end
