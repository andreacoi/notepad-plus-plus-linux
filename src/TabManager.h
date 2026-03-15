#import <Cocoa/Cocoa.h>
#import "NppTabBar.h"

@class EditorView;

NS_ASSUME_NONNULL_BEGIN

/// NSView subclass used as the editor container; accepts file drag-and-drop.
@interface NppDropView : NSView
/// Called on the main thread with an array of dropped file paths.
@property (nonatomic, copy, nullable) void (^dropHandler)(NSArray<NSString *> *paths);
@end

@protocol TabManagerDelegate <NSObject>
- (void)tabManager:(id)tabManager didSelectEditor:(EditorView *)editor;
- (void)tabManager:(id)tabManager didCloseEditor:(EditorView *)editor;
@end

/// Manages the custom tab bar and the set of open editor views.
@interface TabManager : NSObject <NppTabBarDelegate>

@property (nonatomic, weak, nullable) id<TabManagerDelegate> delegate;
@property (nonatomic, readonly) NppTabBar *tabBar;      // the tab bar view
@property (nonatomic, readonly) NSView   *contentView;  // container for editor views
@property (nonatomic, readonly, nullable) EditorView *currentEditor;
@property (nonatomic, readonly) NSArray<EditorView *> *allEditors;

- (instancetype)init;

/// Add a new untitled tab and return its EditorView.
- (EditorView *)addNewTab;

/// Open a file in a new tab (or focus existing tab if already open).
- (nullable EditorView *)openFileAtPath:(NSString *)path;

/// Close the currently active tab.
- (void)closeCurrentTab;

/// Close a specific editor tab.
- (void)closeEditor:(EditorView *)editor;

/// Remove an editor from this manager without any save prompt or deallocation.
/// The EditorView stays alive; caller is responsible for adopting it elsewhere.
- (void)evictEditor:(EditorView *)editor;

/// Insert an existing, already-initialized EditorView into this manager as a new tab.
- (void)adoptEditor:(EditorView *)editor;

/// Notify tab bar that the current editor's modified state changed.
- (void)refreshCurrentTabTitle;

/// Select tab by index programmatically (fires delegate).
- (void)selectTabAtIndex:(NSInteger)index;

/// Reorder tabs to match the given sorted array (must contain same editors, same count).
/// The previously active editor remains selected.
- (void)reorderEditors:(NSArray<EditorView *> *)orderedEditors;

@end

NS_ASSUME_NONNULL_END
