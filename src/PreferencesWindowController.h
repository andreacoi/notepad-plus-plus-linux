#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// NSUserDefaults keys (exported so EditorView can read them)
extern NSString *const kPrefTabWidth;
extern NSString *const kPrefUseTabs;
extern NSString *const kPrefAutoIndent;
extern NSString *const kPrefShowLineNumbers;
extern NSString *const kPrefWordWrap;
extern NSString *const kPrefHighlightCurrentLine;
extern NSString *const kPrefEOLType;
extern NSString *const kPrefEncoding;
extern NSString *const kPrefAutoBackup;
extern NSString *const kPrefBackupInterval;
extern NSString *const kPrefZoomLevel;

// Theme / Style Configurator keys (hex color strings "#RRGGBB")
extern NSString *const kPrefThemePreset;    // preset name or "Custom"
extern NSString *const kPrefStyleFg;        // default foreground
extern NSString *const kPrefStyleBg;        // default background
extern NSString *const kPrefStyleComment;
extern NSString *const kPrefStyleKeyword;
extern NSString *const kPrefStyleString;
extern NSString *const kPrefStyleNumber;
extern NSString *const kPrefStylePreproc;
extern NSString *const kPrefStyleFontName;  // e.g. "Menlo"
extern NSString *const kPrefStyleFontSize;  // integer stored as NSNumber

/// Modeless preferences window. Call +sharedController to get the singleton.
@interface PreferencesWindowController : NSWindowController

+ (instancetype)sharedController;

@end

NS_ASSUME_NONNULL_END
