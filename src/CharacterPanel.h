#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class CharacterPanel;

@protocol CharacterPanelDelegate <NSObject>
/// Insert a string (character or HTML entity) at the current cursor position.
- (void)characterPanel:(CharacterPanel *)panel insertString:(NSString *)str;
- (void)characterPanelDidRequestClose:(CharacterPanel *)panel;
@end

/// Side panel showing the ASCII Codes Insertion table (256 rows, 6 columns).
/// Clicking Value/Hex/Character columns inserts the character; clicking HTML
/// columns inserts the HTML entity text.
@interface CharacterPanel : NSView <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, weak, nullable) id<CharacterPanelDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
