#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Modeless Style Configurator window. Mirrors NPP's "Style Configurator" dialog.
/// Allows selecting built-in theme presets and customizing individual token colors.
@interface StyleConfiguratorWindowController : NSWindowController

+ (instancetype)sharedController;

@end

NS_ASSUME_NONNULL_END
