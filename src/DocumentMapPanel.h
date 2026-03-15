#import <Cocoa/Cocoa.h>
#import "EditorView.h"

NS_ASSUME_NONNULL_BEGIN

@interface DocumentMapPanel : NSView

/// Set the editor to mirror in the mini-map. Pass nil to clear.
- (void)setTrackedEditor:(nullable EditorView *)editor;

@end

NS_ASSUME_NONNULL_END
