#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted on the default notification center after a language change is applied
/// to the main menu and all registered UI.  Observers should update any
/// hard-coded English strings they display.
extern NSNotificationName const NPPLocalizationChanged;

/// NSUserDefaults key for the persisted language selection.
/// Value is the XML filename stem, e.g. @"french" or @"english".
extern NSString * const kPrefLanguage;

// ---------------------------------------------------------------------------
// NppLocalizer — singleton that loads a Notepad++ nativeLang XML file
// (the exact same format used by the Windows version) and applies
// translations to the macOS app's main menu and on-demand string lookups.
//
// Workflow:
//   1. App launch: [NppLocalizer.shared autoLoad] reads kPrefLanguage from
//      NSUserDefaults and applies it.  Call this after MenuBuilder.buildMainMenu.
//   2. Language change: [NppLocalizer.shared loadLanguageNamed:@"french"]
//      translates menus live and posts NPPLocalizationChanged.
//   3. Panels/dialogs: use [NppLocalizer.shared translate:@"..."] to convert
//      English UI strings, and observe NPPLocalizationChanged to retranslate
//      when the language changes at runtime.
// ---------------------------------------------------------------------------
@interface NppLocalizer : NSObject

/// Shared singleton.
+ (instancetype)shared;

/// Read kPrefLanguage from NSUserDefaults and apply it.
/// Call once after the main menu has been built.
- (void)autoLoad;

/// Load the named language (XML filename stem, e.g. @"french").
/// Pass @"english" or nil to reset to English.
/// Returns YES on success; NO if the XML could not be parsed.
/// On success: rebuilds translation maps, retranslates NSApp.mainMenu,
/// saves kPrefLanguage to NSUserDefaults, and posts NPPLocalizationChanged.
- (BOOL)loadLanguageNamed:(nullable NSString *)languageName;

/// Apply current translations to NSApp.mainMenu.
/// Called automatically by loadLanguageNamed:, but you can also call it
/// manually after dynamically modifying the menu.
- (void)applyToMainMenu;

/// Translate an English UI string.
/// Strips Windows accelerator markers (&) from the lookup key.
/// Returns the translated string (stripped of accelerators), or `english`
/// unchanged if no translation is available.
- (NSString *)translate:(NSString *)english;

/// Retrieve a value from the <MiscStrings> section by element name.
/// e.g. @"tab-untitled-string" → @"new " (French: @"nouveau ")
/// Returns `key` unchanged if not found.
- (NSString *)miscString:(NSString *)key;

/// Whether the current language uses right-to-left layout.
@property (nonatomic, readonly) BOOL isRTL;

/// Display name of the current language as declared in the XML
/// (e.g. @"Français"), or @"English" if none is loaded.
@property (nonatomic, readonly) NSString *currentLanguageName;

/// Filename stem of the current language (e.g. @"french"), or @"english".
@property (nonatomic, readonly) NSString *currentLanguageFile;

/// Sorted list of all available language display names (from bundled and
/// user directories).  Suitable for populating a preferences popup.
+ (NSArray<NSString *> *)availableLanguageNames;

/// Map of display name → filename stem for all available languages.
/// e.g. @{ @"Français" : @"french", @"English" : @"english", … }
+ (NSDictionary<NSString *, NSString *> *)availableLanguagesMap;

/// Path of the per-user localization directory.
/// Users can drop additional XML files here to add languages.
/// ~/Library/Application Support/Notepad++/localization/
+ (NSString *)userLanguageDirectory;

/// Path of the localization directory bundled inside the app.
+ (NSString *)bundledLanguageDirectory;

@end

NS_ASSUME_NONNULL_END
