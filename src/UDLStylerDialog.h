#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Modal Styler dialog for UDL styles. Matches the Windows Notepad++ Styler Dialog.
/// Shows Font options (name, size, bold/italic/underline, foreground/background colors)
/// and optionally a Nesting section (for delimiter/comment styles).
@interface UDLStylerDialog : NSObject

/// Run the Styler dialog modally. Returns YES if OK was clicked, NO if Cancel.
/// @param style  Mutable style dictionary to edit (keys: name, fgColor, bgColor, fontStyle, fontName)
/// @param enableNesting  YES for delimiters/comments (shows nesting checkboxes), NO for keywords/operators/etc.
/// @param parentWindow  The parent window (dialog centers on this)
+ (BOOL)runForStyle:(NSMutableDictionary *)style
      enableNesting:(BOOL)enableNesting
       parentWindow:(NSWindow *)parentWindow;

@end

NS_ASSUME_NONNULL_END
