#import <Cocoa/Cocoa.h>
#import "FindInFilesPanel.h"

NS_ASSUME_NONNULL_BEGIN

@class EditorView;

@interface MainWindowController : NSWindowController <FindInFilesPanelDelegate>

/// Open a file (called by AppDelegate when the OS hands us a file to open).
- (void)openFileAtPath:(NSString *)path;

/// The active editor in the currently focused pane (for plugin access).
- (nullable EditorView *)currentEditor;

/// Add a plugin-provided toolbar icon.  Called by NppPluginManager when a
/// plugin sends NPPM_ADDTOOLBARICON_FORDARKMODE.
- (void)addPluginToolbarIcon:(NSImage *)icon tooltip:(NSString *)tooltip cmdID:(int)cmdID;

@end

NS_ASSUME_NONNULL_END
