#import "SidePanelHost.h"

@implementation SidePanelHost {
    NSSegmentedControl *_segControl;
    NSBox              *_sep;
    NSView             *_contentArea;
    NSMutableArray     *_panels; // array of @{ @"view": NSView*, @"title": NSString* }

    // Layout constraints toggled when header is shown/hidden
    NSLayoutConstraint *_segHeightConstraint;
    NSLayoutConstraint *_contentTopFromSep;   // active when header visible (2+ panels)
    NSLayoutConstraint *_contentTopFromSelf;  // active when header hidden  (0-1 panels)
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _panels = [NSMutableArray array];
        [self _buildLayout];
    }
    return self;
}

- (instancetype)init {
    return [self initWithFrame:NSZeroRect];
}

- (void)_buildLayout {
    _segControl = [[NSSegmentedControl alloc] init];
    _segControl.translatesAutoresizingMaskIntoConstraints = NO;
    _segControl.segmentStyle = NSSegmentStyleSmallSquare;
    _segControl.trackingMode = NSSegmentSwitchTrackingSelectOne;
    _segControl.target = self;
    _segControl.action = @selector(_segmentChanged:);
    [self addSubview:_segControl];

    _sep = [[NSBox alloc] init];
    _sep.boxType = NSBoxSeparator;
    _sep.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_sep];

    _contentArea = [[NSView alloc] init];
    _contentArea.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_contentArea];

    // Two mutually-exclusive constraints for the content area's top edge.
    _contentTopFromSep  = [_contentArea.topAnchor constraintEqualToAnchor:_sep.bottomAnchor];
    _contentTopFromSelf = [_contentArea.topAnchor constraintEqualToAnchor:self.topAnchor];
    _segHeightConstraint = [_segControl.heightAnchor constraintEqualToConstant:22];

    // Initial state: header hidden (no panels yet)
    _segControl.hidden = YES;
    _sep.hidden        = YES;
    _segHeightConstraint.constant = 0;
    _contentTopFromSelf.active = YES;   // content fills from top
    _contentTopFromSep.active  = NO;

    [NSLayoutConstraint activateConstraints:@[
        [_segControl.topAnchor     constraintEqualToAnchor:self.topAnchor constant:2],
        [_segControl.leadingAnchor constraintEqualToAnchor:self.leadingAnchor  constant:4],
        [_segControl.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-4],
        _segHeightConstraint,

        [_sep.topAnchor     constraintEqualToAnchor:_segControl.bottomAnchor constant:2],
        [_sep.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [_sep.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_sep.heightAnchor  constraintEqualToConstant:1],

        _contentTopFromSelf,   // active by default
        [_contentArea.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [_contentArea.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_contentArea.bottomAnchor   constraintEqualToAnchor:self.bottomAnchor],
    ]];
}

// ── Public API ────────────────────────────────────────────────────────────────

- (void)showPanel:(NSView *)panel withTitle:(NSString *)title {
    for (NSDictionary *d in _panels) {
        if (d[@"view"] == panel) return; // already shown
    }

    [_panels addObject:@{ @"view": panel, @"title": title }];

    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.hidden = YES;
    [_contentArea addSubview:panel];
    [NSLayoutConstraint activateConstraints:@[
        [panel.topAnchor    constraintEqualToAnchor:_contentArea.topAnchor],
        [panel.leadingAnchor  constraintEqualToAnchor:_contentArea.leadingAnchor],
        [panel.trailingAnchor constraintEqualToAnchor:_contentArea.trailingAnchor],
        [panel.bottomAnchor constraintEqualToAnchor:_contentArea.bottomAnchor],
    ]];

    [self _rebuildSegments];
    NSInteger lastIdx = (NSInteger)_panels.count - 1;
    [_segControl setSelectedSegment:lastIdx];
    [self _showPanelAtIndex:lastIdx];
}

- (void)hidePanel:(NSView *)panel {
    NSInteger idx = -1;
    for (NSInteger i = 0; i < (NSInteger)_panels.count; i++) {
        if (_panels[i][@"view"] == panel) { idx = i; break; }
    }
    if (idx < 0) return;

    [panel removeFromSuperview];
    [_panels removeObjectAtIndex:idx];
    [self _rebuildSegments];

    if (_panels.count > 0) {
        NSInteger showIdx = MIN(idx, (NSInteger)_panels.count - 1);
        [_segControl setSelectedSegment:showIdx];
        [self _showPanelAtIndex:showIdx];
    }
}

- (BOOL)hasPanel:(NSView *)panel {
    for (NSDictionary *d in _panels) {
        if (d[@"view"] == panel) return YES;
    }
    return NO;
}

- (BOOL)hasVisiblePanels {
    return _panels.count > 0;
}

// ── Private helpers ───────────────────────────────────────────────────────────

- (void)_rebuildSegments {
    [_segControl setSegmentCount:(NSInteger)_panels.count];
    for (NSInteger i = 0; i < (NSInteger)_panels.count; i++)
        [_segControl setLabel:_panels[i][@"title"] forSegment:i];

    // Only show the segment switcher when 2+ panels are present;
    // a single panel provides its own title bar.
    BOOL showHeader = (_panels.count > 1);
    _segControl.hidden = !showHeader;
    _sep.hidden        = !showHeader;
    _segHeightConstraint.constant = showHeader ? 22.0 : 0.0;
    _contentTopFromSep.active  =  showHeader;
    _contentTopFromSelf.active = !showHeader;
}

- (void)_showPanelAtIndex:(NSInteger)idx {
    for (NSInteger i = 0; i < (NSInteger)_panels.count; i++)
        ((NSView *)_panels[i][@"view"]).hidden = (i != idx);
}

- (void)_segmentChanged:(id)sender {
    [self _showPanelAtIndex:_segControl.selectedSegment];
}

@end
