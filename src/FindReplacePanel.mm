#import "FindReplacePanel.h"
#import "NppLocalizer.h"
#import "NppThemeManager.h"

static const CGFloat kFindOnlyHeight   = 44.0;
static const CGFloat kFindReplaceHeight = 80.0;
static const CGFloat kHiddenHeight     =  0.0;

@implementation FindReplacePanel {
    // Row 1 — Find
    NSTextField    *_findLabel;     // "Find:" — kept for retranslation
    NSTextField    *_findField;
    NSButton       *_matchCaseBtn;
    NSButton       *_wholeWordBtn;
    NSButton       *_wrapBtn;
    NSButton       *_findPrevBtn;
    NSButton       *_findNextBtn;
    NSButton       *_closeBtn;

    // Row 2 — Replace (hidden in find-only mode)
    NSView         *_replaceRow;
    NSTextField    *_replaceLabel;  // "Replace:" — kept for retranslation
    NSTextField    *_replaceField;
    NSButton       *_replaceBtn;
    NSButton       *_replaceAllBtn;

    BOOL            _replaceVisible;
    BOOL            _panelVisible;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = [NppThemeManager shared].statusBarBackground.CGColor;

        [[NSNotificationCenter defaultCenter]
            addObserver:self selector:@selector(_darkModeChanged:)
                   name:NPPDarkModeChangedNotification object:nil];

        // Separator line on top
        NSBox *sep = [[NSBox alloc] init];
        sep.boxType = NSBoxSeparator;
        sep.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:sep];
        [NSLayoutConstraint activateConstraints:@[
            [sep.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [sep.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [sep.topAnchor constraintEqualToAnchor:self.topAnchor],
            [sep.heightAnchor constraintEqualToConstant:1],
        ]];

        [self buildFindRow];
        [self buildReplaceRow];
        _panelVisible = NO;
        _replaceVisible = NO;
        _replaceRow.hidden = YES;

        // Retranslate when the user switches the app language.
        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(_localizationChanged:)
                   name:NPPLocalizationChanged
                 object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Build UI

- (void)buildFindRow {
    _findLabel = [self makeLabel:@"Find:"];
    NSTextField *label = _findLabel;

    _findField = [NSTextField textFieldWithString:@""];
    _findField.placeholderString = @"Search…";
    _findField.translatesAutoresizingMaskIntoConstraints = NO;
    (void)[[_findField cell] setScrollable:YES];

    _matchCaseBtn = [self makeCheckbox:@"Match Case" action:@selector(optionChanged:)];
    _wholeWordBtn = [self makeCheckbox:@"Whole Word" action:@selector(optionChanged:)];
    _wrapBtn      = [self makeCheckbox:@"Wrap"       action:@selector(optionChanged:)];
    _wrapBtn.state = NSControlStateValueOn; // wrap on by default

    _findPrevBtn = [self makeButton:@"◀" action:@selector(findPrev:) tip:@"Find Previous"];
    _findNextBtn = [self makeButton:@"▶" action:@selector(findNext:) tip:@"Find Next"];
    _closeBtn    = [self makeButton:@"✕" action:@selector(closePanel)  tip:@"Close"];
    _closeBtn.bezelStyle = NSBezelStyleInline;

    for (NSView *v in @[label, _findField, _matchCaseBtn, _wholeWordBtn, _wrapBtn,
                         _findPrevBtn, _findNextBtn, _closeBtn]) {
        [self addSubview:v];
    }

    NSDictionary *views = @{
        @"lbl"   : label,
        @"field" : _findField,
        @"mc"    : _matchCaseBtn,
        @"ww"    : _wholeWordBtn,
        @"wrap"  : _wrapBtn,
        @"prev"  : _findPrevBtn,
        @"next"  : _findNextBtn,
        @"close" : _closeBtn,
    };
    NSDictionary *metrics = @{@"pad": @8, @"sp": @4};

    // Horizontal: |pad-lbl-sp-field-sp-mc-sp-ww-sp-wrap-sp-prev-sp-next-pad-close-pad|
    [self addConstraints:
        [NSLayoutConstraint constraintsWithVisualFormat:
            @"H:|-(pad)-[lbl]-(sp)-[field(>=120)]-(sp)-[mc]-(sp)-[ww]-(sp)-[wrap]-(sp)-[prev(28)]-(sp)-[next(28)]-(>=pad)-[close(24)]-(pad)-|"
                                               options:NSLayoutFormatAlignAllCenterY
                                               metrics:metrics views:views]];

    // Vertical position of the find row: 8pt from top
    [NSLayoutConstraint activateConstraints:@[
        [label.centerYAnchor constraintEqualToAnchor:self.topAnchor constant:30],
    ]];
}

- (void)buildReplaceRow {
    _replaceRow = [[NSView alloc] init];
    _replaceRow.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_replaceRow];

    _replaceLabel = [self makeLabel:@"Replace:"];
    NSTextField *label = _replaceLabel;
    [_replaceRow addSubview:label];

    _replaceField = [NSTextField textFieldWithString:@""];
    _replaceField.placeholderString = @"Replace with…";
    _replaceField.translatesAutoresizingMaskIntoConstraints = NO;
    (void)[[_replaceField cell] setScrollable:YES];
    [_replaceRow addSubview:_replaceField];

    _replaceBtn    = [self makeButton:@"Replace"     action:@selector(replace:)    tip:nil];
    _replaceAllBtn = [self makeButton:@"Replace All" action:@selector(replaceAll:) tip:nil];
    [_replaceRow addSubview:_replaceBtn];
    [_replaceRow addSubview:_replaceAllBtn];

    NSDictionary *views   = @{@"lbl": label, @"field": _replaceField, @"rep": _replaceBtn, @"all": _replaceAllBtn};
    NSDictionary *metrics = @{@"pad": @8, @"sp": @4};

    [_replaceRow addConstraints:
        [NSLayoutConstraint constraintsWithVisualFormat:
            @"H:|-(pad)-[lbl]-(sp)-[field(>=120)]-(sp)-[rep]-(sp)-[all]"
                                               options:NSLayoutFormatAlignAllCenterY
                                               metrics:metrics views:views]];
    [NSLayoutConstraint activateConstraints:@[
        [label.centerYAnchor constraintEqualToAnchor:_replaceRow.centerYAnchor],
    ]];

    // Replace row sits below find row
    [NSLayoutConstraint activateConstraints:@[
        [_replaceRow.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [_replaceRow.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_replaceRow.topAnchor      constraintEqualToAnchor:self.topAnchor constant:kFindOnlyHeight],
        [_replaceRow.heightAnchor   constraintEqualToConstant:kFindOnlyHeight - 8],
    ]];
}

#pragma mark - Public

- (void)openForFind {
    _panelVisible    = YES;
    _replaceVisible  = NO;
    _replaceRow.hidden = YES;
    self.hidden = NO;
    [self.window makeFirstResponder:_findField];
}

- (void)openForReplace {
    _panelVisible    = YES;
    _replaceVisible  = YES;
    _replaceRow.hidden = NO;
    self.hidden = NO;
    [self.window makeFirstResponder:_findField];
}

- (void)closePanel {
    _panelVisible = NO;
    self.hidden = YES;
    [_delegate findPanelDidClose:self];
}

- (CGFloat)preferredHeight {
    if (!_panelVisible) return kHiddenHeight;
    return _replaceVisible ? kFindReplaceHeight : kFindOnlyHeight;
}

#pragma mark - Property accessors

- (NSString *)currentSearchText { return _findField.stringValue ?: @""; }
- (BOOL)currentMatchCase { return _matchCaseBtn.state == NSControlStateValueOn; }
- (BOOL)currentWholeWord { return _wholeWordBtn.state == NSControlStateValueOn; }
- (BOOL)currentWrap      { return _wrapBtn.state      == NSControlStateValueOn; }

#pragma mark - Actions

- (void)findNext:(id)sender {
    NSString *text = _findField.stringValue;
    if (!text.length) return;
    [_delegate findPanel:self findNext:text
              matchCase:_matchCaseBtn.state == NSControlStateValueOn
              wholeWord:_wholeWordBtn.state == NSControlStateValueOn
                   wrap:_wrapBtn.state == NSControlStateValueOn];
}

- (void)findPrev:(id)sender {
    NSString *text = _findField.stringValue;
    if (!text.length) return;
    [_delegate findPanel:self findPrev:text
              matchCase:_matchCaseBtn.state == NSControlStateValueOn
              wholeWord:_wholeWordBtn.state == NSControlStateValueOn
                   wrap:_wrapBtn.state == NSControlStateValueOn];
}

- (void)replace:(id)sender {
    NSString *text = _findField.stringValue;
    if (!text.length) return;
    [_delegate findPanel:self replace:text with:_replaceField.stringValue
              matchCase:_matchCaseBtn.state == NSControlStateValueOn
              wholeWord:_wholeWordBtn.state == NSControlStateValueOn];
}

- (void)replaceAll:(id)sender {
    NSString *text = _findField.stringValue;
    if (!text.length) return;
    [_delegate findPanel:self replaceAll:text with:_replaceField.stringValue
              matchCase:_matchCaseBtn.state == NSControlStateValueOn
              wholeWord:_wholeWordBtn.state == NSControlStateValueOn];
}

- (void)optionChanged:(id)sender {}

#pragma mark - Localization

- (void)_localizationChanged:(NSNotification *)note {
    [self retranslateUI];
}

/// Update all visible strings to the current language.
- (void)retranslateUI {
    NppLocalizer *loc = [NppLocalizer shared];
    _findLabel.stringValue    = [loc translate:@"Find:"];
    _replaceLabel.stringValue = [loc translate:@"Replace:"];
    _matchCaseBtn.title       = [loc translate:@"Match Case"];
    _wholeWordBtn.title       = [loc translate:@"Whole Word"];
    _wrapBtn.title            = [loc translate:@"Wrap"];
    _findPrevBtn.toolTip      = [loc translate:@"Find Previous"];
    _findNextBtn.toolTip      = [loc translate:@"Find Next"];
    _closeBtn.toolTip         = [loc translate:@"Close"];
    _replaceBtn.title         = [loc translate:@"Replace"];
    _replaceAllBtn.title      = [loc translate:@"Replace All"];
}

#pragma mark - Key handling: Enter = find next, Shift+Enter = find prev, Esc = close

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView
    doCommandBySelector:(SEL)cmd {
    if (control == _findField) {
        if (cmd == @selector(insertNewline:)) {
            BOOL shift = ([NSEvent modifierFlags] & NSEventModifierFlagShift) != 0;
            shift ? [self findPrev:nil] : [self findNext:nil];
            return YES;
        }
        if (cmd == @selector(cancelOperation:)) {
            [self closePanel];
            return YES;
        }
    }
    return NO;
}

#pragma mark - Factory helpers

- (NSTextField *)makeLabel:(NSString *)text {
    NSTextField *f = [NSTextField labelWithString:text];
    f.translatesAutoresizingMaskIntoConstraints = NO;
    f.font = [NSFont systemFontOfSize:12];
    f.textColor = [NSColor secondaryLabelColor];
    return f;
}

- (NSButton *)makeCheckbox:(NSString *)title action:(SEL)action {
    NSButton *b = [NSButton checkboxWithTitle:title target:self action:action];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    b.font = [NSFont systemFontOfSize:12];
    return b;
}

- (NSButton *)makeButton:(NSString *)title action:(SEL)action tip:(nullable NSString *)tip {
    NSButton *b = [NSButton buttonWithTitle:title target:self action:action];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    b.bezelStyle = NSBezelStyleRounded;
    b.font = [NSFont systemFontOfSize:12];
    if (tip) b.toolTip = tip;
    return b;
}

- (void)_darkModeChanged:(NSNotification *)n {
    self.layer.backgroundColor = [NppThemeManager shared].statusBarBackground.CGColor;
}

@end
