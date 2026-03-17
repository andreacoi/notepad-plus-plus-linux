#import "EditorView.h"
#import "PreferencesWindowController.h"
#import "StyleConfiguratorWindowController.h"
#import "GitHelper.h"
#import "Scintilla.h"
#import "ScintillaMessages.h"
#include "SciLexer.h"
#include <CommonCrypto/CommonDigest.h>

NSNotificationName const EditorViewCursorDidMoveNotification = @"EditorViewCursorDidMoveNotification";

// Forward-declare Lexilla's CreateLexer (statically linked)
namespace Scintilla { struct ILexer5; }
extern "C" Scintilla::ILexer5 *CreateLexer(const char *name);

/// Returns YES if the named theme belongs to the explicit "dark fold margin" list.
/// These themes get fold-margin bg = Default Style background; all others get #f2f2f2.
static BOOL foldMarginUsesEditorBg(NSString *themeName) {
    static NSSet<NSString *> *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [NSSet setWithArray:@[
            @"Bespin", @"Black board", @"Choco", @"DansLeRuSH-Dark",
            @"DarkModeDefault", @"Deep Black", @"HotFudgeSundae", @"Mono Industrial",
            @"Monokai", @"MossyLawn", @"Obsidian", @"Plastic Code Wrap",
            @"Ruby Blue", @"Solarized", @"Twilight", @"Vibrant Ink",
            @"vim Dark Blue", @"Zenburn"
        ]];
    });
    return themeName && [s containsObject:themeName];
}

/// Read the Default Style bgColor hex directly from the theme XML and return as a
/// Scintilla BGR integer.  Bypasses NSColor entirely to avoid color-space shifts.
/// Returns -1 if the theme XML or bgColor attribute is not found.
static sptr_t foldMarginBGRForTheme(NSString *themeName) {
    static NSString *const kDefault = @"Default (stylers.xml)";
    NSURL *url;
    if (!themeName || [themeName isEqualToString:kDefault]) {
        url = [[NSBundle mainBundle] URLForResource:@"stylers.model" withExtension:@"xml"];
    } else {
        url = [[NSBundle mainBundle] URLForResource:themeName
                                     withExtension:@"xml"
                                      subdirectory:@"themes"];
    }
    if (!url) return -1;
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (!data) return -1;
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:data options:0 error:nil];
    if (!doc) return -1;
    NSArray<NSXMLElement *> *nodes =
        [doc nodesForXPath:@"//GlobalStyles/WidgetStyle[@name='Default Style']" error:nil];
    NSString *bgHex = [[nodes.firstObject attributeForName:@"bgColor"] stringValue];
    if (bgHex.length < 6) return -1;
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:bgHex] scanHexInt:&rgb];
    uint8_t r = (rgb >> 16) & 0xFF;
    uint8_t g = (rgb >>  8) & 0xFF;
    uint8_t b =  rgb        & 0xFF;
    return ((sptr_t)b << 16) | ((sptr_t)g << 8) | r;  // BGR for Scintilla
}

// Language name → Lexilla lexer name
static NSDictionary<NSString *, NSString *> *languageLexerNameMap() {
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"c"          : @"cpp",
            @"cpp"        : @"cpp",
            @"objc"       : @"cpp",
            @"python"     : @"python",
            @"javascript" : @"cpp",
            @"typescript" : @"cpp",
            @"html"       : @"hypertext",
            @"xml"        : @"xml",
            @"css"        : @"css",
            @"bash"       : @"bash",
            @"ruby"       : @"ruby",
            @"swift"      : @"cpp",
            @"json"       : @"json",
            @"markdown"   : @"markdown",
            @"sql"        : @"sql",
            @"lua"        : @"lua",
            @"perl"       : @"perl",
            @"php"        : @"phpscript",
        };
    });
    return map;
}

// File extension → language name
static NSDictionary<NSString *, NSString *> *extensionLanguageMap() {
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"c"    : @"c",     @"h"    : @"c",
            @"cpp"  : @"cpp",   @"cxx"  : @"cpp",
            @"cc"   : @"cpp",   @"hpp"  : @"cpp",
            @"m"    : @"objc",  @"mm"   : @"objc",
            @"py"   : @"python",
            @"js"   : @"javascript", @"mjs"  : @"javascript",
            @"ts"   : @"typescript",
            @"html" : @"html",  @"htm"  : @"html",
            @"xml"  : @"xml",
            @"css"  : @"css",
            @"sh"   : @"bash",  @"bash" : @"bash", @"zsh" : @"bash",
            @"rb"   : @"ruby",
            @"swift": @"swift",
            @"json" : @"json",
            @"md"   : @"markdown", @"markdown": @"markdown",
            @"sql"  : @"sql",
            @"lua"  : @"lua",
            @"pl"   : @"perl",  @"pm"   : @"perl",
            @"php"  : @"php",
        };
    });
    return map;
}

// Mirrors NPP's per-buffer ID — gives each untitled tab a unique number ("new 1", "new 2" …)
static NSInteger _untitledCounter = 0;

// Map a CFStringBuiltInEncoding to NSStringEncoding (short alias for CFStringConvertEncodingToNSStringEncoding)
static inline NSStringEncoding nppEnc(CFStringEncoding cf) {
    return CFStringConvertEncodingToNSStringEncoding(cf);
}

// Files larger than this get a warning + large-file mode (no syntax, no undo).
static const NSUInteger kLargeFileThreshold = 50 * 1024 * 1024; // 50 MB

@implementation EditorView {
    BOOL    _isModified;
    NSStringEncoding _fileEncoding;
    BOOL    _hasBOM;
    BOOL    _largeFileMode;
    BOOL    _wordWrapEnabled;
    BOOL    _isRecordingMacro;
    NSMutableArray<NSDictionary *> *_macroActions;
    NSInteger _untitledIndex;   // unique number for untitled tabs (1-based)
    sptr_t    _lastBracePos;    // cached: last brace position highlighted (-1 = none)
    sptr_t    _lastMatchPos;    // cached: last matching brace position (-1 = none)

    // Begin/End Select state (per-editor)
    sptr_t _beginSelectPos;
    BOOL   _beginSelectActive;

    // File change monitoring (NSFilePresenter)
    NSURL             *_presentedItemURL;
    NSOperationQueue  *_presenterQueue;
    BOOL               _externalChangePending;
    BOOL               _monitoringMode;   // tail -f: auto-reload silently

    // Spell check
    BOOL               _spellCheckEnabled;
    NSTimer           *_spellTimer;
    NSInteger          _spellTag;

    // Git gutter state
    BOOL               _gitGutterEnabled;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _fileEncoding = NSUTF8StringEncoding;
        _currentLanguage = @"";
        _untitledIndex = ++_untitledCounter;
        _lastBracePos = INVALID_POSITION;
        _lastMatchPos = INVALID_POSITION;
        _spellTag = [NSSpellChecker uniqueSpellDocumentTag];
        [self setup];
    }
    return self;
}

- (void)setup {
    _scintillaView = [[ScintillaView alloc] initWithFrame:self.bounds];
    _scintillaView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _scintillaView.delegate = self;
    [self addSubview:_scintillaView];

    // The drag registration is on SCIContentView (the inner view), not ScintillaView itself.
    // Strip NSPasteboardTypeFileURL and NSFilenamesPboardType from it so file drops
    // bubble up to the NppDropView container which handles opening the files.
    NSView *contentView = [_scintillaView content];
    NSMutableArray *dragTypes = [contentView.registeredDraggedTypes mutableCopy];
    [dragTypes removeObject:NSPasteboardTypeFileURL];
    [dragTypes removeObject:NSFilenamesPboardType];
    [contentView unregisterDraggedTypes];
    if (dragTypes.count) [contentView registerForDraggedTypes:dragTypes];

    [self applyDefaultTheme];

    _presenterQueue = [[NSOperationQueue alloc] init];
    _presenterQueue.maxConcurrentOperationCount = 1;
    _presenterQueue.name = @"EditorView.FilePresenter";

    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(_preferencesChanged:)
               name:@"NPPPreferencesChanged" object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (_presentedItemURL) [NSFileCoordinator removeFilePresenter:self];
}

- (void)prepareForClose {
    // NSFileCoordinator holds a strong reference to registered file presenters,
    // preventing dealloc. Explicitly unregister here when a tab is permanently closed.
    if (_presentedItemURL) {
        [NSFileCoordinator removeFilePresenter:self];
        _presentedItemURL = nil;
    }
    [_spellTimer invalidate];
    _spellTimer = nil;
}


#pragma mark - Content copy

- (void)loadContentFromEditor:(EditorView *)source {
    intptr_t len = [source.scintillaView message:SCI_GETLENGTH];
    char *buf = (char *)malloc((size_t)len + 1);
    if (!buf) return;
    [source.scintillaView message:SCI_GETTEXT wParam:(uptr_t)(len + 1) lParam:(sptr_t)buf];
    [_scintillaView message:SCI_SETTEXT wParam:0 lParam:(sptr_t)buf];
    free(buf);
}

#pragma mark - File I/O

- (BOOL)loadFileAtPath:(NSString *)path error:(NSError **)error {
    // ── Large-file guard ──────────────────────────────────────────────────────
    NSUInteger fileSize = 0;
    NSDictionary *attrs = [[NSFileManager defaultManager]
                           attributesOfItemAtPath:path error:nil];
    if (attrs) fileSize = (NSUInteger)[attrs[NSFileSize] unsignedLongLongValue];

    BOOL large = (fileSize > kLargeFileThreshold);
    if (large) {
        NSString *sizeMB = [NSString stringWithFormat:@"%.0f MB",
                            fileSize / (1024.0 * 1024.0)];
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Large File Warning";
        alert.informativeText = [NSString stringWithFormat:
            @"This file is %@. Opening it will disable syntax highlighting "
            @"and undo history to keep the app responsive.\n\n"
            @"Do you want to continue?", sizeMB];
        [alert addButtonWithTitle:@"Open Anyway"];
        [alert addButtonWithTitle:@"Cancel"];
        alert.alertStyle = NSAlertStyleWarning;
        if ([alert runModal] != NSAlertFirstButtonReturn) {
            if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                                    code:NSUserCancelledError
                                                userInfo:nil];
            return NO;
        }
    }

    // Use memory-mapped I/O for large files — OS pages in only what's needed.
    NSDataReadingOptions readOpts = large ? NSDataReadingMappedIfSafe : 0;
    NSData *rawData = [NSData dataWithContentsOfFile:path
                                             options:readOpts
                                               error:error];
    if (!rawData) return NO;

    NSStringEncoding enc = NSUTF8StringEncoding;
    BOOL hasBOM = NO;
    NSData *textData = rawData;
    const uint8_t *b = (const uint8_t *)rawData.bytes;
    NSUInteger len = rawData.length;

    // BOM detection (matches NPP Utf8_16.cpp k_Boms)
    if (len >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
        enc = NSUTF8StringEncoding;
        hasBOM = YES;
        textData = [rawData subdataWithRange:NSMakeRange(3, len - 3)];
    } else if (len >= 2 && b[0] == 0xFF && b[1] == 0xFE) {
        enc = NSUTF16LittleEndianStringEncoding;
        hasBOM = YES;
        textData = [rawData subdataWithRange:NSMakeRange(2, len - 2)];
    } else if (len >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
        enc = NSUTF16BigEndianStringEncoding;
        hasBOM = YES;
        textData = [rawData subdataWithRange:NSMakeRange(2, len - 2)];
    }

    NSString *content = nil;
    if (hasBOM) {
        content = [[NSString alloc] initWithData:textData encoding:enc];
    } else {
        // Try UTF-8 first, then Windows-1252, then Latin-1
        content = [[NSString alloc] initWithData:rawData encoding:NSUTF8StringEncoding];
        if (content) {
            enc = NSUTF8StringEncoding;
        } else {
            NSStringEncoding win1252 = nppEnc(kCFStringEncodingWindowsLatin1);
            content = [[NSString alloc] initWithData:rawData encoding:win1252];
            if (content) {
                enc = win1252;
            } else {
                content = [[NSString alloc] initWithData:rawData encoding:NSISOLatin1StringEncoding];
                if (!content) {
                    if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                                            code:NSFileReadInapplicableStringEncodingError
                                                        userInfo:nil];
                    return NO;
                }
                enc = NSISOLatin1StringEncoding;
            }
        }
    }

    if (!content) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                                code:NSFileReadInapplicableStringEncodingError
                                            userInfo:nil];
        return NO;
    }

    // Update file presenter registration when path changes
    NSURL *newURL = [NSURL fileURLWithPath:path];
    if (_presentedItemURL && ![_presentedItemURL isEqual:newURL]) {
        [NSFileCoordinator removeFilePresenter:self];
        _presentedItemURL = nil;
    }

    [_scintillaView setString:content];
    _filePath = [path copy];
    _fileEncoding = enc;
    _hasBOM = hasBOM;
    _isModified = NO;
    _backupFilePath = nil; // buffer loaded from disk — no backup needed

    _largeFileMode = large;

    NSString *ext = path.pathExtension.lowercaseString;
    NSString *lang = extensionLanguageMap()[ext] ?: @"";
    if (large) {
        // Disable syntax highlighting and undo for large files to stay responsive.
        [self setLanguage:@""];
        [_scintillaView message:SCI_SETUNDOCOLLECTION wParam:0 lParam:0];
    } else {
        [self setLanguage:lang];
        // Re-enable undo in case this tab was previously in large-file mode.
        [_scintillaView message:SCI_SETUNDOCOLLECTION wParam:1 lParam:0];
    }

    [_scintillaView message:SCI_GOTOPOS wParam:0];
    [_scintillaView message:SCI_EMPTYUNDOBUFFER];
    // Tell change history that the just-loaded content IS the save baseline —
    // without this every line would show as orange immediately after file open.
    [_scintillaView message:SCI_SETSAVEPOINT];

    // Register as file presenter for external-change detection
    if (!_presentedItemURL) {
        _presentedItemURL = newURL;
        [NSFileCoordinator addFilePresenter:self];
    }
    return YES;
}

- (BOOL)saveError:(NSError **)error {
    if (!_filePath) return NO;
    return [self saveToPath:_filePath error:error];
}

- (BOOL)saveToPath:(NSString *)path error:(NSError **)error {
    NSString *content = _scintillaView.string;

    // Build the byte payload (BOM + encoded content).
    NSMutableData *out = [NSMutableData data];
    if (_hasBOM) {
        if (_fileEncoding == NSUTF8StringEncoding) {
            const uint8_t bom[] = {0xEF, 0xBB, 0xBF};
            [out appendBytes:bom length:3];
        } else if (_fileEncoding == NSUTF16BigEndianStringEncoding) {
            const uint8_t bom[] = {0xFE, 0xFF};
            [out appendBytes:bom length:2];
        } else if (_fileEncoding == NSUTF16LittleEndianStringEncoding) {
            const uint8_t bom[] = {0xFF, 0xFE};
            [out appendBytes:bom length:2];
        }
    }
    NSData *body = [content dataUsingEncoding:_fileEncoding allowLossyConversion:YES];
    if (!body) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                               code:NSFileWriteInapplicableStringEncodingError
                                           userInfo:nil];
        return NO;
    }
    [out appendData:body];

    // Use NSFileCoordinator so the NSFilePresenter infrastructure knows this write
    // is our own and does NOT call presentedItemDidChange on us (per Apple QA1809).
    __block BOOL ok = NO;
    __block NSError *writeError = nil;
    NSError *coordError = nil;

    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:self];
    NSURL *url = [NSURL fileURLWithPath:path];
    [coordinator coordinateWritingItemAtURL:url
                                    options:NSFileCoordinatorWritingForReplacing
                                      error:&coordError
                                 byAccessor:^(NSURL *newURL) {
        ok = [out writeToURL:newURL options:NSDataWritingAtomic error:&writeError];
    }];

    if (!ok) {
        if (error) *error = writeError ?: coordError;
        return NO;
    }

    _filePath = [path copy];
    _isModified = NO;
    [_scintillaView message:SCI_SETSAVEPOINT];
    if (_backupFilePath) {
        [[NSFileManager defaultManager] removeItemAtPath:_backupFilePath error:nil];
        _backupFilePath = nil;
    }
    [self updateGitDiffMarkers];
    return YES;
}

/// Custom setter: re-register file presenter when path changes.
- (void)setFilePath:(NSString *)filePath {
    if ([_filePath isEqualToString:filePath]) return;
    if (_presentedItemURL) {
        [NSFileCoordinator removeFilePresenter:self];
        _presentedItemURL = nil;
    }
    _filePath = [filePath copy];
    if (_filePath) {
        _presentedItemURL = [NSURL fileURLWithPath:_filePath];
        [NSFileCoordinator addFilePresenter:self];
    }
}

- (NSInteger)untitledIndex { return _untitledIndex; }

/// Restore the untitled index from a saved session so the tab name is preserved.
- (void)restoreUntitledIndex:(NSInteger)index {
    if (index > 0) {
        _untitledIndex = index;
        // Keep the global counter ahead of any restored index to avoid future collisions
        if (index >= _untitledCounter) _untitledCounter = index;
    }
}

- (void)markAsModified {
    _isModified = YES;
}

/// Write content to the backup directory.
/// Mirrors NPP Buffer.cpp: creates ONE timestamped file per buffer on first backup,
/// then overwrites that same file in-place on every subsequent backup cycle.
- (nullable NSString *)saveBackupToDirectory:(NSString *)dir {
    // If we already have a backup file, overwrite it in-place (NPP behaviour)
    if (_backupFilePath) {
        NSError *err;
        if ([_scintillaView.string writeToFile:_backupFilePath atomically:YES
                                      encoding:_fileEncoding error:&err]) {
            return _backupFilePath;
        }
        // Backup file was deleted externally — fall through and create a new one
        _backupFilePath = nil;
    }

    // First backup for this buffer — create with timestamp (created once, reused forever)
    // Use the same name as displayName so each tab gets a unique backup file
    NSString *base = _filePath ? _filePath.lastPathComponent
                               : [NSString stringWithFormat:@"new %ld", (long)_untitledIndex];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd_HHmmss";
    NSString *name = [NSString stringWithFormat:@"%@@%@", base,
                      [fmt stringFromDate:[NSDate date]]];
    NSString *dest = [dir stringByAppendingPathComponent:name];
    NSError *err;
    if ([_scintillaView.string writeToFile:dest atomically:YES
                                  encoding:_fileEncoding error:&err]) {
        _backupFilePath = [dest copy];
        return dest;
    }
    return nil;
}

#pragma mark - NSFilePresenter

- (NSURL *)presentedItemURL { return _presentedItemURL; }
- (NSOperationQueue *)presentedItemOperationQueue { return _presenterQueue; }

- (BOOL)monitoringMode { return _monitoringMode; }
- (void)setMonitoringMode:(BOOL)v { _monitoringMode = v; }

- (void)presentedItemDidChange {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_externalChangePending) return;
        if (!self->_filePath) return;
        self->_externalChangePending = YES;

        if (self->_monitoringMode) {
            // Silent auto-reload in monitoring mode (tail -f behaviour)
            NSError *err;
            [self loadFileAtPath:self->_filePath error:&err];
            self->_externalChangePending = NO;
            return;
        }

        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = [NSString stringWithFormat:@"\"%@\" changed on disk",
                             self->_filePath.lastPathComponent];
        if (!self->_isModified) {
            alert.informativeText = @"This file was modified by another program.";
            [alert addButtonWithTitle:@"Reload"];
            [alert addButtonWithTitle:@"Ignore"];
        } else {
            alert.informativeText = @"This file was modified by another program. "
                                    @"Reloading will discard your unsaved changes.";
            [alert addButtonWithTitle:@"Reload"];
            [alert addButtonWithTitle:@"Keep My Version"];
        }

        if ([alert runModal] == NSAlertFirstButtonReturn) {
            NSError *err;
            [self loadFileAtPath:self->_filePath error:&err];
        }
        self->_externalChangePending = NO;
    });
}

#pragma mark - Language / Lexer

- (void)setLanguage:(NSString *)languageName {
    _currentLanguage = [languageName copy];

    if (!languageName.length) {
        // Plain text — null lexer
        [_scintillaView message:(unsigned int)Scintilla::Message::SetILexer wParam:0 lParam:0];
        return;
    }

    NSString *lexerName = languageLexerNameMap()[languageName.lowercaseString];
    if (!lexerName) return;

    Scintilla::ILexer5 *lexer = CreateLexer(lexerName.UTF8String);
    if (lexer) {
        [_scintillaView message:(unsigned int)Scintilla::Message::SetILexer
                         wParam:0
                         lParam:(sptr_t)lexer];
    }

    // ── Folding — must be set AFTER the lexer is installed ───────────────────
    // The "fold" property is per-lexer; setting it before SetILexer has no effect.
    ScintillaView *sci = _scintillaView;
    [sci message:SCI_SETPROPERTY wParam:(uptr_t)"fold"         lParam:(sptr_t)"1"];
    [sci message:SCI_SETPROPERTY wParam:(uptr_t)"fold.compact" lParam:(sptr_t)"0"];

    NSString *lang = languageName.lowercaseString;
    if ([lang isEqualToString:@"c"]   || [lang isEqualToString:@"cpp"] ||
        [lang isEqualToString:@"objc"]|| [lang isEqualToString:@"javascript"] ||
        [lang isEqualToString:@"typescript"] || [lang isEqualToString:@"swift"]) {
        [sci message:SCI_SETPROPERTY wParam:(uptr_t)"fold.comment"      lParam:(sptr_t)"1"];
        [sci message:SCI_SETPROPERTY wParam:(uptr_t)"fold.preprocessor" lParam:(sptr_t)"1"];
    } else if ([lang isEqualToString:@"html"] || [lang isEqualToString:@"xml"]) {
        [sci message:SCI_SETPROPERTY wParam:(uptr_t)"fold.html"               lParam:(sptr_t)"1"];
        [sci message:SCI_SETPROPERTY wParam:(uptr_t)"fold.html.preprocessor"  lParam:(sptr_t)"1"];
    } else if ([lang isEqualToString:@"python"]) {
        [sci message:SCI_SETPROPERTY wParam:(uptr_t)"fold.quotes.python" lParam:(sptr_t)"1"];
    } else if ([lang isEqualToString:@"lua"]) {
        [sci message:SCI_SETPROPERTY wParam:(uptr_t)"fold.comment.lua" lParam:(sptr_t)"1"];
    } else if ([lang isEqualToString:@"sql"]) {
        [sci message:SCI_SETPROPERTY wParam:(uptr_t)"fold.comment" lParam:(sptr_t)"1"];
        [sci message:SCI_SETPROPERTY wParam:(uptr_t)"fold.sql.only.begin" lParam:(sptr_t)"1"];
    }

    [self applyKeywords:languageName];
    [self applyLexerColors:languageName];

    // Force re-lex so fold markers appear immediately on already-loaded content
    sptr_t docLen = [sci message:SCI_GETLENGTH];
    if (docLen > 0) [sci message:SCI_COLOURISE wParam:0 lParam:docLen];
}

