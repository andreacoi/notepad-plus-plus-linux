#import <Cocoa/Cocoa.h>
#import "TabManager.h"

NS_ASSUME_NONNULL_BEGIN

/// Side panel that lists all open editor tabs and lets the user switch between
/// them by clicking a row.
@interface DocumentListPanel : NSView <NSTableViewDataSource, NSTableViewDelegate>

- (instancetype)initWithTabManager:(TabManager *)tabManager;

/// Reload the list from the tab manager (call after tab open/close/select).
- (void)reloadData;

@end

NS_ASSUME_NONNULL_END
