#import <Cocoa/Cocoa.h>
#import "FindInFilesPanel.h"

NS_ASSUME_NONNULL_BEGIN

@interface MainWindowController : NSWindowController <FindInFilesPanelDelegate>

/// Open a file (called by AppDelegate when the OS hands us a file to open).
- (void)openFileAtPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
