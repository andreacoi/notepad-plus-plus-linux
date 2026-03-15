#import "FindInFilesPanel.h"

// ── Result model ──────────────────────────────────────────────────────────────

@class FIFLineNode;

@interface FIFFileNode : NSObject
@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic) NSMutableArray<FIFLineNode *> *lines;
- (instancetype)initWithPath:(NSString *)path;
@end

@interface FIFLineNode : NSObject
@property (nonatomic) NSInteger lineNumber;
@property (nonatomic, copy) NSString *lineText;   // trimmed line content
@property (nonatomic, copy) NSString *matchText;  // original search pattern
@property (nonatomic) BOOL matchCase;
@property (nonatomic, weak) FIFFileNode *parent;
@end

@implementation FIFFileNode
- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    _filePath    = path;
    _displayName = path.lastPathComponent;
    _lines       = [NSMutableArray array];
    return self;
}
@end

@implementation FIFLineNode @end

// ── Form-area height constant ──────────────────────────────────────────────────
// All form controls (search, dir, filter, options, buttons, status) live in a
// fixed-height container that is anchored to the top of the window. Only the
// results scroll view grows/shrinks when the user resizes vertically.
static const CGFloat kFormHeight = 178.0;

// ── FindInFilesPanel ──────────────────────────────────────────────────────────

@implementation FindInFilesPanel {
    // Search controls
    NSTextField     *_searchField;
    NSTextField     *_dirField;
    NSTextField     *_filterField;
    NSButton        *_matchCaseBox;
    NSButton        *_wholeWordBox;
    NSButton        *_searchBtn;
    NSButton        *_stopBtn;
    NSTextField     *_statusLabel;

    // Results
    NSOutlineView   *_outlineView;
    NSMutableArray<FIFFileNode *> *_results;
    NSInteger        _matchCount;

    // Background search
    NSOperationQueue *_searchQueue;
    BOOL             _searching;
}

+ (instancetype)sharedPanel {
    static FindInFilesPanel *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    NSWindow *win = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 700, 520)
                  styleMask:NSWindowStyleMaskTitled |
                            NSWindowStyleMaskClosable |
                            NSWindowStyleMaskResizable |
                            NSWindowStyleMaskMiniaturizable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    win.title = @"Find in Files";
    win.minSize = NSMakeSize(500, kFormHeight + 100);
    self = [super initWithWindow:win];
    if (self) {
        _results     = [NSMutableArray array];
        _searchQueue = [[NSOperationQueue alloc] init];
        _searchQueue.maxConcurrentOperationCount = 1;
        [self buildUI];
    }
    return self;
}

// ── UI construction ───────────────────────────────────────────────────────────
//
// Layout (AppKit coordinates, y=0 at bottom):
//
//  ┌─────────────────────────────────────────┐  ← window top
//  │  formView  (height=kFormHeight, fixed)  │  NSViewWidthSizable | NSViewMinYMargin
//  ├─────────────────────────────────────────┤
//  │  scrollView (grows with window)         │  NSViewWidthSizable | NSViewHeightSizable
//  └─────────────────────────────────────────┘  ← y=0

