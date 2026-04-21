#import "PanelFrame.h"
#import "NppThemeManager.h"

// ─────────────────────────────────────────────────────────────────────────────
// Close button — pixel-identical to the per-panel _DMPCloseButton /
// _FLPCloseButton / _DLPCloseButton / etc. Hoisted here so all panels share
// one implementation instead of 8 copies.
//
// Behavior:
//   * 1pt grey border at rest, toolbar-blue (#D0EAFF) on hover/press
//   * Light-blue background fill on hover (#E5F3FF) / press (#CCE8FF) in
//     LIGHT mode only — skipped in dark mode to avoid clashing with the
//     dark title-bar background
//   * ✕ glyph centered via NSAttributedString for true vertical alignment
// ─────────────────────────────────────────────────────────────────────────────

@interface _PFCloseButton : NSButton { BOOL _hovering; }
@end

@implementation _PFCloseButton

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.bordered = NO;
        self.buttonType = NSButtonTypeMomentaryChange;
        self.title = @"";
        NSTrackingArea *ta = [[NSTrackingArea alloc]
            initWithRect:NSZeroRect
                 options:(NSTrackingMouseEnteredAndExited |
                          NSTrackingActiveInActiveApp     |
                          NSTrackingInVisibleRect)
                   owner:self userInfo:nil];
        [self addTrackingArea:ta];
    }
    return self;
}

- (void)mouseEntered:(NSEvent *)event { _hovering = YES; [self setNeedsDisplay:YES]; }
- (void)mouseExited:(NSEvent *)event  { _hovering = NO;  [self setNeedsDisplay:YES]; }

- (void)drawRect:(NSRect)dirtyRect {
    BOOL pressed = self.isHighlighted;
    BOOL active  = pressed || _hovering;
    BOOL isDark  = [NppThemeManager shared].isDark;

    if (active && !isDark) {
        NSColor *bg = pressed
            ? [NSColor colorWithRed:0xCC/255.0 green:0xE8/255.0 blue:0xFF/255.0 alpha:1.0]
            : [NSColor colorWithRed:0xE5/255.0 green:0xF3/255.0 blue:0xFF/255.0 alpha:1.0];
        [bg setFill];
        NSRectFill(self.bounds);
    }

    NSColor *bdr = active
        ? [NSColor colorWithRed:0xD0/255.0 green:0xEA/255.0 blue:0xFF/255.0 alpha:1.0]
        : [NSColor colorWithWhite:0.75 alpha:1.0];
    NSBezierPath *border = [NSBezierPath bezierPathWithRect:NSInsetRect(self.bounds, 0.5, 0.5)];
    border.lineWidth = 1.0;
    [bdr setStroke];
    [border stroke];

    NSString *glyph = @"✕";
    NSDictionary *attrs = @{
        NSFontAttributeName: self.font ?: [NSFont systemFontOfSize:11],
        NSForegroundColorAttributeName: [NSColor labelColor],
    };
    NSSize sz = [glyph sizeWithAttributes:attrs];
    NSPoint origin = NSMakePoint(NSMidX(self.bounds) - sz.width / 2.0,
                                 NSMidY(self.bounds) - sz.height / 2.0);
    [glyph drawAtPoint:origin withAttributes:attrs];
}

@end

// ─────────────────────────────────────────────────────────────────────────────
// PanelFrame
// ─────────────────────────────────────────────────────────────────────────────

@implementation PanelFrame {
    NSView        *_titleBar;
    NSTextField   *_titleLabel;
    _PFCloseButton *_closeButton;
    NSBox         *_separator;
    NSView        *_contentView;  // strong — we own the view we wrap
}

@synthesize contentView = _contentView;

- (instancetype)initWithContentView:(NSView *)content title:(NSString *)title {
    NSParameterAssert(content != nil);
    self = [super initWithFrame:NSZeroRect];
    if (!self) return nil;

    _contentView = content;
    [self _buildLayout];
    self.title = title ?: @"";
    [self _applyThemeColors];

    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(_darkModeChanged:)
               name:NPPDarkModeChangedNotification object:nil];

    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)_buildLayout {
    self.translatesAutoresizingMaskIntoConstraints = NO;

    // Title bar
    _titleBar = [[NSView alloc] init];
    _titleBar.translatesAutoresizingMaskIntoConstraints = NO;
    _titleBar.wantsLayer = YES;
    [self addSubview:_titleBar];

    _titleLabel = [NSTextField labelWithString:@""];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [NSFont systemFontOfSize:11];
    _titleLabel.textColor = [NSColor labelColor];
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_titleBar addSubview:_titleLabel];

    _closeButton = [[_PFCloseButton alloc] initWithFrame:NSZeroRect];
    _closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    _closeButton.target = self;
    _closeButton.action = @selector(_closeClicked:);
    _closeButton.font = [NSFont systemFontOfSize:11];
    _closeButton.toolTip = @"Close panel";
    [_titleBar addSubview:_closeButton];

    // Separator
    _separator = [[NSBox alloc] init];
    _separator.boxType = NSBoxSeparator;
    _separator.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_separator];

    // Content
    _contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_contentView];

    [NSLayoutConstraint activateConstraints:@[
        // Title bar (24pt)
        [_titleBar.topAnchor       constraintEqualToAnchor:self.topAnchor],
        [_titleBar.leadingAnchor   constraintEqualToAnchor:self.leadingAnchor],
        [_titleBar.trailingAnchor  constraintEqualToAnchor:self.trailingAnchor],
        [_titleBar.heightAnchor    constraintEqualToConstant:24],

        [_titleLabel.leadingAnchor  constraintEqualToAnchor:_titleBar.leadingAnchor constant:6],
        [_titleLabel.centerYAnchor  constraintEqualToAnchor:_titleBar.centerYAnchor],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_closeButton.leadingAnchor constant:-4],

        [_closeButton.trailingAnchor constraintEqualToAnchor:_titleBar.trailingAnchor constant:-4],
        [_closeButton.centerYAnchor  constraintEqualToAnchor:_titleBar.centerYAnchor],
        [_closeButton.widthAnchor    constraintEqualToConstant:16],
        [_closeButton.heightAnchor   constraintEqualToConstant:16],

        // Separator (1pt)
        [_separator.topAnchor      constraintEqualToAnchor:_titleBar.bottomAnchor],
        [_separator.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [_separator.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_separator.heightAnchor   constraintEqualToConstant:1],

        // Content view fills the rest — flush to edges, no inset.
        [_contentView.topAnchor      constraintEqualToAnchor:_separator.bottomAnchor],
        [_contentView.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [_contentView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_contentView.bottomAnchor   constraintEqualToAnchor:self.bottomAnchor],
    ]];
}

- (void)_closeClicked:(id)sender {
    id<PanelFrameDelegate> d = self.delegate;
    if ([d respondsToSelector:@selector(panelFrameRequestedClose:)])
        [d panelFrameRequestedClose:self];
}

// ── Title binding ─────────────────────────────────────────────────────────

- (NSString *)title { return _titleLabel.stringValue ?: @""; }

- (void)setTitle:(NSString *)title {
    _titleLabel.stringValue = title ?: @"";
}

// ── Theme ─────────────────────────────────────────────────────────────────

- (void)_applyThemeColors {
    _titleBar.layer.backgroundColor = [NppThemeManager shared].tabBarBackground.CGColor;
}

- (void)_darkModeChanged:(NSNotification *)n {
    [self _applyThemeColors];
}

@end
