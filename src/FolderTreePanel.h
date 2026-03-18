#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class FolderTreePanel;

@protocol FolderTreePanelDelegate <NSObject>
- (void)folderTreePanel:(FolderTreePanel *)panel openFileAtURL:(NSURL *)url;
- (void)folderTreePanelDidRequestClose:(FolderTreePanel *)panel;
/// Called when user selects "Find in Files" from the context menu.
- (void)folderTreePanel:(FolderTreePanel *)panel findInFilesAtPath:(NSString *)path;
@end

/// Side panel showing a multi-root file-system tree (Folder as Workspace).
/// Supports adding/removing root folders, context menus, persistent state.
@interface FolderTreePanel : NSView <NSOutlineViewDataSource, NSOutlineViewDelegate>

@property (nonatomic, weak, nullable) id<FolderTreePanelDelegate> delegate;

/// Store active file URL so Locate Current File can find it in the tree.
- (void)setActiveFileURL:(NSURL *)fileURL;

/// Opens an NSOpenPanel to add a root folder to the workspace.
- (void)chooseRootFolder;

@end

NS_ASSUME_NONNULL_END