- (NSString *)displayName {
    if (_filePath) return _filePath.lastPathComponent;
    // Mirror NPP: "new 1", "new 2", … (unique per buffer, like NPP's buffer IDs)
    return [NSString stringWithFormat:@"new %ld", (long)_untitledIndex];
}

#pragma mark - Cursor Info

- (NSInteger)cursorLine {
    sptr_t pos = [_scintillaView message:SCI_GETCURRENTPOS];
    return [_scintillaView message:SCI_LINEFROMPOSITION wParam:(uptr_t)pos] + 1;
}

- (NSInteger)cursorColumn {
    sptr_t pos = [_scintillaView message:SCI_GETCURRENTPOS];
    return [_scintillaView message:SCI_GETCOLUMN wParam:(uptr_t)pos] + 1;
}

- (NSInteger)lineCount {
    return [_scintillaView message:SCI_GETLINECOUNT];
}

- (BOOL)hasBOM { return _hasBOM; }

- (NSString *)encodingName {
    // Base name lookup by NSStringEncoding value
    static NSDictionary<NSNumber *, NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @{
            @(NSUTF8StringEncoding):                                                   @"UTF-8",
            @(NSISOLatin1StringEncoding):                                              @"Latin-1",
            @(NSUTF16BigEndianStringEncoding):                                         @"UTF-16 BE",
            @(NSUTF16LittleEndianStringEncoding):                                      @"UTF-16 LE",
            @(NSUTF16StringEncoding):                                                  @"UTF-16",
            @(nppEnc(kCFStringEncodingWindowsLatin1)):                                 @"Windows-1252",
            @(nppEnc(kCFStringEncodingISOLatin9)):                                     @"Latin-9",
            @(nppEnc(kCFStringEncodingWindowsLatin2)):                          @"Windows-1250",
            @(nppEnc(kCFStringEncodingWindowsCyrillic)):                               @"Windows-1251",
            @(nppEnc(kCFStringEncodingWindowsGreek)):                                  @"Windows-1253",
            @(nppEnc(kCFStringEncodingWindowsBalticRim)):                              @"Windows-1257",
            @(nppEnc(kCFStringEncodingWindowsLatin5)):                                 @"Windows-1254",
            @(nppEnc(kCFStringEncodingBig5)):                                          @"Big5",
            @(nppEnc(kCFStringEncodingGB_2312_80)):                                    @"GB2312",
            @(nppEnc(kCFStringEncodingShiftJIS)):                                      @"Shift-JIS",
            @(nppEnc(kCFStringEncodingEUC_KR)):                                        @"EUC-KR",
        };
    });
    NSString *base = names[@(_fileEncoding)] ?: @"UTF-8";
    if (_hasBOM) base = [base stringByAppendingString:@" BOM"];
    return base;
}

- (void)setFileEncoding:(NSStringEncoding)enc hasBOM:(BOOL)bom {
    _fileEncoding = enc;
    _hasBOM = bom;
    _isModified = YES;
}

- (NSString *)eolName {
    sptr_t mode = [_scintillaView message:SCI_GETEOLMODE];
    switch (mode) {
        case SC_EOL_CRLF: return @"CRLF";
        case SC_EOL_CR:   return @"CR";
        default:          return @"LF";
    }
}

#pragma mark - Find / Replace

- (BOOL)findNext:(NSString *)text matchCase:(BOOL)mc wholeWord:(BOOL)ww wrap:(BOOL)wrap {
    return [_scintillaView findAndHighlightText:text
                                      matchCase:mc
                                      wholeWord:ww
                                       scrollTo:YES
                                           wrap:wrap];
}

- (BOOL)findPrev:(NSString *)text matchCase:(BOOL)mc wholeWord:(BOOL)ww wrap:(BOOL)wrap {
    return [_scintillaView findAndHighlightText:text
                                      matchCase:mc
                                      wholeWord:ww
                                       scrollTo:YES
                                           wrap:wrap
                                      backwards:YES];
}

- (BOOL)replace:(NSString *)text with:(NSString *)replacement
      matchCase:(BOOL)mc wholeWord:(BOOL)ww {
    // If current selection already matches, replace it, then find next.
    NSString *sel = _scintillaView.selectedString;
    BOOL selMatches = mc ? [sel isEqualToString:text]
                         : [sel caseInsensitiveCompare:text] == NSOrderedSame;
    if (selMatches) {
        [_scintillaView message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)replacement.UTF8String];
    }
    // Find the next occurrence
    return [_scintillaView findAndHighlightText:text
                                      matchCase:mc
                                      wholeWord:ww
                                       scrollTo:YES
                                           wrap:YES];
}

- (NSInteger)replaceAll:(NSString *)text with:(NSString *)replacement
             matchCase:(BOOL)mc wholeWord:(BOOL)ww {
    return (NSInteger)[_scintillaView findAndReplaceText:text
                                                  byText:replacement
                                               matchCase:mc
                                               wholeWord:ww
                                                   doAll:YES];
}

#pragma mark - Theme

// Convert NSColor to Scintilla's BGR integer format (r | g<<8 | b<<16)
static sptr_t sciColor(NSColor *c) {
    c = [c colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
    if (!c) return 0;
    long r = (long)([c redComponent]   * 255);
    long g = (long)([c greenComponent] * 255);
    long b = (long)([c blueComponent]  * 255);
    return (b << 16) | (g << 8) | r;
}

// Helper: parse "#RRGGBB" hex string to NSColor
static NSColor *nppColorFromHex(NSString *hex) {
    if ([hex hasPrefix:@"#"]) hex = [hex substringFromIndex:1];
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:hex] scanHexInt:&rgb];
    return [NSColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >>  8) & 0xFF) / 255.0
                            blue:( rgb        & 0xFF) / 255.0
                           alpha:1.0];
}

- (void)applyThemeColors {
    NPPStyleStore *store = [NPPStyleStore sharedStore];
    NSString *fontName = store.globalFontName;
    NSInteger fontSize = store.globalFontSize;

    ScintillaView *sci = _scintillaView;
    NSColor *fg = store.globalFg;
    NSColor *bg = store.globalBg;

    const char *fontNameUTF8 = fontName.UTF8String;
    [sci message:SCI_STYLESETFONT wParam:STYLE_DEFAULT lParam:(sptr_t)fontNameUTF8];
    [sci message:SCI_STYLESETSIZEFRACTIONAL wParam:STYLE_DEFAULT lParam:(sptr_t)(fontSize * 100)];
    [sci setColorProperty:SCI_STYLESETFORE parameter:STYLE_DEFAULT value:fg];
    [sci setColorProperty:SCI_STYLESETBACK parameter:STYLE_DEFAULT value:bg];

    // Propagate defaults to all styles, then re-apply language-specific colors
    [sci message:SCI_STYLECLEARALL];

    // Derive line-number colors from bg (slightly tinted)
    CGFloat bgBrightness = bg.brightnessComponent;
    NSColor *lnFg = bgBrightness > 0.5
        ? [NSColor colorWithWhite:0.5 alpha:1.0]
        : [NSColor colorWithWhite:0.6 alpha:1.0];
    NSColor *lnBg = bgBrightness > 0.5
        ? [NSColor colorWithWhite:0.95 alpha:1.0]
        : [bg colorWithAlphaComponent:1.0]; // same as editor bg in dark themes
    [sci setColorProperty:SCI_STYLESETFORE parameter:STYLE_LINENUMBER value:lnFg];
    [sci setColorProperty:SCI_STYLESETBACK parameter:STYLE_LINENUMBER value:lnBg];

    // Caret
    [sci message:SCI_SETCARETFORE wParam:sciColor(fg)];

    // Caret-line highlight: subtle tint toward the opposite of bg
    NSColor *caretLineBg = bgBrightness > 0.5
        ? [NSColor colorWithRed:0.97 green:0.97 blue:1.0 alpha:1.0]
        : [NSColor colorWithWhite:bgBrightness + 0.08 alpha:1.0];
    [sci message:SCI_SETCARETLINEBACK wParam:sciColor(caretLineBg)];

    // Fold margin column background:
    //   • Listed dark themes → Default Style bg read directly from XML (exact hex, no color-space shift)
    //   • All other themes   → #f2f2f2
    NSString *activeThem = [[NPPStyleStore sharedStore] activeThemeName];
    BOOL darkFold = foldMarginUsesEditorBg(activeThem);
    sptr_t foldBGR = darkFold ? foldMarginBGRForTheme(activeThem) : -1;
    sptr_t foldMarginBGR2 = (foldBGR >= 0) ? foldBGR : 0xF2F2F2;
    [sci message:SCI_SETFOLDMARGINCOLOUR   wParam:1 lParam:foldMarginBGR2];
    [sci message:SCI_SETFOLDMARGINHICOLOUR wParam:1 lParam:foldMarginBGR2];
    NSColor *foldBack2 = darkFold
        ? [NSColor colorWithWhite:bgBrightness + 0.22 alpha:1.0]
        : [NSColor colorWithWhite:0.82 alpha:1.0];
    NSColor *foldFore2 = darkFold
        ? [NSColor colorWithWhite:0.80 alpha:1.0]
        : [NSColor blackColor];
    for (int mn = SC_MARKNUM_FOLDEREND; mn <= SC_MARKNUM_FOLDEROPEN; mn++) {
        [sci setColorProperty:SCI_MARKERSETFORE parameter:mn value:foldFore2];
        [sci setColorProperty:SCI_MARKERSETBACK parameter:mn value:foldBack2];
    }

    // Re-apply language colors with the new theme palette
    if (_currentLanguage.length) [self applyLexerColors:_currentLanguage];
}

- (void)applyDefaultTheme {
    ScintillaView *sci = _scintillaView;

    // 1. Set ALL STYLE_DEFAULT properties first (reads from style store)
    NPPStyleStore *storeD = [NPPStyleStore sharedStore];
    NSString *fontName = storeD.globalFontName;
    NSInteger fontSize = storeD.globalFontSize;
    [sci message:SCI_STYLESETFONT wParam:STYLE_DEFAULT lParam:(sptr_t)fontName.UTF8String];
    [sci message:SCI_STYLESETSIZEFRACTIONAL wParam:STYLE_DEFAULT lParam:(sptr_t)(fontSize * 100)];
    NSColor *fg = storeD.globalFg;
    NSColor *bg = storeD.globalBg;
    [sci setColorProperty:SCI_STYLESETFORE parameter:STYLE_DEFAULT value:fg];
    [sci setColorProperty:SCI_STYLESETBACK parameter:STYLE_DEFAULT value:bg];

    // 2. Propagate STYLE_DEFAULT to ALL lexer styles (must come AFTER colors are set)
    [sci message:SCI_STYLECLEARALL];

    // Line numbers margin (type must be set even if width comes from prefs)
    [sci message:SCI_SETMARGINTYPEN wParam:0 lParam:SC_MARGIN_NUMBER];
    CGFloat bgBrightness = bg.brightnessComponent;
    [sci setColorProperty:SCI_STYLESETFORE parameter:STYLE_LINENUMBER
                    value:(bgBrightness > 0.5 ? [NSColor colorWithWhite:0.5 alpha:1.0]
                                               : [NSColor colorWithWhite:0.6 alpha:1.0])];
    [sci setColorProperty:SCI_STYLESETBACK parameter:STYLE_LINENUMBER
                    value:(bgBrightness > 0.5 ? [NSColor colorWithWhite:0.95 alpha:1.0] : bg)];

    // Caret: thin 1-pixel vertical line
    [sci message:SCI_SETCARETWIDTH wParam:1];
    [sci message:SCI_SETCARETFORE wParam:sciColor(fg)];

    // Current-line highlight background (visibility controlled by prefs)
    NSColor *caretLineBg = bgBrightness > 0.5
        ? [NSColor colorWithRed:0.97 green:0.97 blue:1.0 alpha:1.0]
        : [NSColor colorWithWhite:bgBrightness + 0.08 alpha:1.0];
    [sci message:SCI_SETCARETLINEBACK wParam:sciColor(caretLineBg)];

    // Indentation guides / EOL mode (not user-configurable yet)
    [sci message:SCI_SETINDENTATIONGUIDES wParam:SC_IV_LOOKBOTH];
    [sci message:SCI_SETEOLMODE wParam:SC_EOL_LF];

    // Brace matching: red foreground, light-red background (matches NPP's red bracket highlight)
    [sci setColorProperty:SCI_STYLESETFORE parameter:STYLE_BRACELIGHT
                    value:[NSColor colorWithRed:0.80 green:0.0 blue:0.0 alpha:1.0]];
    [sci setColorProperty:SCI_STYLESETBACK parameter:STYLE_BRACELIGHT
                    value:[NSColor colorWithRed:1.0 green:0.87 blue:0.87 alpha:1.0]];
    [sci message:SCI_STYLESETBOLD wParam:STYLE_BRACELIGHT lParam:1];
    [sci setColorProperty:SCI_STYLESETFORE parameter:STYLE_BRACEBAD
                    value:[NSColor colorWithRed:0.75 green:0.0 blue:0.0 alpha:1.0]];

    // ── Multiple selections & column/rectangular mode ────────────────────────
    // Ctrl+click adds a caret; Alt+drag creates a column (rectangular) selection.
    [sci message:SCI_SETMULTIPLESELECTION         wParam:1];
    [sci message:SCI_SETADDITIONALSELECTIONTYPING wParam:1];
    [sci message:SCI_SETMULTIPASTE                wParam:SC_MULTIPASTE_EACH];
    [sci message:SCI_SETRECTANGULARSELECTIONMODIFIER wParam:SCMOD_ALT];

    // ── Autocomplete settings ────────────────────────────────────────────────
    [sci message:SCI_AUTOCSETIGNORECASE    wParam:1]; // case-insensitive match
    [sci message:SCI_AUTOCSETDROPRESTOFWORD wParam:0];
    [sci message:SCI_AUTOCSETMAXHEIGHT     wParam:10];
    [sci message:SCI_AUTOCSETMAXWIDTH      wParam:40];

    // ── Change-history bar (margin 2, 2 px) ──────────────────────────────────
    // When SC_CHANGE_HISTORY_MARKERS is enabled Scintilla auto-assigns default
    // marker styles to markers 21-24.  The default for HISTORY_SAVED (22) is
    // SC_MARK_BACKGROUND which paints the ENTIRE LINE green — not what we want.
    // Override ALL four history markers first: three → SC_MARK_EMPTY (invisible),
    // one (MODIFIED, 23) → SC_MARK_LEFTRECT in orange.
    [sci message:SCI_SETCHANGEHISTORY
           wParam:SC_CHANGE_HISTORY_ENABLED | SC_CHANGE_HISTORY_MARKERS];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_HISTORY_REVERTED_TO_ORIGIN   lParam:SC_MARK_EMPTY];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_HISTORY_SAVED                lParam:SC_MARK_EMPTY];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_HISTORY_REVERTED_TO_MODIFIED lParam:SC_MARK_EMPTY];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_HISTORY_MODIFIED             lParam:SC_MARK_LEFTRECT];
    [sci setColorProperty:SCI_MARKERSETBACK parameter:SC_MARKNUM_HISTORY_MODIFIED
                    value:[NSColor colorWithRed:1.0 green:0.50 blue:0.0 alpha:1.0]];
    [sci message:SCI_SETMARGINTYPEN      wParam:2 lParam:SC_MARGIN_SYMBOL];
    [sci message:SCI_SETMARGINMASKN      wParam:2 lParam:(1 << SC_MARKNUM_HISTORY_MODIFIED)];
    [sci message:SCI_SETMARGINWIDTHN     wParam:2 lParam:2];
    [sci message:SCI_SETMARGINSENSITIVEN wParam:2 lParam:0];

    // ── Code folding (margin 3) ───────────────────────────────────────────────
    [sci message:SCI_SETMARGINTYPEN      wParam:3 lParam:SC_MARGIN_SYMBOL];
    [sci message:SCI_SETMARGINMASKN      wParam:3 lParam:(sptr_t)SC_MASK_FOLDERS];
    [sci message:SCI_SETMARGINWIDTHN     wParam:3 lParam:12];
    [sci message:SCI_SETMARGINSENSITIVEN wParam:3 lParam:1];
    // Box-tree style (NPP default): ⊟ / ⊞ with connecting lines
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDER        lParam:SC_MARK_BOXPLUS];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDEROPEN    lParam:SC_MARK_BOXMINUS];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDEREND     lParam:SC_MARK_BOXPLUSCONNECTED];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDEROPENMID lParam:SC_MARK_BOXMINUSCONNECTED];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDERMIDTAIL lParam:SC_MARK_TCORNERCURVE];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDERTAIL    lParam:SC_MARK_LCORNERCURVE];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDERSUB     lParam:SC_MARK_VLINE];
    // Fold margin column background:
    //   • Listed dark themes → Default Style bg read directly from XML (exact hex, no color-space shift)
    //   • All other themes   → #f2f2f2
    NSString *activeThm = [[NPPStyleStore sharedStore] activeThemeName];
    BOOL darkFold = foldMarginUsesEditorBg(activeThm);
    sptr_t foldBGR = darkFold ? foldMarginBGRForTheme(activeThm) : -1;
    sptr_t foldMarginBGR = (foldBGR >= 0) ? foldBGR : 0xF2F2F2;
    [sci message:SCI_SETFOLDMARGINCOLOUR   wParam:1 lParam:foldMarginBGR];
    [sci message:SCI_SETFOLDMARGINHICOLOUR wParam:1 lParam:foldMarginBGR];
    // Marker (+/−) colours: adapt to the margin background
    NSColor *foldBack = darkFold
        ? [NSColor colorWithWhite:bgBrightness + 0.22 alpha:1.0]
        : [NSColor colorWithWhite:0.82 alpha:1.0];
    NSColor *foldFore = darkFold
        ? [NSColor colorWithWhite:0.80 alpha:1.0]
        : [NSColor blackColor];
    NSColor *foldRed  = [NSColor colorWithRed:0.80 green:0.0 blue:0.0 alpha:1.0];
    for (int mn = SC_MARKNUM_FOLDEREND; mn <= SC_MARKNUM_FOLDEROPEN; mn++) {
        [sci setColorProperty:SCI_MARKERSETFORE          parameter:mn value:foldFore];
        [sci setColorProperty:SCI_MARKERSETBACK          parameter:mn value:foldBack];
        [sci setColorProperty:SCI_MARKERSETBACKSELECTED  parameter:mn value:foldRed];
    }
    // Enable fold-block highlighting: fold markers in the enclosing block turn red.
    [sci message:SCI_MARKERENABLEHIGHLIGHT wParam:1];
    [sci message:SCI_SETAUTOMATICFOLD
           wParam:SC_AUTOMATICFOLD_SHOW|SC_AUTOMATICFOLD_CLICK|SC_AUTOMATICFOLD_CHANGE];

    // ── Bookmark margin (margin 1) ───────────────────────────────────────────
    [sci message:SCI_SETMARGINTYPEN      wParam:1 lParam:SC_MARGIN_SYMBOL];
    [sci message:SCI_SETMARGINMASKN      wParam:1 lParam:(1 << kBookmarkMarker)];
    [sci message:SCI_SETMARGINWIDTHN     wParam:1 lParam:14];
    [sci message:SCI_SETMARGINSENSITIVEN wParam:1 lParam:1];
    [sci message:SCI_MARKERDEFINE wParam:kBookmarkMarker lParam:SC_MARK_BOOKMARK];
    [sci setColorProperty:SCI_MARKERSETFORE parameter:kBookmarkMarker value:[NSColor whiteColor]];
    [sci setColorProperty:SCI_MARKERSETBACK parameter:kBookmarkMarker
                    value:[NSColor colorWithRed:0.2 green:0.5 blue:1.0 alpha:1]];

    // ── Smart highlight indicator (indicator 8) ──────────────────────────────
    [sci message:SCI_INDICSETSTYLE wParam:kHighlightIndicator lParam:INDIC_ROUNDBOX];
    [sci message:SCI_INDICSETFORE  wParam:kHighlightIndicator
           lParam:sciColor([NSColor colorWithRed:1.0 green:0.85 blue:0.0 alpha:1])];
    [sci message:SCI_INDICSETALPHA wParam:kHighlightIndicator lParam:80];

    // ── Mark-style indicators (indicators 9-13, styles 1-5) ──────────────────
    for (int i = 0; i < 5; i++) {
        [sci message:SCI_INDICSETSTYLE wParam:(uptr_t)kMarkInds[i] lParam:INDIC_ROUNDBOX];
        [sci message:SCI_INDICSETFORE  wParam:(uptr_t)kMarkInds[i] lParam:kMarkColors[i]];
        [sci message:SCI_INDICSETALPHA wParam:(uptr_t)kMarkInds[i] lParam:90];
        [sci message:SCI_INDICSETUNDER wParam:(uptr_t)kMarkInds[i] lParam:1]; // draw under text
    }

    // ── Spell-check indicator (slot 17, INDIC_SQUIGGLE, red) ─────────────────
    [sci message:SCI_INDICSETSTYLE wParam:kSpellIndicator lParam:INDIC_SQUIGGLE];
    [sci message:SCI_INDICSETFORE  wParam:kSpellIndicator lParam:0x0000FF]; // red (BGR)

    // ── Git gutter markers (margin 4, 4px, slots 6-8) ────────────────────────
    [sci message:SCI_MARKERDEFINE  wParam:kGitMarkerAdded    lParam:SC_MARK_LEFTRECT];
    [sci message:SCI_MARKERSETBACK wParam:kGitMarkerAdded    lParam:0x44CC2E]; // green BGR
    [sci message:SCI_MARKERDEFINE  wParam:kGitMarkerModified lParam:SC_MARK_LEFTRECT];
    [sci message:SCI_MARKERSETBACK wParam:kGitMarkerModified lParam:0x12C3F3]; // orange BGR
    [sci message:SCI_MARKERDEFINE  wParam:kGitMarkerDeleted  lParam:SC_MARK_ARROWDOWN];
    [sci message:SCI_MARKERSETBACK wParam:kGitMarkerDeleted  lParam:0x3C74E7]; // red BGR
    [sci message:SCI_SETMARGINTYPEN  wParam:kGitGutterMargin lParam:SC_MARGIN_SYMBOL];
    [sci message:SCI_SETMARGINMASKN  wParam:kGitGutterMargin
           lParam:(1 << kGitMarkerAdded) | (1 << kGitMarkerModified) | (1 << kGitMarkerDeleted)];
    [sci message:SCI_SETMARGINWIDTHN wParam:kGitGutterMargin lParam:4];
    [sci message:SCI_SETMARGINSENSITIVEN wParam:kGitGutterMargin lParam:0];

    // Apply user preferences (tab width, line numbers, wrap, etc.)
    [self applyPreferencesFromDefaults];
}

