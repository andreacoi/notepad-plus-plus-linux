#import "DocumentListPanel.h"
#import "EditorView.h"
#import "StyleConfiguratorWindowController.h"
#import "NppThemeManager.h"

// Phase 2: title bar + close button + separator now supplied by PanelFrame.
// The panel body is just the table view, flush to edges.

@implementation DocumentListPanel {
    TabManager   *_tabManager;
    NSScrollView *_scrollView;
    NSTableView  *_tableView;
    NSArray<EditorView *> *_items;
    CGFloat       _panelFontSize;
}

- (instancetype)initWithTabManager:(TabManager *)tabManager {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _tabManager = tabManager;
        _items = @[];
        { CGFloat z = [[NSUserDefaults standardUserDefaults] floatForKey:@"PanelZoom_DocumentList"]; _panelFontSize = z >= 8 ? z : 11; }
        [self _buildLayout];
    }
    return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)_buildLayout {
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
        [scroll.topAnchor      constraintEqualToAnchor:self.topAnchor],
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


#pragma mark - Panel Zoom

- (void)_saveZoom { [[NSUserDefaults standardUserDefaults] setFloat:_panelFontSize forKey:@"PanelZoom_DocumentList"]; }
- (void)panelZoomIn    { _panelFontSize = MIN(_panelFontSize + 1, 28); _tableView.rowHeight = _panelFontSize + 8; [_tableView reloadData]; [self _saveZoom]; }
- (void)panelZoomOut   { _panelFontSize = MAX(_panelFontSize - 1, 8);  _tableView.rowHeight = _panelFontSize + 8; [_tableView reloadData]; [self _saveZoom]; }
- (void)panelZoomReset { _panelFontSize = 11; _tableView.rowHeight = 19; [_tableView reloadData]; [self _saveZoom]; }
@end
