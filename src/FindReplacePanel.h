#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class FindReplacePanel;

@protocol FindReplacePanelDelegate <NSObject>
- (void)findPanel:(FindReplacePanel *)panel findNext:(NSString *)text
        matchCase:(BOOL)matchCase wholeWord:(BOOL)wholeWord wrap:(BOOL)wrap;
- (void)findPanel:(FindReplacePanel *)panel findPrev:(NSString *)text
        matchCase:(BOOL)matchCase wholeWord:(BOOL)wholeWord wrap:(BOOL)wrap;
- (void)findPanel:(FindReplacePanel *)panel replace:(NSString *)text
             with:(NSString *)replacement
        matchCase:(BOOL)matchCase wholeWord:(BOOL)wholeWord;
- (void)findPanel:(FindReplacePanel *)panel replaceAll:(NSString *)text
             with:(NSString *)replacement
        matchCase:(BOOL)matchCase wholeWord:(BOOL)wholeWord;
- (void)findPanelDidClose:(FindReplacePanel *)panel;
@end

@interface FindReplacePanel : NSView

@property (nonatomic, weak, nullable) id<FindReplacePanelDelegate> delegate;

/// Show in find-only mode (Cmd+F). Focuses the search field.
- (void)openForFind;

/// Show in find+replace mode (Cmd+H). Focuses the search field.
- (void)openForReplace;

/// Hide the panel.
- (void)closePanel;

/// Height the panel should occupy (0 when hidden).
@property (nonatomic, readonly) CGFloat preferredHeight;

/// Last search text (empty string if none entered yet).
@property (nonatomic, readonly) NSString *currentSearchText;
- (void)setSearchText:(NSString *)text;
@property (nonatomic, readonly) BOOL currentMatchCase;
@property (nonatomic, readonly) BOOL currentWholeWord;
@property (nonatomic, readonly) BOOL currentWrap;

@end

NS_ASSUME_NONNULL_END