#pragma mark - Preferences

- (void)applyPreferencesFromDefaults {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    ScintillaView *sci = _scintillaView;

    NSInteger tabWidth = [ud integerForKey:kPrefTabWidth];
    if (tabWidth < 1) tabWidth = 4;
    [sci message:SCI_SETTABWIDTH wParam:(uptr_t)tabWidth];

    BOOL useTabs = [ud boolForKey:kPrefUseTabs];
    [sci message:SCI_SETUSETABS wParam:useTabs ? 1 : 0];

    BOOL showLineNumbers = [ud boolForKey:kPrefShowLineNumbers];
    [sci message:SCI_SETMARGINWIDTHN wParam:0 lParam:showLineNumbers ? 44 : 0];

    BOOL wordWrap = [ud boolForKey:kPrefWordWrap];
    [sci message:SCI_SETWRAPMODE wParam:wordWrap ? SC_WRAP_WORD : SC_WRAP_NONE];
    _wordWrapEnabled = wordWrap;

    BOOL hlLine = [ud boolForKey:kPrefHighlightCurrentLine];
    [sci message:SCI_SETCARETLINEVISIBLE wParam:hlLine ? 1 : 0];

    NSInteger zoomLevel = [ud integerForKey:kPrefZoomLevel];
    [sci message:SCI_SETZOOM wParam:(uptr_t)zoomLevel];
}

- (void)_preferencesChanged:(NSNotification *)note {
    [self applyPreferencesFromDefaults];
    // Re-apply theme colors if the notification carries a theme-change flag
    NSNumber *themeChanged = note.userInfo[@"themeChanged"];
    if (themeChanged.boolValue) [self applyThemeColors];
}

#pragma mark - Keywords

- (void)applyKeywords:(NSString *)lang {
    ScintillaView *sci = _scintillaView;
    lang = lang.lowercaseString;

    if ([@[@"c", @"cpp", @"objc", @"swift", @"typescript"] containsObject:lang]) {
        lang = @"cpp"; // all use the cpp lexer keyword set
    }

    if ([lang isEqualToString:@"cpp"]) {
        const char *kw = "alignas alignof and and_eq asm auto bitand bitor bool break case catch char "
            "char8_t char16_t char32_t class compl concept const consteval constexpr constinit "
            "const_cast continue co_await co_return co_yield decltype default delete do double "
            "dynamic_cast else enum explicit export extern false float for friend goto if inline "
            "int long mutable namespace new noexcept not not_eq nullptr operator or or_eq private "
            "protected public register reinterpret_cast requires return short signed sizeof static "
            "static_assert static_cast struct switch template this thread_local throw true try "
            "typedef typeid typename union unsigned using virtual void volatile wchar_t while "
            "xor xor_eq";
        [sci message:SCI_SETKEYWORDS wParam:0 lParam:(sptr_t)kw];
    } else if ([lang isEqualToString:@"python"]) {
        const char *kw = "False None True and as assert async await break class continue def del "
            "elif else except finally for from global if import in is lambda nonlocal not or "
            "pass raise return try while with yield";
        [sci message:SCI_SETKEYWORDS wParam:0 lParam:(sptr_t)kw];
    } else if ([lang isEqualToString:@"javascript"]) {
        const char *kw = "async await break case catch class const continue debugger default "
            "delete do else export extends false finally for from function if import in "
            "instanceof let new null of return static super switch this throw true try typeof "
            "undefined var void while with yield";
        [sci message:SCI_SETKEYWORDS wParam:0 lParam:(sptr_t)kw];
    } else if ([lang isEqualToString:@"sql"]) {
        const char *kw = "add all alter and any as asc authorization backup begin between by "
            "cascade case check close clustered coalesce column commit compute constraint "
            "contains containstable continue convert create cross current current_date "
            "current_time cursor database dbcc deallocate declare default delete deny desc "
            "distinct distributed double drop dump else end errlvl escape except exec execute "
            "exists exit external fetch file fillfactor for foreign freetext freetexttable "
            "from full function goto grant group having holdlock identity identitycol "
            "identity_insert if in index inner insert intersect into is join key kill left "
            "like lineno load merge national nocheck nonclustered not null nullif of off "
            "offsets on open opendatasource openquery openrowset openxml option or order outer "
            "over percent pivot plan precision primary print proc procedure public raiserror "
            "read readtext reconfigure references replication restore restrict return revert "
            "revoke right rollback rowcount rowguidcol rule save schema securityaudit select "
            "semantickeyphrasetable semanticsimilaritydetailstable semanticsimilaritytable "
            "session_user set setuser shutdown some statistics system_user table tablesample "
            "textsize then to top tran transaction trigger truncate try_convert tsequal "
            "union unique unpivot update updatetext use user values varying view waitfor when "
            "where while with within group writetext";
        [sci message:SCI_SETKEYWORDS wParam:0 lParam:(sptr_t)kw];
    }
}

static const int kBookmarkMarker      = 20;
static const int kHighlightIndicator  =  8; // INDICATOR_CONTAINER = 8, avoids lexer indicators 0-7

// 5 mark-style indicators (9-13): Scintilla BGR colors (b<<16|g<<8|r)
static const int     kMarkInds[5]    = { 9, 10, 11, 12, 13 };
static const sptr_t  kMarkColors[5]  = {
    0xFFFF00, // style 1: cyan   (R=0,   G=255, B=255)
    0x00FFFF, // style 2: yellow (R=255, G=255, B=0  )
    0x00C800, // style 3: green  (R=0,   G=200, B=0  )
    0x0078FF, // style 4: orange (R=255, G=120, B=0  )
    0xFF64C8, // style 5: violet (R=200, G=100, B=255)
};

// Scintilla indicator-range messages not in the main header
static const unsigned int kSCI_IndicatorNext     = 2432;
static const unsigned int kSCI_IndicatorPrevious = 2433;
static const unsigned int kSCI_IndicatorEnd      = 2552;

// Spell-check indicator (slot 17, INDIC_SQUIGGLE red)
static const int kSpellIndicator = 17;

// Git gutter marker slots — must be 0-19 (0-24 are user-definable, but 21-24
// are used by change-history and 25-31 are reserved for fold markers).
static const int kGitMarkerAdded    = 6;
static const int kGitMarkerModified = 7;
static const int kGitMarkerDeleted  = 8;
static const int kGitGutterMargin   = 4;  // margin index for git gutter

#pragma mark - Lexer Colors

- (void)applyLexerColors:(NSString *)lang {
    if (!lang.length) return;
    ScintillaView *sci = _scintillaView;

    // Map EditorView language names to NPP style-store lexer IDs
    NSString *lid = lang.lowercaseString;
    if ([lid isEqualToString:@"c"] || [lid isEqualToString:@"objc"]) lid = @"cpp";
    else if ([lid isEqualToString:@"javascript"] || [lid isEqualToString:@"typescript"] ||
             [lid isEqualToString:@"swift"])                          lid = @"cpp";

    NPPStyleStore *store = [NPPStyleStore sharedStore];
    NSArray<NPPStyleEntry *> *styles = [store stylesForLexer:lid];
    if (!styles.count) return;

    for (NPPStyleEntry *e in styles) {
        int sid = e.styleID;
        if (e.fgColor)
            [sci setColorProperty:SCI_STYLESETFORE parameter:sid value:e.fgColor];
        if (e.bgColor)
            [sci setColorProperty:SCI_STYLESETBACK parameter:sid value:e.bgColor];
        if (e.fontName.length > 0)
            [sci message:SCI_STYLESETFONT wParam:sid lParam:(sptr_t)e.fontName.UTF8String];
        if (e.fontSize > 0)
            [sci message:SCI_STYLESETSIZEFRACTIONAL wParam:sid lParam:(sptr_t)(e.fontSize * 100)];
        [sci message:SCI_STYLESETBOLD      wParam:sid lParam:e.bold      ? 1 : 0];
        [sci message:SCI_STYLESETITALIC    wParam:sid lParam:e.italic    ? 1 : 0];
        [sci message:SCI_STYLESETUNDERLINE wParam:sid lParam:e.underline ? 1 : 0];
    }
}

#pragma mark - Word Wrap

- (BOOL)wordWrapEnabled { return _wordWrapEnabled; }
- (void)setWordWrapEnabled:(BOOL)enabled {
    _wordWrapEnabled = enabled;
    [_scintillaView message:SCI_SETWRAPMODE wParam:enabled ? SC_WRAP_WORD : SC_WRAP_NONE];
}

#pragma mark - Overwrite Mode

- (BOOL)isOverwriteMode { return [_scintillaView message:SCI_GETOVERTYPE] != 0; }

- (void)toggleOverwriteMode {
    BOOL ov = [_scintillaView message:SCI_GETOVERTYPE];
    [_scintillaView message:SCI_SETOVERTYPE wParam:!ov];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:EditorViewCursorDidMoveNotification object:self];
}

#pragma mark - Line Operations

- (void)duplicateLine:(id)sender { [_scintillaView message:SCI_LINEDUPLICATE]; }
- (void)deleteLine:(id)sender    { [_scintillaView message:SCI_LINEDELETE]; }
- (void)moveLineUp:(id)sender    { [_scintillaView message:SCI_MOVESELECTEDLINESUP]; }
- (void)moveLineDown:(id)sender  { [_scintillaView message:SCI_MOVESELECTEDLINESDOWN]; }

- (void)splitLines:(id)sender {
    // SCI_LINESSPLIT(pixelWidth=0) uses the current wrap width
    [_scintillaView message:SCI_LINESSPLIT wParam:0];
}

- (void)toggleLineComment:(id)sender {
    NSString *prefix = @"//";
    NSDictionary *commentMap = @{
        @"python":@"#", @"bash":@"#", @"ruby":@"#", @"perl":@"#",
        @"r":@"#", @"yaml":@"#", @"makefile":@"#", @"cmake":@"#", @"toml":@"#",
        @"sql":@"--", @"lua":@"--", @"haskell":@"--",
    };
    NSString *mapped = commentMap[_currentLanguage.lowercaseString];
    if (mapped) prefix = mapped;
    if (!prefix.length) return;

    ScintillaView *sci = _scintillaView;
    sptr_t selStart = [sci message:SCI_GETSELECTIONSTART];
    sptr_t selEnd   = [sci message:SCI_GETSELECTIONEND];
    NSInteger firstLine = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)selStart];
    NSInteger lastLine  = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)selEnd];
    if (selEnd > selStart &&
        [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)lastLine] == selEnd) lastLine--;

    // Determine if all non-empty lines already start with the comment prefix
    BOOL allCommented = YES;
    for (NSInteger ln = firstLine; ln <= lastLine && allCommented; ln++) {
        sptr_t len = [sci message:SCI_LINELENGTH wParam:(uptr_t)ln];
        if (len <= 0) continue;
        char *buf = (char *)malloc((size_t)len + 1);
        if (!buf) continue;
        [sci message:SCI_GETLINE wParam:(uptr_t)ln lParam:(sptr_t)buf];
        buf[len] = '\0';
        NSInteger i = 0;
        while (i < len && (buf[i]==' ' || buf[i]=='\t')) i++;
        // skip empty/whitespace-only lines
        if (i >= len || buf[i]=='\r' || buf[i]=='\n') { free(buf); continue; }
        if (strncmp(buf + i, prefix.UTF8String, prefix.length) != 0) allCommented = NO;
        free(buf);
    }

    [sci message:SCI_BEGINUNDOACTION];
    for (NSInteger ln = firstLine; ln <= lastLine; ln++) {
        sptr_t len = [sci message:SCI_LINELENGTH wParam:(uptr_t)ln];
        if (len <= 0) continue;
        char *buf = (char *)malloc((size_t)len + 1);
        if (!buf) continue;
        [sci message:SCI_GETLINE wParam:(uptr_t)ln lParam:(sptr_t)buf];
        buf[len] = '\0';
        NSInteger i = 0;
        while (i < len && (buf[i]==' ' || buf[i]=='\t')) i++;
        if (i >= len || buf[i]=='\r' || buf[i]=='\n') { free(buf); continue; }
        sptr_t lineStart = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)ln];
        sptr_t insertPos = lineStart + i;
        if (allCommented) {
            // Remove prefix (and one trailing space if present)
            NSInteger removeLen = (NSInteger)prefix.length;
            if (i + removeLen < len && buf[i + removeLen] == ' ') removeLen++;
            [sci message:SCI_DELETERANGE wParam:(uptr_t)insertPos lParam:removeLen];
        } else {
            NSString *ins = [prefix stringByAppendingString:@" "];
            [sci message:SCI_INSERTTEXT wParam:(uptr_t)insertPos lParam:(sptr_t)ins.UTF8String];
        }
        free(buf);
    }
    [sci message:SCI_ENDUNDOACTION];
}

// Returns the single-line comment prefix for the current language.
- (NSString *)_lineCommentPrefix {
    NSDictionary *commentMap = @{
        @"python":@"#", @"bash":@"#", @"ruby":@"#", @"perl":@"#",
        @"r":@"#", @"yaml":@"#", @"makefile":@"#", @"cmake":@"#", @"toml":@"#",
        @"sql":@"--", @"lua":@"--", @"haskell":@"--",
    };
    NSString *mapped = commentMap[_currentLanguage.lowercaseString];
    return mapped ?: @"//";
}

- (void)addSingleLineComment:(id)sender {
    NSString *prefix = [self _lineCommentPrefix];
    ScintillaView *sci = _scintillaView;
    sptr_t selStart = [sci message:SCI_GETSELECTIONSTART];
    sptr_t selEnd   = [sci message:SCI_GETSELECTIONEND];
    NSInteger firstLine = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)selStart];
    NSInteger lastLine  = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)selEnd];
    if (selEnd > selStart &&
        [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)lastLine] == selEnd) lastLine--;

    [sci message:SCI_BEGINUNDOACTION];
    for (NSInteger ln = firstLine; ln <= lastLine; ln++) {
        sptr_t len = [sci message:SCI_LINELENGTH wParam:(uptr_t)ln];
        if (len <= 0) continue;
        char *buf = (char *)malloc((size_t)len + 1);
        if (!buf) continue;
        [sci message:SCI_GETLINE wParam:(uptr_t)ln lParam:(sptr_t)buf];
        buf[len] = '\0';
        NSInteger i = 0;
        while (i < len && (buf[i]==' ' || buf[i]=='\t')) i++;
        if (i >= len || buf[i]=='\r' || buf[i]=='\n') { free(buf); continue; }
        sptr_t lineStart = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)ln];
        sptr_t insertPos = lineStart + i;
        NSString *ins = [prefix stringByAppendingString:@" "];
        [sci message:SCI_INSERTTEXT wParam:(uptr_t)insertPos lParam:(sptr_t)ins.UTF8String];
        free(buf);
    }
    [sci message:SCI_ENDUNDOACTION];
}

- (void)removeSingleLineComment:(id)sender {
    NSString *prefix = [self _lineCommentPrefix];
    ScintillaView *sci = _scintillaView;
    sptr_t selStart = [sci message:SCI_GETSELECTIONSTART];
    sptr_t selEnd   = [sci message:SCI_GETSELECTIONEND];
    NSInteger firstLine = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)selStart];
    NSInteger lastLine  = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)selEnd];
    if (selEnd > selStart &&
        [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)lastLine] == selEnd) lastLine--;

    [sci message:SCI_BEGINUNDOACTION];
    for (NSInteger ln = firstLine; ln <= lastLine; ln++) {
        sptr_t len = [sci message:SCI_LINELENGTH wParam:(uptr_t)ln];
        if (len <= 0) continue;
        char *buf = (char *)malloc((size_t)len + 1);
        if (!buf) continue;
        [sci message:SCI_GETLINE wParam:(uptr_t)ln lParam:(sptr_t)buf];
        buf[len] = '\0';
        NSInteger i = 0;
        while (i < len && (buf[i]==' ' || buf[i]=='\t')) i++;
        if (i >= len || buf[i]=='\r' || buf[i]=='\n') { free(buf); continue; }
        if (strncmp(buf + i, prefix.UTF8String, prefix.length) == 0) {
            sptr_t lineStart = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)ln];
            sptr_t removeStart = lineStart + i;
            NSInteger removeLen = (NSInteger)prefix.length;
            if (i + removeLen < len && buf[i + removeLen] == ' ') removeLen++;
            [sci message:SCI_DELETERANGE wParam:(uptr_t)removeStart lParam:removeLen];
        }
        free(buf);
    }
    [sci message:SCI_ENDUNDOACTION];
}

#pragma mark - Block Comment

- (void)toggleBlockComment:(id)sender {
    // Language → {open, close} delimiters
    NSDictionary<NSString *, NSArray<NSString *> *> *delimiters = @{
        @"c":          @[@"/*",   @"*/"],
        @"cpp":        @[@"/*",   @"*/"],
        @"objc":       @[@"/*",   @"*/"],
        @"javascript": @[@"/*",   @"*/"],
        @"typescript": @[@"/*",   @"*/"],
        @"swift":      @[@"/*",   @"*/"],
        @"css":        @[@"/*",   @"*/"],
        @"sql":        @[@"/*",   @"*/"],
        @"lua":        @[@"--[[", @"]]"],
        @"html":       @[@"<!--", @"-->"],
        @"xml":        @[@"<!--", @"-->"],
    };
    NSArray<NSString *> *pair = delimiters[_currentLanguage.lowercaseString];
    if (!pair) return;

    NSString *open  = pair[0];
    NSString *close = pair[1];
    ScintillaView *sci = _scintillaView;
    sptr_t selStart = [sci message:SCI_GETSELECTIONSTART];
    sptr_t selEnd   = [sci message:SCI_GETSELECTIONEND];

    // Check whether selection is already wrapped — if so, remove delimiters
    NSString *docText = sci.string;
    if ((sptr_t)docText.length >= selStart + (sptr_t)open.length + (sptr_t)close.length) {
        NSString *before = [docText substringWithRange:NSMakeRange((NSUInteger)selStart,
                                                                    (NSUInteger)open.length)];
        NSString *after  = selEnd >= (sptr_t)close.length
            ? [docText substringWithRange:NSMakeRange((NSUInteger)(selEnd - close.length),
                                                      (NSUInteger)close.length)]
            : @"";
        if ([before isEqualToString:open] && [after isEqualToString:close]) {
            [sci message:SCI_BEGINUNDOACTION];
            [sci message:SCI_DELETERANGE wParam:(uptr_t)(selEnd - close.length) lParam:(sptr_t)close.length];
            [sci message:SCI_DELETERANGE wParam:(uptr_t)selStart lParam:(sptr_t)open.length];
            [sci message:SCI_ENDUNDOACTION];
            return;
        }
    }

    // Wrap selection with open/close
    [sci message:SCI_BEGINUNDOACTION];
    [sci message:SCI_INSERTTEXT wParam:(uptr_t)selEnd   lParam:(sptr_t)close.UTF8String];
    [sci message:SCI_INSERTTEXT wParam:(uptr_t)selStart lParam:(sptr_t)open.UTF8String];
    [sci message:SCI_SETSEL
          wParam:(uptr_t)selStart
           lParam:selEnd + (sptr_t)(open.length + close.length)];
    [sci message:SCI_ENDUNDOACTION];
}

- (void)addBlockComment:(id)sender {
    NSDictionary<NSString *, NSArray<NSString *> *> *delimiters = @{
        @"c":@[@"/* ",@" */"], @"cpp":@[@"/* ",@" */"], @"objc":@[@"/* ",@" */"],
        @"javascript":@[@"/* ",@" */"], @"typescript":@[@"/* ",@" */"],
        @"swift":@[@"/* ",@" */"], @"css":@[@"/* ",@" */"], @"sql":@[@"/* ",@" */"],
        @"lua":@[@"--[[",@"]]"], @"html":@[@"<!-- ",@" -->"], @"xml":@[@"<!-- ",@" -->"],
    };
    NSArray<NSString *> *pair = delimiters[_currentLanguage.lowercaseString];
    if (!pair) { NSBeep(); return; }
    NSString *open = pair[0], *close = pair[1];
    ScintillaView *sci = _scintillaView;
    sptr_t selStart = [sci message:SCI_GETSELECTIONSTART];
    sptr_t selEnd   = [sci message:SCI_GETSELECTIONEND];
    [sci message:SCI_BEGINUNDOACTION];
    [sci message:SCI_INSERTTEXT wParam:(uptr_t)selEnd   lParam:(sptr_t)close.UTF8String];
    [sci message:SCI_INSERTTEXT wParam:(uptr_t)selStart lParam:(sptr_t)open.UTF8String];
    [sci message:SCI_ENDUNDOACTION];
}

