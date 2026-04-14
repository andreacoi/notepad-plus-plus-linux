#import <Cocoa/Cocoa.h>

@class MainWindowController;
struct SCNotification;

NS_ASSUME_NONNULL_BEGIN

/// Notification posted after all plugins have been loaded and NPPN_READY fired.
extern NSNotificationName const NppPluginsDidLoadNotification;

/// Manages the lifecycle of Notepad++ dylib plugins on macOS.
///
/// Responsibilities:
///   - Discover and load .dylib plugins from ~/.notepad++/plugins/
///   - Resolve the 5 mandatory C exports (setInfo, getName, etc.)
///   - Build NppData with opaque handles and a sendMessage function pointer
///   - Dispatch NPPM_* messages from plugins to the host
///   - Route SCI_* messages from plugins to the correct ScintillaView
///   - Broadcast NPPN_* notifications to all loaded plugins
///   - Provide menu items for the Plugins menu
///   - Allocate non-overlapping command/marker/indicator IDs
@interface NppPluginManager : NSObject

/// Shared singleton.  Created on first access.
+ (instancetype)shared;

/// Must be called once after the main window is fully initialized.
/// Stores the controller reference for editor access and message routing.
- (void)setMainWindowController:(MainWindowController *)mwc;

/// Scan the plugin directory, load all .dylib plugins, call setInfo/getFuncsArray.
/// Call this after setMainWindowController: and before fireReady.
- (void)loadPlugins;

/// Fire NPPN_READY + NPPN_TBMODIFICATION to all loaded plugins.
/// Call once after loadPlugins and after the UI is fully set up.
- (void)fireReady;

/// Fire NPPN_BEFORESHUTDOWN + NPPN_SHUTDOWN and unload all plugins.
- (void)shutdown;

/// Broadcast an NPPN_* notification to all plugins.
- (void)notifyPluginsWithCode:(unsigned int)code;

/// Broadcast an NPPN_* notification with a buffer identifier.
- (void)notifyPluginsWithCode:(unsigned int)code bufferID:(intptr_t)bufferID;

/// Forward a raw Scintilla notification to all plugins.
/// Forwarded codes: SCN_CHARADDED, SCN_MODIFIED, SCN_AUTOCSELECTION,
/// SCN_AUTOCCANCELLED, SCN_UPDATEUI, SCN_PAINTED.
/// Reentrancy guarded — plugin-triggered nested notifications are dropped.
- (void)forwardScintillaNotification:(SCNotification *)scn;

/// Returns YES if at least one plugin was loaded successfully.
@property (nonatomic, readonly) BOOL hasPlugins;

/// Returns the number of loaded plugins.
@property (nonatomic, readonly) NSInteger pluginCount;

/// Build and return NSMenuItems for the Plugins menu.
/// Each loaded plugin gets a submenu with its FuncItem entries.
/// Caller inserts these into the Plugins menu at the appropriate position.
- (NSArray<NSMenuItem *> *)pluginMenuItems;

/// Execute a plugin command by its assigned command ID (from FuncItem._cmdID).
- (void)runPluginCommandWithID:(int)cmdID;

/// Returns all plugin actions for toolbar config XML generation.
/// Each entry: @{@"pluginName", @"actionName", @"cmdID", @"hasToolbarIcon"}
- (NSArray<NSDictionary *> *)allPluginActions;

@end

NS_ASSUME_NONNULL_END
