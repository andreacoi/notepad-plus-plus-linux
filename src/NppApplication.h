#import <Cocoa/Cocoa.h>

/// NSApplication subclass that intercepts menu actions during macro recording.
/// When an EditorView is recording a macro and a recordable menu action fires,
/// the selector name is captured as a type-2 (menu command) macro step.
@interface NppApplication : NSApplication

/// Call once after the main menu is fully built to populate the recordable selectors set.
- (void)buildRecordableSelectorsFromMenu;

/// Reentrancy guard: set YES during playback to prevent recording playback actions.
@property (nonatomic) BOOL playingBackMacro;

@end