- (void)removeBlockComment:(id)sender {
    NSDictionary<NSString *, NSArray<NSString *> *> *delimiters = @{
        @"c":@[@"/* ",@" */"], @"cpp":@[@"/* ",@" */"], @"objc":@[@"/* ",@" */"],
        @"javascript":@[@"/* ",@" */"], @"typescript":@[@"/* ",@" */"],
        @"swift":@[@"/* ",@" */"], @"css":@[@"/* ",@" */"], @"sql":@[@"/* ",@" */"],
        @"lua":@[@"--[[",@"]]"], @"html":@[@"<!-- ",@" -->"], @"xml":@[@"<!-- ",@" -->"],
    };
    // Also try without trailing space
    NSArray<NSString *> *pair = delimiters[_currentLanguage.lowercaseString];
    if (!pair) { NSBeep(); return; }
    ScintillaView *sci = _scintillaView;
    NSString *docText = sci.string;
    sptr_t selStart = [sci message:SCI_GETSELECTIONSTART];
    sptr_t selEnd   = [sci message:SCI_GETSELECTIONEND];

    // Search backward from selStart for opening delimiter
    NSString *open = pair[0], *openTrim = [pair[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *close = pair[1], *closeTrim = [pair[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSUInteger searchStart = (NSUInteger)MAX(0LL, selStart - (sptr_t)open.length);
    NSRange openRange = [docText rangeOfString:open  options:NSBackwardsSearch
                                         range:NSMakeRange(0, (NSUInteger)selStart + open.length)];
    if (openRange.location == NSNotFound)
        openRange = [docText rangeOfString:openTrim options:NSBackwardsSearch
                                     range:NSMakeRange(0, (NSUInteger)selStart + openTrim.length)];
    (void)searchStart;

    NSUInteger closeSearchStart = (NSUInteger)MAX(0LL, selEnd - (sptr_t)close.length);
    NSRange closeRange = [docText rangeOfString:close options:0
                                          range:NSMakeRange(closeSearchStart, docText.length - closeSearchStart)];
    if (closeRange.location == NSNotFound) {
        NSUInteger cs2 = (NSUInteger)MAX(0LL, selEnd - (sptr_t)closeTrim.length);
        closeRange = [docText rangeOfString:closeTrim options:0
                                      range:NSMakeRange(cs2, docText.length - cs2)];
    }

    if (openRange.location == NSNotFound || closeRange.location == NSNotFound) { NSBeep(); return; }

    [sci message:SCI_BEGINUNDOACTION];
    // Remove close first (higher position) so start positions stay valid
    [sci message:SCI_DELETERANGE wParam:(uptr_t)closeRange.location lParam:(sptr_t)closeRange.length];
    [sci message:SCI_DELETERANGE wParam:(uptr_t)openRange.location  lParam:(sptr_t)openRange.length];
    [sci message:SCI_ENDUNDOACTION];
}

#pragma mark - Multi-Select

// Scintilla multi-selection message numbers
static const unsigned int kSCI_SetMultipleSelection     = 2563;
static const unsigned int kSCI_SetAdditionalSelTyping   = 2565;
static const unsigned int kSCI_GetSelections             = 2570;
static const unsigned int kSCI_AddSelection              = 2573;
static const unsigned int kSCI_SetMainSelection          = 2574;
static const unsigned int kSCI_GetSelectionNCaret        = 2577;
static const unsigned int kSCI_DropSelectionN            = 2671;
static const unsigned int kSCI_SetRectSelCaret           = 2588;
static const unsigned int kSCI_SetRectSelAnchor          = 2590;

- (BOOL)beginSelectActive { return _beginSelectActive; }

- (void)beginEndSelect:(id)sender {
    ScintillaView *sci = _scintillaView;
    if (!_beginSelectActive) {
        _beginSelectPos   = [sci message:SCI_GETCURRENTPOS];
        _beginSelectActive = YES;
    } else {
        sptr_t current = [sci message:SCI_GETCURRENTPOS];
        [sci message:SCI_SETSEL
              wParam:(uptr_t)MIN(_beginSelectPos, current)
               lParam:MAX(_beginSelectPos, current)];
        _beginSelectActive = NO;
    }
}

- (void)beginEndSelectColumnMode:(id)sender {
    ScintillaView *sci = _scintillaView;
    if (!_beginSelectActive) {
        _beginSelectPos   = [sci message:SCI_GETCURRENTPOS];
        _beginSelectActive = YES;
    } else {
        sptr_t current = [sci message:SCI_GETCURRENTPOS];
        [sci message:kSCI_SetRectSelAnchor wParam:(uptr_t)_beginSelectPos];
        [sci message:kSCI_SetRectSelCaret  wParam:(uptr_t)current];
        _beginSelectActive = NO;
    }
}

- (void)_enableMultiSelect {
    [_scintillaView message:kSCI_SetMultipleSelection   wParam:1];
    [_scintillaView message:kSCI_SetAdditionalSelTyping wParam:1];
}

- (NSString *)_currentSelectionOrWord {
    ScintillaView *sci = _scintillaView;
    sptr_t selStart = [sci message:SCI_GETSELECTIONSTART];
    sptr_t selEnd   = [sci message:SCI_GETSELECTIONEND];
    if (selStart == selEnd) {
        selStart = [sci message:SCI_WORDSTARTPOSITION wParam:(uptr_t)selStart lParam:1];
        selEnd   = [sci message:SCI_WORDENDPOSITION   wParam:(uptr_t)selEnd   lParam:1];
    }
    if (selStart >= selEnd) return nil;
    NSString *text = sci.string;
    NSUInteger len = (NSUInteger)(selEnd - selStart);
    if ((NSUInteger)selStart + len > text.length) return nil;
    return [text substringWithRange:NSMakeRange((NSUInteger)selStart, len)];
}

- (void)multiSelectAllInCurrentDocument:(id)sender {
    NSString *word = [self _currentSelectionOrWord];
    if (!word.length) return;
    ScintillaView *sci = _scintillaView;
    NSString *text = sci.string;
    [self _enableMultiSelect];
    BOOL first = YES;
    NSRange search = NSMakeRange(0, text.length);
    NSRange found;
    while ((found = [text rangeOfString:word options:NSLiteralSearch range:search]).location != NSNotFound) {
        uptr_t caret  = (uptr_t)(found.location + found.length);
        sptr_t anchor = (sptr_t)found.location;
        if (first) {
            [sci message:SCI_SETSEL wParam:caret lParam:anchor];
            first = NO;
        } else {
            [sci message:kSCI_AddSelection wParam:caret lParam:anchor];
        }
        NSUInteger next = found.location + 1;
        if (next >= text.length) break;
        search = NSMakeRange(next, text.length - next);
    }
}

- (void)multiSelectNextInCurrentDocument:(id)sender {
    ScintillaView *sci = _scintillaView;
    sptr_t selStart = [sci message:SCI_GETSELECTIONSTART];
    sptr_t selEnd   = [sci message:SCI_GETSELECTIONEND];
    if (selStart == selEnd) return;
    NSString *text = sci.string;
    NSUInteger wordLen = (NSUInteger)(selEnd - selStart);
    if ((NSUInteger)selStart + wordLen > text.length) return;
    NSString *word = [text substringWithRange:NSMakeRange((NSUInteger)selStart, wordLen)];

    // Find the furthest caret position across all current selections
    NSInteger n = [sci message:kSCI_GetSelections];
    sptr_t searchFrom = selEnd;
    for (NSInteger i = 0; i < n; i++) {
        sptr_t c = [sci message:kSCI_GetSelectionNCaret wParam:(uptr_t)i];
        if (c > searchFrom) searchFrom = c;
    }

    NSRange search = NSMakeRange((NSUInteger)searchFrom, text.length - (NSUInteger)searchFrom);
    NSRange found = [text rangeOfString:word options:NSLiteralSearch range:search];
    if (found.location == NSNotFound)
        found = [text rangeOfString:word options:NSLiteralSearch]; // wrap
    if (found.location == NSNotFound) return;

    [self _enableMultiSelect];
    [sci message:kSCI_AddSelection
          wParam:(uptr_t)(found.location + found.length)
           lParam:(sptr_t)found.location];
}

- (void)undoLatestMultiSelect:(id)sender {
    ScintillaView *sci = _scintillaView;
    NSInteger n = [sci message:kSCI_GetSelections];
    if (n <= 1) return;
    [sci message:kSCI_DropSelectionN wParam:(uptr_t)(n - 1)];
}

- (void)skipCurrentAndGoToNextMultiSelect:(id)sender {
    ScintillaView *sci = _scintillaView;
    sptr_t mainStart = [sci message:SCI_GETSELECTIONSTART];
    sptr_t mainEnd   = [sci message:SCI_GETSELECTIONEND];
    if (mainStart == mainEnd) return;
    NSString *text = sci.string;
    NSUInteger wordLen = (NSUInteger)(mainEnd - mainStart);
    if ((NSUInteger)mainStart + wordLen > text.length) return;
    NSString *word = [text substringWithRange:NSMakeRange((NSUInteger)mainStart, wordLen)];

    // Drop the main selection (index 0)
    NSInteger n = [sci message:kSCI_GetSelections];
    if (n > 1) {
        [sci message:kSCI_DropSelectionN wParam:0];
        [sci message:kSCI_SetMainSelection wParam:0];
    }

    // Find next occurrence after old mainEnd
    NSRange search = NSMakeRange((NSUInteger)mainEnd, text.length - (NSUInteger)mainEnd);
    NSRange found = [text rangeOfString:word options:NSLiteralSearch range:search];
    if (found.location == NSNotFound)
        found = [text rangeOfString:word options:NSLiteralSearch];
    if (found.location == NSNotFound) return;

    [self _enableMultiSelect];
    [sci message:kSCI_AddSelection
          wParam:(uptr_t)(found.location + found.length)
           lParam:(sptr_t)found.location];
}

#pragma mark - Blank / EOL Cleanup

/// Returns the first and last line numbers to process.
/// When text is selected, returns only lines in the selection; otherwise returns the whole document.
- (void)_selectionLineRange:(sptr_t *)outFirst last:(sptr_t *)outLast {
    ScintillaView *sci = _scintillaView;
    sptr_t selStart = [sci message:SCI_GETSELECTIONSTART];
    sptr_t selEnd   = [sci message:SCI_GETSELECTIONEND];
    if (selStart == selEnd) {
        *outFirst = 0;
        *outLast  = [sci message:SCI_GETLINECOUNT] - 1;
    } else {
        *outFirst = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)selStart];
        *outLast  = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)selEnd];
        // Don't include a line that is only selected by the anchor sitting at its start
        if ([sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)*outLast] == selEnd)
            (*outLast)--;
    }
}

- (void)removeUnnecessaryBlankAndEOL:(id)sender {
    [self trimTrailingWhitespace:sender];
    // Remove trailing blank lines at end of document
    ScintillaView *sci = _scintillaView;
    [sci message:SCI_BEGINUNDOACTION];
    sptr_t docLen = [sci message:SCI_GETLENGTH];
    sptr_t pos = docLen;
    while (pos > 0) {
        sptr_t ch = [sci message:SCI_GETCHARAT wParam:(uptr_t)(pos - 1)];
        if (ch == '\n' || ch == '\r') pos--;
        else break;
    }
    if (pos < docLen) {
        [sci message:SCI_SETTARGETRANGE wParam:(uptr_t)pos lParam:docLen];
        const char empty[] = "";
        [sci message:SCI_REPLACETARGET wParam:(uptr_t)-1 lParam:(sptr_t)empty];
    }
    [sci message:SCI_ENDUNDOACTION];
}

#pragma mark - Read-Only (internal clear)

- (void)clearReadOnlyFlag:(id)sender {
    // Force Scintilla read-only OFF (even if already off)
    [_scintillaView message:SCI_SETREADONLY wParam:0];
}

#pragma mark - Code Folding

- (void)foldAll:(id)sender    { [_scintillaView message:SCI_FOLDALL wParam:SC_FOLDACTION_CONTRACT]; }
- (void)unfoldAll:(id)sender  { [_scintillaView message:SCI_FOLDALL wParam:SC_FOLDACTION_EXPAND]; }

- (void)foldCurrentLevel:(id)sender {
    sptr_t line = [_scintillaView message:SCI_LINEFROMPOSITION
                                   wParam:[_scintillaView message:SCI_GETCURRENTPOS]];
    sptr_t level = [_scintillaView message:SCI_GETFOLDLEVEL wParam:(uptr_t)line];
    if (level & SC_FOLDLEVELHEADERFLAG) {
        BOOL expanded = [_scintillaView message:SCI_GETFOLDEXPANDED wParam:(uptr_t)line];
        [_scintillaView message:SCI_FOLDLINE wParam:(uptr_t)line
                         lParam:expanded ? SC_FOLDACTION_CONTRACT : SC_FOLDACTION_EXPAND];
    }
}

#pragma mark - Bookmarks

- (void)toggleBookmark:(id)sender {
    sptr_t line = [_scintillaView message:SCI_LINEFROMPOSITION
                                   wParam:[_scintillaView message:SCI_GETCURRENTPOS]];
    sptr_t mask = [_scintillaView message:SCI_MARKERGET wParam:(uptr_t)line];
    if (mask & (1 << kBookmarkMarker))
        [_scintillaView message:SCI_MARKERDELETE wParam:(uptr_t)line lParam:kBookmarkMarker];
    else
        [_scintillaView message:SCI_MARKERADD wParam:(uptr_t)line lParam:kBookmarkMarker];
}

- (void)nextBookmark:(id)sender {
    sptr_t cur = [_scintillaView message:SCI_LINEFROMPOSITION
                                  wParam:[_scintillaView message:SCI_GETCURRENTPOS]];
    sptr_t found = [_scintillaView message:SCI_MARKERNEXT
                                    wParam:(uptr_t)(cur + 1) lParam:(1 << kBookmarkMarker)];
    if (found < 0) // wrap
        found = [_scintillaView message:SCI_MARKERNEXT wParam:0 lParam:(1 << kBookmarkMarker)];
    if (found >= 0) {
        [_scintillaView message:SCI_GOTOLINE wParam:(uptr_t)found];
        [_scintillaView message:SCI_SCROLLCARET];
    }
}

- (void)previousBookmark:(id)sender {
    sptr_t cur = [_scintillaView message:SCI_LINEFROMPOSITION
                                  wParam:[_scintillaView message:SCI_GETCURRENTPOS]];
    sptr_t found = [_scintillaView message:SCI_MARKERPREVIOUS
                                    wParam:(uptr_t)(cur - 1) lParam:(1 << kBookmarkMarker)];
    if (found < 0) { // wrap to end
        sptr_t last = [_scintillaView message:SCI_GETLINECOUNT] - 1;
        found = [_scintillaView message:SCI_MARKERPREVIOUS
                                 wParam:(uptr_t)last lParam:(1 << kBookmarkMarker)];
    }
    if (found >= 0) {
        [_scintillaView message:SCI_GOTOLINE wParam:(uptr_t)found];
        [_scintillaView message:SCI_SCROLLCARET];
    }
}

- (void)clearAllBookmarks:(id)sender {
    [_scintillaView message:SCI_MARKERDELETEALL wParam:kBookmarkMarker];
}

#pragma mark - Navigation

- (void)goToLineNumber:(NSInteger)lineNumber {
    NSInteger total = [_scintillaView message:SCI_GETLINECOUNT];
    lineNumber = MAX(1, MIN(lineNumber, total));
    [_scintillaView message:SCI_GOTOLINE wParam:(uptr_t)(lineNumber - 1)];
    [_scintillaView message:SCI_SCROLLCARET];
}

#pragma mark - Change History Navigation

static const int kHistoryMask =
    (1 << SC_MARKNUM_HISTORY_MODIFIED) |
    (1 << SC_MARKNUM_HISTORY_SAVED) |
    (1 << SC_MARKNUM_HISTORY_REVERTED_TO_MODIFIED) |
    (1 << SC_MARKNUM_HISTORY_REVERTED_TO_ORIGIN);

