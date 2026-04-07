#import "ClipboardHistoryPanel.h"
#import "NppLocalizer.h"
#import "StyleConfiguratorWindowController.h"
#import "NppThemeManager.h"

static const NSUInteger kMaxHistory = 30;

@implementation ClipboardHistoryPanel {
    NSView             *_titleBar;
    NSTextField        *_titleLabel;
    NSScrollView       *_scrollView;
    NSTableView        *_tableView;
    NSMutableArray<NSString *> *_history;
    NSTimer            *_timer;
    NSInteger           _lastChangeCount;
    CGFloat             _panelFontSize;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _history = [NSMutableArray array];
        { CGFloat z = [[NSUserDefaults standardUserDefaults] floatForKey:@"PanelZoom_ClipboardHistory"]; _panelFontSize = z >= 8 ? z : 11; }
        _lastChangeCount = [NSPasteboard generalPasteboard].changeCount;
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

- (void)_locChanged:(NSNotification *)n { [self retranslateUI]; }
- (void)retranslateUI {
    _titleLabel.stringValue = [[NppLocalizer shared] translate:@"Clipboard History"];
}

- (instancetype)init {
    return [self initWithFrame:NSZeroRect];
}

- (void)_buildLayout {
    // ── Title bar ──────────────────────────────────────────────────────────────
    _titleBar = [[NSView alloc] init];
    _titleBar.translatesAutoresizingMaskIntoConstraints = NO;
    _titleBar.wantsLayer = YES;
    _titleBar.layer.backgroundColor = [NppThemeManager shared].panelBackground.CGColor;
    [self addSubview:_titleBar];

    _titleLabel = [NSTextField labelWithString:[[NppLocalizer shared] translate:@"Clipboard History"]];
    NSTextField *titleLabel = _titleLabel;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
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
        [_titleBar.topAnchor     constraintEqualToAnchor:self.topAnchor],
        [_titleBar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_titleBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_titleBar.heightAnchor  constraintEqualToConstant:28],

        [titleLabel.leadingAnchor  constraintEqualToAnchor:_titleBar.leadingAnchor constant:8],
        [titleLabel.centerYAnchor  constraintEqualToAnchor:_titleBar.centerYAnchor],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:closeBtn.leadingAnchor constant:-4],

        [closeBtn.trailingAnchor constraintEqualToAnchor:_titleBar.trailingAnchor constant:-6],
        [closeBtn.centerYAnchor  constraintEqualToAnchor:_titleBar.centerYAnchor],
        [closeBtn.widthAnchor    constraintEqualToConstant:20],
        [closeBtn.heightAnchor   constraintEqualToConstant:20],
    ]];

    // ── Separator below title ──────────────────────────────────────────────────
    NSBox *sep = [[NSBox alloc] init];
    sep.boxType = NSBoxSeparator;
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:sep];
    [NSLayoutConstraint activateConstraints:@[
        [sep.topAnchor     constraintEqualToAnchor:_titleBar.bottomAnchor],
        [sep.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [sep.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [sep.heightAnchor  constraintEqualToConstant:1],
    ]];

    // ── Table ──────────────────────────────────────────────────────────────────
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

    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"clip"];
    col.resizingMask = NSTableColumnAutoresizingMask;
    [_tableView addTableColumn:col];
    [_tableView sizeLastColumnToFit];

    scroll.documentView = _tableView;
    [self addSubview:scroll];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor    constraintEqualToAnchor:sep.bottomAnchor],
        [scroll.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [scroll.bottomAnchor   constraintEqualToAnchor:self.bottomAnchor],
    ]];
}

- (void)_applyTheme {
    NPPStyleStore *store = [NPPStyleStore sharedStore];
    NSColor *bg = [store globalBg];
    _scrollView.backgroundColor = bg;
    _tableView.backgroundColor  = bg;
    [_tableView reloadData];
}

- (void)_themeChanged:(NSNotification *)note {
    [self _applyTheme];
}

- (void)_closePanel:(id)sender {
    [_delegate clipboardHistoryPanelDidRequestClose:self];
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

// ── Copy support ──────────────────────────────────────────────────────────────

/// NSTableView calls this for each selected row when the user presses Cmd+C.
/// Returning a writer here lets NSTableView handle copy: internally, preventing
/// the action from propagating up the responder chain and crashing.
- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView
              pasteboardWriterForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_history.count) return nil;
    NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
    [item setString:_history[row] forType:NSPasteboardTypeString];
    return item;
}

/// Fallback: if copy: bubbles up from the table without being handled, copy the
/// full (non-truncated) text of the selected entry to the general pasteboard.
- (void)copy:(id)sender {
    NSInteger row = _tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)_history.count) return;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:_history[row] forType:NSPasteboardTypeString];
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
    }
    NPPStyleStore *store = [NPPStyleStore sharedStore];
    NSString *fontName = [store globalFontName];
    int fontSize = [store globalFontSize];
    cell.font = [NSFont fontWithName:fontName size:fontSize ?: 12];
    cell.font = [NSFont systemFontOfSize:_panelFontSize];
    cell.textColor = [store globalFg];
    cell.stringValue = display;
    return cell;
}


- (void)_darkModeChanged:(NSNotification *)n {
    _titleBar.layer.backgroundColor = [NppThemeManager shared].panelBackground.CGColor;
}

#pragma mark - Panel Zoom

- (void)_saveZoom { [[NSUserDefaults standardUserDefaults] setFloat:_panelFontSize forKey:@"PanelZoom_ClipboardHistory"]; }
- (void)panelZoomIn    { _panelFontSize = MIN(_panelFontSize + 1, 28); _tableView.rowHeight = _panelFontSize + 8; [_tableView reloadData]; [self _saveZoom]; }
- (void)panelZoomOut   { _panelFontSize = MAX(_panelFontSize - 1, 8);  _tableView.rowHeight = _panelFontSize + 8; [_tableView reloadData]; [self _saveZoom]; }
- (void)panelZoomReset { _panelFontSize = 11; _tableView.rowHeight = 19; [_tableView reloadData]; [self _saveZoom]; }
@end