- (void)buildUI {
    NSView *root = self.window.contentView;
    CGFloat winH = 520, winW = 700;

    // ── Results scroll view (bottom, grows vertically) ────────────────────────
    CGFloat scrollH = winH - kFormHeight;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, winW, scrollH)];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller   = YES;
    scroll.hasHorizontalScroller = YES;
    scroll.borderType = NSBezelBorder;

    _outlineView = [[NSOutlineView alloc] init];
    _outlineView.dataSource = self;
    _outlineView.delegate   = self;
    _outlineView.autoresizesOutlineColumn = NO;
    _outlineView.indentationPerLevel = 16;

    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"result"];
    col.title = @"Results";
    col.width = winW - 75;
    col.resizingMask = NSTableColumnAutoresizingMask;
    [_outlineView addTableColumn:col];
    _outlineView.outlineTableColumn = col;

    NSTableColumn *lineCol = [[NSTableColumn alloc] initWithIdentifier:@"line"];
    lineCol.title = @"Line";
    lineCol.width = 55;
    lineCol.resizingMask = NSTableColumnNoResizing;
    [_outlineView addTableColumn:lineCol];

    _outlineView.target       = self;
    _outlineView.doubleAction = @selector(outlineDoubleClicked:);

    scroll.documentView = _outlineView;
    [root addSubview:scroll];

    // ── Form container (top, fixed height, anchored to top) ───────────────────
    // NSViewMinYMargin = flexible bottom margin → stays at top when window resizes.
    NSView *form = [[NSView alloc] initWithFrame:NSMakeRect(0, winH - kFormHeight, winW, kFormHeight)];
    form.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [root addSubview:form];

    // Controls are laid out inside `form` from top to bottom.
    // In AppKit (y=0 at bottom of `form`), top = kFormHeight.
    // Each row occupies 30px; options 28px; buttons 36px; status 22px.
    // Row Y values (bottom of each control), top-to-bottom visual order:
    CGFloat y = kFormHeight - 30;   // Search row

    // Search
    [form addSubview:[self labelIn:form at:NSMakeRect(10, y+4, 65, 18) text:@"Search:"]];
    _searchField = [self fieldIn:form frame:NSMakeRect(80, y, winW - 90, 22)
                     placeholder:@"Text to search for"];
    y -= 30;

    // Directory
    [form addSubview:[self labelIn:form at:NSMakeRect(10, y+4, 65, 18) text:@"Directory:"]];
    _dirField = [self fieldIn:form frame:NSMakeRect(80, y, winW - 140, 22) placeholder:@""];
    _dirField.stringValue = NSHomeDirectory();

    NSButton *browseBtn = [NSButton buttonWithTitle:@"…" target:self action:@selector(browseDirectory:)];
    browseBtn.frame = NSMakeRect(winW - 55, y, 45, 22);
    browseBtn.autoresizingMask = NSViewMinXMargin;
    [form addSubview:browseBtn];
    y -= 30;

    // Filter
    [form addSubview:[self labelIn:form at:NSMakeRect(10, y+4, 65, 18) text:@"Filter:"]];
    _filterField = [self fieldIn:form frame:NSMakeRect(80, y, 200, 22) placeholder:@"*.txt, *.cpp, …"];
    _filterField.stringValue = @"*.*";
    y -= 28;

    // Options
    _matchCaseBox = [NSButton checkboxWithTitle:@"Match case" target:nil action:nil];
    _matchCaseBox.frame = NSMakeRect(80, y, 115, 20);
    _matchCaseBox.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;
    [form addSubview:_matchCaseBox];

    _wholeWordBox = [NSButton checkboxWithTitle:@"Whole word" target:nil action:nil];
    _wholeWordBox.frame = NSMakeRect(205, y, 115, 20);
    _wholeWordBox.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;
    [form addSubview:_wholeWordBox];
    y -= 36;

    // Buttons (right-aligned)
    _stopBtn = [NSButton buttonWithTitle:@"Stop" target:self action:@selector(stopSearch:)];
    _stopBtn.frame = NSMakeRect(winW - 100, y, 90, 28);
    _stopBtn.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    _stopBtn.enabled = NO;
    [form addSubview:_stopBtn];

    _searchBtn = [NSButton buttonWithTitle:@"Search" target:self action:@selector(startSearch:)];
    _searchBtn.frame = NSMakeRect(winW - 200, y, 90, 28);
    _searchBtn.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    _searchBtn.keyEquivalent = @"\r";
    [form addSubview:_searchBtn];
    y -= 28;

    // Status label
    _statusLabel = [NSTextField labelWithString:@""];
    _statusLabel.frame = NSMakeRect(10, y, winW - 20, 18);
    _statusLabel.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [form addSubview:_statusLabel];
}

// ── Layout helpers ────────────────────────────────────────────────────────────

- (NSTextField *)labelIn:(NSView *)parent at:(NSRect)r text:(NSString *)t {
    NSTextField *f = [NSTextField labelWithString:t];
    f.frame = r;
    f.alignment = NSTextAlignmentRight;
    f.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;
    return f;
}