- (void)goToNextChange:(id)sender {
    ScintillaView *sci = _scintillaView;
    sptr_t cur = [sci message:SCI_LINEFROMPOSITION
                       wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
    sptr_t count = [sci message:SCI_GETLINECOUNT];
    for (sptr_t ln = cur + 1; ln < count; ln++) {
        if ([sci message:SCI_MARKERGET wParam:(uptr_t)ln] & kHistoryMask) {
            [sci message:SCI_GOTOLINE wParam:(uptr_t)ln];
            [sci message:SCI_SCROLLCARET];
            return;
        }
    }
    NSBeep();
}

- (void)goToPreviousChange:(id)sender {
    ScintillaView *sci = _scintillaView;
    sptr_t cur = [sci message:SCI_LINEFROMPOSITION
                       wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
    for (sptr_t ln = cur - 1; ln >= 0; ln--) {
        if ([sci message:SCI_MARKERGET wParam:(uptr_t)ln] & kHistoryMask) {
            [sci message:SCI_GOTOLINE wParam:(uptr_t)ln];
            [sci message:SCI_SCROLLCARET];
            return;
        }
    }
    NSBeep();
}

- (void)clearAllChanges:(id)sender {
    ScintillaView *sci = _scintillaView;
    // Disable then re-enable to reset all history markers
    [sci message:SCI_SETCHANGEHISTORY wParam:SC_CHANGE_HISTORY_DISABLED];
    [sci message:SCI_SETCHANGEHISTORY wParam:SC_CHANGE_HISTORY_ENABLED | SC_CHANGE_HISTORY_MARKERS];
}

#pragma mark - Incremental Search (highlight all matches)

static const int kIndicatorIncSearch = 28; // Scintilla indicator slot for incremental search

- (void)highlightAllMatches:(NSString *)text matchCase:(BOOL)mc {
    ScintillaView *sci = _scintillaView;
    // Clear previous incremental search highlights
    [sci message:SCI_SETINDICATORCURRENT wParam:kIndicatorIncSearch];
    [sci message:SCI_INDICATORCLEARRANGE wParam:0 lParam:[sci message:SCI_GETLENGTH]];
    if (!text.length) return;

    // Configure indicator style: semi-transparent rounded box
    [sci message:SCI_INDICSETSTYLE  wParam:kIndicatorIncSearch lParam:INDIC_ROUNDBOX];
    [sci message:SCI_INDICSETFORE   wParam:kIndicatorIncSearch lParam:0x00AA44]; // green
    [sci message:SCI_INDICSETALPHA  wParam:kIndicatorIncSearch lParam:80];

    // Search flags
    int flags = 0;
    if (mc) flags |= SCFIND_MATCHCASE;

    sptr_t docLen = [sci message:SCI_GETLENGTH];
    const char *needle = text.UTF8String;
    [sci message:SCI_SETTARGETRANGE wParam:0 lParam:docLen];
    [sci message:SCI_SETSEARCHFLAGS wParam:(uptr_t)flags];

    sptr_t pos = 0;
    while (pos < docLen) {
        [sci message:SCI_SETTARGETRANGE wParam:(uptr_t)pos lParam:docLen];
        sptr_t found = [sci message:SCI_SEARCHINTARGET wParam:strlen(needle) lParam:(sptr_t)needle];
        if (found < 0) break;
        sptr_t end = [sci message:SCI_GETTARGETEND];
        [sci message:SCI_INDICATORFILLRANGE wParam:(uptr_t)found lParam:end - found];
        pos = end > found ? end : found + 1;
    }
}

- (void)clearIncrementalSearchHighlights {
    ScintillaView *sci = _scintillaView;
    [sci message:SCI_SETINDICATORCURRENT wParam:kIndicatorIncSearch];
    [sci message:SCI_INDICATORCLEARRANGE wParam:0 lParam:[sci message:SCI_GETLENGTH]];
}

#pragma mark - Brace Highlight

// Mirrors NPP's ScintillaEditView::braceMatch().
// When the caret is adjacent to ()[]{}:
//   - Highlights the matched pair via STYLE_BRACELIGHT (red bold)
// Fold block highlighting (red ⊞/⊟ symbols and connecting lines for the enclosing block)
// is handled automatically by SCI_MARKERENABLEHIGHLIGHT — no manual marker work needed.
- (void)updateBraceHighlight {
    ScintillaView *sci = _scintillaView;
    sptr_t caretPos = [sci message:SCI_GETCURRENTPOS];
    sptr_t docLen   = [sci message:SCI_GETLENGTH];

    const char *braces = "()[]{}";
    sptr_t bracePos = INVALID_POSITION;

    // Check character after caret first, then before (NPP order)
    if (caretPos < docLen) {
        int ch = (int)[sci message:SCI_GETCHARAT wParam:(uptr_t)caretPos];
        if (strchr(braces, ch)) bracePos = caretPos;
    }
    if (bracePos == INVALID_POSITION && caretPos > 0) {
        int ch = (int)[sci message:SCI_GETCHARAT wParam:(uptr_t)(caretPos - 1)];
        if (strchr(braces, ch)) bracePos = caretPos - 1;
    }

    sptr_t matchPos = INVALID_POSITION;
    if (bracePos != INVALID_POSITION)
        matchPos = [sci message:SCI_BRACEMATCH wParam:(uptr_t)bracePos lParam:0];

    // Nothing changed — skip redundant updates
    if (bracePos == _lastBracePos && matchPos == _lastMatchPos) return;
    _lastBracePos = bracePos;
    _lastMatchPos = matchPos;

    if (bracePos == INVALID_POSITION) {
        [sci message:SCI_BRACEHIGHLIGHT wParam:(uptr_t)INVALID_POSITION lParam:INVALID_POSITION];
        return;
    }

    if (matchPos != INVALID_POSITION) {
        [sci message:SCI_BRACEHIGHLIGHT wParam:(uptr_t)bracePos lParam:matchPos];
    } else {
        [sci message:SCI_BRACEBADLIGHT wParam:(uptr_t)bracePos lParam:0];
    }
}

#pragma mark - Smart Highlight

- (void)updateSmartHighlight {
    ScintillaView *sci = _scintillaView;
    sptr_t selStart = [sci message:SCI_GETSELECTIONSTART];
    sptr_t selEnd   = [sci message:SCI_GETSELECTIONEND];

    // Always clear first
    [sci message:SCI_SETINDICATORCURRENT wParam:kHighlightIndicator];
    [sci message:SCI_INDICATORCLEARRANGE wParam:0 lParam:[sci message:SCI_GETLENGTH]];

    NSInteger selLen = selEnd - selStart;
    if (selLen < 2) return;

    // Only highlight single-word selections (no newlines)
    NSString *selText = sci.selectedString;
    if (!selText.length ||
        [selText rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound)
        return;

    const char *needle = selText.UTF8String;
    NSInteger needleLen = (NSInteger)strlen(needle);
    [sci message:SCI_SETSEARCHFLAGS wParam:SCFIND_WHOLEWORD | SCFIND_MATCHCASE];

    sptr_t docLen = [sci message:SCI_GETLENGTH];
    sptr_t pos = 0;
    while (pos < docLen) {
        [sci message:SCI_SETTARGETSTART wParam:(uptr_t)pos];
        [sci message:SCI_SETTARGETEND   wParam:(uptr_t)docLen];
        sptr_t found = [sci message:SCI_SEARCHINTARGET wParam:(uptr_t)needleLen lParam:(sptr_t)needle];
        if (found < 0) break;
        sptr_t foundEnd = [sci message:SCI_GETTARGETEND];
        if (found != selStart) // skip the current selection itself
            [sci message:SCI_INDICATORFILLRANGE wParam:(uptr_t)found lParam:foundEnd - found];
        pos = foundEnd;
    }
}

#pragma mark - Macro Recording

- (BOOL)isRecordingMacro { return _isRecordingMacro; }

- (NSArray<NSDictionary *> *)macroActions { return [_macroActions copy]; }

- (void)runMacroActions:(NSArray<NSDictionary *> *)actions {
    if (!actions.count) { NSBeep(); return; }
    ScintillaView *sci = _scintillaView;
    [sci message:SCI_BEGINUNDOACTION];
    for (NSDictionary *action in actions) {
        unsigned int msg = [action[@"msg"] unsignedIntValue];
        uptr_t       wp  = (uptr_t)[action[@"wp"] unsignedLongLongValue];
        NSString    *text = action[@"text"];
        if (text) {
            [sci message:msg wParam:wp lParam:(sptr_t)text.UTF8String];
        } else {
            sptr_t lp = (sptr_t)[action[@"lp"] longLongValue];
            [sci message:msg wParam:wp lParam:lp];
        }
    }
    [sci message:SCI_ENDUNDOACTION];
}

- (void)startMacroRecording {
    _macroActions = [NSMutableArray array];
    _isRecordingMacro = YES;
    [_scintillaView message:SCI_STARTRECORD];
}

- (void)stopMacroRecording {
    [_scintillaView message:SCI_STOPRECORD];
    _isRecordingMacro = NO;
}

- (void)runMacro {
    if (!_macroActions.count) { NSBeep(); return; }
    ScintillaView *sci = _scintillaView;
    [sci message:SCI_BEGINUNDOACTION];
    for (NSDictionary *action in _macroActions) {
        unsigned int msg = [action[@"msg"] unsignedIntValue];
        uptr_t       wp  = (uptr_t)[action[@"wp"] unsignedLongLongValue];
        NSString    *text = action[@"text"]; // set for text-carrying messages
        if (text) {
            [sci message:msg wParam:wp lParam:(sptr_t)text.UTF8String];
        } else {
            sptr_t lp = (sptr_t)[action[@"lp"] longLongValue];
            [sci message:msg wParam:wp lParam:lp];
        }
    }
    [sci message:SCI_ENDUNDOACTION];
}

#pragma mark - Auto-close & Word Completion

- (void)handleCharAdded:(int)ch {
    ScintillaView *sci = _scintillaView;

    // Auto-close bracket pairs — only when there's no existing selection
    if ([sci message:SCI_GETSELECTIONSTART] == [sci message:SCI_GETSELECTIONEND]) {
        const char *closeStr = nullptr;
        if      (ch == '(') closeStr = ")";
        else if (ch == '[') closeStr = "]";
        else if (ch == '{') closeStr = "}";

        if (closeStr) {
            sptr_t pos = [sci message:SCI_GETCURRENTPOS];
            [sci message:SCI_INSERTTEXT wParam:(uptr_t)pos lParam:(sptr_t)closeStr];
            [sci message:SCI_GOTOPOS   wParam:(uptr_t)pos];
        }
    }

    // Word completion: trigger at 3+ chars
    if (isalnum(ch) || ch == '_') {
        [self updateAutoComplete];
    } else {
        [sci message:SCI_AUTOCCANCEL];
    }
}

- (void)updateAutoComplete {
    ScintillaView *sci = _scintillaView;
    sptr_t pos       = [sci message:SCI_GETCURRENTPOS];
    sptr_t wordStart = [sci message:SCI_WORDSTARTPOSITION wParam:(uptr_t)pos lParam:1];
    NSInteger prefixLen = pos - wordStart;
    if (prefixLen < 3) { [sci message:SCI_AUTOCCANCEL]; return; }

    NSString *docText = sci.string;
    if (!docText || docText.length > 300000) { [sci message:SCI_AUTOCCANCEL]; return; }
    if (wordStart < 0 || wordStart + prefixLen > (sptr_t)docText.length) {
        [sci message:SCI_AUTOCCANCEL]; return;
    }

    NSString *prefix = [docText substringWithRange:NSMakeRange((NSUInteger)wordStart,
                                                                (NSUInteger)prefixLen)];

    // Collect unique words from document that start with the prefix
    NSMutableCharacterSet *wordCS = [[NSCharacterSet alphanumericCharacterSet] mutableCopy];
    [wordCS addCharactersInString:@"_"];
    NSCharacterSet *splitCS = wordCS.invertedSet;

    NSMutableSet<NSString *> *wordSet = [NSMutableSet set];
    NSArray<NSString *> *tokens = [docText componentsSeparatedByCharactersInSet:splitCS];
    NSUInteger plen = (NSUInteger)prefixLen;
    for (NSString *word in tokens) {
        if (word.length > plen && [word hasPrefix:prefix]) {
            [wordSet addObject:word];
        }
    }
    [wordSet removeObject:prefix]; // don't suggest the prefix itself

    if (!wordSet.count) { [sci message:SCI_AUTOCCANCEL]; return; }

    NSArray<NSString *> *sorted = [[wordSet allObjects]
        sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    NSString *wordList = [sorted componentsJoinedByString:@" "];
    [sci message:SCI_AUTOCSHOW wParam:(uptr_t)prefixLen lParam:(sptr_t)wordList.UTF8String];
}

#pragma mark - ScintillaNotificationProtocol

- (void)notification:(SCNotification *)notification {
    switch (notification->nmhdr.code) {
        case SCN_MODIFIED:
            if (notification->modificationType & (SC_MOD_INSERTTEXT | SC_MOD_DELETETEXT)) {
                _isModified = YES;
            }
            break;
        case SCN_CHARADDED:
            [self handleCharAdded:notification->ch];
            break;
        case SCN_MACRORECORD:
            if (_isRecordingMacro) {
                unsigned int msg = (unsigned int)notification->message;
                uptr_t wp = notification->wParam;
                sptr_t lp = notification->lParam;
                NSMutableDictionary *action = [NSMutableDictionary dictionaryWithDictionary:@{
                    @"msg": @(msg),
                    @"wp":  @(wp),
                    @"lp":  @(lp),
                }];
                // SCI_REPLACESEL carries typed text in lParam (const char *)
                if ((msg == SCI_REPLACESEL || msg == SCI_ADDTEXT || msg == SCI_INSERTTEXT) && lp) {
                    action[@"text"] = [NSString stringWithUTF8String:(const char *)lp];
                }
                [_macroActions addObject:action];
            }
            break;
        case SCN_UPDATEUI:
            [self updateBraceHighlight];
            [self updateSmartHighlight];
            if (_spellCheckEnabled) [self _scheduleSpellCheck];
            [[NSNotificationCenter defaultCenter]
                postNotificationName:EditorViewCursorDidMoveNotification
                              object:self];
            break;
        case SCN_MARGINCLICK:
            if (notification->margin == 1) { // bookmark margin
                NSInteger line = [_scintillaView message:SCI_LINEFROMPOSITION
                                                  wParam:(uptr_t)notification->position];
                sptr_t mask = [_scintillaView message:SCI_MARKERGET wParam:(uptr_t)line];
                if (mask & (1 << kBookmarkMarker))
                    [_scintillaView message:SCI_MARKERDELETE wParam:(uptr_t)line lParam:kBookmarkMarker];
                else
                    [_scintillaView message:SCI_MARKERADD wParam:(uptr_t)line lParam:kBookmarkMarker];
            }
            break;
        default:
            break;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Text helpers

/// Get selected text as NSString. Returns nil if no selection.
- (nullable NSString *)selectedText {
    sptr_t len = [_scintillaView message:SCI_GETSELTEXT wParam:0 lParam:0];
    if (len <= 1) return nil; // no selection (len includes NUL)
    char *buf = (char *)malloc((size_t)len);
    [_scintillaView message:SCI_GETSELTEXT wParam:0 lParam:(sptr_t)buf];
    NSString *s = [NSString stringWithUTF8String:buf] ?: @"";
    free(buf);
    return s.length ? s : nil;
}

/// Replace the current selection with str (wraps in undo group).
- (void)replaceSelectionWith:(NSString *)str {
    [_scintillaView message:SCI_BEGINUNDOACTION];
    [_scintillaView message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)str.UTF8String];
    [_scintillaView message:SCI_ENDUNDOACTION];
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Case Conversion

- (void)convertToUppercase:(id)sender {
    NSString *sel = [self selectedText]; if (!sel) return;
    [self replaceSelectionWith:sel.uppercaseString];
}

- (void)convertToLowercase:(id)sender {
    NSString *sel = [self selectedText]; if (!sel) return;
    [self replaceSelectionWith:sel.lowercaseString];
}

- (void)convertToProperCase:(id)sender {
    NSString *sel = [self selectedText]; if (!sel) return;
    [self replaceSelectionWith:sel.capitalizedString];
}

- (void)convertToSentenceCase:(id)sender {
    NSString *sel = [self selectedText]; if (!sel) return;
    NSMutableString *result = [sel mutableCopy];
    BOOL nextUpper = YES;
    for (NSUInteger i = 0; i < result.length; i++) {
        unichar c = [result characterAtIndex:i];
        if (nextUpper && isalpha(c)) {
            [result replaceCharactersInRange:NSMakeRange(i, 1)
                                  withString:[[NSString stringWithCharacters:&c length:1] uppercaseString]];
            nextUpper = NO;
        } else if (c == '.' || c == '!' || c == '?') {
            nextUpper = YES;
        }
    }
    [self replaceSelectionWith:result];
}

- (void)convertToInvertedCase:(id)sender {
    NSString *sel = [self selectedText]; if (!sel) return;
    NSMutableString *result = [NSMutableString stringWithCapacity:sel.length];
    for (NSUInteger i = 0; i < sel.length; i++) {
        unichar c = [sel characterAtIndex:i];
        NSString *ch = [NSString stringWithCharacters:&c length:1];
        [result appendString:isupper(c) ? ch.lowercaseString : ch.uppercaseString];
    }
    [self replaceSelectionWith:result];
}

- (void)convertToRandomCase:(id)sender {
    NSString *sel = [self selectedText]; if (!sel) return;
    NSMutableString *result = [NSMutableString stringWithCapacity:sel.length];
    for (NSUInteger i = 0; i < sel.length; i++) {
        unichar c = [sel characterAtIndex:i];
        NSString *ch = [NSString stringWithCharacters:&c length:1];
        [result appendString:(arc4random_uniform(2) == 0) ? ch.uppercaseString : ch.lowercaseString];
    }
    [self replaceSelectionWith:result];
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Line Sorting / Cleanup

/// Returns all lines in the current selection (or whole document if no selection).
/// Also sets *startPos and *endPos to the document range that was used.
- (NSMutableArray<NSString *> *)linesForSortingStartPos:(sptr_t *)startPos endPos:(sptr_t *)endPos {
    ScintillaView *sci = _scintillaView;
    sptr_t selStart = [sci message:SCI_GETSELECTIONSTART];
    sptr_t selEnd   = [sci message:SCI_GETSELECTIONEND];
    BOOL hasSelection = (selStart != selEnd);

    sptr_t lineStart, lineEnd;
    if (hasSelection) {
        lineStart = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)selStart];
        lineEnd   = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)selEnd];
        // If selection ends at col 0 of the next line, don't include that line
        if (selEnd == [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)lineEnd] && lineEnd > lineStart)
            lineEnd--;
    } else {
        lineStart = 0;
        lineEnd   = [sci message:SCI_GETLINECOUNT] - 1;
    }

    *startPos = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)lineStart];
    *endPos   = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)lineEnd];

    NSMutableArray *lines = [NSMutableArray array];
    for (sptr_t ln = lineStart; ln <= lineEnd; ln++) {
        sptr_t start = [sci message:SCI_POSITIONFROMLINE    wParam:(uptr_t)ln];
        sptr_t end   = [sci message:SCI_GETLINEENDPOSITION  wParam:(uptr_t)ln];
        sptr_t len   = end - start;
        char *buf = (char *)calloc((size_t)(len + 1), 1);
        Sci_TextRangeFull tr;
        tr.chrg.cpMin = (Sci_Position)start;
        tr.chrg.cpMax = (Sci_Position)end;
        tr.lpstrText  = buf;
        [sci message:SCI_GETTEXTRANGEFULL wParam:0 lParam:(sptr_t)&tr];
        NSString *line = [NSString stringWithUTF8String:buf] ?: @"";
        free(buf);
        [lines addObject:line];
    }
    return lines;
}

- (void)applySortedLines:(NSArray<NSString *> *)lines startPos:(sptr_t)start endPos:(sptr_t)end {
    NSString *eol = self.eolName;
    NSString *sep = [eol isEqualToString:@"CRLF"] ? @"\r\n" : [eol isEqualToString:@"CR"] ? @"\r" : @"\n";
    NSString *joined = [lines componentsJoinedByString:sep];
    [_scintillaView message:SCI_BEGINUNDOACTION];
    [_scintillaView message:SCI_SETTARGETSTART wParam:(uptr_t)start];
    [_scintillaView message:SCI_SETTARGETEND   wParam:(uptr_t)end];
    [_scintillaView message:SCI_REPLACETARGET  wParam:(uptr_t)joined.length
                                               lParam:(sptr_t)joined.UTF8String];
    [_scintillaView message:SCI_ENDUNDOACTION];
}

- (void)sortLinesAscending:(id)sender {
    sptr_t s, e;
    NSMutableArray *lines = [self linesForSortingStartPos:&s endPos:&e];
    [lines sortUsingSelector:@selector(compare:)];
    [self applySortedLines:lines startPos:s endPos:e];
}

- (void)sortLinesDescending:(id)sender {
    sptr_t s, e;
    NSMutableArray *lines = [self linesForSortingStartPos:&s endPos:&e];
    [lines sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [b compare:a];
    }];
    [self applySortedLines:lines startPos:s endPos:e];
}

- (void)sortLinesAscendingCI:(id)sender {
    sptr_t s, e;
    NSMutableArray *lines = [self linesForSortingStartPos:&s endPos:&e];
    [lines sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [a caseInsensitiveCompare:b];
    }];
    [self applySortedLines:lines startPos:s endPos:e];
}

