#import <Cocoa/Cocoa.h>
#import "EditorView.h"

NS_ASSUME_NONNULL_BEGIN

@class FunctionListPanel;

@protocol FunctionListPanelDelegate <NSObject>
@optional
- (void)functionListPanelDidRequestClose:(FunctionListPanel *)panel;
@end

/// Tree-based function/method browser panel with title bar, sort, search, and
/// hierarchical display (classes→methods) following the Windows NPP design.
@interface FunctionListPanel : NSView <NSOutlineViewDataSource, NSOutlineViewDelegate,
                                       NSTextFieldDelegate>

@property (nonatomic, weak, nullable) id<FunctionListPanelDelegate> delegate;

/// Scan the given editor for function/method signatures and populate the tree.
- (void)loadEditor:(EditorView *)editor;

/// Force a re-scan of the current editor.
- (void)reload;

@end

NS_ASSUME_NONNULL_END