- (NSTextField *)fieldIn:(NSView *)parent frame:(NSRect)r placeholder:(NSString *)ph {
    NSTextField *f = [[NSTextField alloc] initWithFrame:r];
    f.placeholderString = ph;
    f.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [parent addSubview:f];
    return f;
}

// ── Search ────────────────────────────────────────────────────────────────────

- (void)startSearch:(id)sender {
    NSString *text = _searchField.stringValue;
    if (!text.length) { NSBeep(); return; }

    NSString *dir       = _dirField.stringValue;
    NSString *filter    = _filterField.stringValue;
    BOOL      matchCase = _matchCaseBox.state == NSControlStateValueOn;
    BOOL      wholeWord = _wholeWordBox.state == NSControlStateValueOn;

    [_searchQueue cancelAllOperations];
    [_results removeAllObjects];
    _matchCount = 0;
    [_outlineView reloadData];

    _searchBtn.enabled       = NO;
    _stopBtn.enabled         = YES;
    _searching               = YES;
    _statusLabel.stringValue = @"Searching…";

    NSBlockOperation *op = [NSBlockOperation blockOperationWithBlock:^{
        [self searchDirectory:dir pattern:text filter:filter matchCase:matchCase wholeWord:wholeWord];
    }];
    __weak NSBlockOperation *weakOp = op;
    op.completionBlock = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!weakOp.isCancelled)
                self->_statusLabel.stringValue = [NSString stringWithFormat:
                    @"Found %ld match(es) in %ld file(s).",
                    (long)self->_matchCount, (long)self->_results.count];
            self->_searchBtn.enabled = YES;
            self->_stopBtn.enabled   = NO;
            self->_searching         = NO;
        });
    };
    [_searchQueue addOperation:op];
}

- (void)stopSearch:(id)sender {
    [_searchQueue cancelAllOperations];
    _searchBtn.enabled       = YES;
    _stopBtn.enabled         = NO;
    _statusLabel.stringValue = @"Search stopped.";
}

- (void)searchDirectory:(NSString *)dir
                pattern:(NSString *)pattern
                 filter:(NSString *)filter
              matchCase:(BOOL)matchCase
              wholeWord:(BOOL)wholeWord {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *en = [fm enumeratorAtPath:dir];
    NSString *rel;

    // Build file-name glob predicates
    NSArray<NSString *> *globs = [filter componentsSeparatedByString:@","];
    NSMutableArray<NSPredicate *> *preds = [NSMutableArray array];
    for (NSString *g in globs) {
        NSString *t = [g stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (t.length) [preds addObject:[NSPredicate predicateWithFormat:@"SELF LIKE %@", t]];
    }

    NSStringCompareOptions cmpOpts = matchCase ? 0 : NSCaseInsensitiveSearch;

    while ((rel = [en nextObject])) {
        if ([_searchQueue.operations.firstObject isCancelled]) break;

        NSString *name = rel.lastPathComponent;
        BOOL pass = (preds.count == 0);
        for (NSPredicate *p in preds)
            if ([p evaluateWithObject:name]) { pass = YES; break; }
        if (!pass) continue;

        NSString *full = [dir stringByAppendingPathComponent:rel];
        BOOL isDir = NO;
        [fm fileExistsAtPath:full isDirectory:&isDir];
        if (isDir) continue;

        NSString *content = [NSString stringWithContentsOfFile:full
                                                      encoding:NSUTF8StringEncoding error:nil];
        if (!content) continue;

        NSArray<NSString *> *fileLines = [content componentsSeparatedByCharactersInSet:
            [NSCharacterSet newlineCharacterSet]];

        FIFFileNode *fileNode = nil;
        NSInteger ln = 0;
        for (NSString *line in fileLines) {
            ln++;
            NSRange range = [line rangeOfString:pattern options:cmpOpts];
            if (range.location == NSNotFound) continue;

            if (wholeWord) {
                if (range.location > 0) {
                    unichar c = [line characterAtIndex:range.location - 1];
                    if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:c] || c == '_')
                        continue;
                }
                NSUInteger end = range.location + range.length;
                if (end < line.length) {
                    unichar c = [line characterAtIndex:end];
                    if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:c] || c == '_')
                        continue;
                }
            }

            if (!fileNode) fileNode = [[FIFFileNode alloc] initWithPath:full];

            FIFLineNode *node  = [[FIFLineNode alloc] init];
            node.lineNumber    = ln;
            node.lineText      = [line stringByTrimmingCharactersInSet:
                                  [NSCharacterSet whitespaceCharacterSet]];
            node.matchText     = pattern;
            node.matchCase     = matchCase;
            node.parent        = fileNode;
            [fileNode.lines addObject:node];
        }

        if (fileNode) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self->_results addObject:fileNode];
                self->_matchCount += (NSInteger)fileNode.lines.count;
                [self->_outlineView reloadData];
                [self->_outlineView expandItem:fileNode];
                self->_statusLabel.stringValue = [NSString stringWithFormat:
                    @"Searching… %ld match(es) so far", (long)self->_matchCount];
            });
        }
    }
}