- (void)sortLinesByLengthAsc:(id)sender {
    sptr_t s, e;
    NSMutableArray *lines = [self linesForSortingStartPos:&s endPos:&e];
    [lines sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        if (a.length < b.length) return NSOrderedAscending;
        if (a.length > b.length) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    [self applySortedLines:lines startPos:s endPos:e];
}

- (void)sortLinesByLengthDesc:(id)sender {
    sptr_t s, e;
    NSMutableArray *lines = [self linesForSortingStartPos:&s endPos:&e];
    [lines sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        if (a.length > b.length) return NSOrderedAscending;
        if (a.length < b.length) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    [self applySortedLines:lines startPos:s endPos:e];
}

- (void)removeDuplicateLines:(id)sender {
    sptr_t s, e;
    NSMutableArray *lines = [self linesForSortingStartPos:&s endPos:&e];
    NSMutableOrderedSet *seen = [NSMutableOrderedSet orderedSet];
    for (NSString *line in lines) [seen addObject:line];
    [self applySortedLines:seen.array startPos:s endPos:e];
}

- (void)trimTrailingWhitespace:(id)sender {
    ScintillaView *sci = _scintillaView;
    sptr_t firstLine, lastLine;
    [self _selectionLineRange:&firstLine last:&lastLine];
    [sci message:SCI_BEGINUNDOACTION];
    NSCharacterSet *ws = [NSCharacterSet whitespaceCharacterSet];
    for (sptr_t ln = firstLine; ln <= lastLine; ln++) {
        sptr_t start = [sci message:SCI_POSITIONFROMLINE   wParam:(uptr_t)ln];
        sptr_t end   = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)ln];
        sptr_t len   = end - start;
        if (len <= 0) continue;
        char *buf = (char *)calloc((size_t)(len + 1), 1);
        Sci_TextRangeFull tr;
        tr.chrg.cpMin = (Sci_Position)start;
        tr.chrg.cpMax = (Sci_Position)end;
        tr.lpstrText  = buf;
        [sci message:SCI_GETTEXTRANGEFULL wParam:0 lParam:(sptr_t)&tr];
        NSString *lineStr = [NSString stringWithUTF8String:buf] ?: @"";
        free(buf);
        NSString *trimmed = [lineStr stringByReplacingOccurrencesOfString:@"\\s+$"
                                                               withString:@""
                                                                  options:NSRegularExpressionSearch
                                                                    range:NSMakeRange(0, lineStr.length)];
        if (![trimmed isEqualToString:lineStr]) {
            sptr_t trimLen = (sptr_t)[trimmed lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
            sptr_t newEnd  = start + trimLen;
            [sci message:SCI_SETTARGETSTART wParam:(uptr_t)newEnd];
            [sci message:SCI_SETTARGETEND   wParam:(uptr_t)end];
            [sci message:SCI_REPLACETARGET  wParam:0 lParam:(sptr_t)""];
        }
    }
    [sci message:SCI_ENDUNDOACTION];
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Text Direction

static const unsigned int kSCI_SetBidirectional = 2709; // Scintilla::Message::SetBidirectional
static const unsigned int kSCI_GetBidirectional = 2708;

- (void)setTextDirectionRTL:(id)sender {
    [_scintillaView message:kSCI_SetBidirectional wParam:2]; // Bidirectional::R2L
}

- (void)setTextDirectionLTR:(id)sender {
    [_scintillaView message:kSCI_SetBidirectional wParam:1]; // Bidirectional::L2R
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - View Toggles

- (void)showWhiteSpaceAndTab:(id)sender {
    ScintillaView *sci = _scintillaView;
    sptr_t current = [sci message:SCI_GETVIEWWS];
    [sci message:SCI_SETVIEWWS wParam:(current == SCWS_INVISIBLE ? SCWS_VISIBLEALWAYS : SCWS_INVISIBLE)];
}

- (void)showEndOfLine:(id)sender {
    ScintillaView *sci = _scintillaView;
    sptr_t current = [sci message:SCI_GETVIEWEOL];
    [sci message:SCI_SETVIEWEOL wParam:(!current ? 1 : 0)];
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Fold Levels

/// Private helper — fold or unfold all headers at a specific fold level (0-based).
- (void)_setFoldLevel:(int)level collapsed:(BOOL)collapse {
    ScintillaView *sci = _scintillaView;
    sptr_t maxLine = [sci message:SCI_GETLINECOUNT];
    for (sptr_t ln = 0; ln < maxLine; ln++) {
        sptr_t lvl = [sci message:SCI_GETFOLDLEVEL wParam:(uptr_t)ln];
        if (!(lvl & SC_FOLDLEVELHEADERFLAG)) continue;
        sptr_t lvlNum = (lvl - SC_FOLDLEVELBASE) & SC_FOLDLEVELNUMBERMASK;
        if (lvlNum != level) continue;
        sptr_t expanded = [sci message:SCI_GETFOLDEXPANDED wParam:(uptr_t)ln];
        if (collapse && expanded)
            [sci message:SCI_FOLDCHILDREN wParam:(uptr_t)ln lParam:SC_FOLDACTION_CONTRACT];
        else if (!collapse && !expanded)
            [sci message:SCI_FOLDCHILDREN wParam:(uptr_t)ln lParam:SC_FOLDACTION_EXPAND];
    }
}

- (void)foldLevel1:(id)s   { [self _setFoldLevel:0 collapsed:YES]; }
- (void)foldLevel2:(id)s   { [self _setFoldLevel:1 collapsed:YES]; }
- (void)foldLevel3:(id)s   { [self _setFoldLevel:2 collapsed:YES]; }
- (void)foldLevel4:(id)s   { [self _setFoldLevel:3 collapsed:YES]; }
- (void)foldLevel5:(id)s   { [self _setFoldLevel:4 collapsed:YES]; }
- (void)foldLevel6:(id)s   { [self _setFoldLevel:5 collapsed:YES]; }
- (void)foldLevel7:(id)s   { [self _setFoldLevel:6 collapsed:YES]; }
- (void)foldLevel8:(id)s   { [self _setFoldLevel:7 collapsed:YES]; }

- (void)unfoldLevel1:(id)s { [self _setFoldLevel:0 collapsed:NO]; }
- (void)unfoldLevel2:(id)s { [self _setFoldLevel:1 collapsed:NO]; }
- (void)unfoldLevel3:(id)s { [self _setFoldLevel:2 collapsed:NO]; }
- (void)unfoldLevel4:(id)s { [self _setFoldLevel:3 collapsed:NO]; }
- (void)unfoldLevel5:(id)s { [self _setFoldLevel:4 collapsed:NO]; }
- (void)unfoldLevel6:(id)s { [self _setFoldLevel:5 collapsed:NO]; }
- (void)unfoldLevel7:(id)s { [self _setFoldLevel:6 collapsed:NO]; }
- (void)unfoldLevel8:(id)s { [self _setFoldLevel:7 collapsed:NO]; }

- (void)unfoldCurrentLevel:(id)sender {
    ScintillaView *sci = _scintillaView;
    sptr_t curLine = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
    [sci message:SCI_FOLDCHILDREN wParam:(uptr_t)curLine lParam:SC_FOLDACTION_EXPAND];
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Insert Blank Lines / Date-Time

- (void)insertBlankLineAbove:(id)sender {
    ScintillaView *sci = _scintillaView;
    sptr_t curLine = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
    sptr_t linePos = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)curLine];
    NSString *eol = self.eolName;
    NSString *eolStr = [eol isEqualToString:@"CRLF"] ? @"\r\n" : [eol isEqualToString:@"CR"] ? @"\r" : @"\n";
    [sci message:SCI_BEGINUNDOACTION];
    [sci message:SCI_INSERTTEXT wParam:(uptr_t)linePos lParam:(sptr_t)eolStr.UTF8String];
    [sci message:SCI_SETEMPTYSELECTION wParam:(uptr_t)linePos];
    [sci message:SCI_ENDUNDOACTION];
}

- (void)insertBlankLineBelow:(id)sender {
    ScintillaView *sci = _scintillaView;
    sptr_t curLine = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
    sptr_t lineEnd = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)curLine];
    NSString *eol = self.eolName;
    NSString *eolStr = [eol isEqualToString:@"CRLF"] ? @"\r\n" : [eol isEqualToString:@"CR"] ? @"\r" : @"\n";
    [sci message:SCI_BEGINUNDOACTION];
    [sci message:SCI_INSERTTEXT wParam:(uptr_t)lineEnd lParam:(sptr_t)eolStr.UTF8String];
    [sci message:SCI_SETEMPTYSELECTION wParam:(uptr_t)(lineEnd + (sptr_t)eolStr.length)];
    [sci message:SCI_ENDUNDOACTION];
}

- (void)insertDateTimeShort:(id)sender {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateStyle = NSDateFormatterShortStyle;
    fmt.timeStyle = NSDateFormatterShortStyle;
    NSString *s = [fmt stringFromDate:[NSDate date]];
    [self replaceSelectionWith:s];
}

- (void)insertDateTimeLong:(id)sender {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateStyle = NSDateFormatterLongStyle;
    fmt.timeStyle = NSDateFormatterLongStyle;
    NSString *s = [fmt stringFromDate:[NSDate date]];
    [self replaceSelectionWith:s];
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Case Conversion (Blend variants)

/// Proper Case (Blend): uppercase first letter of each word, leave rest unchanged.
- (void)convertToProperCaseBlend:(id)sender {
    NSString *sel = [self selectedText]; if (!sel) return;
    NSMutableString *result = [sel mutableCopy];
    BOOL prevWasAlnum = NO;
    for (NSUInteger i = 0; i < result.length; i++) {
        unichar c = [result characterAtIndex:i];
        if ([[NSCharacterSet letterCharacterSet] characterIsMember:c]) {
            if (!prevWasAlnum) {
                unichar up = [[[NSString stringWithCharacters:&c length:1] uppercaseString] characterAtIndex:0];
                [result replaceCharactersInRange:NSMakeRange(i, 1)
                                     withString:[NSString stringWithCharacters:&up length:1]];
            }
            prevWasAlnum = YES;
        } else {
            prevWasAlnum = [[NSCharacterSet alphanumericCharacterSet] characterIsMember:c];
        }
    }
    [self replaceSelectionWith:result];
}

/// Sentence case (Blend): uppercase first letter of each sentence, leave rest unchanged.
- (void)convertToSentenceCaseBlend:(id)sender {
    NSString *sel = [self selectedText]; if (!sel) return;
    NSMutableString *result = [sel mutableCopy];
    BOOL nextUpper = YES;
    for (NSUInteger i = 0; i < result.length; i++) {
        unichar c = [result characterAtIndex:i];
        if ([[NSCharacterSet letterCharacterSet] characterIsMember:c]) {
            if (nextUpper) {
                unichar up = [[[NSString stringWithCharacters:&c length:1] uppercaseString] characterAtIndex:0];
                [result replaceCharactersInRange:NSMakeRange(i, 1)
                                     withString:[NSString stringWithCharacters:&up length:1]];
                nextUpper = NO;
            }
        } else if (c == '.' || c == '!' || c == '?') {
            nextUpper = YES;
        }
    }
    [self replaceSelectionWith:result];
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Join Lines / Sort Extensions

- (void)joinLines:(id)sender {
    ScintillaView *sci = _scintillaView;
    sptr_t selStart = [sci message:SCI_GETSELECTIONSTART];
    sptr_t selEnd   = [sci message:SCI_GETSELECTIONEND];
    if (selStart == selEnd)
        [sci message:SCI_TARGETWHOLEDOCUMENT];
    else
        [sci message:SCI_TARGETFROMSELECTION];
    [sci message:SCI_LINESJOIN];
}

- (void)sortLinesRandomly:(id)sender {
    sptr_t s, e;
    NSMutableArray *lines = [self linesForSortingStartPos:&s endPos:&e];
    for (NSUInteger i = lines.count - 1; i > 0; i--) {
        NSUInteger j = arc4random_uniform((uint32_t)(i + 1));
        [lines exchangeObjectAtIndex:i withObjectAtIndex:j];
    }
    [self applySortedLines:lines startPos:s endPos:e];
}

- (void)sortLinesReverse:(id)sender {
    sptr_t s, e;
    NSMutableArray *lines = [self linesForSortingStartPos:&s endPos:&e];
    NSArray *reversed = lines.reverseObjectEnumerator.allObjects;
    [self applySortedLines:reversed startPos:s endPos:e];
}

- (void)sortLinesIntAsc:(id)sender {
    sptr_t s, e;
    NSMutableArray *lines = [self linesForSortingStartPos:&s endPos:&e];
    [lines sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        long long va = [a longLongValue];
        long long vb = [b longLongValue];
        return va < vb ? NSOrderedAscending : va > vb ? NSOrderedDescending : NSOrderedSame;
    }];
    [self applySortedLines:lines startPos:s endPos:e];
}

- (void)sortLinesIntDesc:(id)sender {
    sptr_t s, e;
    NSMutableArray *lines = [self linesForSortingStartPos:&s endPos:&e];
    [lines sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        long long va = [a longLongValue];
        long long vb = [b longLongValue];
        return va > vb ? NSOrderedAscending : va < vb ? NSOrderedDescending : NSOrderedSame;
    }];
    [self applySortedLines:lines startPos:s endPos:e];
}

- (void)sortLinesDecimalDotAsc:(id)sender {
    sptr_t s, e;
    NSMutableArray *lines = [self linesForSortingStartPos:&s endPos:&e];
    [lines sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        double va = a.doubleValue;
        double vb = b.doubleValue;
        return va < vb ? NSOrderedAscending : va > vb ? NSOrderedDescending : NSOrderedSame;
    }];
    [self applySortedLines:lines startPos:s endPos:e];
}

- (void)sortLinesDecimalDotDesc:(id)sender {
    sptr_t s, e;
    NSMutableArray *lines = [self linesForSortingStartPos:&s endPos:&e];
    [lines sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        double va = a.doubleValue;
        double vb = b.doubleValue;
        return va > vb ? NSOrderedAscending : va < vb ? NSOrderedDescending : NSOrderedSame;
    }];
    [self applySortedLines:lines startPos:s endPos:e];
}

- (void)sortLinesDecimalCommaAsc:(id)sender {
    sptr_t s, e;
    NSMutableArray *lines = [self linesForSortingStartPos:&s endPos:&e];
    NSLocale *commaLocale = [NSLocale localeWithLocaleIdentifier:@"fr_FR"]; // uses comma as decimal separator
    [lines sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        double va = [[NSDecimalNumber decimalNumberWithString:a locale:commaLocale] doubleValue];
        double vb = [[NSDecimalNumber decimalNumberWithString:b locale:commaLocale] doubleValue];
        return va < vb ? NSOrderedAscending : va > vb ? NSOrderedDescending : NSOrderedSame;
    }];
    [self applySortedLines:lines startPos:s endPos:e];
}

- (void)sortLinesDecimalCommaDesc:(id)sender {
    sptr_t s, e;
    NSMutableArray *lines = [self linesForSortingStartPos:&s endPos:&e];
    NSLocale *commaLocale = [NSLocale localeWithLocaleIdentifier:@"fr_FR"];
    [lines sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        double va = [[NSDecimalNumber decimalNumberWithString:a locale:commaLocale] doubleValue];
        double vb = [[NSDecimalNumber decimalNumberWithString:b locale:commaLocale] doubleValue];
        return va > vb ? NSOrderedAscending : va < vb ? NSOrderedDescending : NSOrderedSame;
    }];
    [self applySortedLines:lines startPos:s endPos:e];
}

- (void)removeConsecutiveDuplicateLines:(id)sender {
    sptr_t s, e;
    NSMutableArray *lines = [self linesForSortingStartPos:&s endPos:&e];
    NSMutableArray *result = [NSMutableArray array];
    NSString *prev = nil;
    for (NSString *line in lines) {
        if (![line isEqualToString:prev]) [result addObject:line];
        prev = line;
    }
    [self applySortedLines:result startPos:s endPos:e];
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Blank Operations

/// Helper: read the text of line `ln` (without EOL) as NSString, or nil if empty.
- (NSString *)_lineTextAt:(sptr_t)ln {
    ScintillaView *sci = _scintillaView;
    sptr_t start = [sci message:SCI_POSITIONFROMLINE    wParam:(uptr_t)ln];
    sptr_t end   = [sci message:SCI_GETLINEENDPOSITION  wParam:(uptr_t)ln];
    sptr_t len   = end - start;
    if (len <= 0) return @"";
    char *buf = (char *)calloc((size_t)(len + 1), 1);
    Sci_TextRangeFull tr;
    tr.chrg.cpMin = (Sci_Position)start;
    tr.chrg.cpMax = (Sci_Position)end;
    tr.lpstrText  = buf;
    [sci message:SCI_GETTEXTRANGEFULL wParam:0 lParam:(sptr_t)&tr];
    NSString *s = [NSString stringWithUTF8String:buf] ?: @"";
    free(buf);
    return s;
}

/// Helper: replace the content of line `ln` (without EOL) with `newText`.
- (void)_setLineText:(NSString *)newText atLine:(sptr_t)ln {
    ScintillaView *sci = _scintillaView;
    sptr_t start = [sci message:SCI_POSITIONFROMLINE    wParam:(uptr_t)ln];
    sptr_t end   = [sci message:SCI_GETLINEENDPOSITION  wParam:(uptr_t)ln];
    const char *utf8 = newText.UTF8String;
    [sci message:SCI_SETTARGETSTART wParam:(uptr_t)start];
    [sci message:SCI_SETTARGETEND   wParam:(uptr_t)end];
    [sci message:SCI_REPLACETARGET  wParam:(uptr_t)strlen(utf8) lParam:(sptr_t)utf8];
}

- (void)trimLeadingSpaces:(id)sender {
    ScintillaView *sci = _scintillaView;
    sptr_t firstLine, lastLine;
    [self _selectionLineRange:&firstLine last:&lastLine];
    [sci message:SCI_BEGINUNDOACTION];
    for (sptr_t ln = lastLine; ln >= firstLine; ln--) {
        NSString *orig = [self _lineTextAt:ln];
        NSString *trimmed = [orig stringByReplacingOccurrencesOfString:@"^[\\t ]+"
                                                            withString:@""
                                                               options:NSRegularExpressionSearch
                                                                 range:NSMakeRange(0, orig.length)];
        if (![trimmed isEqualToString:orig]) [self _setLineText:trimmed atLine:ln];
    }
    [sci message:SCI_ENDUNDOACTION];
}

- (void)trimLeadingAndTrailingSpaces:(id)sender {
    ScintillaView *sci = _scintillaView;
    sptr_t firstLine, lastLine;
    [self _selectionLineRange:&firstLine last:&lastLine];
    [sci message:SCI_BEGINUNDOACTION];
    for (sptr_t ln = lastLine; ln >= firstLine; ln--) {
        NSString *orig = [self _lineTextAt:ln];
        NSString *trimmed = [orig stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (![trimmed isEqualToString:orig]) [self _setLineText:trimmed atLine:ln];
    }
    [sci message:SCI_ENDUNDOACTION];
}

- (void)eolToSpace:(id)sender {
    // Replace all line endings with a single space (same as NPP's "EOL to Space")
    ScintillaView *sci = _scintillaView;
    sptr_t selStart = [sci message:SCI_GETSELECTIONSTART];
    sptr_t selEnd   = [sci message:SCI_GETSELECTIONEND];
    if (selStart == selEnd) {
        [sci message:SCI_TARGETWHOLEDOCUMENT];
    } else {
        [sci message:SCI_SETTARGETSTART wParam:(uptr_t)selStart];
        [sci message:SCI_SETTARGETEND   wParam:(uptr_t)selEnd];
    }
    [sci message:SCI_LINESJOIN];
}

- (void)trimBothAndEOLToSpace:(id)sender {
    [self trimLeadingAndTrailingSpaces:sender];
    [self eolToSpace:sender];
}

- (void)removeBlankLines:(id)sender {
    ScintillaView *sci = _scintillaView;
    sptr_t firstLine, lastLine;
    [self _selectionLineRange:&firstLine last:&lastLine];
    [sci message:SCI_BEGINUNDOACTION];
    // Iterate bottom-up so deletions don't invalidate indices
    for (sptr_t ln = lastLine; ln >= firstLine; ln--) {
        NSString *text = [self _lineTextAt:ln];
        NSString *stripped = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (stripped.length == 0) {
            sptr_t lineStart = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)ln];
            sptr_t nextStart;
            if (ln + 1 < [sci message:SCI_GETLINECOUNT])
                nextStart = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)(ln + 1)];
            else
                nextStart = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)ln];
            [sci message:SCI_SETTARGETSTART wParam:(uptr_t)lineStart];
            [sci message:SCI_SETTARGETEND   wParam:(uptr_t)nextStart];
            [sci message:SCI_REPLACETARGET  wParam:0 lParam:(sptr_t)""];
        }
    }
    [sci message:SCI_ENDUNDOACTION];
}

- (void)mergeBlankLines:(id)sender {
    ScintillaView *sci = _scintillaView;
    sptr_t firstLine, lastLine;
    [self _selectionLineRange:&firstLine last:&lastLine];
    [sci message:SCI_BEGINUNDOACTION];
    // Go bottom-up; delete blank line if the previous line is also blank
    for (sptr_t ln = lastLine; ln >= MAX(firstLine, 1); ln--) {
        NSString *cur  = [self _lineTextAt:ln];
        NSString *prev = [self _lineTextAt:ln - 1];
        BOOL curBlank  = [[cur  stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length] == 0;
        BOOL prevBlank = [[prev stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length] == 0;
        if (curBlank && prevBlank) {
            sptr_t lineStart = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)ln];
            sptr_t nextStart;
            if (ln + 1 < [sci message:SCI_GETLINECOUNT])
                nextStart = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)(ln + 1)];
            else
                nextStart = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)ln];
            [sci message:SCI_SETTARGETSTART wParam:(uptr_t)lineStart];
            [sci message:SCI_SETTARGETEND   wParam:(uptr_t)nextStart];
            [sci message:SCI_REPLACETARGET  wParam:0 lParam:(sptr_t)""];
        }
    }
    [sci message:SCI_ENDUNDOACTION];
}

- (void)tabsToSpaces:(id)sender {
    ScintillaView *sci = _scintillaView;
    sptr_t tabWidth = [sci message:SCI_GETTABWIDTH];
    if (tabWidth <= 0) tabWidth = 4;
    sptr_t firstLine, lastLine;
    [self _selectionLineRange:&firstLine last:&lastLine];
    NSString *spaces = [@"" stringByPaddingToLength:(NSUInteger)tabWidth withString:@" " startingAtIndex:0];
    [sci message:SCI_BEGINUNDOACTION];
    for (sptr_t ln = lastLine; ln >= firstLine; ln--) {
        NSString *orig = [self _lineTextAt:ln];
        if (![orig containsString:@"\t"]) continue;
        NSString *replaced = [orig stringByReplacingOccurrencesOfString:@"\t" withString:spaces];
        if (![replaced isEqualToString:orig]) [self _setLineText:replaced atLine:ln];
    }
    [sci message:SCI_ENDUNDOACTION];
}

- (void)spacesToTabsLeading:(id)sender {
    ScintillaView *sci = _scintillaView;
    sptr_t tabWidth = [sci message:SCI_GETTABWIDTH];
    if (tabWidth <= 0) tabWidth = 4;
    sptr_t firstLine, lastLine;
    [self _selectionLineRange:&firstLine last:&lastLine];
    [sci message:SCI_BEGINUNDOACTION];
    for (sptr_t ln = lastLine; ln >= firstLine; ln--) {
        NSString *orig = [self _lineTextAt:ln];
        // Count leading spaces
        NSUInteger i = 0;
        while (i < orig.length && [orig characterAtIndex:i] == ' ') i++;
        if (i < (NSUInteger)tabWidth) continue;
        NSUInteger tabs = i / (NSUInteger)tabWidth;
        NSUInteger rem  = i % (NSUInteger)tabWidth;
        NSMutableString *newLine = [NSMutableString string];
        for (NSUInteger t = 0; t < tabs; t++) [newLine appendString:@"\t"];
        for (NSUInteger r = 0; r < rem;  r++) [newLine appendString:@" "];
        [newLine appendString:[orig substringFromIndex:i]];
        if (![newLine isEqualToString:orig]) [self _setLineText:newLine atLine:ln];
    }
    [sci message:SCI_ENDUNDOACTION];
}

- (void)spacesToTabsAll:(id)sender {
    ScintillaView *sci = _scintillaView;
    sptr_t tabWidth = [sci message:SCI_GETTABWIDTH];
    if (tabWidth <= 0) tabWidth = 4;
    sptr_t firstLine, lastLine;
    [self _selectionLineRange:&firstLine last:&lastLine];
    NSString *tabStr = @"\t";
    NSString *spaceGroup = [@"" stringByPaddingToLength:(NSUInteger)tabWidth withString:@" " startingAtIndex:0];
    [sci message:SCI_BEGINUNDOACTION];
    for (sptr_t ln = lastLine; ln >= firstLine; ln--) {
        NSString *orig = [self _lineTextAt:ln];
        NSString *replaced = [orig stringByReplacingOccurrencesOfString:spaceGroup withString:tabStr];
        if (![replaced isEqualToString:orig]) [self _setLineText:replaced atLine:ln];
    }
    [sci message:SCI_ENDUNDOACTION];
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Read-Only

- (void)toggleReadOnly:(id)sender {
    ScintillaView *sci = _scintillaView;
    sptr_t isRO = [sci message:SCI_GETREADONLY];
    [sci message:SCI_SETREADONLY wParam:(uptr_t)(!isRO)];
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Go to Matching Brace / Select and Find

- (void)goToMatchingBrace:(id)sender {
    ScintillaView *sci = _scintillaView;
    sptr_t pos = [sci message:SCI_GETCURRENTPOS];
    // Try current position and one before for brace detection
    sptr_t match = [sci message:SCI_BRACEMATCH wParam:(uptr_t)pos lParam:0];
    if (match == INVALID_POSITION && pos > 0)
        match = [sci message:SCI_BRACEMATCH wParam:(uptr_t)(pos - 1) lParam:0];
    if (match != INVALID_POSITION)
        [sci message:SCI_SETEMPTYSELECTION wParam:(uptr_t)(match + 1)];
}

- (void)selectAndFindNext:(id)sender {
    ScintillaView *sci = _scintillaView;
    // If no selection, select the current word first
    sptr_t selStart = [sci message:SCI_GETSELECTIONSTART];
    sptr_t selEnd   = [sci message:SCI_GETSELECTIONEND];
    if (selStart == selEnd) {
        sptr_t pos   = [sci message:SCI_GETCURRENTPOS];
        sptr_t wStart = [sci message:SCI_WORDSTARTPOSITION wParam:(uptr_t)pos lParam:1];
        sptr_t wEnd   = [sci message:SCI_WORDENDPOSITION   wParam:(uptr_t)pos lParam:1];
        if (wEnd > wStart)
            [sci message:SCI_SETSEL wParam:(uptr_t)wStart lParam:wEnd];
    }
    NSString *word = [self selectedText];
    if (word.length)
        [self findNext:word matchCase:YES wholeWord:NO wrap:YES];
}

- (void)selectAndFindPrevious:(id)sender {
    ScintillaView *sci = _scintillaView;
    sptr_t selStart = [sci message:SCI_GETSELECTIONSTART];
    sptr_t selEnd   = [sci message:SCI_GETSELECTIONEND];
    if (selStart == selEnd) {
        sptr_t pos   = [sci message:SCI_GETCURRENTPOS];
        sptr_t wStart = [sci message:SCI_WORDSTARTPOSITION wParam:(uptr_t)pos lParam:1];
        sptr_t wEnd   = [sci message:SCI_WORDENDPOSITION   wParam:(uptr_t)pos lParam:1];
        if (wEnd > wStart)
            [sci message:SCI_SETSEL wParam:(uptr_t)wStart lParam:wEnd];
    }
    NSString *word = [self selectedText];
    if (word.length)
        [self findPrev:word matchCase:YES wholeWord:NO wrap:YES];
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Bookmark Line Operations

/// Returns indices of all lines that have (or don't have) the bookmark marker.
- (NSArray<NSNumber *> *)_bookmarkedLines:(BOOL)bookmarked {
    ScintillaView *sci = _scintillaView;
    NSMutableArray *result = [NSMutableArray array];
    sptr_t lineCount = [sci message:SCI_GETLINECOUNT];
    sptr_t mask = (1 << kBookmarkMarker);
    for (sptr_t ln = 0; ln < lineCount; ln++) {
        sptr_t markers = [sci message:SCI_MARKERGET wParam:(uptr_t)ln];
        if (bookmarked ? (markers & mask) : !(markers & mask))
            [result addObject:@(ln)];
    }
    return result;
}

/// Collect text of a list of lines (by index) joined with the document EOL.
- (NSString *)_textOfLines:(NSArray<NSNumber *> *)lineIndices {
    NSString *eol = self.eolName;
    NSString *sep = [eol isEqualToString:@"CRLF"] ? @"\r\n" : [eol isEqualToString:@"CR"] ? @"\r" : @"\n";
    NSMutableArray *parts = [NSMutableArray array];
    for (NSNumber *n in lineIndices)
        [parts addObject:[self _lineTextAt:n.integerValue]];
    return [parts componentsJoinedByString:sep];
}

- (void)cutBookmarkedLines:(id)sender {
    [self copyBookmarkedLines:sender];
    [self removeBookmarkedLines:sender];
}

- (void)copyBookmarkedLines:(id)sender {
    NSArray *bLines = [self _bookmarkedLines:YES];
    if (!bLines.count) return;
    NSString *text = [self _textOfLines:bLines];
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:text forType:NSPasteboardTypeString];
}

- (void)removeBookmarkedLines:(id)sender {
    ScintillaView *sci = _scintillaView;
    NSArray *bLines = [self _bookmarkedLines:YES];
    if (!bLines.count) return;
    [sci message:SCI_BEGINUNDOACTION];
    // Delete bottom-up so indices stay valid
    for (NSNumber *n in bLines.reverseObjectEnumerator) {
        sptr_t ln = n.integerValue;
        sptr_t lineStart = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)ln];
        sptr_t nextStart;
        if (ln + 1 < [sci message:SCI_GETLINECOUNT])
            nextStart = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)(ln + 1)];
        else
            nextStart = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)ln];
        [sci message:SCI_SETTARGETSTART wParam:(uptr_t)lineStart];
        [sci message:SCI_SETTARGETEND   wParam:(uptr_t)nextStart];
        [sci message:SCI_REPLACETARGET  wParam:0 lParam:(sptr_t)""];
    }
    [sci message:SCI_ENDUNDOACTION];
}

