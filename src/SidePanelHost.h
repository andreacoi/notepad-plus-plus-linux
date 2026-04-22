#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class SidePanelHost;

/// Delegate that owns higher-level side-panel semantics (toolbar refresh,
/// divider collapse etc.).  SidePanelHost itself only manages the view
/// hierarchy inside the stack view; the delegate decides what hiding a
/// panel actually means in the broader app.
@protocol SidePanelHostDelegate <NSObject>
/// User clicked the close X in the title bar wrapping `contentView`.
/// Implementer is expected to call -hidePanel: (plus whatever else it
/// needs — e.g. toolbar-state refresh).
- (void)sidePanelHost:(SidePanelHost *)host
    didRequestCloseForContentView:(NSView *)contentView;

@optional
/// Fired by pop-out / dock-back actions after the panel has finished its
/// state transition. Host sends this so the container app can re-evaluate
/// layout decisions that depend on how many panels are DOCKED — notably,
/// whether the side-panel split should collapse (zero docked) or expand
/// (dock-back into empty side pane). Not fired for show/hide paths — the
/// caller of showPanel:/hidePanel: already owns that layout logic.
- (void)sidePanelHostDidChangePanelLayout:(SidePanelHost *)host;
@end

/// Container that hosts one or more side panels stacked vertically. Callers
/// pass in raw content views (the historical API); internally every content
/// view is wrapped in a PanelFrame that provides the uniform title bar,
/// separator, and close button. The wrapping is transparent — callers
/// continue to identify panels by their content-view pointer.
@interface SidePanelHost : NSView

/// Delegate that receives close-X requests routed through PanelFrame.
@property (nonatomic, weak, nullable) id<SidePanelHostDelegate> delegate;

/// Show `panel` in the host. If the content view isn't yet wrapped in a
/// PanelFrame, one is created on the fly with the given title.  Calling
/// twice with the same view is a safe no-op.
- (void)showPanel:(NSView *)panel withTitle:(NSString *)title;

/// Remove `panel` from the host.  The content view and its PanelFrame
/// wrapper are both detached from the stack; the wrapper is discarded so
/// a subsequent showPanel: rebuilds it with fresh state.
- (void)hidePanel:(NSView *)panel;

/// Returns YES if `panel` is currently hosted — either docked in the
/// stack OR popped out into its own floating window. The answer reflects
/// "is the user seeing this panel anywhere?", so MWC's toggle logic
/// continues to work unchanged when a panel is popped.
- (BOOL)hasPanel:(NSView *)panel;

/// Returns YES if at least one panel is currently DOCKED in the stack.
/// Popped-out panels do not count — they don't occupy side-pane real
/// estate, so MainWindowController should collapse the side split when
/// every remaining panel is popped.
- (BOOL)hasVisiblePanels;

/// Returns YES if `panel` is registered AND currently popped out. When
/// a panel is popped, isPanelPopped: is YES and the stack does not
/// contain its PanelFrame; hasPanel: is still YES because the panel is
/// hosted (just in a different surface).
- (BOOL)isPanelPopped:(NSView *)panel;

/// Move a currently-docked panel into a FloatingPanelWindow. The
/// PanelFrame (and therefore the content view it wraps) is reparented —
/// the NSView instance survives the move, so selection / scroll / first-
/// responder / outline expansion state are preserved.
///
/// No-op if the panel is not currently docked (unregistered or already
/// popped).
- (void)popOutPanel:(NSView *)panel;

/// Move a currently-popped panel back into the stack. The FloatingPanelWindow
/// is closed and released. No-op if the panel is not currently popped.
- (void)dockBackPanel:(NSView *)panel;

@end

NS_ASSUME_NONNULL_END
