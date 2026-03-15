#import "ClipboardHistoryPanel.h"

static const NSUInteger kMaxHistory = 30;

@implementation ClipboardHistoryPanel {
    NSTableView        *_tableView;
    NSMutableArray<NSString *> *_history;
    NSTimer            *_timer;
    NSInteger           _lastChangeCount;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _history = [NSMutableArray array];
        _lastChangeCount = [NSPasteboard generalPasteboard].changeCount;
        [self _buildLayout];
    }
    return self;
}

- (instancetype)init {
    return [self initWithFrame:NSZeroRect];
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

    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"clip"];
    col.resizingMask = NSTableColumnAutoresizingMask;
    [_tableView addTableColumn:col];
    [_tableView sizeLastColumnToFit];

    scroll.documentView = _tableView;
    [self addSubview:scroll];

    NSButton *clearBtn = [NSButton buttonWithTitle:@"Clear All"
                                            target:self
                                            action:@selector(_clearAll:)];
    clearBtn.translatesAutoresizingMaskIntoConstraints = NO;
    clearBtn.bezelStyle = NSBezelStyleRounded;
    [self addSubview:clearBtn];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:clearBtn.topAnchor constant:-2],

        [clearBtn.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4],
        [clearBtn.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-4],
        [clearBtn.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-4],
        [clearBtn.heightAnchor constraintEqualToConstant:22],
    ]];
    // Row click disabled — paste interaction removed to prevent crash
}

// ── Public API ────────────────────────────────────────────────────────────────

- (void)startMonitoring {
    if (_timer) return;
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.75
                                              target:self
                                            selector:@selector(_pollPasteboard:)
                                            userInfo:nil
                                             repeats:YES];
}

- (void)stopMonitoring {
    [_timer invalidate];
    _timer = nil;
}

// ── Private ───────────────────────────────────────────────────────────────────

- (void)_pollPasteboard:(NSTimer *)t {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSInteger current = pb.changeCount;
    if (current == _lastChangeCount) return;
    _lastChangeCount = current;

    NSString *str = [pb stringForType:NSPasteboardTypeString];
    if (!str.length) return;

    // Skip duplicate of most recent entry
    if (_history.count && [_history.firstObject isEqualToString:str]) return;

    [_history insertObject:str atIndex:0];
    if (_history.count > kMaxHistory) [_history removeLastObject];

    [_tableView reloadData];
}

- (void)_clearAll:(id)sender {
    [_history removeAllObjects];
    [_tableView reloadData];
}

// ── NSTableViewDataSource ─────────────────────────────────────────────────────

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)_history.count;
}

// ── NSTableViewDelegate ───────────────────────────────────────────────────────

- (nullable NSView *)tableView:(NSTableView *)tableView
            viewForTableColumn:(nullable NSTableColumn *)tableColumn
                           row:(NSInteger)row {
    NSString *entry = _history[row];
    // Truncate long entries for display
    NSString *display = entry.length > 80
        ? [[entry substringToIndex:80] stringByAppendingString:@"…"]
        : entry;
    // Collapse newlines for single-line display
    display = [display stringByReplacingOccurrencesOfString:@"\n" withString:@"↵"];
    display = [display stringByReplacingOccurrencesOfString:@"\r" withString:@"↵"];

    NSTextField *cell = [tableView makeViewWithIdentifier:@"ClipCell" owner:nil];
    if (!cell) {
        cell = [[NSTextField alloc] init];
        cell.identifier = @"ClipCell";
        cell.editable = NO;
        cell.bordered = NO;
        cell.drawsBackground = NO;
        cell.font = [NSFont systemFontOfSize:12];
    }
    cell.stringValue = display;
    return cell;
}

@end