// ── Browse ────────────────────────────────────────────────────────────────────

- (void)browseDirectory:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories   = YES;
    panel.canChooseFiles         = NO;
    panel.allowsMultipleSelection = NO;
    panel.directoryURL = [NSURL fileURLWithPath:_dirField.stringValue];
    if ([panel runModal] == NSModalResponseOK)
        _dirField.stringValue = panel.URL.path;
}

// ── Double-click → open file, go to line, highlight match ────────────────────

- (void)outlineDoubleClicked:(id)sender {
    id item = [_outlineView itemAtRow:_outlineView.clickedRow];
    if ([item isKindOfClass:[FIFLineNode class]]) {
        FIFLineNode *node = item;
        [_delegate findInFilesPanel:self
                           openFile:node.parent.filePath
                             atLine:node.lineNumber
                          matchText:node.matchText
                          matchCase:node.matchCase];
    } else if ([item isKindOfClass:[FIFFileNode class]]) {
        FIFFileNode *node = item;
        [_delegate findInFilesPanel:self
                           openFile:node.filePath
                             atLine:1
                          matchText:@""
                          matchCase:NO];
    }
}

// ── NSOutlineViewDataSource ───────────────────────────────────────────────────

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(nullable id)item {
    if (!item) return (NSInteger)_results.count;
    if ([item isKindOfClass:[FIFFileNode class]])
        return (NSInteger)((FIFFileNode *)item).lines.count;
    return 0;
}

- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item {
    return [item isKindOfClass:[FIFFileNode class]];
}

- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)index ofItem:(nullable id)item {
    if (!item) return _results[(NSUInteger)index];
    return ((FIFFileNode *)item).lines[(NSUInteger)index];
}

// ── NSOutlineViewDelegate ─────────────────────────────────────────────────────

- (nullable NSView *)outlineView:(NSOutlineView *)ov
              viewForTableColumn:(nullable NSTableColumn *)col
                            item:(id)item {
    NSString *ident = col.identifier;
    NSTextField *cell = [ov makeViewWithIdentifier:ident owner:self];
    if (!cell) {
        cell = [NSTextField labelWithString:@""];
        cell.identifier = ident;
    }

    if ([ident isEqualToString:@"result"]) {
        if ([item isKindOfClass:[FIFFileNode class]]) {
            FIFFileNode *node = item;
            cell.stringValue = [NSString stringWithFormat:@"%@ (%ld match%@)",
                node.displayName, (long)node.lines.count,
                node.lines.count == 1 ? @"" : @"es"];
            cell.font = [NSFont boldSystemFontOfSize:12];
        } else {
            cell.stringValue = ((FIFLineNode *)item).lineText;
            cell.font = [NSFont systemFontOfSize:12];
        }
    } else {  // "line" column
        if ([item isKindOfClass:[FIFLineNode class]])
            cell.stringValue = [NSString stringWithFormat:@"%ld", (long)((FIFLineNode *)item).lineNumber];
        else
            cell.stringValue = @"";
        cell.alignment = NSTextAlignmentRight;
    }
    return cell;
}

@end
