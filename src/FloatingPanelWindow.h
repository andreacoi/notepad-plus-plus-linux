#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class PanelFrame;

/// NSPanel that hosts a detached side-panel. The `PanelFrame` (chrome +
/// content view) becomes the window's contentView; closing via the red
/// traffic light routes through PanelFrame's close delegate so the panel
/// is unregistered through the exact same hide path that the in-title
/// close X uses.
///
/// Window style is `NSWindowStyleMaskUtilityWindow` + titled + closable +
/// resizable. Floating + becomesKeyOnlyIfNeeded so the detached panel
/// doesn't steal focus from the editor while the user is typing.
///
/// Frame is persisted across launches via setFrameAutosaveName: — the name
/// is derived from the contentView's class so each panel type remembers
/// where the user last left it.
@interface FloatingPanelWindow : NSPanel

/// The PanelFrame currently installed as this window's content view.
/// Weak because the PanelFrame itself retains the content view; the
/// window is owned by SidePanelHost via its `_poppedWindows` map.
@property (nonatomic, weak, readonly, nullable) PanelFrame *panelFrame;

/// Designated initializer. The given `frame` is installed as contentView.
/// Caller is responsible for calling -makeKeyAndOrderFront: after this.
- (instancetype)initWithPanelFrame:(PanelFrame *)frame;

- (instancetype)initWithContentRect:(NSRect)contentRect
                          styleMask:(NSWindowStyleMask)style
                            backing:(NSBackingStoreType)backingStoreType
                              defer:(BOOL)flag NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