- (void)removeNonBookmarkedLines:(id)sender {
    ScintillaView *sci = _scintillaView;
    NSArray *bLines = [self _bookmarkedLines:NO];
    if (!bLines.count) return;
    [sci message:SCI_BEGINUNDOACTION];
    for (NSNumber *n in bLines.reverseObjectEnumerator) {
        sptr_t ln = n.integerValue;
        sptr_t lineStart = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)ln];
        sptr_t nextStart;
        if (ln + 1 < [sci message:SCI_GETLINECOUNT])
            nextStart = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)(ln + 1)];
        else
            nextStart = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)ln];
        [sci message:SCI_SETTARGETSTART wParam:(uptr_t)lineStart];
        [sci message:SCI_SETTARGETEND   wParam:(uptr_t)nextStart];
        [sci message:SCI_REPLACETARGET  wParam:0 lParam:(sptr_t)""];
    }
    [sci message:SCI_ENDUNDOACTION];
}

- (void)inverseBookmark:(id)sender {
    ScintillaView *sci = _scintillaView;
    sptr_t lineCount = [sci message:SCI_GETLINECOUNT];
    sptr_t mask = (1 << kBookmarkMarker);
    for (sptr_t ln = 0; ln < lineCount; ln++) {
        sptr_t markers = [sci message:SCI_MARKERGET wParam:(uptr_t)ln];
        if (markers & mask)
            [sci message:SCI_MARKERDELETE wParam:(uptr_t)ln lParam:kBookmarkMarker];
        else
            [sci message:SCI_MARKERADD    wParam:(uptr_t)ln lParam:kBookmarkMarker];
    }
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Column Mode / Select In Braces

/// Toggle rectangular (column) selection mode on/off.
- (void)columnMode:(id)sender {
    ScintillaView *sci = _scintillaView;
    sptr_t mode = [sci message:SCI_GETSELECTIONMODE];
    [sci message:SCI_SETSELECTIONMODE
          wParam:(mode == SC_SEL_RECTANGLE ? SC_SEL_STREAM : SC_SEL_RECTANGLE)];
}

/// Select all text between the brace/bracket/paren pair surrounding the cursor.
- (void)selectAllInBraces:(id)sender {
    ScintillaView *sci = _scintillaView;
    sptr_t pos = [sci message:SCI_GETCURRENTPOS];
    sptr_t match = INVALID_POSITION;
    sptr_t bracePos = INVALID_POSITION;
    // Try the character at pos and one before
    for (sptr_t tryPos = pos; tryPos >= MAX(0, pos - 1) && match == INVALID_POSITION; tryPos--) {
        sptr_t ch = [sci message:SCI_GETCHARAT wParam:(uptr_t)tryPos];
        if (ch == '(' || ch == '[' || ch == '{' || ch == ')' || ch == ']' || ch == '}') {
            match = [sci message:SCI_BRACEMATCH wParam:(uptr_t)tryPos lParam:0];
            if (match != INVALID_POSITION) bracePos = tryPos;
        }
    }
    if (match == INVALID_POSITION) return;
    sptr_t selStart = MIN(bracePos, match);
    sptr_t selEnd   = MAX(bracePos, match) + 1;
    [sci message:SCI_SETSEL wParam:(uptr_t)selStart lParam:selEnd];
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Base64 Encode / Decode

- (void)base64Encode:(id)sender {
    NSString *sel = [self selectedText]; if (!sel) return;
    NSData   *data    = [sel dataUsingEncoding:NSUTF8StringEncoding];
    NSString *encoded = [data base64EncodedStringWithOptions:0];
    [self replaceSelectionWith:encoded];
}

- (void)base64Decode:(id)sender {
    NSString *sel = [self selectedText]; if (!sel) return;
    NSData   *data = [[NSData alloc] initWithBase64EncodedString:sel
                      options:NSDataBase64DecodingIgnoreUnknownCharacters];
    if (!data) return;
    NSString *decoded = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!decoded) return;
    [self replaceSelectionWith:decoded];
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - ASCII / Hex Conversion

- (void)asciiToHex:(id)sender {
    NSString *sel = [self selectedText]; if (!sel) return;
    NSData *data = [sel dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return;
    const unsigned char *bytes = (const unsigned char *)data.bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:data.length * 3];
    for (NSUInteger i = 0; i < data.length; i++) {
        if (i > 0) [hex appendString:@" "];
        [hex appendFormat:@"%02X", bytes[i]];
    }
    [self replaceSelectionWith:hex];
}

- (void)hexToAscii:(id)sender {
    NSString *sel = [self selectedText]; if (!sel) return;
    // Split on whitespace / commas; parse each token as a hex byte
    NSArray<NSString *> *parts = [sel componentsSeparatedByCharactersInSet:
        [NSCharacterSet characterSetWithCharactersInString:@" ,\t\r\n"]];
    NSMutableData *data = [NSMutableData data];
    for (NSString *part in parts) {
        if (!part.length) continue;
        unsigned int byte = 0;
        if ([[NSScanner scannerWithString:part] scanHexInt:&byte]) {
            unsigned char b = (unsigned char)(byte & 0xFF);
            [data appendBytes:&b length:1];
        }
    }
    if (!data.length) { NSBeep(); return; }
    NSString *ascii = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                   ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    if (!ascii) { NSBeep(); return; }
    [self replaceSelectionWith:ascii];
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Auto-Completion Actions

- (void)triggerWordCompletion:(id)sender {
    // Force-trigger the document-word autocomplete (same as updateAutoComplete but min prefix = 1)
    ScintillaView *sci = _scintillaView;
    sptr_t pos       = [sci message:SCI_GETCURRENTPOS];
    sptr_t wordStart = [sci message:SCI_WORDSTARTPOSITION wParam:(uptr_t)pos lParam:1];
    NSInteger prefixLen = pos - wordStart;
    if (prefixLen < 1) { NSBeep(); return; }

    NSString *docText = sci.string;
    if (!docText || docText.length > 300000) { NSBeep(); return; }
    NSString *prefix = [docText substringWithRange:NSMakeRange((NSUInteger)wordStart,
                                                                (NSUInteger)prefixLen)];
    NSMutableCharacterSet *wordCS = [[NSCharacterSet alphanumericCharacterSet] mutableCopy];
    [wordCS addCharactersInString:@"_"];
    NSMutableSet<NSString *> *wordSet = [NSMutableSet set];
    for (NSString *word in [docText componentsSeparatedByCharactersInSet:wordCS.invertedSet]) {
        if (word.length > (NSUInteger)prefixLen && [word hasPrefix:prefix])
            [wordSet addObject:word];
    }
    [wordSet removeObject:prefix];
    if (!wordSet.count) { NSBeep(); return; }
    NSString *wordList = [[wordSet.allObjects
        sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]
        componentsJoinedByString:@" "];
    [sci message:SCI_AUTOCSHOW wParam:(uptr_t)prefixLen lParam:(sptr_t)wordList.UTF8String];
}

- (void)triggerFunctionParametersHint:(id)sender {
    // Show a calltip for the function name preceding the nearest open paren
    ScintillaView *sci = _scintillaView;
    sptr_t pos = [sci message:SCI_GETCURRENTPOS];
    // Scan back for the most recent '('
    sptr_t scan = pos - 1;
    while (scan >= 0 && (int)[sci message:SCI_GETCHARAT wParam:(uptr_t)scan] != '(') scan--;
    if (scan < 0) { NSBeep(); return; }
    sptr_t nameEnd   = scan;
    sptr_t nameStart = [sci message:SCI_WORDSTARTPOSITION wParam:(uptr_t)nameEnd lParam:1];
    if (nameStart >= nameEnd) { NSBeep(); return; }
    sptr_t nameLen = nameEnd - nameStart;
    char *buf = (char *)calloc((size_t)(nameLen + 1), 1);
    Sci_TextRangeFull tr = { {(Sci_Position)nameStart, (Sci_Position)nameEnd}, buf };
    [sci message:SCI_GETTEXTRANGEFULL wParam:0 lParam:(sptr_t)&tr];
    NSString *funcName = [NSString stringWithUTF8String:buf] ?: @"";
    free(buf);
    if (!funcName.length) { NSBeep(); return; }
    NSString *tip = [NSString stringWithFormat:@"%@( ... )", funcName];
    [sci message:SCI_CALLTIPSHOW wParam:(uptr_t)nameStart lParam:(sptr_t)tip.UTF8String];
}

- (void)triggerFunctionCompletion:(id)sender {
    // Show autocomplete using words already in the document (approximates function-name completion).
    // A full implementation would load per-language API files; this provides useful behaviour without them.
    [self triggerWordCompletion:sender];
}

- (void)showFunctionParametersPreviousHint:(id)sender {
    // Navigate to the previous enclosing function call and show its calltip.
    ScintillaView *sci = _scintillaView;
    if ([sci message:SCI_CALLTIPACTIVE]) [sci message:SCI_CALLTIPCANCEL];
    sptr_t pos = [sci message:SCI_GETCURRENTPOS];
    int depth = 0;
    sptr_t scan = pos - 1;
    while (scan > 0) {
        char ch = (char)[sci message:SCI_GETCHARAT wParam:(uptr_t)scan];
        if (ch == ')') { depth++; scan--; continue; }
        if (ch == '(' && depth > 0) { depth--; scan--; continue; }
        if (ch == '(') {
            // Found enclosing '(' — move cursor just inside and show calltip
            [sci message:SCI_GOTOPOS wParam:(uptr_t)(scan + 1)];
            [self triggerFunctionParametersHint:sender];
            return;
        }
        scan--;
    }
    NSBeep();
}

- (void)showFunctionParametersNextHint:(id)sender {
    // Navigate forward to the next function call '(' and show its calltip.
    ScintillaView *sci = _scintillaView;
    if ([sci message:SCI_CALLTIPACTIVE]) [sci message:SCI_CALLTIPCANCEL];
    sptr_t pos = [sci message:SCI_GETCURRENTPOS];
    sptr_t len = [sci message:SCI_GETLENGTH];
    sptr_t scan = pos;
    while (scan < len) {
        char ch = (char)[sci message:SCI_GETCHARAT wParam:(uptr_t)scan];
        if (ch == '(') {
            [sci message:SCI_GOTOPOS wParam:(uptr_t)(scan + 1)];
            [self triggerFunctionParametersHint:sender];
            return;
        }
        scan++;
    }
    NSBeep();
}

- (void)triggerPathCompletion:(id)sender {
    // Complete a filesystem path at the cursor using NSFileManager.
    ScintillaView *sci = _scintillaView;
    sptr_t pos = [sci message:SCI_GETCURRENTPOS];
    sptr_t lineNum   = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)pos];
    sptr_t lineStart = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)lineNum];
    sptr_t lineLen   = pos - lineStart;
    if (lineLen <= 0) { NSBeep(); return; }

    char *lineBuf = (char *)malloc((size_t)lineLen + 1);
    if (!lineBuf) { NSBeep(); return; }
    Sci_TextRangeFull tr = { {(Sci_Position)lineStart, (Sci_Position)pos}, lineBuf };
    [sci message:SCI_GETTEXTRANGEFULL wParam:0 lParam:(sptr_t)&tr];
    lineBuf[lineLen] = '\0';
    NSString *lineText = [NSString stringWithUTF8String:lineBuf] ?: @"";
    free(lineBuf);

    // Find start of path: last whitespace, quote, comma, equals, or open-paren
    NSCharacterSet *delimiters = [NSCharacterSet characterSetWithCharactersInString:@" \t\"'=,;("];
    NSRange delimRange = [lineText rangeOfCharacterFromSet:delimiters options:NSBackwardsSearch];
    NSString *pathPrefix = (delimRange.location == NSNotFound)
        ? lineText
        : [lineText substringFromIndex:delimRange.location + 1];
    if (!pathPrefix.length || pathPrefix.length > 1024) { NSBeep(); return; }

    NSString *dir, *filePrefix;
    if ([pathPrefix hasSuffix:@"/"]) {
        dir        = pathPrefix;
        filePrefix = @"";
    } else {
        dir        = [pathPrefix stringByDeletingLastPathComponent];
        filePrefix = [pathPrefix lastPathComponent];
        if (!dir.length) dir = @".";
    }

    NSArray<NSString *> *contents = [[NSFileManager defaultManager]
        contentsOfDirectoryAtPath:dir error:nil];
    if (!contents.count) { NSBeep(); return; }

    NSMutableArray<NSString *> *matches = [NSMutableArray array];
    for (NSString *name in contents) {
        if (filePrefix.length && ![name.lowercaseString hasPrefix:filePrefix.lowercaseString]) continue;
        BOOL isDir = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:[dir stringByAppendingPathComponent:name]
                                             isDirectory:&isDir];
        [matches addObject:isDir ? [name stringByAppendingString:@"/"] : name];
    }
    if (!matches.count) { NSBeep(); return; }
    [matches sortUsingSelector:@selector(caseInsensitiveCompare:)];
    NSString *wordList = [matches componentsJoinedByString:@" "];
    [sci message:SCI_AUTOCSHOW wParam:(uptr_t)filePrefix.length lParam:(sptr_t)wordList.UTF8String];
}

- (void)finishOrSelectAutocompleteItem:(id)sender {
    ScintillaView *sci = _scintillaView;
    if ([sci message:SCI_AUTOCACTIVE])
        [sci message:SCI_AUTOCCOMPLETE];
    else if ([sci message:SCI_CALLTIPACTIVE])
        [sci message:SCI_CALLTIPCANCEL];
    else
        NSBeep();
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Cryptographic Hashes

/// Compute a hex-digest hash of `data` using the given algorithm name (MD5, SHA-1, SHA-256, SHA-512).
+ (nullable NSString *)hexHashForAlgorithm:(NSString *)algo data:(NSData *)data {
    const void *bytes = data.bytes;
    CC_LONG len = (CC_LONG)data.length;
    if ([algo isEqualToString:@"MD5"]) {
        unsigned char d[CC_MD5_DIGEST_LENGTH];
        CC_MD5(bytes, len, d);
        NSMutableString *s = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
        for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) [s appendFormat:@"%02x", d[i]];
        return s;
    } else if ([algo isEqualToString:@"SHA-1"]) {
        unsigned char d[CC_SHA1_DIGEST_LENGTH];
        CC_SHA1(bytes, len, d);
        NSMutableString *s = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
        for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) [s appendFormat:@"%02x", d[i]];
        return s;
    } else if ([algo isEqualToString:@"SHA-256"]) {
        unsigned char d[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256(bytes, len, d);
        NSMutableString *s = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
        for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [s appendFormat:@"%02x", d[i]];
        return s;
    } else if ([algo isEqualToString:@"SHA-512"]) {
        unsigned char d[CC_SHA512_DIGEST_LENGTH];
        CC_SHA512(bytes, len, d);
        NSMutableString *s = [NSMutableString stringWithCapacity:CC_SHA512_DIGEST_LENGTH * 2];
        for (int i = 0; i < CC_SHA512_DIGEST_LENGTH; i++) [s appendFormat:@"%02x", d[i]];
        return s;
    }
    return nil;
}

/// Insert hash of the selected text (or whole document if no selection) at the cursor.
- (void)generateHashForAlgorithm:(NSString *)algo {
    NSString *text = [self selectedText];
    BOOL hadSelection = (text != nil);
    if (!text) {
        // Hash entire document
        sptr_t docLen = [_scintillaView message:SCI_GETLENGTH];
        char *buf = (char *)calloc((size_t)docLen + 1, 1);
        [_scintillaView message:SCI_GETTEXT wParam:(uptr_t)(docLen + 1) lParam:(sptr_t)buf];
        text = [NSString stringWithUTF8String:buf] ?: @"";
        free(buf);
    }
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    NSString *hash = [EditorView hexHashForAlgorithm:algo data:data];
    if (!hash) return;
    if (hadSelection)
        [self replaceSelectionWith:hash];
    else
        [_scintillaView message:SCI_APPENDTEXT
                         wParam:(uptr_t)strlen(hash.UTF8String)
                         lParam:(sptr_t)hash.UTF8String];
}

/// Copy hash of the selected text (or whole document) to the clipboard.
- (void)copyHashForAlgorithm:(NSString *)algo {
    NSString *text = [self selectedText];
    if (!text) {
        sptr_t docLen = [_scintillaView message:SCI_GETLENGTH];
        char *buf = (char *)calloc((size_t)docLen + 1, 1);
        [_scintillaView message:SCI_GETTEXT wParam:(uptr_t)(docLen + 1) lParam:(sptr_t)buf];
        text = [NSString stringWithUTF8String:buf] ?: @"";
        free(buf);
    }
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    NSString *hash = [EditorView hexHashForAlgorithm:algo data:data];
    if (!hash) return;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:hash forType:NSPasteboardTypeString];
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Column Editor

- (NSInteger)columnEditorLineCount {
    ScintillaView *sci = _scintillaView;
    sptr_t selStart = [sci message:SCI_GETSELECTIONSTART];
    sptr_t selEnd   = [sci message:SCI_GETSELECTIONEND];
    sptr_t line1 = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)selStart];
    sptr_t line2 = (selStart == selEnd)
        ? [sci message:SCI_GETLINECOUNT] - 1
        : [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)selEnd];
    return (NSInteger)MAX(1, line2 - line1 + 1);
}

- (void)columnInsertStrings:(NSArray<NSString *> *)strings {
    if (!strings.count) return;
    ScintillaView *sci = _scintillaView;
    sptr_t selStart = [sci message:SCI_GETSELECTIONSTART];
    sptr_t selEnd   = [sci message:SCI_GETSELECTIONEND];
    sptr_t line1    = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)selStart];
    sptr_t line2    = (selStart == selEnd)
        ? [sci message:SCI_GETLINECOUNT] - 1
        : [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)selEnd];
    sptr_t col      = [sci message:SCI_GETCOLUMN wParam:(uptr_t)selStart];

    [sci message:SCI_BEGINUNDOACTION];
    for (sptr_t ln = line2; ln >= line1; ln--) {
        NSInteger strIdx = (NSInteger)(ln - line1);
        if (strIdx >= (NSInteger)strings.count) strIdx = (NSInteger)strings.count - 1;
        NSString *text   = strings[strIdx];
        const char *utf8 = text.UTF8String;
        if (!utf8) continue;
        sptr_t pos       = [sci message:SCI_FINDCOLUMN    wParam:(uptr_t)ln lParam:col];
        sptr_t lineEnd   = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)ln];
        sptr_t actualCol = [sci message:SCI_GETCOLUMN wParam:(uptr_t)pos];
        if (actualCol < col && pos >= lineEnd) {
            NSMutableString *pad = [NSMutableString string];
            for (sptr_t sp = actualCol; sp < col; sp++) [pad appendString:@" "];
            [sci message:SCI_INSERTTEXT wParam:(uptr_t)pos lParam:(sptr_t)pad.UTF8String];
            pos += (sptr_t)pad.length;
        }
        [sci message:SCI_INSERTTEXT wParam:(uptr_t)pos lParam:(sptr_t)utf8];
    }
    [sci message:SCI_ENDUNDOACTION];
}

