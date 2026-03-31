#import <Cocoa/Cocoa.h>
#import "FindInFilesPanel.h"

NS_ASSUME_NONNULL_BEGIN

@class EditorView;

@interface MainWindowController : NSWindowController <FindInFilesPanelDelegate>

/// Open a file (called by AppDelegate when the OS hands us a file to open).
- (void)openFileAtPath:(NSString *)path;

/// The active editor in the currently focused pane (for plugin access).
- (nullable EditorView *)currentEditor;

/// Load a session file (plist format with tabs array).
- (void)loadSessionFromPath:(NSString *)path;

/// Restore the last session from ~/.notepad++/session.plist.
- (BOOL)restoreLastSession;

/// Add a plugin-provided toolbar icon.  Called by NppPluginManager when a
/// plugin sends NPPM_ADDTOOLBARICON_FORDARKMODE.
- (void)addPluginToolbarIcon:(NSImage *)icon tooltip:(NSString *)tooltip cmdID:(int)cmdID;

/// Rebuild the Macro menu from shortcuts.xml (called after macro save/delete).
- (void)rebuildMacroMenu;

/// Build and apply the editor right-click context menu to all editors.
- (void)applyEditorContextMenuToAll;

@end

NS_ASSUME_NONNULL_END
