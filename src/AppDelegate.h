#import <Cocoa/Cocoa.h>

@class MainWindowController;
@class NppCommandLineParams;

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (nonatomic, strong) MainWindowController *mainWindowController;

/// Command line parameters parsed in main(). Set before NSApplication runs.
@property (nonatomic, strong, nullable) NppCommandLineParams *cliParams;

/// Launch timestamp for -loadingTime display.
@property (nonatomic, strong, nullable) NSDate *launchStart;

@end
