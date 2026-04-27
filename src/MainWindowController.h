#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class EditorView;

@interface MainWindowController : NSWindowController

/// Open a file (called by AppDelegate when the OS hands us a file to open).
- (void)openFileAtPath:(NSString *)path;

/// The active editor in the currently focused pane (for plugin access).
- (nullable EditorView *)currentEditor;

/// Editor for a specific view: 0 = primary tab manager, 1 = secondary (vertical split).
/// Returns nil if the secondary view has no tabs.
- (nullable EditorView *)editorForPluginView:(int)viewId;

/// Load a session file (plist format with tabs array).
- (void)loadSessionFromPath:(NSString *)path;

/// Restore the last session from ~/.notepad++/session.plist.
- (BOOL)restoreLastSession;

/// Add a plugin-provided toolbar icon.  Called by NppPluginManager when a
/// plugin sends NPPM_ADDTOOLBARICON_FORDARKMODE.
///
/// The icon is resolved from disk at the current appearance and re-resolved
/// automatically on theme change. Lookup order:
///   1. Dark mode + iconHint   →  <pluginDir>/<base>_dark.<ext>
///   2.                        →  <pluginDir>/<iconHint>
///   3. Dark mode (no hint)    →  <pluginDir>/toolbar_dark.png
///   4.                        →  <pluginDir>/toolbar.png
///
/// `pluginDir` must be the absolute path of the plugin's resources directory.
/// `iconHint` may be nil/empty — in that case only steps 3+4 apply (the
/// "convention" path). `tooltip` becomes both the toolTip string and the
/// overflow-menu label.
- (void)addPluginToolbarIconForPluginDir:(NSString *)pluginDir
                                iconHint:(nullable NSString *)iconHint
                                 tooltip:(NSString *)tooltip
                                   cmdID:(int)cmdID;

/// Rebuild the Macro menu from shortcuts.xml (called after macro save/delete).
- (void)rebuildMacroMenu;

/// Build and apply the editor right-click context menu to all editors.
- (void)applyEditorContextMenuToAll;

/// Plugin panel docking — add `panel` to the side-panel host so it sits
/// alongside built-in panels (Document List, Function List, etc.).  Thin
/// forwarder to the private `_setPanelVisible:title:show:` — plugins call
/// this via the NPPM_DMM_SHOWPANEL message rather than directly.
- (void)showPluginPanel:(NSView *)panel withTitle:(NSString *)title;

/// Plugin panel docking — remove `panel` from the side-panel host.  Does
/// not release any strong reference the host holds on the view; the
/// NppPluginManager registry keeps the view alive until the plugin
/// unregisters it.
- (void)hidePluginPanel:(NSView *)panel;

/// Query whether a plugin panel is currently attached to the side-panel
/// host.  Returns NO for nil.
- (BOOL)isPluginPanelShown:(nullable NSView *)panel;

@end

/// Write current NSUserDefaults preferences to ~/.notepad++/config.xml.
void writeConfigXML(void);

/// Read ~/.notepad++/config.xml and apply settings to NSUserDefaults.
void readConfigXML(void);

/// Regenerate toolbarButtonsConf_example.xml with current plugin entries.
void regenerateToolbarExample(void);

NS_ASSUME_NONNULL_END
