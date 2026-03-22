#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class GitPanel;

@protocol GitPanelDelegate <NSObject>
- (void)gitPanel:(GitPanel *)panel openFileAtPath:(NSString *)path;
- (void)gitPanel:(GitPanel *)panel diffFileAtPath:(NSString *)path;
- (void)gitPanelDidRequestClose:(GitPanel *)panel;
@end

/// Side panel showing git status, with stage/unstage/commit controls.
@interface GitPanel : NSView <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, weak, nullable) id<GitPanelDelegate> delegate;

/// Set the repo root path. Pass nil to show "No git repository" state.
- (void)setRepoRoot:(nullable NSString *)root;

/// Async refresh: re-read branch + status from git.
- (void)refresh;

@end

NS_ASSUME_NONNULL_END
