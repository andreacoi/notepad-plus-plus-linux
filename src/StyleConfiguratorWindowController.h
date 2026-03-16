#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// ── Style data model (also used by EditorView) ────────────────────────────────

/// One style slot for a language (e.g. "COMMENT" → styleID=1 in cpp lexer).
@interface NPPStyleEntry : NSObject <NSCopying>
@property (nonatomic, copy)     NSString            *name;
@property (nonatomic)           int                  styleID;
@property (nonatomic, nullable) NSColor             *fgColor;   // nil = not set
@property (nonatomic, nullable) NSColor             *bgColor;
@property (nonatomic, copy)     NSString            *fontName;  // @"" = inherit
@property (nonatomic)           int                  fontSize;  // 0 = inherit
@property (nonatomic)           BOOL                 bold, italic, underline;
@end

/// All styles for a single language/lexer.
@interface NPPLexer : NSObject <NSCopying>
@property (nonatomic, copy)   NSString                        *lexerID;       // @"cpp", @"global"
@property (nonatomic, copy)   NSString                        *displayName;   // @"C++", @"Global Styles"
@property (nonatomic, strong) NSMutableArray<NPPStyleEntry *> *styles;
- (nullable NPPStyleEntry *)styleForID:(int)sid;
@end

// ── Style store (singleton) ───────────────────────────────────────────────────

/// Shared style store.  Reads defaults from bundled stylers.model.xml; stores
/// user overrides in NSUserDefaults key "NPPStyleOverrides".
@interface NPPStyleStore : NSObject

+ (NPPStyleStore *)sharedStore;

/// Parse the bundled XML and apply any saved overrides.  Call once at launch.
- (void)loadFromDefaults;

/// Return all style entries for a lexer (resolved = XML default + user override).
/// Mapping: "c"/"objc" are aliased to "cpp"; unknown IDs return nil.
- (nullable NSArray<NPPStyleEntry *> *)stylesForLexer:(NSString *)lexerID;

/// Ordered list of all lexers (Global Styles first, then alphabetical).
@property (readonly, nonatomic) NSArray<NPPLexer *> *allLexers;

/// Convenience: global "Default Style" resolved properties for STYLE_DEFAULT.
@property (readonly, nonatomic) NSColor  *globalFg;
@property (readonly, nonatomic) NSColor  *globalBg;
@property (readonly, nonatomic) NSString *globalFontName;
@property (readonly, nonatomic) int       globalFontSize;

/// Called by StyleConfiguratorWindowController on "Save & Close".
/// Replaces in-memory lexers with `lexers`, persists, and posts NPPPreferencesChanged.
- (void)commitLexers:(NSArray<NPPLexer *> *)lexers;

@end

// ── Window controller ─────────────────────────────────────────────────────────

/// Modeless Style Configurator window — matches Windows Notepad++ layout.
@interface StyleConfiguratorWindowController : NSWindowController

+ (instancetype)sharedController;

@end

NS_ASSUME_NONNULL_END
