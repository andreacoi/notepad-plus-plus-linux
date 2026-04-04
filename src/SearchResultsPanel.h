#import <Cocoa/Cocoa.h>
#import "SearchEngine.h"

NS_ASSUME_NONNULL_BEGIN

@class SearchResultsPanel;

@protocol SearchResultsPanelDelegate <NSObject>
- (void)searchResultsPanel:(SearchResultsPanel *)panel
          navigateToFile:(NSString *)path
                  atLine:(NSInteger)line
               matchText:(NSString *)text
               matchCase:(BOOL)mc;
@optional
- (void)searchResultsPanelDidRequestClose:(SearchResultsPanel *)panel;
@end

/// Bottom panel displaying search results in a Scintilla editor with LexSearchResult.
/// Supports 3-level folding, matched text highlighting, and result navigation.
@interface SearchResultsPanel : NSView

@property (nonatomic, weak, nullable) id<SearchResultsPanelDelegate> delegate;

/// Add results from a search operation. Accumulates with previous results.
- (void)addResults:(NSArray<NPPFileResults *> *)fileResults
     forSearchText:(NSString *)searchText
           options:(NPPFindOptions *)opts
      filesSearched:(NSInteger)filesSearched;

/// Clear all search results.
- (void)clearAll;

/// Navigate to next/previous result line. Returns YES if navigated.
- (BOOL)navigateToNextResult;
- (BOOL)navigateToPreviousResult;

/// Toggle fold/unfold all.
- (void)foldAll;
- (void)unfoldAll;

@end

NS_ASSUME_NONNULL_END
