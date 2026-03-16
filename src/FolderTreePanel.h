#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class FolderTreePanel;

@protocol FolderTreePanelDelegate <NSObject>
- (void)folderTreePanel:(FolderTreePanel *)panel openFileAtURL:(NSURL *)url;
@end

/// Side panel showing a file-system folder tree.
/// Automatically follows the active tab's parent folder unless locked.
@interface FolderTreePanel : NSView <NSOutlineViewDataSource, NSOutlineViewDelegate>

@property (nonatomic, weak, nullable) id<FolderTreePanelDelegate> delegate;

/// Called on tab switch; ignored when the panel is locked.
- (void)setActiveFileURL:(NSURL *)fileURL;

@end

NS_ASSUME_NONNULL_END
