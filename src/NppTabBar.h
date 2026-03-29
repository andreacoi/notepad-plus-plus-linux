#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class NppTabBar;

@protocol NppTabBarDelegate <NSObject>
- (void)tabBar:(NppTabBar *)bar didSelectTabAtIndex:(NSInteger)index;
- (void)tabBar:(NppTabBar *)bar didCloseTabAtIndex:(NSInteger)index;
@end

/// Left-aligned, scrollable tab bar styled after Notepad++.
@interface NppTabBar : NSView

@property (nonatomic, weak, nullable) id<NppTabBarDelegate> delegate;
@property (nonatomic, readonly) NSInteger selectedIndex;
@property (nonatomic, readonly) NSInteger tabCount;

- (void)addTabWithTitle:(NSString *)title modified:(BOOL)modified;
- (void)removeTabAtIndex:(NSInteger)index;
- (void)setTitle:(NSString *)title modified:(BOOL)modified atIndex:(NSInteger)index;
- (void)selectTabAtIndex:(NSInteger)index;

/// Pin or unpin the tab at index. Pinned tabs hide the × button and block close.
- (void)pinTabAtIndex:(NSInteger)index toggle:(BOOL)toggle;
/// Returns YES if the tab at index is pinned.
- (BOOL)isTabPinnedAtIndex:(NSInteger)index;

/// Swap two tab items by index (preserves all properties including pin and color).
- (void)swapTabAtIndex:(NSInteger)a withIndex:(NSInteger)b;

/// Set a per-tab color identifier (-1 = none/default orange, 0–4 = color 1–5).
- (void)setTabColorAtIndex:(NSInteger)index colorId:(NSInteger)colorId;
/// Returns the color identifier for the tab at index (-1 if none).
- (NSInteger)tabColorAtIndex:(NSInteger)index;

/// When YES tabs wrap to multiple rows instead of scrolling horizontally.
@property (nonatomic) BOOL wrapMode;

@end

NS_ASSUME_NONNULL_END
