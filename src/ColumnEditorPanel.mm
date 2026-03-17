#import "ColumnEditorPanel.h"
#import "EditorView.h"

// ── ColumnEditorPanel ─────────────────────────────────────────────────────────
// Mirrors NPP's Column / Multi-Selection Editor dialog.
// Two modes (Text / Number) selected by radio buttons at the top.

@interface ColumnEditorPanel ()
@end

@implementation ColumnEditorPanel {
    NSWindow        *_sheet;
    // Mode radios
    NSButton        *_textRadio;
    NSButton        *_numRadio;
    // Text section
    NSTextField     *_textField;
    // Number section — format radios
    NSButton        *_decRadio;
    NSButton        *_octRadio;
    NSButton        *_hexRadio;
    NSPopUpButton   *_hexCasePop;   // a-f / A-F
    NSButton        *_binRadio;
    // Number section — value fields
    NSTextField     *_numInitial;
    NSTextField     *_numStep;
    NSTextField     *_numRepeat;
    NSPopUpButton   *_leadingPop;   // None / Zeros / Spaces
    // References
    EditorView      *_editor;
    NSWindow        *_parentWindow;
    // Cached number-section views for enable/disable
    NSArray         *_numberOnlyViews;
}

+ (void)showForEditor:(EditorView *)editor parentWindow:(NSWindow *)window {
    ColumnEditorPanel *panel = [[ColumnEditorPanel alloc] init];
    [panel presentForEditor:editor parentWindow:window];
}

- (void)presentForEditor:(EditorView *)editor parentWindow:(NSWindow *)window {
    _editor = editor;
    _parentWindow = window;
    [self buildSheet];
    [window beginSheet:_sheet completionHandler:^(NSModalResponse r) {
        if (r == NSModalResponseOK) [self apply];
    }];
}

// ── Helpers ───────────────────────────────────────────────────────────────────

static NSTextField *_lbl(NSString *s, NSRect r) {
    NSTextField *f = [NSTextField labelWithString:s];
    f.frame = r;
    return f;
}

// ── Build sheet ───────────────────────────────────────────────────────────────

