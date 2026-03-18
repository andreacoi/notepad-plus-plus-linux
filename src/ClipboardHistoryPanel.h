#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class ClipboardHistoryPanel;

@protocol ClipboardHistoryPanelDelegate <NSObject>
- (void)clipboardHistoryPanelDidRequestClose:(ClipboardHistoryPanel *)panel;
@end

/// Side panel that records clipboard changes and lets the user re-paste any
/// previous entry by clicking it.
@interface ClipboardHistoryPanel : NSView <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, weak, nullable) id<ClipboardHistoryPanelDelegate> delegate;

/// Begin polling the pasteboard (call when panel becomes visible).
- (void)startMonitoring;

/// Stop polling the pasteboard (call when panel is hidden/closed).
- (void)stopMonitoring;

@end

NS_ASSUME_NONNULL_END
