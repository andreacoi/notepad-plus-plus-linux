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

/// Returns YES if `panel` is currently hosted (visible or not).
- (BOOL)hasPanel:(NSView *)panel;

/// Returns YES if at least one panel is registered.
- (BOOL)hasVisiblePanels;

@end

NS_ASSUME_NONNULL_END
