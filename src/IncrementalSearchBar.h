#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class EditorView;

/// Delegate to handle navigation requests from the incremental search bar.
@protocol IncrementalSearchBarDelegate <NSObject>
- (void)incrementalSearchBar:(id)bar findText:(NSString *)text
                   matchCase:(BOOL)mc forward:(BOOL)fwd;
- (void)incrementalSearchBarDidClose:(id)bar;
@end

/// Narrow live-search bar shown below the editor (triggered by Cmd+I).
/// Highlights all matches as the user types and jumps to the first one.
@interface IncrementalSearchBar : NSView <NSTextFieldDelegate, NSControlTextEditingDelegate>

@property (nonatomic, weak, nullable) id<IncrementalSearchBarDelegate> delegate;

/// Preferred height when visible.
@property (nonatomic, readonly) CGFloat preferredHeight;

/// Make the search field first responder.
- (void)activate;

/// Dismiss the bar and clear highlights.
- (void)close;

/// Update the status label (e.g. "Not found"). Pass found=NO for red color.
- (void)setStatus:(NSString *)text found:(BOOL)found;

@end

NS_ASSUME_NONNULL_END
