#import <Cocoa/Cocoa.h>
#import "EditorView.h"

NS_ASSUME_NONNULL_BEGIN

@interface FunctionListPanel : NSView <NSTableViewDataSource, NSTableViewDelegate>

/// Scan the given editor for function/method signatures and populate the list.
- (void)loadEditor:(EditorView *)editor;

@end

NS_ASSUME_NONNULL_END
