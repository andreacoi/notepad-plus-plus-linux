#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Container that hosts one or more side panels, switching between them via
/// a segmented control at the top.  Designed to be the right pane of the
/// main NSSplitView.
@interface SidePanelHost : NSView

/// Show `panel` in the host (adds a segment if not already present).
- (void)showPanel:(NSView *)panel withTitle:(NSString *)title;

/// Remove `panel` from the host (removes its segment).
- (void)hidePanel:(NSView *)panel;

/// Returns YES if `panel` is currently hosted (visible or not).
- (BOOL)hasPanel:(NSView *)panel;

/// Returns YES if at least one panel is registered.
- (BOOL)hasVisiblePanels;

@end

NS_ASSUME_NONNULL_END
