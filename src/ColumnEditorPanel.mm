#import "ColumnEditorPanel.h"
#import "EditorView.h"

// ── ColumnEditorPanel ─────────────────────────────────────────────────────────
// Mirrors NPP's Column Editor: two modes — Text and Number.
// Presented as a modal sheet so focus stays on the parent window.

@interface ColumnEditorPanel () <NSTabViewDelegate>
@end

@implementation ColumnEditorPanel {
    NSWindow      *_sheet;
    NSTabView     *_tabs;
    // Text tab
    NSTextField   *_textField;
    // Number tab
    NSTextField   *_numInitial;
    NSTextField   *_numStep;
    NSTextField   *_numFormat;
    // reference
    EditorView    *_editor;
    NSWindow      *_parentWindow;
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

// ── Build sheet UI ────────────────────────────────────────────────────────────

- (void)buildSheet {
    _sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,380,220)
                                         styleMask:NSWindowStyleMaskTitled
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    _sheet.title = @"Column Editor";

    NSView *root = _sheet.contentView;

    // Tab view
    _tabs = [[NSTabView alloc] initWithFrame:NSMakeRect(10, 50, 360, 155)];
    _tabs.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    NSTabViewItem *textTab   = [[NSTabViewItem alloc] initWithIdentifier:@"text"];
    textTab.label = @"Text to Insert";
    NSTabViewItem *numberTab = [[NSTabViewItem alloc] initWithIdentifier:@"number"];
    numberTab.label = @"Number to Insert";

    [self buildTextTab:textTab];
    [self buildNumberTab:numberTab];

    [_tabs addTabViewItem:textTab];
    [_tabs addTabViewItem:numberTab];
    [root addSubview:_tabs];

    // Buttons
    NSButton *cancel = [NSButton buttonWithTitle:@"Cancel"
                                          target:self action:@selector(onCancel:)];
    cancel.keyEquivalent = @"\033";
    cancel.frame = NSMakeRect(185, 12, 90, 28);
    [root addSubview:cancel];

    NSButton *ok = [NSButton buttonWithTitle:@"OK"
                                       target:self action:@selector(onOK:)];
    ok.keyEquivalent = @"\r";
    ok.frame = NSMakeRect(280, 12, 90, 28);
    [root addSubview:ok];
}

- (void)buildTextTab:(NSTabViewItem *)item {
    NSView *v = [[NSView alloc] init];

    NSTextField *label = [NSTextField labelWithString:@"Text:"];
    label.frame = NSMakeRect(10, 70, 50, 20);
    [v addSubview:label];

    _textField = [[NSTextField alloc] initWithFrame:NSMakeRect(65, 67, 270, 22)];
    _textField.placeholderString = @"Insert at caret column on each selected line";
    [v addSubview:_textField];

    item.view = v;
}

- (void)buildNumberTab:(NSTabViewItem *)item {
    NSView *v = [[NSView alloc] init];

    NSTextField *l1 = [NSTextField labelWithString:@"Initial number:"];
    l1.frame = NSMakeRect(10, 90, 100, 20);
    _numInitial = [[NSTextField alloc] initWithFrame:NSMakeRect(115, 88, 180, 22)];
    _numInitial.placeholderString = @"1";

    NSTextField *l2 = [NSTextField labelWithString:@"Increase by:"];
    l2.frame = NSMakeRect(10, 60, 100, 20);
    _numStep = [[NSTextField alloc] initWithFrame:NSMakeRect(115, 58, 180, 22)];
    _numStep.placeholderString = @"1";

    NSTextField *l3 = [NSTextField labelWithString:@"Format:"];
    l3.frame = NSMakeRect(10, 30, 100, 20);
    _numFormat = [[NSTextField alloc] initWithFrame:NSMakeRect(115, 28, 180, 22)];
    _numFormat.placeholderString = @"%d  (or %04d, %x, %X, …)";

    for (NSView *sub in @[l1, _numInitial, l2, _numStep, l3, _numFormat])
        [v addSubview:sub];

    item.view = v;
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

// ── Apply to editor ───────────────────────────────────────────────────────────

- (void)apply {
    NSString *selectedTab = _tabs.selectedTabViewItem.identifier;

    if ([selectedTab isEqualToString:@"text"]) {
        NSString *text = _textField.stringValue;
        if (text.length) [_editor columnInsertText:text];

    } else {
        long long start  = _numInitial.stringValue.length ? _numInitial.stringValue.longLongValue : 1;
        long long step   = _numStep.stringValue.length    ? _numStep.stringValue.longLongValue    : 1;
        NSString *fmt    = _numFormat.stringValue.length  ? _numFormat.stringValue                : @"%d";
        [_editor columnInsertNumbersFrom:start step:step format:fmt];
    }
}

@end
