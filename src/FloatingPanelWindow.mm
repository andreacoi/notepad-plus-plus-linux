#import "FloatingPanelWindow.h"
#import "PanelFrame.h"
#import "NppThemeManager.h"

// Default geometry for a freshly-popped panel. setFrameAutosaveName:
// overrides this with the last-used frame whenever one is remembered.
static const CGFloat kDefaultWidth  = 320.0;
static const CGFloat kDefaultHeight = 480.0;
static const CGFloat kFPWIconSize   = 11;

static NSImage *_FPWLoadIcon(NSString *name) {
    NSString *subdir = [NppThemeManager shared].isDark
        ? @"icons/dark/panels/toolbar"
        : @"icons/standard/panels/toolbar";
    NSURL *url = [[NSBundle mainBundle] URLForResource:name withExtension:@"png"
                                          subdirectory:subdir];
    NSImage *img = url ? [[NSImage alloc] initWithContentsOfURL:url] : nil;
    if (img) img.size = NSMakeSize(kFPWIconSize, kFPWIconSize);
    return img;
}

// ─────────────────────────────────────────────────────────────────────────────
// _FPWDockBackButton — SF Symbol button lives in the window's native title
// bar (via NSTitlebarAccessoryViewController). Clicking it asks the
// PanelFrame to flip back to docked state through the existing delegate
// chain — same route the in-chrome pop button uses when docked, so both
// paths converge on SidePanelHost.panelFrameRequestedTogglePop:.
// ─────────────────────────────────────────────────────────────────────────────

@interface _FPWDockBackButton : NSButton {
    BOOL _hovering;
}
@end

@implementation _FPWDockBackButton

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.bordered   = NO;
        self.buttonType = NSButtonTypeMomentaryChange;
        self.title      = @"";
        self.toolTip    = @"Dock back";
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

- (void)mouseEntered:(NSEvent *)e { _hovering = YES; [self setNeedsDisplay:YES]; }
- (void)mouseExited:(NSEvent *)e  { _hovering = NO;  [self setNeedsDisplay:YES]; }

- (void)drawRect:(NSRect)dirtyRect {
    // Matches the in-panel toolbar button style exactly: no border at rest,
    // blueish border + light-blue fill (light mode only) on hover/press.
    BOOL pressed = self.isHighlighted;
    BOOL active  = pressed || _hovering;
    BOOL isDark  = [NppThemeManager shared].isDark;

    if (active) {
        if (!isDark) {
            NSColor *bg = pressed
                ? [NSColor colorWithRed:0xCC/255.0 green:0xE8/255.0 blue:0xFF/255.0 alpha:1.0]
                : [NSColor colorWithRed:0xE5/255.0 green:0xF3/255.0 blue:0xFF/255.0 alpha:1.0];
            [bg setFill];
            NSRectFill(self.bounds);
        }
        NSColor *bdr = [NSColor colorWithRed:0xD0/255.0 green:0xEA/255.0 blue:0xFF/255.0 alpha:1.0];
        NSBezierPath *border = [NSBezierPath bezierPathWithRect:NSInsetRect(self.bounds, 0.5, 0.5)];
        border.lineWidth = 1.0;
        [bdr setStroke];
        [border stroke];
    }

    NSImage *icon = _FPWLoadIcon(@"pop_in");
    if (!icon) return;

    NSSize isz = icon.size;
    NSRect target = NSMakeRect(NSMidX(self.bounds) - isz.width / 2.0,
                               NSMidY(self.bounds) - isz.height / 2.0,
                               isz.width, isz.height);
    [icon drawInRect:target
            fromRect:NSZeroRect
           operation:NSCompositingOperationSourceOver
            fraction:1.0
      respectFlipped:YES
               hints:nil];
}

@end

@interface FloatingPanelWindow () <NSWindowDelegate>
@property (nonatomic, weak) PanelFrame *panelFrame;
@end

@implementation FloatingPanelWindow

