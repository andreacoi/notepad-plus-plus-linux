#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class PanelFrame;

/// Delegate notified when the user clicks the close X in the title bar.
/// Implementer is responsible for the actual hide — typically by calling
/// `[MainWindowController hidePluginPanel:]` or the equivalent built-in
/// toggle. PanelFrame itself never mutates the view hierarchy.
@protocol PanelFrameDelegate <NSObject>
- (void)panelFrameRequestedClose:(PanelFrame *)frame;
/// User clicked the pop-out / dock-back button. The implementer is
/// responsible for the actual state transition (usually via
/// -[SidePanelHost popOutPanel:] / -[SidePanelHost dockBackPanel:]).
/// PanelFrame does NOT mutate its own view hierarchy here — it just
/// reports the click. The implementer calls -setPopped: when the
/// transition has completed so the button can swap its glyph.
- (void)panelFrameRequestedTogglePop:(PanelFrame *)frame;
@end

/// Uniform chrome wrapper for all side panels — built-in and plugin-registered.
///
/// Visual spec (matches FunctionList / Document Map):
///   * 24pt title bar with tabBarBackground color (#F0F0F0 light, dark variant)
///   * Title label left-aligned, 11pt system font
///   * 16×16 close X on the right (permanent 1pt grey border, toolbar-blue
///     on hover/press, light-blue fill in light mode, fill skipped in dark)
///   * 1pt NSBoxSeparator below the title bar
///   * Content view fills the remaining space, flush to edges
///
/// Panels that need additional controls (sort, refresh, etc.) place them
/// inside their own content view — NOT in this title bar. The title bar
/// is close-only by design so all 8 built-in panels + future plugin
/// panels have identical chrome.
///
/// PanelFrame auto-updates its title-bar color on dark-mode changes via
/// NPPDarkModeChangedNotification. Panels should not duplicate that
/// observer.
@interface PanelFrame : NSView

/// The content view passed at construction; fills the area below the separator.
@property (nonatomic, readonly) NSView *contentView;

/// Title text displayed in the title bar. Reassignment updates the label live
/// (use this on NPPLocalizationChanged if the title is localized).
@property (nonatomic, copy) NSString *title;

/// Receives -panelFrameRequestedClose: when the close X is clicked.
@property (nonatomic, weak, nullable) id<PanelFrameDelegate> delegate;

/// Visual state of the pop-out button. Owner (SidePanelHost) flips this
/// once it has completed the actual dock/pop transition — PanelFrame only
/// uses it to pick the right SF Symbol for the toggle button.
@property (nonatomic, getter=isPopped) BOOL popped;

/// Designated initializer. `content` must not be nil; `title` may be any
/// pre-localized string the caller wants displayed.
- (instancetype)initWithContentView:(NSView *)content
                              title:(NSString *)title NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder  NS_UNAVAILABLE;

/// Programmatic close — used by FloatingPanelWindow to route a red-X
/// close through the same delegate chain as the in-title X click.
- (void)simulateCloseClick;

@end

NS_ASSUME_NONNULL_END
