#import "SearchResultsPanel.h"
#import "NppThemeManager.h"
#import "StyleConfiguratorWindowController.h"
#import "ScintillaView.h"
#import "Scintilla.h"
#import "SciLexer.h"
#include <vector>

// Forward-declare Lexilla's CreateLexer (statically linked)
#include "ILexer.h"
extern "C" Scintilla::ILexer5 *CreateLexer(const char *name);

// Fold levels matching LexSearchResult.cxx
enum { searchHeaderLevel = SC_FOLDLEVELBASE, fileHeaderLevel, resultLevel };

// ── Internal data for tracking results ───────────────────────────────────────

struct _SRLineInfo {
    std::string filePath;
    int lineNumber;       // 1-based, 0 = header line
};

// ── SearchResultsPanel ───────────────────────────────────────────────────────

@implementation SearchResultsPanel {
    ScintillaView *_sci;
    NSScrollView  *_scrollContainer;
    NSView        *_titleBar;

    // Parallel data — one entry per line in the ScintillaView
    std::vector<_SRLineInfo> _lineInfos;

    // SearchResultMarkings for the lexer
    std::vector<SearchResultMarkingLine> _markingLines;
    SearchResultMarkings _markingsStruct;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self _buildUI];
        [self _applyTheme];
        _markingsStruct._length   = 0;
        _markingsStruct._markings = nullptr;

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_themeChanged:)
                                                     name:@"NPPPreferencesChanged" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_darkModeChanged:)
                                                     name:NPPDarkModeChangedNotification object:nil];
    }
    return self;
}

- (instancetype)init { return [self initWithFrame:NSZeroRect]; }

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - UI Construction

