#import <Cocoa/Cocoa.h>
#import "UserDefineLangManager.h"

NS_ASSUME_NONNULL_BEGIN

/// "Define Your Language" dialog — macOS port of the Windows UDL editor.
/// 4-tab form: Folder & Default, Keywords Lists, Comment & Number, Operators & Delimiters.
@interface UserDefineDialog : NSWindowController <NSWindowDelegate>

+ (instancetype)sharedController;

/// Show the dialog, optionally selecting a language by name.
- (void)showWithLanguage:(nullable NSString *)langName;

@end

NS_ASSUME_NONNULL_END