/// Column insert: insert `text` at the caret column on every line of the current
/// rectangular (or multi-line stream) selection (or to end of document if nothing selected).
- (void)columnInsertText:(NSString *)text {
    if (!text.length) return;
    ScintillaView *sci = _scintillaView;
    sptr_t selStart = [sci message:SCI_GETSELECTIONSTART];
    sptr_t selEnd   = [sci message:SCI_GETSELECTIONEND];
    sptr_t line1    = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)selStart];
    // When nothing is selected, extend to end of document
    sptr_t line2    = (selStart == selEnd)
        ? [sci message:SCI_GETLINECOUNT] - 1
        : [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)selEnd];
    // Column to insert at = column of the anchor (start of selection)
    sptr_t col = [sci message:SCI_GETCOLUMN wParam:(uptr_t)selStart];

    const char *utf8 = text.UTF8String;
    [sci message:SCI_BEGINUNDOACTION];
    // Insert from bottom to top so earlier positions aren't shifted
    for (sptr_t ln = line2; ln >= line1; ln--) {
        // SCI_FINDCOLUMN returns the closest position for this column (handles tabs)
        sptr_t pos = [sci message:SCI_FINDCOLUMN wParam:(uptr_t)ln lParam:col];
        sptr_t lineEnd = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)ln];
        // Pad with spaces if line is shorter than the target column
        sptr_t actualCol = [sci message:SCI_GETCOLUMN wParam:(uptr_t)pos];
        if (actualCol < col && pos >= lineEnd) {
            NSMutableString *pad = [NSMutableString string];
            for (sptr_t sp = actualCol; sp < col; sp++) [pad appendString:@" "];
            [sci message:SCI_INSERTTEXT wParam:(uptr_t)pos lParam:(sptr_t)pad.UTF8String];
            pos += (sptr_t)pad.length;
        }
        [sci message:SCI_INSERTTEXT wParam:(uptr_t)pos lParam:(sptr_t)utf8];
    }
    [sci message:SCI_ENDUNDOACTION];
}

- (void)columnInsertNumbersFrom:(long long)startVal step:(long long)step format:(NSString *)fmt {
    ScintillaView *sci = _scintillaView;
    sptr_t selStart = [sci message:SCI_GETSELECTIONSTART];
    sptr_t selEnd   = [sci message:SCI_GETSELECTIONEND];
    sptr_t line1    = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)selStart];
    sptr_t line2    = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)selEnd];
    sptr_t col      = [sci message:SCI_GETCOLUMN wParam:(uptr_t)selStart];
    NSString *fmtStr = fmt.length ? fmt : @"%lld";

    [sci message:SCI_BEGINUNDOACTION];
    long long val = startVal + step * (line2 - line1); // insert bottom-up
    for (sptr_t ln = line2; ln >= line1; ln--, val -= step) {
        NSString *numStr = [NSString stringWithFormat:fmtStr, val];
        const char *utf8 = numStr.UTF8String;
        sptr_t pos     = [sci message:SCI_FINDCOLUMN    wParam:(uptr_t)ln lParam:col];
        sptr_t lineEnd = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)ln];
        sptr_t actualCol = [sci message:SCI_GETCOLUMN wParam:(uptr_t)pos];
        if (actualCol < col && pos >= lineEnd) {
            NSMutableString *pad = [NSMutableString string];
            for (sptr_t sp = actualCol; sp < col; sp++) [pad appendString:@" "];
            [sci message:SCI_INSERTTEXT wParam:(uptr_t)pos lParam:(sptr_t)pad.UTF8String];
            pos += (sptr_t)pad.length;
        }
        [sci message:SCI_INSERTTEXT wParam:(uptr_t)pos lParam:(sptr_t)utf8];
    }
    [sci message:SCI_ENDUNDOACTION];
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Mark Text (styles 1-5)

- (void)markStyle:(NSInteger)style allOccurrencesOf:(NSString *)text matchCase:(BOOL)mc wholeWord:(BOOL)ww {
    if (style < 1 || style > 5 || !text.length) return;
    ScintillaView *sci = _scintillaView;
    int ind = kMarkInds[style - 1];
    sptr_t docLen = [sci message:SCI_GETLENGTH];

    [sci message:SCI_SETINDICATORCURRENT wParam:(uptr_t)ind];
    [sci message:SCI_INDICATORCLEARRANGE wParam:0 lParam:docLen];

    const char *needle = text.UTF8String;
    if (!needle || !*needle) return;
    int flags = 0;
    if (mc) flags |= SCFIND_MATCHCASE;
    if (ww) flags |= SCFIND_WHOLEWORD;
    [sci message:SCI_SETSEARCHFLAGS wParam:(uptr_t)flags];

    sptr_t pos = 0;
    while (pos < docLen) {
        [sci message:SCI_SETTARGETRANGE wParam:(uptr_t)pos lParam:docLen];
        sptr_t found = [sci message:SCI_SEARCHINTARGET wParam:strlen(needle) lParam:(sptr_t)needle];
        if (found < 0) break;
        sptr_t end = [sci message:SCI_GETTARGETEND];
        [sci message:SCI_INDICATORFILLRANGE wParam:(uptr_t)found lParam:end - found];
        pos = end > found ? end : found + 1;
    }
}

- (void)markStyleSelection:(NSInteger)style {
    if (style < 1 || style > 5) return;
    ScintillaView *sci = _scintillaView;
    sptr_t sel0 = [sci message:SCI_GETSELECTIONSTART];
    sptr_t sel1 = [sci message:SCI_GETSELECTIONEND];
    if (sel0 == sel1) return;
    [sci message:SCI_SETINDICATORCURRENT wParam:(uptr_t)kMarkInds[style - 1]];
    [sci message:SCI_INDICATORFILLRANGE  wParam:(uptr_t)sel0 lParam:sel1 - sel0];
}

- (void)clearMarkStyle:(NSInteger)style {
    if (style < 1 || style > 5) return;
    ScintillaView *sci = _scintillaView;
    [sci message:SCI_SETINDICATORCURRENT wParam:(uptr_t)kMarkInds[style - 1]];
    [sci message:SCI_INDICATORCLEARRANGE wParam:0 lParam:[sci message:SCI_GETLENGTH]];
}

- (void)clearAllMarkStyles {
    for (NSInteger i = 1; i <= 5; i++) [self clearMarkStyle:i];
}

- (void)jumpToNextMark:(NSInteger)dir {
    ScintillaView *sci = _scintillaView;
    sptr_t caretPos = [sci message:SCI_GETCURRENTPOS];
    sptr_t docLen   = [sci message:SCI_GETLENGTH];
    sptr_t best = -1;

    if (dir > 0) {
        sptr_t from = caretPos + 1;
        for (int i = 0; i < 5; i++) {
            sptr_t p = [sci message:kSCI_IndicatorNext wParam:(uptr_t)kMarkInds[i] lParam:from];
            if (p >= 0 && (best < 0 || p < best)) best = p;
        }
        if (best < 0) { // wrap
            for (int i = 0; i < 5; i++) {
                sptr_t p = [sci message:kSCI_IndicatorNext wParam:(uptr_t)kMarkInds[i] lParam:0];
                if (p >= 0 && (best < 0 || p < best)) best = p;
            }
        }
    } else {
        sptr_t from = caretPos > 0 ? caretPos - 1 : 0;
        for (int i = 0; i < 5; i++) {
            sptr_t p = [sci message:kSCI_IndicatorPrevious wParam:(uptr_t)kMarkInds[i] lParam:from];
            if (p >= 0 && (best < 0 || p > best)) best = p;
        }
        if (best < 0) { // wrap
            for (int i = 0; i < 5; i++) {
                sptr_t p = [sci message:kSCI_IndicatorPrevious wParam:(uptr_t)kMarkInds[i] lParam:docLen];
                if (p >= 0 && (best < 0 || p > best)) best = p;
            }
        }
    }
    if (best >= 0) {
        [sci message:SCI_GOTOPOS wParam:(uptr_t)best];
        [sci message:SCI_SCROLLCARET];
    }
}

- (void)copyTextWithMarkStyle:(NSInteger)style {
    if (style < 1 || style > 5) return;
    ScintillaView *sci = _scintillaView;
    int ind = kMarkInds[style - 1];
    sptr_t docLen = [sci message:SCI_GETLENGTH];
    char *buf = (char *)calloc((size_t)docLen + 1, 1);
    [sci message:SCI_GETTEXT wParam:(uptr_t)(docLen + 1) lParam:(sptr_t)buf];

    NSMutableString *result = [NSMutableString string];
    sptr_t pos = 0;
    while (pos < docLen) {
        sptr_t start = [sci message:kSCI_IndicatorNext wParam:(uptr_t)ind lParam:pos];
        if (start < 0 || start >= docLen) break;
        sptr_t end = [sci message:kSCI_IndicatorEnd  wParam:(uptr_t)ind lParam:start];
        if (end <= start) { pos = start + 1; continue; }
        NSString *chunk = [[NSString alloc] initWithBytes:buf + start
                                                   length:(NSUInteger)(end - start)
                                                 encoding:NSUTF8StringEncoding];
        if (chunk) {
            if (result.length) [result appendString:@"\n"];
            [result appendString:chunk];
        }
        pos = end;
    }
    free(buf);
    if (result.length) {
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        [pb clearContents];
        [pb setString:result forType:NSPasteboardTypeString];
    }
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Paste to Bookmarked Lines

- (void)pasteToBookmarkedLines:(id)sender {
    NSString *clipText = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
    if (!clipText) return;
    ScintillaView *sci = _scintillaView;
    sptr_t lineCount = [sci message:SCI_GETLINECOUNT];

    NSMutableArray<NSNumber *> *lines = [NSMutableArray array];
    for (sptr_t ln = 0; ln < lineCount; ln++) {
        if ([sci message:SCI_MARKERGET wParam:(uptr_t)ln] & (1 << kBookmarkMarker))
            [lines addObject:@(ln)];
    }
    if (!lines.count) return;

    const char *repl = clipText.UTF8String;
    NSUInteger replLen = strlen(repl);
    [sci message:SCI_BEGINUNDOACTION];
    // Process from end to preserve earlier line positions.
    for (NSInteger i = (NSInteger)lines.count - 1; i >= 0; i--) {
        sptr_t ln        = (sptr_t)[lines[i] integerValue];
        sptr_t lineStart = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)ln];
        sptr_t lineEnd   = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)ln];
        [sci message:SCI_SETTARGETRANGE wParam:(uptr_t)lineStart lParam:lineEnd];
        [sci message:SCI_REPLACETARGET  wParam:(uptr_t)replLen lParam:(sptr_t)repl];
    }
    [sci message:SCI_ENDUNDOACTION];
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - View Symbol Toggles

- (void)toggleWrapSymbol:(id)sender {
    ScintillaView *sci = _scintillaView;
    sptr_t flags = [sci message:SCI_GETWRAPVISUALFLAGS];
    [sci message:SCI_SETWRAPVISUALFLAGS wParam:(uptr_t)(flags ? SC_WRAPVISUALFLAG_NONE : SC_WRAPVISUALFLAG_END)];
}

- (void)toggleHideLineMarks:(id)sender {
    ScintillaView *sci = _scintillaView;
    sptr_t w = [sci message:SCI_GETMARGINWIDTHN wParam:1];
    [sci message:SCI_SETMARGINWIDTHN wParam:1 lParam:w > 0 ? 0 : 16];
}

- (void)hideLinesInSelection:(id)sender {
    ScintillaView *sci = _scintillaView;
    sptr_t startLine = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETSELECTIONSTART]];
    sptr_t endLine   = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETSELECTIONEND]];
    if (startLine <= endLine)
        [sci message:SCI_HIDELINES wParam:(uptr_t)startLine lParam:endLine];
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Base64 URL-Safe + Padding Variants

- (void)base64EncodeWithPadding:(id)sender {
    // Standard base64 already includes padding; identical to base64Encode:.
    [self base64Encode:sender];
}

- (void)base64DecodeStrict:(id)sender {
    NSString *sel = [self selectedText]; if (!sel) return;
    NSData *data = [[NSData alloc] initWithBase64EncodedString:sel options:0];
    if (!data) { NSBeep(); return; }
    NSString *decoded = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                     ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    if (!decoded) { NSBeep(); return; }
    [self replaceSelectionWith:decoded];
}

- (void)base64URLSafeEncode:(id)sender {
    NSString *sel = [self selectedText]; if (!sel) return;
    NSData *data = [sel dataUsingEncoding:NSUTF8StringEncoding]; if (!data) return;
    NSString *enc = [data base64EncodedStringWithOptions:0];
    enc = [enc stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    enc = [enc stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    enc = [enc stringByReplacingOccurrencesOfString:@"=" withString:@""];
    [self replaceSelectionWith:enc];
}

- (void)base64URLSafeDecode:(id)sender {
    NSString *sel = [self selectedText]; if (!sel) return;
    NSString *b64 = [sel stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    b64 = [b64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    NSUInteger pad = (4 - b64.length % 4) % 4;
    if (pad) b64 = [b64 stringByPaddingToLength:b64.length + pad withString:@"=" startingAtIndex:0];
    NSData *data = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
    if (!data) { NSBeep(); return; }
    NSString *decoded = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!decoded) { NSBeep(); return; }
    [self replaceSelectionWith:decoded];
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Export to HTML / RTF

- (nullable NSString *)generateHTML {
    ScintillaView *sci = _scintillaView;
    sptr_t docLen = [sci message:SCI_GETLENGTH];
    char *buf = (char *)calloc((size_t)docLen + 1, 1);
    [sci message:SCI_GETTEXT wParam:(uptr_t)(docLen + 1) lParam:(sptr_t)buf];
    NSString *raw = [NSString stringWithUTF8String:buf] ?: @"";
    free(buf);

    // Escape HTML entities
    NSMutableString *escaped = [raw mutableCopy];
    [escaped replaceOccurrencesOfString:@"&"  withString:@"&amp;"  options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"<"  withString:@"&lt;"   options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@">"  withString:@"&gt;"   options:0 range:NSMakeRange(0, escaped.length)];

    NSString *name = self.displayName;
    return [NSString stringWithFormat:
        @"<!DOCTYPE html>\n<html>\n<head><meta charset=\"utf-8\"><title>%@</title>\n"
        @"<style>body{background:#fff;color:#000}pre{font-family:monospace;font-size:13px;white-space:pre-wrap}</style>\n"
        @"</head>\n<body>\n<pre>%@</pre>\n</body>\n</html>", name, escaped];
}

- (nullable NSString *)generateRTF {
    ScintillaView *sci = _scintillaView;
    sptr_t docLen = [sci message:SCI_GETLENGTH];
    char *buf = (char *)calloc((size_t)docLen + 1, 1);
    [sci message:SCI_GETTEXT wParam:(uptr_t)(docLen + 1) lParam:(sptr_t)buf];
    NSString *raw = [NSString stringWithUTF8String:buf] ?: @"";
    free(buf);

    // Build RTF: escape \, {, }, non-ASCII chars; map newlines to \par
    NSMutableString *rtf = [NSMutableString stringWithString:
        @"{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0\\fmodern\\fcharset0 Courier New;}}"
        @"{\\colortbl ;\\red0\\green0\\blue0;}\\f0\\fs20\\cf1 "];
    for (NSUInteger i = 0; i < raw.length; i++) {
        unichar ch = [raw characterAtIndex:i];
        if      (ch == '\\') [rtf appendString:@"\\\\"];
        else if (ch == '{')  [rtf appendString:@"\\{"];
        else if (ch == '}')  [rtf appendString:@"\\}"];
        else if (ch == '\n') [rtf appendString:@"\\par\n"];
        else if (ch == '\r') {}  // skip CR
        else if (ch > 127)   [rtf appendFormat:@"\\'%02X", (unsigned int)(ch & 0xFF)];
        else                 [rtf appendFormat:@"%c", (char)ch];
    }
    [rtf appendString:@"}"];
    return [rtf copy];
}

#pragma mark - Spell Check

- (BOOL)spellCheckEnabled { return _spellCheckEnabled; }

- (void)setSpellCheckEnabled:(BOOL)enabled {
    _spellCheckEnabled = enabled;
    if (enabled) [self runSpellCheck];
    else         [self clearSpellCheck];
}

- (void)clearSpellCheck {
    [_spellTimer invalidate];
    _spellTimer = nil;
    ScintillaView *sci = _scintillaView;
    intptr_t len = [sci message:SCI_GETLENGTH];
    [sci message:SCI_SETINDICATORCURRENT wParam:kSpellIndicator];
    [sci message:SCI_INDICATORCLEARRANGE wParam:0 lParam:len];
}

- (void)runSpellCheck {
    if (!_spellCheckEnabled) return;
    ScintillaView *sci = _scintillaView;
    intptr_t docLen = [sci message:SCI_GETLENGTH];
    char *buf = (char *)calloc((size_t)docLen + 1, 1);
    if (!buf) return;
    [sci message:SCI_GETTEXT wParam:(uptr_t)(docLen + 1) lParam:(sptr_t)buf];
    NSString *text = [NSString stringWithUTF8String:buf] ?: @"";
    free(buf);

    // Clear existing spell marks
    [sci message:SCI_SETINDICATORCURRENT wParam:kSpellIndicator];
    [sci message:SCI_INDICATORCLEARRANGE wParam:0 lParam:docLen];

    if (!text.length) return;

    NSSpellChecker *checker = [NSSpellChecker sharedSpellChecker];
    NSArray<NSTextCheckingResult *> *results =
        [checker checkString:text
                       range:NSMakeRange(0, text.length)
                       types:NSTextCheckingTypeSpelling
                     options:nil
     inSpellDocumentWithTag:_spellTag
                 orthography:nil
                   wordCount:nil];

    for (NSTextCheckingResult *r in results) {
        // Convert NSString char range to UTF-8 byte range for Scintilla
        NSRange charRange = r.range;
        NSRange utf8BeforeRange = NSMakeRange(0, charRange.location);
        NSString *before = [text substringWithRange:utf8BeforeRange];
        NSString *word   = [text substringWithRange:charRange];
        NSUInteger byteStart = [before lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        NSUInteger byteLen   = [word   lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        if (byteLen == 0) continue;
        [sci message:SCI_INDICATORFILLRANGE wParam:byteStart lParam:(sptr_t)byteLen];
    }
}

- (void)_spellTimerFired:(NSTimer *)timer {
    _spellTimer = nil;
    [self runSpellCheck];
}

- (void)_scheduleSpellCheck {
    if (!_spellCheckEnabled) return;
    [_spellTimer invalidate];
    _spellTimer = [NSTimer scheduledTimerWithTimeInterval:1.5
                                                   target:self
                                                 selector:@selector(_spellTimerFired:)
                                                 userInfo:nil
                                                  repeats:NO];
}

#pragma mark - Git Gutter

- (void)clearGitDiffMarkers {
    ScintillaView *sci = _scintillaView;
    [sci message:SCI_MARKERDELETEALL wParam:(uptr_t)kGitMarkerAdded];
    [sci message:SCI_MARKERDELETEALL wParam:(uptr_t)kGitMarkerModified];
    [sci message:SCI_MARKERDELETEALL wParam:(uptr_t)kGitMarkerDeleted];
}

- (void)updateGitDiffMarkers {
    if (!_filePath) { [self clearGitDiffMarkers]; return; }
    NSString *fp = [_filePath copy];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *root = [GitHelper gitRootForPath:fp];
        if (!root) {
            dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf clearGitDiffMarkers]; });
            return;
        }
        NSString *diff = [GitHelper diffForFile:fp root:root];
        // Parse hunk headers: @@ -old,count +new,count @@
        // Build sets of new-file line numbers (1-based) for each marker type.
        NSMutableSet<NSNumber *> *addedLines    = [NSMutableSet set];
        NSMutableSet<NSNumber *> *modifiedLines = [NSMutableSet set];
        NSMutableSet<NSNumber *> *deletedLines  = [NSMutableSet set];
        if (diff.length) {
            NSArray<NSString *> *lines = [diff componentsSeparatedByString:@"\n"];
            NSInteger newLine = 0; // tracks current new-file line number
            NSInteger hunkNewStart = 0;
            NSInteger hunkOldStart = 0;
            for (NSString *line in lines) {
                if ([line hasPrefix:@"@@"]) {
                    // @@ -old_start,old_count +new_start,new_count @@
                    NSRegularExpression *re = [NSRegularExpression
                        regularExpressionWithPattern:@"\\+([0-9]+)"
                                             options:0 error:nil];
                    NSRegularExpression *reOld = [NSRegularExpression
                        regularExpressionWithPattern:@"-([0-9]+)"
                                             options:0 error:nil];
                    NSTextCheckingResult *mNew = [re firstMatchInString:line options:0
                                                                  range:NSMakeRange(0, line.length)];
                    NSTextCheckingResult *mOld = [reOld firstMatchInString:line options:0
                                                                     range:NSMakeRange(0, line.length)];
                    if (mNew) hunkNewStart = [[line substringWithRange:[mNew rangeAtIndex:1]] integerValue];
                    if (mOld) hunkOldStart = [[line substringWithRange:[mOld rangeAtIndex:1]] integerValue];
                    newLine = hunkNewStart - 1; // will be incremented on first context/add line
                    (void)hunkOldStart;
                } else if ([line hasPrefix:@"+"]) {
                    newLine++;
                    [addedLines addObject:@(newLine)];
                } else if ([line hasPrefix:@"-"]) {
                    // Deleted line: mark the line before it in the new file
                    NSInteger markLine = MAX(1, newLine);
                    [deletedLines addObject:@(markLine)];
                } else if (![line hasPrefix:@"\\"]) {
                    // Context line (not "\ No newline at end of file")
                    newLine++;
                }
            }
            // Lines that appear in both added and deleted sets are modifications
            NSMutableSet<NSNumber *> *both = [addedLines mutableCopy];
            [both intersectSet:deletedLines];
            for (NSNumber *n in both) {
                [addedLines removeObject:n];
                [deletedLines removeObject:n];
                [modifiedLines addObject:n];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            [self clearGitDiffMarkers];
            ScintillaView *sci = self->_scintillaView;
            for (NSNumber *n in addedLines) {
                NSInteger line0 = n.integerValue - 1; // Scintilla is 0-based
                [sci message:SCI_MARKERADD wParam:(uptr_t)line0 lParam:kGitMarkerAdded];
            }
            for (NSNumber *n in modifiedLines) {
                NSInteger line0 = n.integerValue - 1;
                [sci message:SCI_MARKERADD wParam:(uptr_t)line0 lParam:kGitMarkerModified];
            }
            for (NSNumber *n in deletedLines) {
                NSInteger line0 = MAX(0, n.integerValue - 1);
                [sci message:SCI_MARKERADD wParam:(uptr_t)line0 lParam:kGitMarkerDeleted];
            }
        });
    });
}

@end