- (void)buildSheet {
    // Content height: ~300 px
    _sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 390, 300)
                                         styleMask:NSWindowStyleMaskTitled
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    _sheet.title = @"Column / Multi-Selection Editor";

    NSView *root = _sheet.contentView;

    // ── OK / Cancel buttons (bottom) ──────────────────────────────
    NSButton *cancelBtn = [NSButton buttonWithTitle:@"Cancel"
                                             target:self action:@selector(onCancel:)];
    cancelBtn.keyEquivalent = @"\033";
    cancelBtn.frame = NSMakeRect(192, 12, 90, 28);
    [root addSubview:cancelBtn];

    NSButton *okBtn = [NSButton buttonWithTitle:@"OK"
                                          target:self action:@selector(onOK:)];
    okBtn.keyEquivalent = @"\r";
    okBtn.frame = NSMakeRect(288, 12, 90, 28);
    [root addSubview:okBtn];

    // ── Number section (above buttons) ────────────────────────────
    CGFloat numY = 50;   // bottom of number rows

    // Leading
    NSTextField *leadLbl = _lbl(@"Leading:", NSMakeRect(16, numY, 110, 20));
    _leadingPop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(130, numY - 2, 120, 22) pullsDown:NO];
    [_leadingPop addItemsWithTitles:@[@"None", @"Zeros", @"Spaces"]];

    // Repeat
    NSTextField *repLbl  = _lbl(@"Repeat:", NSMakeRect(16, numY + 28, 110, 20));
    _numRepeat = [[NSTextField alloc] initWithFrame:NSMakeRect(130, numY + 26, 90, 22)];
    _numRepeat.placeholderString = @"1";

    // Increase by
    NSTextField *stepLbl = _lbl(@"Increase by:", NSMakeRect(16, numY + 56, 110, 20));
    _numStep = [[NSTextField alloc] initWithFrame:NSMakeRect(130, numY + 54, 90, 22)];
    _numStep.placeholderString = @"1";

    // Initial number
    NSTextField *initLbl = _lbl(@"Initial number:", NSMakeRect(16, numY + 84, 110, 20));
    _numInitial = [[NSTextField alloc] initWithFrame:NSMakeRect(130, numY + 82, 90, 22)];
    _numInitial.placeholderString = @"1";

    for (NSView *v in @[leadLbl, _leadingPop, repLbl, _numRepeat,
                        stepLbl, _numStep, initLbl, _numInitial])
        [root addSubview:v];

    // ── Format box ────────────────────────────────────────────────
    CGFloat fmtBoxY = numY + 108;   // above the number fields
    NSBox *fmtBox = [[NSBox alloc] initWithFrame:NSMakeRect(12, fmtBoxY, 366, 60)];
    fmtBox.title = @"Format";
    [root addSubview:fmtBox];

    NSView *fv = fmtBox.contentView;
    CGFloat fy = 10;

    _decRadio = [NSButton radioButtonWithTitle:@"Dec" target:self action:@selector(onFormatChange:)];
    _decRadio.frame = NSMakeRect(8, fy, 55, 20);
    _decRadio.tag = 0;
    _decRadio.state = NSControlStateValueOn;

    _octRadio = [NSButton radioButtonWithTitle:@"Oct" target:self action:@selector(onFormatChange:)];
    _octRadio.frame = NSMakeRect(68, fy, 55, 20);
    _octRadio.tag = 1;

    _hexRadio = [NSButton radioButtonWithTitle:@"Hex" target:self action:@selector(onFormatChange:)];
    _hexRadio.frame = NSMakeRect(128, fy, 50, 20);
    _hexRadio.tag = 2;

    _hexCasePop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(180, fy - 2, 80, 22) pullsDown:NO];
    [_hexCasePop addItemsWithTitles:@[@"a-f", @"A-F"]];

    _binRadio = [NSButton radioButtonWithTitle:@"Bin" target:self action:@selector(onFormatChange:)];
    _binRadio.frame = NSMakeRect(268, fy, 55, 20);
    _binRadio.tag = 3;

    for (NSView *v in @[_decRadio, _octRadio, _hexRadio, _hexCasePop, _binRadio])
        [fv addSubview:v];

    // ── Separator between sections ────────────────────────────────
    CGFloat sepY = fmtBoxY + 66;
    NSBox *sep = [[NSBox alloc] initWithFrame:NSMakeRect(8, sepY, 374, 1)];
    sep.boxType = NSBoxSeparator;
    [root addSubview:sep];

    // ── Text field ────────────────────────────────────────────────
    CGFloat textY = sepY + 8;
    _textField = [[NSTextField alloc] initWithFrame:NSMakeRect(16, textY, 358, 22)];
    _textField.placeholderString = @"Insert text at caret column on each line";
    [root addSubview:_textField];

    // ── Mode radio buttons (top) ───────────────────────────────────
    CGFloat radioY = textY + 32;

    _textRadio = [NSButton radioButtonWithTitle:@"Text to Insert"
                                          target:self action:@selector(onModeChange:)];
    _textRadio.frame = NSMakeRect(16, radioY, 155, 20);
    _textRadio.tag = 0;
    _textRadio.state = NSControlStateValueOn;

    _numRadio = [NSButton radioButtonWithTitle:@"Number to Insert"
                                         target:self action:@selector(onModeChange:)];
    _numRadio.frame = NSMakeRect(185, radioY, 170, 20);
    _numRadio.tag = 1;

    [root addSubview:_textRadio];
    [root addSubview:_numRadio];

    // Cache number-only controls for enable/disable
    _numberOnlyViews = @[fmtBox, initLbl, _numInitial, stepLbl, _numStep,
                         repLbl, _numRepeat, leadLbl, _leadingPop];

    [self updateEnabledState];
}

// ── Mode / format action ──────────────────────────────────────────────────────

- (void)onModeChange:(id)sender {
    [self updateEnabledState];
}

- (void)onFormatChange:(id)sender {
    // Hex case popup enabled only when Hex radio selected
    _hexCasePop.enabled = (_hexRadio.state == NSControlStateValueOn);
}

