#import "SidePanelHost.h"
#import "PanelFrame.h"
#import "FloatingPanelWindow.h"

// Each panel shows its own content with a PanelFrame-provided title bar +
// close button. Docked panels live inside an NSStackView that distributes
// them evenly; popped panels live inside a FloatingPanelWindow, one per
// panel. The PanelFrame is the same NSView in both states — only its
// superview (and therefore its window) changes, so selection / scroll /
// first-responder / outline expansion state survive pop/dock.
//
// The stack holds PanelFrame wrappers, not raw content views. Callers
// continue to pass content views via showPanel:/hidePanel:/hasPanel: —
// SidePanelHost maps content→frame internally via NSMapTable, so existing
// MainWindowController code that does `[host hasPanel:_docMapPanel]`
// works unchanged regardless of pop state.

@interface SidePanelHost () <PanelFrameDelegate>
@end

@implementation SidePanelHost {
    NSStackView *_stack;
    // Maps content-view → wrapping PanelFrame. A frame lives here as long
    // as the panel is registered (docked OR popped); its superview tells
    // us which state it's in.
    NSMapTable<NSView *, PanelFrame *> *_frames;
    // Insertion order for stacked display. Kept in sync with _frames.
    NSMutableArray<NSView *> *_order;
    // Maps content-view → FloatingPanelWindow for every currently-popped
    // panel. Strong-to-strong — the host owns the window retain while the
    // panel is popped.
    NSMapTable<NSView *, FloatingPanelWindow *> *_poppedWindows;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _frames         = [NSMapTable strongToStrongObjectsMapTable];
        _order          = [NSMutableArray array];
        _poppedWindows  = [NSMapTable strongToStrongObjectsMapTable];
        [self _buildLayout];
    }
    return self;
}

- (instancetype)init { return [self initWithFrame:NSZeroRect]; }