- (instancetype)initWithPanelFrame:(PanelFrame *)frame {
    NSParameterAssert(frame != nil);

    NSRect defaultRect = NSMakeRect(0, 0, kDefaultWidth, kDefaultHeight);
    NSUInteger style = NSWindowStyleMaskTitled    |
                       NSWindowStyleMaskClosable  |
                       NSWindowStyleMaskResizable |
                       NSWindowStyleMaskUtilityWindow;

    self = [super initWithContentRect:defaultRect
                            styleMask:style
                              backing:NSBackingStoreBuffered
                                defer:YES];
    if (!self) return nil;

    _panelFrame           = frame;
    self.title            = frame.title ?: @"";
    self.floatingPanel    = YES;
    // Only become key when the user actually interacts with a control
    // inside the panel — keeps typing in the editor snappy.
    self.becomesKeyOnlyIfNeeded = YES;
    self.hidesOnDeactivate      = NO;
    // SidePanelHost owns the strong retain; we don't want AppKit releasing
    // the window object out from under us when the user clicks the red X.
    self.releasedWhenClosed     = NO;
    self.delegate               = self;

    // Install the PanelFrame as the contentView. This reparents its view
    // hierarchy from SidePanelHost's stack into this NSPanel; AppKit sends
    // -viewWillMoveToWindow: / -viewDidMoveToWindow: to every descendant.
    self.contentView = frame;

    // Dock-back button in the native title bar, trailing edge. The
    // PanelFrame's own chrome is collapsed when popped (see
    // -[PanelFrame setPopped:]), so this accessory is the only visible
    // dock-back affordance while the panel is floating.
    _FPWDockBackButton *btn = [[_FPWDockBackButton alloc]
        initWithFrame:NSMakeRect(0, 0, 22, 22)];
    btn.target = self;
    btn.action = @selector(_dockBackClicked:);

    NSView *holder = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 28, 22)];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [holder addSubview:btn];
    [NSLayoutConstraint activateConstraints:@[
        [btn.trailingAnchor constraintEqualToAnchor:holder.trailingAnchor constant:-4],
        [btn.centerYAnchor  constraintEqualToAnchor:holder.centerYAnchor],
        [btn.widthAnchor    constraintEqualToConstant:22],
        [btn.heightAnchor   constraintEqualToConstant:22],
    ]];

    NSTitlebarAccessoryViewController *acc = [[NSTitlebarAccessoryViewController alloc] init];
    acc.layoutAttribute = NSLayoutAttributeRight;
    acc.view = holder;
    [self addTitlebarAccessoryViewController:acc];

    // Center the first pop-out on the main screen; autosave will then
    // remember the user-chosen location on subsequent pops.
    [self center];

    // Autosave name must be stable across launches — derive from the
    // wrapped content view's class so each panel remembers its own
    // frame independently.
    if (frame.contentView) {
        NSString *cls = NSStringFromClass([frame.contentView class]);
        NSString *autosave = [@"NppFloatingPanel_" stringByAppendingString:cls];
        // setFrameAutosaveName: returns NO if the name is already in use
        // (rare edge case: two FloatingPanelWindows for panels of the
        // same class existed simultaneously). Fall back to a per-pointer
        // name so both panels still remember their frames independently
        // within this launch.
        if (![self setFrameAutosaveName:autosave]) {
            NSString *unique = [NSString stringWithFormat:@"%@_%p", autosave, (void *)frame.contentView];
            [self setFrameAutosaveName:unique];
        }
    }

    return self;
}

// ── Dock-back action ──────────────────────────────────────────────────────

// Clicking the accessory button routes through the PanelFrame's pop
// delegate — same entry point the in-chrome pop-out button uses when
// docked. SidePanelHost detects current state and flips to docked.
- (void)_dockBackClicked:(id)sender {
    PanelFrame *frame = self.panelFrame;
    id delegate = frame.delegate;
    if ([delegate respondsToSelector:@selector(panelFrameRequestedTogglePop:)])
        [delegate panelFrameRequestedTogglePop:frame];
}

// ── Zoom forwarding ───────────────────────────────────────────────────────
//
// When this window is key, the main menu's Cmd+/-/0 actions dispatch via
// the key window's responder chain. MainWindowController (which handles
// zoom for the main window) is NOT in our chain — it owns the main
// window, not this popped one. Implementing zoomIn:/zoomOut:/resetZoom:
// here puts the floating window itself in the chain so the same shortcut
// keys work, routed to the popped panel's own -panelZoomIn/Out/Reset.
//
// Each method is a no-op if the hosted panel doesn't implement the
// matching zoom selector (plugin panels may not). -respondsToSelector:
// on a nil recipient returns NO, so the `panelFrame` being released
// mid-transition is also safe.

- (void)zoomIn:(id)sender {
    id cv = self.panelFrame.contentView;
    if ([cv respondsToSelector:@selector(panelZoomIn)])
        [cv performSelector:@selector(panelZoomIn)];
}

- (void)zoomOut:(id)sender {
    id cv = self.panelFrame.contentView;
    if ([cv respondsToSelector:@selector(panelZoomOut)])
        [cv performSelector:@selector(panelZoomOut)];
}

- (void)resetZoom:(id)sender {
    id cv = self.panelFrame.contentView;
    if ([cv respondsToSelector:@selector(panelZoomReset)])
        [cv performSelector:@selector(panelZoomReset)];
}

// ── NSWindowDelegate ──────────────────────────────────────────────────────

// Red traffic-light close: route through the PanelFrame's close chain so
// the hide flow (panelWillClose → _setPanelVisible:show:NO → SidePanelHost
// hidePanel:) runs exactly as if the user had clicked the X in the title
// bar. Return NO so AppKit doesn't perform its own close — SidePanelHost's
// hidePanel: will call -[NSWindow close] after cleanup.
- (BOOL)windowShouldClose:(NSWindow *)sender {
    [self.panelFrame simulateCloseClick];
    return NO;
}

@end
