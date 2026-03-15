#import "FunctionListPanel.h"
#import "Scintilla.h"
#import "ScintillaMessages.h"

@implementation FunctionListPanel {
    NSScrollView           *_scrollView;
    NSTableView            *_tableView;
    NSMutableArray<NSDictionary *> *_items;  // @{@"name":NSString, @"line":NSNumber}
    __weak EditorView      *_editor;
    NSTextField            *_emptyLabel;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _items = [NSMutableArray array];
        [self buildUI];
    }
    return self;
}

- (instancetype)init {
    return [self initWithFrame:NSZeroRect];
}

- (void)buildUI {
    _tableView = [[NSTableView alloc] init];
    _tableView.headerView = nil;
    _tableView.rowHeight = 20;
    _tableView.intercellSpacing = NSMakeSize(0, 1);
    _tableView.allowsMultipleSelection = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [_tableView setTarget:self];
    [_tableView setAction:@selector(tableViewClicked:)];

    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"func"];
    col.resizingMask = NSTableColumnAutoresizingMask;
    [_tableView addTableColumn:col];

    _scrollView = [[NSScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.hasHorizontalScroller = NO;
    _scrollView.borderType = NSNoBorder;
    _scrollView.documentView = _tableView;
    [self addSubview:_scrollView];

    _emptyLabel = [NSTextField labelWithString:@"No functions found"];
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyLabel.textColor = [NSColor secondaryLabelColor];
    _emptyLabel.hidden = YES;
    [self addSubview:_emptyLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_emptyLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_emptyLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];
}

#pragma mark - Public API

- (void)loadEditor:(EditorView *)editor {
    _editor = editor;
    [_items removeAllObjects];

    if (!editor) {
        [_tableView reloadData];
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
    [_tableView reloadData];
    [self _updateEmptyState];
}

#pragma mark - Regex scanning

- (void)_scanText:(NSString *)text forLanguage:(NSString *)lang {
    lang = lang.lowercaseString;

    // Build array of (pattern, captureGroup) tuples
    NSMutableArray *patterns = [NSMutableArray array];

    if ([lang isEqualToString:@"python"]) {
        [patterns addObject:@[@"(?m)^[ \\t]*def\\s+(\\w+)\\s*\\(", @1]];
    } else if ([lang isEqualToString:@"ruby"]) {
        [patterns addObject:@[@"(?m)^[ \\t]*def\\s+(\\w+)", @1]];
    } else if ([lang isEqualToString:@"bash"]) {
        [patterns addObject:@[@"(?m)^[ \\t]*(\\w+)\\s*\\(\\s*\\)", @1]];
    } else if ([@[@"javascript", @"typescript"] containsObject:lang]) {
        [patterns addObject:@[@"(?m)function\\s+(\\w+)\\s*\\(", @1]];
        [patterns addObject:@[@"(?m)(\\w+)\\s*[:=]\\s*(?:async\\s+)?function\\s*\\(", @1]];
        [patterns addObject:@[@"(?m)(?:async\\s+)?(\\w+)\\s*\\([^)]*\\)\\s*\\{", @1]];
    } else if ([@[@"c", @"cpp", @"objc", @"swift", @"java", @"csharp"] containsObject:lang]) {
        [patterns addObject:@[@"(?m)^[\\w\\*]+(?:[\\s\\*]+)[\\w:~]+::(\\w+)\\s*\\(", @1]];
        [patterns addObject:@[@"(?m)^[\\t ]*[\\w\\*]+(?:[\\s\\*]+)(\\w+)\\s*\\([^;{]*\\)\\s*\\{", @1]];
    } else {
        // Generic: C-style functions
        [patterns addObject:@[@"(?m)^[\\t ]*[\\w\\*]+(?:[\\s\\*]+)(\\w+)\\s*\\([^;]*\\)\\s*\\{", @1]];
    }

    NSArray *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];

    for (NSArray *entry in patterns) {
        NSString *patStr = entry[0];
        NSError *err;
        NSRegularExpression *re = [NSRegularExpression
            regularExpressionWithPattern:patStr
                                 options:NSRegularExpressionAnchorsMatchLines
                                   error:&err];
        if (!re) continue;

        [re enumerateMatchesInString:text
                             options:0
                               range:NSMakeRange(0, text.length)
                          usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
            NSRange nameRange = [match rangeAtIndex:1];
            if (nameRange.location == NSNotFound) return;
            NSString *name = [text substringWithRange:nameRange];

            // Find 1-based line number by counting newlines before match
            NSUInteger charIdx = match.range.location;
            NSUInteger lineNum = 1;
            for (NSUInteger li = 0; li < MIN(charIdx, (NSUInteger)lines.count * 200); ) {
                NSRange lineRange = [text lineRangeForRange:NSMakeRange(lineNum - 1 < lines.count ? li : 0, 0)];
                // Simple approach: count newlines up to charIdx
                NSString *before = [text substringToIndex:charIdx];
                lineNum = [[before componentsSeparatedByString:@"\n"] count];
                break;
            }
            // Simpler: count \n chars before charIdx
            NSUInteger nl = 0;
            for (NSUInteger ci = 0; ci < charIdx && ci < (NSUInteger)text.length; ci++) {
                if ([text characterAtIndex:ci] == '\n') nl++;
            }
            lineNum = nl + 1;

            // Avoid duplicates
            for (NSDictionary *existing in self->_items) {
                if ([existing[@"name"] isEqualToString:name]) return;
            }
            [self->_items addObject:@{@"name": name, @"line": @(lineNum)}];
        }];
    }

    // Sort by line number
    [_items sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"line" ascending:YES]]];
}

- (void)_updateEmptyState {
    _emptyLabel.hidden = (_items.count > 0);
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv {
    return (NSInteger)_items.count;
}

- (nullable id)tableView:(NSTableView *)tv
objectValueForTableColumn:(nullable NSTableColumn *)col
                     row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_items.count) return nil;
    NSDictionary *item = _items[row];
    NSInteger line = [item[@"line"] integerValue];
    return [NSString stringWithFormat:@"  %@  (ln %ld)", item[@"name"], (long)line];
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tv
   viewForTableColumn:(nullable NSTableColumn *)col
                  row:(NSInteger)row {
    NSTextField *cell = [tv makeViewWithIdentifier:@"FuncCell" owner:self];
    if (!cell) {
        cell = [[NSTextField alloc] init];
        cell.identifier = @"FuncCell";
        cell.editable = NO;
        cell.bordered = NO;
        cell.drawsBackground = NO;
        cell.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    }
    cell.stringValue = [self tableView:tv objectValueForTableColumn:col row:row] ?: @"";
    return cell;
}

#pragma mark - Click handler

- (void)tableViewClicked:(id)sender {
    NSInteger row = _tableView.clickedRow;
    if (row < 0 || row >= (NSInteger)_items.count) return;
    EditorView *ed = _editor;
    if (!ed) return;
    NSInteger line = [_items[row][@"line"] integerValue];
    [ed goToLineNumber:line];
    [ed.window makeFirstResponder:ed.scintillaView];
}

@end
