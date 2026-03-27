#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Parses and stores Notepad++ command line arguments.
/// Mirrors the Windows CmdLineParams struct with macOS-appropriate types.
@interface NppCommandLineParams : NSObject

// Boolean flags
@property (nonatomic, readonly) BOOL showHelp;
@property (nonatomic, readonly) BOOL multiInstance;
@property (nonatomic, readonly) BOOL noPlugin;
@property (nonatomic, readonly) BOOL noSession;
@property (nonatomic, readonly) BOOL noTabBar;
@property (nonatomic, readonly) BOOL readOnly;
@property (nonatomic, readonly) BOOL fullReadOnly;
@property (nonatomic, readonly) BOOL fullReadOnlySavingForbidden;
@property (nonatomic, readonly) BOOL monitorFiles;
@property (nonatomic, readonly) BOOL alwaysOnTop;
@property (nonatomic, readonly) BOOL quickPrint;
@property (nonatomic, readonly) BOOL showLoadingTime;
@property (nonatomic, readonly) BOOL recursive;
@property (nonatomic, readonly) BOOL openFoldersAsWorkspace;
@property (nonatomic, readonly) BOOL isSessionFile;

// Numeric params
@property (nonatomic, readonly) NSInteger lineNumber;     // -n (1-based, 0 = not set)
@property (nonatomic, readonly) NSInteger columnNumber;   // -c (1-based, 0 = not set)
@property (nonatomic, readonly) NSInteger bytePosition;   // -p (-1 = not set)
@property (nonatomic, readonly) CGFloat windowX;          // -x (NAN = not set)
@property (nonatomic, readonly) CGFloat windowY;          // -y (NAN = not set)

// String params
@property (nonatomic, copy, readonly, nullable) NSString *language;       // -l
@property (nonatomic, copy, readonly, nullable) NSString *udlName;        // -udl="name"
@property (nonatomic, copy, readonly, nullable) NSString *localization;   // -L
@property (nonatomic, copy, readonly, nullable) NSString *sessionFile;    // -openSession path
@property (nonatomic, copy, readonly, nullable) NSString *settingsDir;    // -settingsDir="path"
@property (nonatomic, copy, readonly, nullable) NSString *titleAdd;       // -titleAdd="text"

// File paths (remaining non-flag arguments)
@property (nonatomic, copy, readonly) NSArray<NSString *> *filePaths;

/// Parse command line arguments. Call from main() before NSApplication runs.
- (instancetype)initWithArgc:(int)argc argv:(const char **)argv;

/// Returns YES if any CLI arguments were provided (beyond the program name).
@property (nonatomic, readonly) BOOL hasArguments;

@end

NS_ASSUME_NONNULL_END
