#import <Cocoa/Cocoa.h>

/// Builds the application's main menu bar programmatically.
@interface MenuBuilder : NSObject
+ (void)buildMainMenu;

/// Insert dynamically-loaded plugin menu items into the Plugins menu.
/// Items are placed before the separator that precedes "Plugins Admin…".
+ (void)insertPluginMenuItems:(NSArray<NSMenuItem *> *)items;
@end
