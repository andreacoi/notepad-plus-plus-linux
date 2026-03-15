#import <Cocoa/Cocoa.h>

@class EditorView;

NS_ASSUME_NONNULL_BEGIN

/// Modal sheet for inserting text or sequential numbers at the caret column.
@interface ColumnEditorPanel : NSObject

/// Present the column editor as a sheet attached to parentWindow.
+ (void)showForEditor:(EditorView *)editor parentWindow:(NSWindow *)window;

@end

NS_ASSUME_NONNULL_END
