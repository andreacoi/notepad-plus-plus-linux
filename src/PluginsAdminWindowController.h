#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Plugins Admin window — browse, install, update, and remove plugins.
/// Mirrors the Windows Notepad++ Plugins Admin with 4 tabs:
///   Available | Updates | Installed | Incompatible
@interface PluginsAdminWindowController : NSWindowController

/// Shared singleton (window created on first access).
+ (instancetype)sharedController;

@end

NS_ASSUME_NONNULL_END
