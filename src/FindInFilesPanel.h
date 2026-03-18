#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class FindInFilesPanel;

@protocol FindInFilesPanelDelegate <NSObject>
/// Called when the user double-clicks a result. Jump to that file+line and
/// highlight the matched text (case-sensitivity matches the original search).
- (void)findInFilesPanel:(FindInFilesPanel *)panel
                openFile:(NSString *)path
                  atLine:(NSInteger)line
               matchText:(NSString *)matchText
               matchCase:(BOOL)matchCase;
@end

/// Modeless panel: background recursive search with live results tree.
@interface FindInFilesPanel : NSWindowController <NSOutlineViewDataSource,
                                                   NSOutlineViewDelegate>

@property (nonatomic, weak, nullable) id<FindInFilesPanelDelegate> delegate;

/// Pre-fill the directory field before showing the panel.
@property (nonatomic, copy) NSString *searchDirectory;

+ (instancetype)sharedPanel;

@end

NS_ASSUME_NONNULL_END
