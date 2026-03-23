#import "DocumentMapPanel.h"
#import "NppLocalizer.h"
#import "ScintillaView.h"
#import "Scintilla.h"
#import "ScintillaMessages.h"

namespace Scintilla { struct ILexer5; }
extern "C" Scintilla::ILexer5 *CreateLexer(const char *name);

// ─────────────────────────────────────────────────────────────────────────────
@class _DMViewportOverlay;

@interface DocumentMapPanel ()
- (NSRect)_viewportRectForOverlay:(_DMViewportOverlay *)overlay;
- (void)_overlayMouseDown:(NSPoint)pt;
- (void)_overlayMouseDragged:(NSPoint)pt;
- (void)_overlayScrollWheel:(NSEvent *)event;
@end

// ─────────────────────────────────────────────────────────────────────────────
@interface _DMViewportOverlay : NSView
@property (nonatomic, weak) DocumentMapPanel *panel;
@end

@implementation _DMViewportOverlay

- (BOOL)isOpaque                          { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent *)e    { return YES; }
- (void)cursorUpdate:(NSEvent *)e         { [[NSCursor arrowCursor] set]; }

- (void)drawRect:(NSRect)dirty {
    NSRect vr = [self.panel _viewportRectForOverlay:self];
    if (NSIsEmptyRect(vr)) return;
    [[NSColor colorWithRed:1.0 green:0.72 blue:0.57 alpha:0.45] setFill];
    [NSBezierPath fillRect:vr];
}

- (void)mouseDown:(NSEvent *)e {
    [self.panel _overlayMouseDown:[self convertPoint:e.locationInWindow fromView:nil]];
}
- (void)mouseDragged:(NSEvent *)e {
    [self.panel _overlayMouseDragged:[self convertPoint:e.locationInWindow fromView:nil]];
}
- (void)mouseUp:(NSEvent *)e     { /* intentionally empty */ }
- (void)scrollWheel:(NSEvent *)e { [self.panel _overlayScrollWheel:e]; }

@end

// ─────────────────────────────────────────────────────────────────────────────
@implementation DocumentMapPanel {
    NSView             *_titleBar;
    NSTextField        *_titleLabel;
    ScintillaView      *_mapSci;
    _DMViewportOverlay *_overlay;
    __weak EditorView  *_trackedEditor;
    NSTimer            *_contentDebounce;
    CGFloat             _grabOffset;   // fromTop offset from mouse to rect center at mouseDown
}

// ── Init / dealloc ────────────────────────────────────────────────────────────

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self _buildLayout];
        [[NSNotificationCenter defaultCenter]
            addObserver:self selector:@selector(_cursorMoved:)
                   name:EditorViewCursorDidMoveNotification object:nil];
        [[NSNotificationCenter defaultCenter]
            addObserver:self selector:@selector(_prefsChanged:)
                   name:@"NPPPreferencesChanged" object:nil];
        [[NSNotificationCenter defaultCenter]
            addObserver:self selector:@selector(_locChanged:)
                   name:NPPLocalizationChanged object:nil];
        [self retranslateUI];
    }
    return self;
}

- (void)_locChanged:(NSNotification *)n { [self retranslateUI]; }
- (void)retranslateUI {
    _titleLabel.stringValue = [[NppLocalizer shared] translate:@"Document Map"];
}
- (instancetype)init { return [self initWithFrame:NSZeroRect]; }
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_contentDebounce invalidate];
}

// ── Layout ────────────────────────────────────────────────────────────────────

