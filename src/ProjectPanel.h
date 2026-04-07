#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class ProjectPanel;

@protocol ProjectPanelDelegate <NSObject>
- (void)projectPanel:(ProjectPanel *)panel openFileAtPath:(NSString *)path;
- (void)projectPanelDidRequestClose:(ProjectPanel *)panel;
- (void)projectPanel:(ProjectPanel *)panel findInFilesAtPath:(NSString *)path;
@end

/// Project Panel — virtual workspace tree with projects, folders, and files.
/// Contains 3 independent workspaces switchable via bottom segment control.
@interface ProjectPanel : NSView <NSOutlineViewDataSource, NSOutlineViewDelegate>

@property (nonatomic, weak, nullable) id<ProjectPanelDelegate> delegate;

/// Switch to workspace tab (0, 1, or 2) and show it.
- (void)activateTab:(NSInteger)tabIndex;

/// Current active tab index (0-2).
@property (nonatomic, readonly) NSInteger activeTab;

/// Returns all file paths from the workspace at the given tab index (0-2).
/// Returns empty array if the workspace has no loaded XML or no files.
- (NSArray<NSString *> *)allFilePathsFromWorkspace:(NSInteger)tabIndex;

/// Returns YES if the workspace at the given tab has a loaded XML with files.
- (BOOL)workspaceHasContent:(NSInteger)tabIndex;

@end

NS_ASSUME_NONNULL_END