- (void)updateEnabledState {
    BOOL textMode = (_textRadio.state == NSControlStateValueOn);
    _textField.enabled = textMode;
    for (NSView *v in _numberOnlyViews) {
        if ([v respondsToSelector:@selector(setEnabled:)])
            [(id)v setEnabled:!textMode];
    }
    // Hex case popup also gated by hex radio
    _hexCasePop.enabled = (!textMode && _hexRadio.state == NSControlStateValueOn);
    // Visual dim (alpha)
    _textField.alphaValue   = textMode ? 1.0 : 0.5;
    for (NSView *v in _numberOnlyViews)
        v.alphaValue = textMode ? 0.5 : 1.0;
}

// ── Button actions ────────────────────────────────────────────────────────────

- (void)onOK:(id)sender {
    [_parentWindow endSheet:_sheet returnCode:NSModalResponseOK];
    [_sheet orderOut:nil];
}

- (void)onCancel:(id)sender {
    [_parentWindow endSheet:_sheet returnCode:NSModalResponseCancel];
    [_sheet orderOut:nil];
}

// ── Number formatting ─────────────────────────────────────────────────────────

- (NSString *)_rawFormatNum:(long long)n {
    NSInteger tag = 0;
    for (NSButton *r in @[_decRadio, _octRadio, _hexRadio, _binRadio])
        if (r.state == NSControlStateValueOn) { tag = r.tag; break; }
    switch (tag) {
        case 0: return [NSString stringWithFormat:@"%lld", n];
        case 1: return [NSString stringWithFormat:@"%llo", n];
        case 2: {
            BOOL upper = (_hexCasePop.indexOfSelectedItem == 1);
            return upper ? [NSString stringWithFormat:@"%llX", n]
                         : [NSString stringWithFormat:@"%llx", n];
        }
        case 3: {
            if (n == 0) return @"0";
            BOOL neg = (n < 0);
            unsigned long long un = (unsigned long long)(neg ? -n : n);
            NSMutableString *b = [NSMutableString string];
            while (un > 0) { [b insertString:(un & 1) ? @"1" : @"0" atIndex:0]; un >>= 1; }
            if (neg) [b insertString:@"-" atIndex:0];
            return b;
        }
    }
    return [NSString stringWithFormat:@"%lld", n];
}

// ── Apply to editor ───────────────────────────────────────────────────────────

- (void)apply {
    if (_textRadio.state == NSControlStateValueOn) {
        // Text mode — repeat text on every line
        NSString *text = _textField.stringValue;
        if (!text.length) return;
        NSInteger count = [_editor columnEditorLineCount];
        NSMutableArray<NSString *> *arr = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
        for (NSInteger i = 0; i < count; i++) [arr addObject:text];
        [_editor columnInsertStrings:arr];
        return;
    }

    // Number mode
    long long start  = _numInitial.stringValue.length ? _numInitial.stringValue.longLongValue : 1;
    long long step   = _numStep.stringValue.length    ? _numStep.stringValue.longLongValue    : 1;
    long long repeat = MAX(1LL, _numRepeat.stringValue.length
                                    ? _numRepeat.stringValue.longLongValue : 1);
    NSInteger leading = _leadingPop.indexOfSelectedItem;  // 0=None 1=Zeros 2=Spaces

    NSInteger lineCount = [_editor columnEditorLineCount];
    NSMutableArray<NSString *> *arr = [NSMutableArray arrayWithCapacity:(NSUInteger)lineCount];

    long long val = start;
    for (NSInteger i = 0; i < lineCount; i++) {
        if (i > 0 && (i % repeat) == 0) val += step;
        [arr addObject:[self _rawFormatNum:val]];
    }

    if (leading != 0) {
        // Determine max width for padding
        NSInteger maxW = 0;
        for (NSString *s in arr) maxW = MAX(maxW, (NSInteger)s.length);
        NSString *padChar = (leading == 1) ? @"0" : @" ";
        for (NSInteger i = 0; i < (NSInteger)arr.count; i++) {
            NSString *s = arr[(NSUInteger)i];
            while ((NSInteger)s.length < maxW)
                s = [padChar stringByAppendingString:s];
            arr[(NSUInteger)i] = s;
        }
    }

    [_editor columnInsertStrings:arr];
}

@end
