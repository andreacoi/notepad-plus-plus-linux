#import "DocumentListPanel.h"
#import "EditorView.h"

@implementation DocumentListPanel {
    TabManager   *_tabManager;
    NSTableView  *_tableView;
    NSArray<EditorView *> *_items;
}

- (instancetype)initWithTabManager:(TabManager *)tabManager {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _tabManager = tabManager;
        _items = @[];
        [self _buildLayout];
    }
    return self;
}

- (void)_buildLayout {
    NSScrollView *scroll = [[NSScrollView alloc] init];
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
        [scroll.topAnchor constraintEqualToAnchor:self.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    // Single-click to select
    _tableView.target = self;
    _tableView.action = @selector(_rowClicked:);
}

- (void)reloadData {
    NSInteger prevSel = _tableView.selectedRow;
    _items = [_tabManager.allEditors copy];

    // Determine which row corresponds to the current editor
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
        // clear stale selection
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
    return cell;
}

// ── Row click ─────────────────────────────────────────────────────────────────

- (void)_rowClicked:(id)sender {
    NSInteger row = _tableView.clickedRow;
    if (row >= 0 && row < (NSInteger)_items.count) {
        [_tabManager selectTabAtIndex:row];
    }
}

@end
