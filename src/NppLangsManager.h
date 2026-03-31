#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Parsed language definition from langs.xml.
@interface NppLangDef : NSObject
@property (nonatomic, copy) NSString *name;               // e.g. "cpp"
@property (nonatomic, copy) NSString *extensions;          // space-separated, e.g. "cpp cxx cc h"
@property (nonatomic, copy) NSString *commentLine;         // e.g. "//"
@property (nonatomic, copy) NSString *commentStart;        // e.g. "/*"
@property (nonatomic, copy) NSString *commentEnd;          // e.g. "*/"
@property (nonatomic) NSInteger tabSettings;               // -1=default, else encoded value
@property (nonatomic) BOOL exclude;                        // YES = hidden from Language menu
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *keywords;
    // keys: "instre1", "instre2", "type1".."type7", "substyle1".."substyle8"
@end

/// Singleton that reads and caches language definitions from langs.xml.
@interface NppLangsManager : NSObject

+ (instancetype)shared;

/// Load from ~/.notepad++/langs.xml (or bundle fallback).
- (void)loadLangs;

/// Look up language definition by name (e.g. "cpp", "python").
- (nullable NppLangDef *)langDefForName:(NSString *)name;

/// Look up language name by file extension (e.g. "cpp" for "h", "python" for "py").
- (nullable NSString *)languageForExtension:(NSString *)ext;

/// Get comment delimiters for a language. Returns nil if not defined.
- (nullable NSString *)commentLineForLanguage:(NSString *)lang;
- (nullable NSString *)commentStartForLanguage:(NSString *)lang;
- (nullable NSString *)commentEndForLanguage:(NSString *)lang;

/// Get keywords for a language and keyword class (e.g. "instre1", "type1").
- (nullable NSString *)keywordsForLanguage:(NSString *)lang keywordClass:(NSString *)kwClass;

/// All loaded language names (ordered as in XML).
@property (nonatomic, readonly) NSArray<NSString *> *allLanguageNames;

/// Extension → language map (built from all loaded langs).
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *extensionMap;

@end

NS_ASSUME_NONNULL_END
