#import <Cocoa/Cocoa.h>
#import "EditorView.h"

NS_ASSUME_NONNULL_BEGIN

@class DocumentMapPanel;

@protocol DocumentMapPanelDelegate <NSObject>
- (void)documentMapPanelDidRequestClose:(DocumentMapPanel *)panel;
@end

@interface DocumentMapPanel : NSView

@property (nonatomic, weak, nullable) id<DocumentMapPanelDelegate> delegate;

/// Set the editor to mirror in the mini-map. Pass nil to clear.
- (void)setTrackedEditor:(nullable EditorView *)editor;

@end

NS_ASSUME_NONNULL_END
