#import "IncrementalSearchBar.h"
#import "NppLocalizer.h"
#import "NppThemeManager.h"

static const CGFloat kBarHeight = 36.0;

@implementation IncrementalSearchBar {
    NSTextField *_findLabel;
    NSTextField *_searchField;
    NSButton    *_prevBtn, *_nextBtn, *_closeBtn;
    NSButton    *_matchCaseBtn;
    NSTextField *_statusLabel;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.wantsLayer = YES;
    self.layer.backgroundColor = [NppThemeManager shared].statusBarBackground.CGColor;
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(_darkModeChanged:)
               name:NPPDarkModeChangedNotification object:nil];

    // Separator at the top
    NSBox *sep = [[NSBox alloc] init];
    sep.boxType = NSBoxSeparator;
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:sep];

    // "Find:" label
    _findLabel = [NSTextField labelWithString:@"Find:"];
    NSTextField *label = _findLabel;
    label.font = [NSFont systemFontOfSize:12];
    label.textColor = [NSColor secondaryLabelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:label];

    // Search field
    _searchField = [NSTextField textFieldWithString:@""];
    _searchField.placeholderString = [[NppLocalizer shared] translate:@"Type to search…"];
    _searchField.translatesAutoresizingMaskIntoConstraints = NO;
    _searchField.delegate = self;
    [[_searchField cell] setScrollable:YES];
    [self addSubview:_searchField];

    // Prev / Next
    _prevBtn = [self makeButton:@"◀" action:@selector(findPrev:) tip:@"Find Previous (Shift+Enter)"];
    _nextBtn = [self makeButton:@"▶" action:@selector(findNext:) tip:@"Find Next (Enter)"];

    // Match Case
    _matchCaseBtn = [NSButton checkboxWithTitle:@"Match Case" target:self action:@selector(optionChanged:)];
    _matchCaseBtn.font = [NSFont systemFontOfSize:12];
    _matchCaseBtn.translatesAutoresizingMaskIntoConstraints = NO;

    // Status label
    _statusLabel = [NSTextField labelWithString:@""];
    _statusLabel.font = [NSFont systemFontOfSize:11];
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;

    // Close
    _closeBtn = [self makeButton:@"✕" action:@selector(closeBar:) tip:@"Close (Esc)"];
    _closeBtn.bezelStyle = NSBezelStyleInline;

    for (NSView *v in @[label, _searchField, _prevBtn, _nextBtn,
                        _matchCaseBtn, _statusLabel, _closeBtn])
        [self addSubview:v];

    NSDictionary *views = @{
        @"sep":    sep,
        @"lbl":    label,
        @"field":  _searchField,
        @"prev":   _prevBtn,
        @"next":   _nextBtn,
        @"mc":     _matchCaseBtn,
        @"status": _statusLabel,
        @"close":  _closeBtn,
    };
    NSDictionary *metrics = @{@"pad": @8, @"sp": @4};

    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint
        constraintsWithVisualFormat:@"H:|-(0)-[sep]-(0)-|" options:0 metrics:nil views:views]];
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint
        constraintsWithVisualFormat:@"H:|-(pad)-[lbl]-(sp)-[field(>=120)]-(sp)-[prev(28)]-(sp)-[next(28)]-(sp)-[mc]-(sp)-[status(>=60)]-(>=pad)-[close(24)]-(pad)-|"
                           options:NSLayoutFormatAlignAllCenterY metrics:metrics views:views]];
    [NSLayoutConstraint activateConstraints:@[
        [sep.topAnchor constraintEqualToAnchor:self.topAnchor],
        [sep.heightAnchor constraintEqualToConstant:1],
        [label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];

    [self retranslateUI];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_localizationChanged:)
                                                 name:NPPLocalizationChanged
                                               object:nil];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)_localizationChanged:(NSNotification *)note { [self retranslateUI]; }

- (void)retranslateUI {
    NppLocalizer *loc = [NppLocalizer shared];
    _findLabel.stringValue   = [loc translate:@"Find:"];
    _matchCaseBtn.title      = [loc translate:@"Match Case"];
    _prevBtn.toolTip         = [loc translate:@"Find Previous"];
    _nextBtn.toolTip         = [loc translate:@"Find Next"];
    _closeBtn.toolTip        = [loc translate:@"Close"];
}

- (CGFloat)preferredHeight { return kBarHeight; }

- (void)activate {
    [self.window makeFirstResponder:_searchField];
}

- (void)close {
    [_delegate incrementalSearchBarDidClose:self];
}

- (NSButton *)makeButton:(NSString *)title action:(SEL)action tip:(NSString *)tip {
    NSButton *b = [NSButton buttonWithTitle:title target:self action:action];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    b.bezelStyle = NSBezelStyleRounded;
    b.font = [NSFont systemFontOfSize:12];
    b.toolTip = tip;
    return b;
}

#pragma mark - Actions

- (void)findNext:(id)sender {
    NSString *text = _searchField.stringValue;
    if (!text.length) return;
    [_delegate incrementalSearchBar:self findText:text
                          matchCase:(_matchCaseBtn.state == NSControlStateValueOn)
                            forward:YES];
}

- (void)findPrev:(id)sender {
    NSString *text = _searchField.stringValue;
    if (!text.length) return;
    [_delegate incrementalSearchBar:self findText:text
                          matchCase:(_matchCaseBtn.state == NSControlStateValueOn)
                            forward:NO];
}

- (void)optionChanged:(id)sender {
    [self textDidChange:nil]; // re-run highlights with new match-case setting
}

- (void)closeBar:(id)sender {
    [self close];
}

- (void)setStatus:(NSString *)text found:(BOOL)found {
    _statusLabel.stringValue = text;
    _statusLabel.textColor = found
        ? [NSColor secondaryLabelColor]
        : [NSColor colorWithRed:0.9 green:0.0 blue:0.0 alpha:1.0];
}

#pragma mark - NSControlTextEditingDelegate (live search as user types)

- (void)controlTextDidChange:(NSNotification *)obj {
    if (obj.object != _searchField) return;
    [self textDidChange:obj];
}

- (void)textDidChange:(id)unused {
    NSString *text = _searchField.stringValue;
    if (!text.length) {
        [_delegate incrementalSearchBar:self findText:@"" matchCase:NO forward:YES];
        [self setStatus:@"" found:YES];
        return;
    }
    BOOL mc = (_matchCaseBtn.state == NSControlStateValueOn);
    [_delegate incrementalSearchBar:self findText:text matchCase:mc forward:YES];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)tv doCommandBySelector:(SEL)cmd {
    if (control == _searchField) {
        if (cmd == @selector(insertNewline:)) {
            BOOL shift = ([NSEvent modifierFlags] & NSEventModifierFlagShift) != 0;
            shift ? [self findPrev:nil] : [self findNext:nil];
            return YES;
        }
        if (cmd == @selector(cancelOperation:)) {
            [self close];
            return YES;
        }
    }
    return NO;
}

- (void)_darkModeChanged:(NSNotification *)n {
    self.layer.backgroundColor = [NppThemeManager shared].statusBarBackground.CGColor;
}

@end