- (void)_buildLayout {
    _titleBar = [[NSView alloc] init];
    _titleBar.translatesAutoresizingMaskIntoConstraints = NO;
    _titleBar.wantsLayer = YES;
    _titleBar.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;
    [self addSubview:_titleBar];

    _titleLabel = [NSTextField labelWithString:@"Document Map"];
    NSTextField *lbl = _titleLabel;
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.font = [NSFont boldSystemFontOfSize:11];
    lbl.textColor = [NSColor labelColor];
    lbl.lineBreakMode = NSLineBreakByTruncatingTail;
    [_titleBar addSubview:lbl];

    NSButton *closeBtn = [NSButton buttonWithTitle:@"✕"
                                            target:self
                                            action:@selector(_closePanel:)];
    closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    closeBtn.bezelStyle = NSBezelStyleInline;
    closeBtn.bordered = NO;
    closeBtn.font = [NSFont systemFontOfSize:11];
    [_titleBar addSubview:closeBtn];

    [NSLayoutConstraint activateConstraints:@[
        [_titleBar.topAnchor      constraintEqualToAnchor:self.topAnchor],
        [_titleBar.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [_titleBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_titleBar.heightAnchor   constraintEqualToConstant:28],

        [lbl.leadingAnchor  constraintEqualToAnchor:_titleBar.leadingAnchor constant:8],
        [lbl.centerYAnchor  constraintEqualToAnchor:_titleBar.centerYAnchor],
        [lbl.trailingAnchor constraintLessThanOrEqualToAnchor:closeBtn.leadingAnchor constant:-4],

        [closeBtn.trailingAnchor constraintEqualToAnchor:_titleBar.trailingAnchor constant:-6],
        [closeBtn.centerYAnchor  constraintEqualToAnchor:_titleBar.centerYAnchor],
        [closeBtn.widthAnchor    constraintEqualToConstant:20],
        [closeBtn.heightAnchor   constraintEqualToConstant:20],
    ]];

    NSBox *sep = [[NSBox alloc] init];
    sep.boxType = NSBoxSeparator;
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:sep];
    [NSLayoutConstraint activateConstraints:@[
        [sep.topAnchor      constraintEqualToAnchor:_titleBar.bottomAnchor],
        [sep.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [sep.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [sep.heightAnchor   constraintEqualToConstant:1],
    ]];

    NSView *content = [[NSView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.topAnchor      constraintEqualToAnchor:sep.bottomAnchor],
        [content.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [content.bottomAnchor   constraintEqualToAnchor:self.bottomAnchor],
    ]];

    _mapSci = [[ScintillaView alloc] initWithFrame:NSZeroRect];
    _mapSci.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:_mapSci];
    [NSLayoutConstraint activateConstraints:@[
        [_mapSci.topAnchor      constraintEqualToAnchor:content.topAnchor],
        [_mapSci.leadingAnchor  constraintEqualToAnchor:content.leadingAnchor],
        [_mapSci.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [_mapSci.bottomAnchor   constraintEqualToAnchor:content.bottomAnchor],
    ]];
    [self _configureMapSci];

    _overlay = [[_DMViewportOverlay alloc] initWithFrame:NSZeroRect];
    _overlay.translatesAutoresizingMaskIntoConstraints = NO;
    _overlay.panel = self;
    [content addSubview:_overlay positioned:NSWindowAbove relativeTo:_mapSci];
    [NSLayoutConstraint activateConstraints:@[
        [_overlay.topAnchor      constraintEqualToAnchor:content.topAnchor],
        [_overlay.leadingAnchor  constraintEqualToAnchor:content.leadingAnchor],
        [_overlay.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [_overlay.bottomAnchor   constraintEqualToAnchor:content.bottomAnchor],
    ]];
}

- (void)_configureMapSci {
    [_mapSci message:SCI_SETREADONLY         wParam:1];
    for (int m = 0; m < 5; m++)
        [_mapSci message:SCI_SETMARGINWIDTHN wParam:(uptr_t)m lParam:0];
    [_mapSci message:SCI_SETCARETLINEVISIBLE wParam:0];
    [_mapSci message:SCI_SETCARETWIDTH       wParam:0];
    [_mapSci message:SCI_SETHSCROLLBAR       wParam:0];
    [_mapSci message:SCI_SETVSCROLLBAR       wParam:0];
    [_mapSci message:SCI_SETWRAPMODE         wParam:SC_WRAP_NONE];
    [_mapSci message:SCI_STYLESETSIZEFRACTIONAL wParam:STYLE_DEFAULT lParam:400]; // 4pt
    [_mapSci message:SCI_STYLECLEARALL];
}

- (void)_closePanel:(id)sender {
    [_delegate documentMapPanelDidRequestClose:self];
}

// ── Public API ────────────────────────────────────────────────────────────────

- (void)setTrackedEditor:(EditorView *)editor {
    _trackedEditor = editor;
    [self _updateMapContent];
}

// ── Content update (debounced) ────────────────────────────────────────────────

- (void)_scheduleContentUpdate {
    [_contentDebounce invalidate];
    _contentDebounce = [NSTimer scheduledTimerWithTimeInterval:0.25
                                                        target:self
                                                      selector:@selector(_updateMapContent)
                                                      userInfo:nil
                                                       repeats:NO];
}

- (void)_updateMapContent {
    EditorView *ed = _trackedEditor;
    if (!ed) {
        [_mapSci message:SCI_SETREADONLY wParam:0];
        [_mapSci message:SCI_CLEARALL];
        [_mapSci message:SCI_SETREADONLY wParam:1];
        [_overlay setNeedsDisplay:YES];
        return;
    }

    intptr_t len = [ed.scintillaView message:SCI_GETLENGTH];
    char *buf = (char *)malloc((size_t)len + 1);
    if (!buf) return;
    [ed.scintillaView message:SCI_GETTEXT wParam:(uptr_t)(len + 1) lParam:(sptr_t)buf];
    [_mapSci message:SCI_SETREADONLY wParam:0];
    [_mapSci message:SCI_SETTEXT     wParam:0 lParam:(sptr_t)buf];
    [_mapSci message:SCI_SETREADONLY wParam:1];
    free(buf);

    NSString *lang = ed.currentLanguage;
    if (lang.length) {
        NSDictionary *lexerMap = @{
            @"c": @"cpp", @"cpp": @"cpp", @"objc": @"cpp", @"swift": @"cpp",
            @"python": @"python", @"javascript": @"cpp", @"typescript": @"cpp",
            @"html": @"hypertext", @"xml": @"xml", @"css": @"css",
            @"bash": @"bash", @"ruby": @"ruby", @"json": @"json",
            @"sql": @"sql", @"lua": @"lua", @"perl": @"perl",
        };
        NSString *lexerName = lexerMap[lang.lowercaseString] ?: lang;
        Scintilla::ILexer5 *lexer = CreateLexer(lexerName.UTF8String);
        if (lexer) [_mapSci message:SCI_SETILEXER wParam:0 lParam:(sptr_t)lexer];
    }

    [self _applyThemeFromEditor:ed];
    [self _syncScroll];
}

// ── Theme mirroring ───────────────────────────────────────────────────────────

- (void)_applyThemeFromEditor:(EditorView *)ed {
    ScintillaView *src = ed.scintillaView;
    sptr_t defaultFg = [src message:SCI_STYLEGETFORE wParam:STYLE_DEFAULT];
    sptr_t defaultBg = [src message:SCI_STYLEGETBACK wParam:STYLE_DEFAULT];
    [_mapSci message:SCI_STYLESETFORE wParam:STYLE_DEFAULT lParam:defaultFg];
    [_mapSci message:SCI_STYLESETBACK wParam:STYLE_DEFAULT lParam:defaultBg];
    for (int s = 0; s < 128; s++) {
        sptr_t fg = [src message:SCI_STYLEGETFORE wParam:(uptr_t)s];
        [_mapSci message:SCI_STYLESETFORE wParam:(uptr_t)s lParam:fg];
        [_mapSci message:SCI_STYLESETBACK wParam:(uptr_t)s lParam:defaultBg];
    }
}

// ── Scroll sync (proportional — immediate on every cursor/scroll event) ───────
//
// Proportional strategy: src at p% of scrollable range → map at p%.
// This lets the viewport rect reach the very top and bottom of the panel.

- (void)_syncScroll {
    EditorView *ed = _trackedEditor;
    if (!ed) return;

    intptr_t srcFirst   = [ed.scintillaView message:SCI_GETFIRSTVISIBLELINE];
    intptr_t srcVisible = MAX((intptr_t)1, [ed.scintillaView message:SCI_LINESONSCREEN]);
    intptr_t srcTotal   = MAX((intptr_t)1, [ed.scintillaView message:SCI_GETLINECOUNT]);
    intptr_t mapTotal   = MAX((intptr_t)1, [_mapSci message:SCI_GETLINECOUNT]);
    intptr_t mapLineH   = MAX((intptr_t)1, [_mapSci message:SCI_TEXTHEIGHT wParam:0]);
    intptr_t panelH     = MAX((intptr_t)1, (intptr_t)_mapSci.bounds.size.height);
    intptr_t mapVisLines = panelH / mapLineH;

    intptr_t maxSrcFirst = MAX((intptr_t)1, srcTotal - srcVisible);
    intptr_t maxMapFirst = MAX((intptr_t)0, mapTotal - mapVisLines);

    CGFloat p = (CGFloat)srcFirst / (CGFloat)maxSrcFirst;
    p = MAX(0.0f, MIN(1.0f, p));
    intptr_t newFirst = (intptr_t)(p * (CGFloat)maxMapFirst + 0.5f);
    newFirst = MAX((intptr_t)0, MIN(maxMapFirst, newFirst));

    intptr_t curFirst = [_mapSci message:SCI_GETFIRSTVISIBLELINE];
    if (newFirst != curFirst)
        [_mapSci message:SCI_SETFIRSTVISIBLELINE wParam:(uptr_t)newFirst];

    [_overlay setNeedsDisplay:YES];
}

// ── Viewport rectangle ────────────────────────────────────────────────────────
//
// The rect is 50% of the viewport-band height. It slides within the band:
// aligned to the band's top at the document start, bottom at document end.
// This guarantees the rect reaches both edges of the panel.
//
// The rect center is a LINEAR function of srcFirst:
//   center_fromTop(srcFirst) = srcFirst * K + rectH/2
//   K = [(maxSrcFirst - maxMapFirst)*mapLineH + (bandH - rectH)] / maxSrcFirst
//
// This linearity is exploited in _dragToFromTop: to compute the exact srcFirst
// for any target mouse position — giving true 1:1 mouse tracking.

- (NSRect)_viewportRectForOverlay:(_DMViewportOverlay *)overlay {
    EditorView *ed = _trackedEditor;
    if (!ed) return NSZeroRect;

    intptr_t srcFirst   = [ed.scintillaView message:SCI_GETFIRSTVISIBLELINE];
    intptr_t srcVisible = MAX((intptr_t)1, [ed.scintillaView message:SCI_LINESONSCREEN]);
    intptr_t srcTotal   = MAX((intptr_t)1, [ed.scintillaView message:SCI_GETLINECOUNT]);
    intptr_t mapFirst   = [_mapSci message:SCI_GETFIRSTVISIBLELINE];
    intptr_t mapTotal   = MAX((intptr_t)1, [_mapSci message:SCI_GETLINECOUNT]);
    intptr_t mapLineH   = MAX((intptr_t)1, [_mapSci message:SCI_TEXTHEIGHT wParam:0]);

    // Pixel positions of the viewport band measured from the top of the map content.
    intptr_t mapVpStart = (srcFirst * mapTotal) / srcTotal;
    intptr_t mapVpEnd   = MIN(mapTotal, ((srcFirst + srcVisible) * mapTotal) / srcTotal + 1);
    CGFloat pixTop  = (CGFloat)(mapVpStart - mapFirst) * (CGFloat)mapLineH;
    CGFloat pixBtm  = (CGFloat)(mapVpEnd   - mapFirst) * (CGFloat)mapLineH;
    CGFloat bandH   = MAX(4.0f, pixBtm - pixTop);
    CGFloat rectH   = bandH * 0.5f;   // 50% of the viewport band

    // Slide: p=0 → rect at band top; p=1 → rect at band bottom.
    intptr_t maxSrcFirst = MAX((intptr_t)1, srcTotal - srcVisible);
    CGFloat p = MAX(0.0f, MIN(1.0f, (CGFloat)srcFirst / (CGFloat)maxSrcFirst));
    CGFloat pixRectTop = pixTop + p * (bandH - rectH);
    CGFloat pixRectBtm = pixRectTop + rectH;

    // Convert from top-origin pixel coords to AppKit (bottom-origin).
    CGFloat h     = overlay.bounds.size.height;
    CGFloat w     = overlay.bounds.size.width;
    CGFloat rectY = h - pixRectBtm;

    if (rectY < 0)          { rectH += rectY; rectY = 0; }
    if (rectH < 2)            rectH = 2;
    if (rectY + rectH > h)    rectH = h - rectY;
    if (rectH <= 0)           return NSZeroRect;

    return NSMakeRect(0, rectY, w, rectH);
}

// ── Mouse handling ────────────────────────────────────────────────────────────
//
// On mouseDown: if the click lands on the rect, record the grab offset so the
// grabbed point tracks the mouse exactly. If outside the rect, snap the rect
// center to the mouse (grabOffset = 0).
//
// On drag: _dragToFromTop: inverts the linear rect-center formula to compute
// the exact srcFirst that places the rect center at the target position.
// Result: 1:1 pixel tracking regardless of document size or panel height.

- (void)_overlayMouseDown:(NSPoint)pt {
    NSRect   vr            = [self _viewportRectForOverlay:_overlay];
    CGFloat  h             = _overlay.bounds.size.height;
    CGFloat  fromTop       = h - pt.y;                        // distance from panel top
    CGFloat  rectCenterFT  = h - NSMidY(vr);                 // rect center, fromTop

    // Grab offset: keeps the exact grab point under the pointer during drag.
    _grabOffset = NSPointInRect(pt, vr) ? (fromTop - rectCenterFT) : 0.0f;

    [self _dragToFromTop:fromTop - _grabOffset];
}

- (void)_overlayMouseDragged:(NSPoint)pt {
    CGFloat fromTop = _overlay.bounds.size.height - pt.y;
    [self _dragToFromTop:fromTop - _grabOffset];
}

// Sets srcFirst so the viewport rect center lands at targetCenterFromTop.
// Uses the analytical inverse of:  center = srcFirst * K + rectH/2
- (void)_dragToFromTop:(CGFloat)targetCenterFromTop {
    EditorView *ed = _trackedEditor;
    if (!ed) return;

    intptr_t srcTotal   = MAX((intptr_t)1, [ed.scintillaView message:SCI_GETLINECOUNT]);
    intptr_t srcVisible = MAX((intptr_t)1, [ed.scintillaView message:SCI_LINESONSCREEN]);
    intptr_t mapTotal   = MAX((intptr_t)1, [_mapSci message:SCI_GETLINECOUNT]);
    intptr_t mapLineH   = MAX((intptr_t)1, [_mapSci message:SCI_TEXTHEIGHT wParam:0]);
    intptr_t panelH     = MAX((intptr_t)1, (intptr_t)_mapSci.bounds.size.height);
    intptr_t mapVisLines = panelH / mapLineH;
    intptr_t maxSrcFirst = MAX((intptr_t)1, srcTotal - srcVisible);
    intptr_t maxMapFirst = MAX((intptr_t)0, mapTotal - mapVisLines);

    // bandH and rectH must match _viewportRectForOverlay: exactly.
    CGFloat bandH = (CGFloat)srcVisible * (CGFloat)mapLineH;
    CGFloat rectH = bandH * 0.5f;

    // K = d(rectCenter)/d(srcFirst) — derived from the proportional-scroll geometry.
    // Since mapTotal == srcTotal (same document), this simplifies to:
    //   K = [(maxSrcFirst - maxMapFirst)*mapLineH + (bandH - rectH)] / maxSrcFirst
    CGFloat K = ((CGFloat)(maxSrcFirst - maxMapFirst) * (CGFloat)mapLineH + (bandH - rectH))
                / (CGFloat)maxSrcFirst;
    if (K < 0.01f) K = 0.01f;   // guard: tiny documents where geometry degenerates

    // Invert: srcFirst = (targetCenter - rectH/2) / K
    intptr_t newSrcFirst = (intptr_t)((targetCenterFromTop - rectH * 0.5f) / K + 0.5f);
    newSrcFirst = MAX((intptr_t)0, MIN(maxSrcFirst, newSrcFirst));

    [ed.scintillaView message:SCI_SETFIRSTVISIBLELINE wParam:(uptr_t)newSrcFirst];
    [self _syncScroll];
}

- (void)_overlayScrollWheel:(NSEvent *)event {
    [_trackedEditor.scintillaView scrollWheel:event];
}

// ── Notifications ─────────────────────────────────────────────────────────────

- (void)_cursorMoved:(NSNotification *)note {
    if (note.object != _trackedEditor) return;
    [self _syncScroll];
    [self _scheduleContentUpdate];
}

- (void)_prefsChanged:(NSNotification *)note {
    EditorView *ed = _trackedEditor;
    if (ed) [self _applyThemeFromEditor:ed];
    [_overlay setNeedsDisplay:YES];
}

@end