- (void)_buildLayout {
    _stack = [[NSStackView alloc] init];
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    _stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _stack.distribution = NSStackViewDistributionFillEqually;
    _stack.spacing = 0;
    [self addSubview:_stack];
    [NSLayoutConstraint activateConstraints:@[
        [_stack.topAnchor      constraintEqualToAnchor:self.topAnchor],
        [_stack.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [_stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_stack.bottomAnchor   constraintEqualToAnchor:self.bottomAnchor],
    ]];
}

// ── Public API ────────────────────────────────────────────────────────────

- (void)showPanel:(NSView *)panel withTitle:(NSString *)title {
    if (!panel) return;

    PanelFrame *frame = [_frames objectForKey:panel];
    if (frame) {
        // Already hosted — just update the title in case the caller wants
        // to refresh a localized string. The frame is already in the stack
        // OR in a floating window; either way, updating the title keeps
        // both surfaces in sync.
        frame.title = title ?: @"";
        FloatingPanelWindow *w = [_poppedWindows objectForKey:panel];
        if (w) w.title = title ?: @"";
        return;
    }

    // First-time registration: wrap in PanelFrame and add to the stack.
    frame = [[PanelFrame alloc] initWithContentView:panel title:(title ?: @"")];
    frame.delegate = self;

    [_frames setObject:frame forKey:panel];
    [_order addObject:panel];

    [self _installFrameInStack:frame];
}

// Add a frame to the bottom of the stack. Extracted so popOut/dockBack can
// reinstall the same frame after a round-trip without duplicating layout
// wiring.
- (void)_installFrameInStack:(PanelFrame *)frame {
    [_stack addArrangedSubview:frame];
    [NSLayoutConstraint activateConstraints:@[
        [frame.leadingAnchor  constraintEqualToAnchor:_stack.leadingAnchor],
        [frame.trailingAnchor constraintEqualToAnchor:_stack.trailingAnchor],
    ]];
}

- (void)hidePanel:(NSView *)panel {
    if (!panel) return;
    PanelFrame *frame = [_frames objectForKey:panel];
    if (!frame) return;

    // Popped path: close and release the floating window. The PanelFrame
    // is the window's contentView, so closing the window drops the frame
    // from its view hierarchy; clearing our _poppedWindows entry drops the
    // last strong ref and AppKit deallocates the window.
    FloatingPanelWindow *w = [_poppedWindows objectForKey:panel];
    if (w) {
        // Break the window→frame link so any late -windowShouldClose: from
        // a racy close click can't re-enter the hide chain.
        w.delegate = nil;
        // Detach the frame from the window before -close so the frame
        // survives (we discard it explicitly below) and the window's
        // dealloc doesn't drag it down.
        w.contentView = [[NSView alloc] initWithFrame:NSZeroRect];
        [w close];
        [_poppedWindows removeObjectForKey:panel];
    } else {
        // Docked path.
        [_stack removeArrangedSubview:frame];
    }

    [frame removeFromSuperview];
    [_frames removeObjectForKey:panel];
    [_order removeObject:panel];
}

- (BOOL)hasPanel:(NSView *)panel {
    if (!panel) return NO;
    return [_frames objectForKey:panel] != nil;
}

- (BOOL)hasVisiblePanels {
    // Only docked panels count — popped panels live in their own windows
    // and should not keep the side split open.
    return _stack.arrangedSubviews.count > 0;
}

- (BOOL)isPanelPopped:(NSView *)panel {
    if (!panel) return NO;
    return [_poppedWindows objectForKey:panel] != nil;
}

- (void)popOutPanel:(NSView *)panel {
    if (!panel) return;
    PanelFrame *frame = [_frames objectForKey:panel];
    if (!frame) return;
    if ([_poppedWindows objectForKey:panel]) return;  // already popped

    // Remove from the stack. Any width/height constraints we added against
    // _stack's anchors die with the removal — AppKit deactivates them as
    // soon as the frame leaves the stack.
    [_stack removeArrangedSubview:frame];
    [frame removeFromSuperview];

    // Re-parent into a fresh floating window. Assigning contentView moves
    // the frame's view hierarchy into the window; AppKit fires
    // -viewWillMoveToWindow:/-viewDidMoveToWindow: on every descendant so
    // window-sensitive state (e.g. first responder) is rebound cleanly.
    FloatingPanelWindow *w = [[FloatingPanelWindow alloc] initWithPanelFrame:frame];
    [_poppedWindows setObject:w forKey:panel];

    frame.popped = YES;
    [w makeKeyAndOrderFront:nil];

    [self _notifyLayoutChanged];
}

- (void)dockBackPanel:(NSView *)panel {
    if (!panel) return;
    PanelFrame *frame = [_frames objectForKey:panel];
    if (!frame) return;

    FloatingPanelWindow *w = [_poppedWindows objectForKey:panel];
    if (!w) return;  // not popped

    // Detach the frame from the window so -close doesn't walk into our
    // contentView hierarchy. Assigning contentView to a throwaway NSView
    // is the standard Cocoa way to "evict" a contentView cleanly.
    w.delegate = nil;
    w.contentView = [[NSView alloc] initWithFrame:NSZeroRect];
    [w close];
    [_poppedWindows removeObjectForKey:panel];

    frame.popped = NO;
    [self _installFrameInStack:frame];

    [self _notifyLayoutChanged];
}

- (void)_notifyLayoutChanged {
    id<SidePanelHostDelegate> d = self.delegate;
    if ([d respondsToSelector:@selector(sidePanelHostDidChangePanelLayout:)])
        [d sidePanelHostDidChangePanelLayout:self];
}

// ── PanelFrameDelegate ────────────────────────────────────────────────────

- (void)panelFrameRequestedClose:(PanelFrame *)frame {
    NSView *contentView = frame.contentView;
    if (!contentView) return;
    id<SidePanelHostDelegate> d = self.delegate;
    if ([d respondsToSelector:@selector(sidePanelHost:didRequestCloseForContentView:)])
        [d sidePanelHost:self didRequestCloseForContentView:contentView];
}

- (void)panelFrameRequestedTogglePop:(PanelFrame *)frame {
    NSView *contentView = frame.contentView;
    if (!contentView) return;
    if ([self isPanelPopped:contentView])
        [self dockBackPanel:contentView];
    else
        [self popOutPanel:contentView];
}

@end