- (void)_buildUI {
    self.translatesAutoresizingMaskIntoConstraints = NO;

    _sci = [[ScintillaView alloc] initWithFrame:NSZeroRect];
    _sci.translatesAutoresizingMaskIntoConstraints = NO;

    // Install LexSearchResult lexer
    Scintilla::ILexer5 *lexer = CreateLexer("searchResult");
    if (lexer) {
        [_sci message:SCI_SETILEXER wParam:0 lParam:(sptr_t)lexer];
    }

    // Read-only
    [_sci message:SCI_SETREADONLY wParam:1];

    // Folding setup
    [_sci message:SCI_SETPROPERTY wParam:(uptr_t)"fold" lParam:(sptr_t)"1"];
    [_sci message:SCI_SETMARGINTYPEN  wParam:2 lParam:SC_MARGIN_SYMBOL];
    [_sci message:SCI_SETMARGINMASKN  wParam:2 lParam:SC_MASK_FOLDERS];
    [_sci message:SCI_SETMARGINWIDTHN wParam:2 lParam:16];
    [_sci message:SCI_SETMARGINSENSITIVEN wParam:2 lParam:1];
    [_sci message:SCI_SETAUTOMATICFOLD wParam:SC_AUTOMATICFOLD_SHOW | SC_AUTOMATICFOLD_CLICK | SC_AUTOMATICFOLD_CHANGE];

    // Fold markers: box style
    [_sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDEROPEN    lParam:SC_MARK_BOXMINUS];
    [_sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDER        lParam:SC_MARK_BOXPLUS];
    [_sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDERSUB     lParam:SC_MARK_VLINE];
    [_sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDERTAIL    lParam:SC_MARK_LCORNER];
    [_sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDEREND     lParam:SC_MARK_BOXPLUSCONNECTED];
    [_sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDEROPENMID lParam:SC_MARK_BOXMINUSCONNECTED];
    [_sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDERMIDTAIL lParam:SC_MARK_TCORNER];

    // Fold marker colors
    for (int i = SC_MARKNUM_FOLDEREND; i <= SC_MARKNUM_FOLDEROPEN; i++) {
        [_sci message:SCI_MARKERSETFORE wParam:i lParam:0xFFFFFF];
        [_sci message:SCI_MARKERSETBACK wParam:i lParam:0x808080];
    }

    // Hide line number margin, show only fold margin
    [_sci message:SCI_SETMARGINWIDTHN wParam:0 lParam:0];
    [_sci message:SCI_SETMARGINWIDTHN wParam:1 lParam:0];

    // No caret line highlight by default
    [_sci message:SCI_SETCARETLINEVISIBLE wParam:1];

    // EOL-filled styles for headers
    [_sci message:SCI_STYLESETEOLFILLED wParam:SCE_SEARCHRESULT_FILE_HEADER lParam:1];
    [_sci message:SCI_STYLESETEOLFILLED wParam:SCE_SEARCHRESULT_SEARCH_HEADER lParam:1];

    // Set self as ScintillaView delegate to receive notifications
    _sci.delegate = (id)self;

    // ── Title bar with close button ─────────────────────────────────────
    _titleBar = [[NSView alloc] init];
    _titleBar.translatesAutoresizingMaskIntoConstraints = NO;
    _titleBar.wantsLayer = YES;
    _titleBar.layer.backgroundColor = [NppThemeManager shared].panelBackground.CGColor;
    NSView *titleBar = _titleBar;

    NSTextField *titleLabel = [NSTextField labelWithString:@"Search results"];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [NSFont systemFontOfSize:11];
    [titleBar addSubview:titleLabel];

    NSButton *closeBtn = [[NSButton alloc] init];
    closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    closeBtn.bezelStyle = NSBezelStyleSmallSquare;
    closeBtn.bordered = NO;
    closeBtn.title = @"\u2715";
    closeBtn.font = [NSFont systemFontOfSize:10];
    closeBtn.toolTip = @"Close Search Results";
    closeBtn.target = self;
    closeBtn.action = @selector(_closePanel:);
    [closeBtn.widthAnchor constraintEqualToConstant:18].active = YES;
    [closeBtn.heightAnchor constraintEqualToConstant:18].active = YES;
    [titleBar addSubview:closeBtn];

    [NSLayoutConstraint activateConstraints:@[
        [titleBar.heightAnchor constraintEqualToConstant:22],
        [titleLabel.leadingAnchor constraintEqualToAnchor:titleBar.leadingAnchor constant:6],
        [titleLabel.centerYAnchor constraintEqualToAnchor:titleBar.centerYAnchor],
        [closeBtn.trailingAnchor constraintEqualToAnchor:titleBar.trailingAnchor constant:-4],
        [closeBtn.centerYAnchor constraintEqualToAnchor:titleBar.centerYAnchor],
    ]];

    NSBox *sep = [[NSBox alloc] init];
    sep.boxType = NSBoxSeparator;
    sep.translatesAutoresizingMaskIntoConstraints = NO;

    [self addSubview:titleBar];
    [self addSubview:sep];
    [self addSubview:_sci];
    [NSLayoutConstraint activateConstraints:@[
        [titleBar.topAnchor      constraintEqualToAnchor:self.topAnchor],
        [titleBar.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [titleBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [sep.topAnchor           constraintEqualToAnchor:titleBar.bottomAnchor],
        [sep.leadingAnchor       constraintEqualToAnchor:self.leadingAnchor],
        [sep.trailingAnchor      constraintEqualToAnchor:self.trailingAnchor],
        [sep.heightAnchor        constraintEqualToConstant:1],
        [_sci.topAnchor          constraintEqualToAnchor:sep.bottomAnchor],
        [_sci.leadingAnchor      constraintEqualToAnchor:self.leadingAnchor],
        [_sci.trailingAnchor     constraintEqualToAnchor:self.trailingAnchor],
        [_sci.bottomAnchor       constraintEqualToAnchor:self.bottomAnchor],
    ]];
}

#pragma mark - Theme

/// Convert NSColor to Scintilla BGR integer.
static sptr_t _srSciColor(NSColor *c) {
    c = [c colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
    if (!c) return 0;
    long r = (long)([c redComponent]   * 255);
    long g = (long)([c greenComponent] * 255);
    long b = (long)([c blueComponent]  * 255);
    return (b << 16) | (g << 8) | r;
}

- (void)_applyTheme {
    BOOL dark = [NppThemeManager shared].isDark;
    NPPStyleStore *store = [NPPStyleStore sharedStore];

    // Background & foreground from editor theme
    NSColor *bgColor = [store globalBg];
    NSColor *fgColor = [store globalFg];
    sptr_t bg = _srSciColor(bgColor);
    sptr_t fg = _srSciColor(fgColor);
    CGFloat bgBrightness = bgColor.brightnessComponent;

    [_sci message:SCI_STYLESETBACK wParam:STYLE_DEFAULT lParam:bg];
    [_sci message:SCI_STYLESETFORE wParam:STYLE_DEFAULT lParam:fg];
    [_sci message:SCI_STYLECLEARALL];

    // Search header: purple-ish bg #bebefc, dark blue fg #01057e
    [_sci message:SCI_STYLESETFORE  wParam:SCE_SEARCHRESULT_SEARCH_HEADER lParam:(dark ? 0xFCBEBE : 0x7E0501)];
    [_sci message:SCI_STYLESETBACK  wParam:SCE_SEARCHRESULT_SEARCH_HEADER lParam:(dark ? 0x3A3A50 : 0xFCBEBE)];
    [_sci message:SCI_STYLESETBOLD  wParam:SCE_SEARCHRESULT_SEARCH_HEADER lParam:1];

    // File header: green bg #d0f0d0, green fg #007000
    [_sci message:SCI_STYLESETFORE  wParam:SCE_SEARCHRESULT_FILE_HEADER lParam:(dark ? 0x80FF80 : 0x007000)];
    [_sci message:SCI_STYLESETBACK  wParam:SCE_SEARCHRESULT_FILE_HEADER lParam:(dark ? 0x2E4A2E : 0xD0F0D0)];
    [_sci message:SCI_STYLESETBOLD  wParam:SCE_SEARCHRESULT_FILE_HEADER lParam:1];

    // Line number: green
    [_sci message:SCI_STYLESETFORE  wParam:SCE_SEARCHRESULT_LINE_NUMBER lParam:(dark ? 0x808080 : 0x008000)];
    [_sci message:SCI_STYLESETBACK  wParam:SCE_SEARCHRESULT_LINE_NUMBER lParam:bg];

    // Matched text: red fg #ff0b05, yellow bg #ffffbf
    [_sci message:SCI_STYLESETFORE  wParam:SCE_SEARCHRESULT_WORD2SEARCH lParam:(dark ? 0x00AAFF : 0x050BFF)];
    [_sci message:SCI_STYLESETBACK  wParam:SCE_SEARCHRESULT_WORD2SEARCH lParam:(dark ? 0x404000 : 0xBFFFFF)];
    [_sci message:SCI_STYLESETBOLD  wParam:SCE_SEARCHRESULT_WORD2SEARCH lParam:1];

    // Default text
    [_sci message:SCI_STYLESETFORE  wParam:SCE_SEARCHRESULT_DEFAULT lParam:fg];
    [_sci message:SCI_STYLESETBACK  wParam:SCE_SEARCHRESULT_DEFAULT lParam:bg];

    // Current line highlight
    sptr_t caretBg = dark ? 0x404040 : 0xE8E8E8;
    [_sci message:SCI_STYLESETBACK  wParam:SCE_SEARCHRESULT_CURRENT_LINE lParam:caretBg];
    [_sci message:SCI_SETCARETLINEBACK wParam:caretBg];

    // EOL-filled for headers
    [_sci message:SCI_STYLESETEOLFILLED wParam:SCE_SEARCHRESULT_FILE_HEADER lParam:1];
    [_sci message:SCI_STYLESETEOLFILLED wParam:SCE_SEARCHRESULT_SEARCH_HEADER lParam:1];

    // ── Fold markers: match editor theme ─────────────────────────────────
    // Fold margin background
    NPPStyleEntry *gsFoldMargin = [store globalStyleNamed:@"Fold margin"];
    sptr_t foldMarginBGR;
    if (gsFoldMargin && gsFoldMargin.bgColor) {
        foldMarginBGR = _srSciColor(gsFoldMargin.bgColor);
    } else {
        foldMarginBGR = dark ? 0x2D2D2D : 0xF2F2F2;
    }
    [_sci message:SCI_SETFOLDMARGINCOLOUR   wParam:1 lParam:foldMarginBGR];
    [_sci message:SCI_SETFOLDMARGINHICOLOUR wParam:1 lParam:foldMarginBGR];

    // Fold marker fore/back colors from "Fold" global style
    NPPStyleEntry *gsFold = [store globalStyleNamed:@"Fold"];
    NSColor *foldFore = gsFold.fgColor ?: (bgBrightness > 0.5 ? [NSColor blackColor]
                                                                : [NSColor colorWithWhite:0.80 alpha:1.0]);
    NSColor *foldBack = gsFold.bgColor ?: (bgBrightness > 0.5 ? [NSColor colorWithWhite:0.82 alpha:1.0]
                                                                : [NSColor colorWithWhite:bgBrightness + 0.22 alpha:1.0]);
    for (int mn = SC_MARKNUM_FOLDEREND; mn <= SC_MARKNUM_FOLDEROPEN; mn++) {
        [_sci message:SCI_MARKERSETFORE wParam:mn lParam:_srSciColor(foldFore)];
        [_sci message:SCI_MARKERSETBACK wParam:mn lParam:_srSciColor(foldBack)];
    }

    // ── Title bar background ─────────────────────────────────────────────
    _titleBar.layer.backgroundColor = [NppThemeManager shared].panelBackground.CGColor;

    // ── Appearance for dark/light disclosure triangles ────────────────────
    _sci.appearance = [NSAppearance appearanceNamed:
        dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];

    // Re-colourise if we have content
    if ([_sci message:SCI_GETLENGTH] > 0)
        [_sci message:SCI_COLOURISE wParam:0 lParam:-1];
}

- (void)_themeChanged:(NSNotification *)n {
    [self _applyTheme];
}

- (void)_darkModeChanged:(NSNotification *)n {
    [self _applyTheme];
}

#pragma mark - Scintilla notifications

// ScintillaNotificationProtocol
- (void)notification:(SCNotification *)scn {
    if (scn->nmhdr.code == SCN_DOUBLECLICK) {
        sptr_t line = [_sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)scn->position];
        [self _navigateToResultLine:line];
    }
}

- (void)_navigateToResultLine:(sptr_t)lineIdx {
    if (lineIdx < 0 || (size_t)lineIdx >= _lineInfos.size()) return;

    const _SRLineInfo &info = _lineInfos[lineIdx];
    if (info.lineNumber <= 0) return; // header line — don't navigate

    NSString *path = [NSString stringWithUTF8String:info.filePath.c_str()];
    [_delegate searchResultsPanel:self navigateToFile:path atLine:info.lineNumber
                        matchText:@"" matchCase:NO];
}

- (void)_closePanel:(id)sender {
    [_delegate searchResultsPanel:self navigateToFile:@"" atLine:0 matchText:@"" matchCase:NO];
    // Notify delegate to collapse the panel — we use a special "close" signal
    if ([_delegate respondsToSelector:@selector(searchResultsPanelDidRequestClose:)])
        [(id)_delegate searchResultsPanelDidRequestClose:self];
}

#pragma mark - Public API

- (void)addResults:(NSArray<NPPFileResults *> *)fileResults
     forSearchText:(NSString *)searchText
           options:(NPPFindOptions *)opts
      filesSearched:(NSInteger)filesSearched {
    if (!fileResults.count) return;

    [_sci message:SCI_SETREADONLY wParam:0];

    // Count total hits
    NSInteger totalHits = 0;
    for (NPPFileResults *fr in fileResults)
        totalHits += (NSInteger)fr.results.count;

    // Search mode label
    NSString *modeLabel = @"Normal";
    if (opts.searchType == NPPSearchExtended) modeLabel = @"Extended";
    else if (opts.searchType == NPPSearchRegex) modeLabel = @"Regex";

    NSMutableString *optLabel = [NSMutableString string];
    if (opts.matchCase) [optLabel appendString:@"Case"];
    if (opts.wholeWord) {
        if (optLabel.length) [optLabel appendString:@"/"];
        [optLabel appendString:@"Word"];
    }

    NSString *suffix = @"";
    if (optLabel.length) suffix = [NSString stringWithFormat:@" [%@: %@]", modeLabel, optLabel];
    else suffix = [NSString stringWithFormat:@" [%@]", modeLabel];

    // Search header
    NSString *header = [NSString stringWithFormat:@"Search \"%@\" (%ld hit%@ in %ld file%@ of %ld searched)%@\n",
        searchText,
        (long)totalHits, totalHits == 1 ? @"" : @"s",
        (long)fileResults.count, fileResults.count == 1 ? @"" : @"s",
        (long)filesSearched,
        suffix];

    sptr_t startPos = [_sci message:SCI_GETLENGTH];
    [_sci message:SCI_APPENDTEXT wParam:header.length lParam:(sptr_t)header.UTF8String];

    // Add line info for search header
    _SRLineInfo headerInfo = {};
    headerInfo.lineNumber = 0;
    _lineInfos.push_back(headerInfo);

    // Empty marking for header line
    SearchResultMarkingLine emptyMarking = {};
    _markingLines.push_back(emptyMarking);

    for (NPPFileResults *fileRes in fileResults) {
        // File header
        NSString *fileHeader = [NSString stringWithFormat:@" %@ (%ld hit%@)\n",
            fileRes.filePath,
            (long)fileRes.results.count,
            fileRes.results.count == 1 ? @"" : @"s"];
        [_sci message:SCI_APPENDTEXT wParam:fileHeader.length lParam:(sptr_t)fileHeader.UTF8String];

        _SRLineInfo fileInfo = {};
        fileInfo.filePath = fileRes.filePath.UTF8String ?: "";
        fileInfo.lineNumber = 0;
        _lineInfos.push_back(fileInfo);
        _markingLines.push_back(SearchResultMarkingLine{});

        for (NPPSearchResult *r in fileRes.results) {
            // Result line: \tLine NNNN: text\n
            NSString *linePrefix = [NSString stringWithFormat:@"\tLine %6ld: ", (long)r.lineNumber];
            NSString *resultLine = [NSString stringWithFormat:@"%@%@\n", linePrefix, r.lineText];

            // Calculate marking position for highlighted match
            const char *prefixUTF8 = linePrefix.UTF8String;
            size_t prefixBytes = strlen(prefixUTF8);

            // Convert character-based matchStart to byte offset in lineText
            NSString *beforeMatch = [r.lineText substringToIndex:MIN((NSUInteger)r.matchStart, r.lineText.length)];
            size_t matchByteStart = strlen(beforeMatch.UTF8String);
            NSString *matchStr = @"";
            if (r.matchStart + r.matchLength <= (NSInteger)r.lineText.length)
                matchStr = [r.lineText substringWithRange:NSMakeRange(r.matchStart, r.matchLength)];
            size_t matchByteLen = strlen(matchStr.UTF8String);

            SearchResultMarkingLine marking = {};
            if (matchByteLen > 0) {
                // LexSearchResult: ColourTo(startLine + mi.first - 1, DEFAULT) then
                // ColourTo(startLine + mi.second - 1, WORD2SEARCH).
                // So mi.first = offset of first highlighted byte (0-based within line buffer)
                // and mi.second = offset of last highlighted byte + 1
                intptr_t segStart = (intptr_t)(prefixBytes + matchByteStart);
                intptr_t segEnd   = (intptr_t)(prefixBytes + matchByteStart + matchByteLen);
                marking._segmentPostions.push_back(std::make_pair(segStart, segEnd));
            }
            _markingLines.push_back(marking);

            [_sci message:SCI_APPENDTEXT wParam:resultLine.length lParam:(sptr_t)resultLine.UTF8String];

            _SRLineInfo lineInfo = {};
            lineInfo.filePath = r.filePath.UTF8String ?: "";
            lineInfo.lineNumber = (int)r.lineNumber;
            _lineInfos.push_back(lineInfo);
        }
    }

    // Update markings struct pointer for lexer
    _markingsStruct._length   = (intptr_t)_markingLines.size();
    _markingsStruct._markings = _markingLines.data();

    // Pass pointer to lexer
    char ptrStr[64];
    snprintf(ptrStr, sizeof(ptrStr), "%p", &_markingsStruct);
    [_sci message:SCI_SETPROPERTY wParam:(uptr_t)"@MarkingsStruct" lParam:(sptr_t)ptrStr];

    [_sci message:SCI_SETREADONLY wParam:1];

    // Trigger re-colourise
    [_sci message:SCI_COLOURISE wParam:0 lParam:-1];

    // Scroll to show the new results
    sptr_t lastLine = [_sci message:SCI_GETLINECOUNT] - 1;
    sptr_t firstNewLine = [_sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)startPos];
    [_sci message:SCI_GOTOLINE wParam:(uptr_t)firstNewLine];

    // Expand all folds in new results
    for (sptr_t line = firstNewLine; line <= lastLine; line++) {
        sptr_t level = [_sci message:SCI_GETFOLDLEVEL wParam:(uptr_t)line];
        if (level & SC_FOLDLEVELHEADERFLAG) {
            if (!([_sci message:SCI_GETFOLDEXPANDED wParam:(uptr_t)line]))
                [_sci message:SCI_TOGGLEFOLD wParam:(uptr_t)line];
        }
    }
}

- (void)clearAll {
    [_sci message:SCI_SETREADONLY wParam:0];
    [_sci message:SCI_CLEARALL];
    [_sci message:SCI_SETREADONLY wParam:1];
    _lineInfos.clear();
    _markingLines.clear();
    _markingsStruct._length = 0;
    _markingsStruct._markings = nullptr;
}

- (BOOL)navigateToNextResult {
    sptr_t currentLine = [_sci message:SCI_LINEFROMPOSITION
                                wParam:(uptr_t)[_sci message:SCI_GETCURRENTPOS]];
    sptr_t lineCount = [_sci message:SCI_GETLINECOUNT];

    for (sptr_t line = currentLine + 1; line < lineCount; line++) {
        if ((size_t)line < _lineInfos.size() && _lineInfos[line].lineNumber > 0) {
            [_sci message:SCI_GOTOLINE wParam:(uptr_t)line];
            [self _navigateToResultLine:line];
            return YES;
        }
    }
    // Wrap to beginning
    for (sptr_t line = 0; line <= currentLine && line < lineCount; line++) {
        if ((size_t)line < _lineInfos.size() && _lineInfos[line].lineNumber > 0) {
            [_sci message:SCI_GOTOLINE wParam:(uptr_t)line];
            [self _navigateToResultLine:line];
            return YES;
        }
    }
    return NO;
}

- (BOOL)navigateToPreviousResult {
    sptr_t currentLine = [_sci message:SCI_LINEFROMPOSITION
                                wParam:(uptr_t)[_sci message:SCI_GETCURRENTPOS]];
    sptr_t lineCount = [_sci message:SCI_GETLINECOUNT];

    for (sptr_t line = currentLine - 1; line >= 0; line--) {
        if ((size_t)line < _lineInfos.size() && _lineInfos[line].lineNumber > 0) {
            [_sci message:SCI_GOTOLINE wParam:(uptr_t)line];
            [self _navigateToResultLine:line];
            return YES;
        }
    }
    // Wrap to end
    for (sptr_t line = lineCount - 1; line > currentLine; line--) {
        if ((size_t)line < _lineInfos.size() && _lineInfos[line].lineNumber > 0) {
            [_sci message:SCI_GOTOLINE wParam:(uptr_t)line];
            [self _navigateToResultLine:line];
            return YES;
        }
    }
    return NO;
}

- (void)foldAll {
    sptr_t lineCount = [_sci message:SCI_GETLINECOUNT];
    for (sptr_t line = 0; line < lineCount; line++) {
        sptr_t level = [_sci message:SCI_GETFOLDLEVEL wParam:(uptr_t)line];
        if ((level & SC_FOLDLEVELHEADERFLAG) && [_sci message:SCI_GETFOLDEXPANDED wParam:(uptr_t)line])
            [_sci message:SCI_TOGGLEFOLD wParam:(uptr_t)line];
    }
}

- (void)unfoldAll {
    sptr_t lineCount = [_sci message:SCI_GETLINECOUNT];
    for (sptr_t line = 0; line < lineCount; line++) {
        sptr_t level = [_sci message:SCI_GETFOLDLEVEL wParam:(uptr_t)line];
        if ((level & SC_FOLDLEVELHEADERFLAG) && !([_sci message:SCI_GETFOLDEXPANDED wParam:(uptr_t)line]))
            [_sci message:SCI_TOGGLEFOLD wParam:(uptr_t)line];
    }
}

#pragma mark - Context menu

- (NSMenu *)menuForEvent:(NSEvent *)event {
    NSMenu *m = [[NSMenu alloc] init];
    [m addItemWithTitle:@"Copy"       action:@selector(copy:)       keyEquivalent:@"c"];
    [m addItemWithTitle:@"Select All" action:@selector(selectAll:)  keyEquivalent:@"a"];
    [m addItem:[NSMenuItem separatorItem]];
    [m addItemWithTitle:@"Clear All"    action:@selector(_clearAll:)    keyEquivalent:@""];
    [m addItem:[NSMenuItem separatorItem]];
    [m addItemWithTitle:@"Fold All"     action:@selector(_foldAll:)     keyEquivalent:@""];
    [m addItemWithTitle:@"Unfold All"   action:@selector(_unfoldAll:)   keyEquivalent:@""];
    for (NSMenuItem *mi in m.itemArray) mi.target = self;
    return m;
}

- (void)copy:(id)sender      { [_sci message:SCI_COPY]; }
- (void)selectAll:(id)sender  { [_sci message:SCI_SELECTALL]; }
- (void)_clearAll:(id)sender  { [self clearAll]; }
- (void)_foldAll:(id)sender   { [self foldAll]; }
- (void)_unfoldAll:(id)sender { [self unfoldAll]; }

@end
