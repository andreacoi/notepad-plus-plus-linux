#import "SidePanelHost.h"
#import "PanelFrame.h"

// Each panel shows its own content with a PanelFrame-provided title bar +
// close button. Multiple panels are stacked vertically and all visible
// simultaneously. The NSStackView distributes them equally.
//
// The stack holds PanelFrame wrappers, not raw content views. Callers
// continue to pass content views via showPanel:/hidePanel:/hasPanel: —
// SidePanelHost maps content→frame internally via NSMapTable, so existing
// MainWindowController code that does `[host hasPanel:_docMapPanel]`
// works unchanged after the Phase 2 wrap.

@interface SidePanelHost () <PanelFrameDelegate>
@end

@implementation SidePanelHost {
    NSStackView *_stack;
    // Maps content-view → wrapping PanelFrame so the public API
    // (hasPanel:, hidePanel:) can continue to be keyed by content view.
    // Strong-to-strong so the frame lives as long as the mapping does.
    NSMapTable<NSView *, PanelFrame *> *_frames;
    // Insertion order for stacked display. NSMapTable doesn't preserve
    // order; we keep a parallel array of content views.
    NSMutableArray<NSView *> *_order;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _frames = [NSMapTable strongToStrongObjectsMapTable];
        _order  = [NSMutableArray array];
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
        // to refresh a localized string. The frame is already in the stack.
        frame.title = title ?: @"";
        return;
    }

    // First-time registration: wrap in PanelFrame and add to the stack.
    frame = [[PanelFrame alloc] initWithContentView:panel title:(title ?: @"")];
    frame.delegate = self;

    [_frames setObject:frame forKey:panel];
    [_order addObject:panel];

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

    [_stack removeArrangedSubview:frame];
    [frame removeFromSuperview];
    [_frames removeObjectForKey:panel];
    [_order removeObject:panel];
}

- (BOOL)hasPanel:(NSView *)panel {
    if (!panel) return NO;
    return [_frames objectForKey:panel] != nil;
}

- (BOOL)hasVisiblePanels {
    return _order.count > 0;
}

// ── PanelFrameDelegate ────────────────────────────────────────────────────

- (void)panelFrameRequestedClose:(PanelFrame *)frame {
    NSView *contentView = frame.contentView;
    if (!contentView) return;
    id<SidePanelHostDelegate> d = self.delegate;
    if ([d respondsToSelector:@selector(sidePanelHost:didRequestCloseForContentView:)])
        [d sidePanelHost:self didRequestCloseForContentView:contentView];
}

@end
