#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted when the user saves shortcut changes. MainWindowController should
/// refresh menu accelerators and Scintilla key bindings.
extern NSNotificationName const NPPShortcutsChangedNotification;

/// The 5 tabs of the Shortcut Mapper, matching Windows NPP.
typedef NS_ENUM(NSInteger, ShortcutMapperTab) {
    ShortcutMapperTabMainMenu = 0,
    ShortcutMapperTabMacros,
    ShortcutMapperTabRunCommands,
    ShortcutMapperTabPluginCommands,
    ShortcutMapperTabScintillaCommands,
};

/// Shortcut Mapper window — allows viewing and editing keyboard shortcuts
/// for all commands across 5 categories.
@interface ShortcutMapperWindowController : NSWindowController

/// Show the mapper, optionally opening a specific tab.
- (void)showWithTab:(ShortcutMapperTab)tab;

@end

NS_ASSUME_NONNULL_END
