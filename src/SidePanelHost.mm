#import "SidePanelHost.h"

// Each panel has its own title bar + close button, so no tab switcher is needed.
// Multiple open panels are stacked vertically and all visible simultaneously.

@implementation SidePanelHost {
    NSStackView    *_stack;
    NSMutableArray *_panels;   // array of NSView*
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _panels = [NSMutableArray array];
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

// ── Public API ────────────────────────────────────────────────────────────────

- (void)showPanel:(NSView *)panel withTitle:(NSString *)title {
    for (NSView *v in _panels) {
        if (v == panel) return;   // already shown
    }
    [_panels addObject:panel];
    [_stack addArrangedSubview:panel];
    // Force panel to fill the full stack width regardless of alignment mode.
    [NSLayoutConstraint activateConstraints:@[
        [panel.leadingAnchor  constraintEqualToAnchor:_stack.leadingAnchor],
        [panel.trailingAnchor constraintEqualToAnchor:_stack.trailingAnchor],
    ]];
}

- (void)hidePanel:(NSView *)panel {
    if (![_panels containsObject:panel]) return;
    [_stack removeArrangedSubview:panel];
    [panel removeFromSuperview];
    [_panels removeObject:panel];
}

- (BOOL)hasPanel:(NSView *)panel {
    return [_panels containsObject:panel];
}

- (BOOL)hasVisiblePanels {
    return _panels.count > 0;
}

@end
