#import <Cocoa/Cocoa.h>
#import "FindInFilesPanel.h"

NS_ASSUME_NONNULL_BEGIN

@class EditorView;

@interface MainWindowController : NSWindowController <FindInFilesPanelDelegate>

/// Open a file (called by AppDelegate when the OS hands us a file to open).
- (void)openFileAtPath:(NSString *)path;

/// The active editor in the currently focused pane (for plugin access).
- (nullable EditorView *)currentEditor;

@end

NS_ASSUME_NONNULL_END
