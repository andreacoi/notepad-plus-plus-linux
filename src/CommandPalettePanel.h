#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Floating command palette — fuzzy-search all menu items and execute them.
/// Invoke with Cmd+Shift+P. Dismiss with Escape or by clicking away.
@interface CommandPalettePanel : NSPanel <NSTableViewDataSource,
                                          NSTableViewDelegate,
                                          NSTextFieldDelegate,
                                          NSWindowDelegate>

/// Show the palette centered over the given window.
- (void)showOverWindow:(NSWindow *)window;

/// (Re)build the command index from the current main menu.
- (void)buildIndex;

@end

NS_ASSUME_NONNULL_END
