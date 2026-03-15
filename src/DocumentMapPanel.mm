#import "DocumentMapPanel.h"
#import "ScintillaView.h"
#import "Scintilla.h"
#import "ScintillaMessages.h"

// Forward-declare Lexilla
namespace Scintilla { struct ILexer5; }
extern "C" Scintilla::ILexer5 *CreateLexer(const char *name);

@implementation DocumentMapPanel {
    ScintillaView  *_mapSci;
    __weak EditorView *_trackedEditor;
    NSTimer        *_debounceTimer;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self buildMapView];
        [[NSNotificationCenter defaultCenter]
            addObserver:self selector:@selector(_cursorMoved:)
                   name:EditorViewCursorDidMoveNotification object:nil];
    }
    return self;
}

- (instancetype)init {
    return [self initWithFrame:NSZeroRect];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_debounceTimer invalidate];
}

- (void)buildMapView {
    _mapSci = [[ScintillaView alloc] initWithFrame:self.bounds];
    _mapSci.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self addSubview:_mapSci];

    // Read-only, no margins, no caret line, no scrollbars, tiny font
    [_mapSci message:SCI_SETREADONLY wParam:1];
    for (int m = 0; m < 5; m++)
        [_mapSci message:SCI_SETMARGINWIDTHN wParam:(uptr_t)m lParam:0];
    [_mapSci message:SCI_SETCARETLINEVISIBLE wParam:0];
    [_mapSci message:SCI_SETHSCROLLBAR wParam:0];
    [_mapSci message:SCI_SETVSCROLLBAR wParam:0];
    // Very small font: 4pt (fractional = 4*100 = 400)
    [_mapSci message:SCI_STYLESETSIZEFRACTIONAL wParam:STYLE_DEFAULT lParam:400];
    [_mapSci message:SCI_STYLECLEARALL];
    // No word wrap (map should scroll to reflect source)
    [_mapSci message:SCI_SETWRAPMODE wParam:SC_WRAP_NONE];
}

#pragma mark - Public API

- (void)setTrackedEditor:(EditorView *)editor {
    _trackedEditor = editor;
    [self _updateMap];
}

#pragma mark - Map update

- (void)_scheduleUpdate {
    [_debounceTimer invalidate];
    _debounceTimer = [NSTimer scheduledTimerWithTimeInterval:0.3
                                                      target:self
                                                    selector:@selector(_updateMap)
                                                    userInfo:nil
                                                     repeats:NO];
}

- (void)_updateMap {
    EditorView *ed = _trackedEditor;
    if (!ed) {
        [_mapSci message:SCI_SETREADONLY wParam:0];
        [_mapSci message:SCI_CLEARALL];
        [_mapSci message:SCI_SETREADONLY wParam:1];
        return;
    }

    // Copy text from source
    intptr_t len = [ed.scintillaView message:SCI_GETLENGTH];
    char *buf = (char *)malloc((size_t)len + 1);
    if (!buf) return;
    [ed.scintillaView message:SCI_GETTEXT wParam:(uptr_t)(len + 1) lParam:(sptr_t)buf];

    [_mapSci message:SCI_SETREADONLY wParam:0];
    [_mapSci message:SCI_SETTEXT wParam:0 lParam:(sptr_t)buf];
    [_mapSci message:SCI_SETREADONLY wParam:1];
    free(buf);

    // Apply same lexer
    NSString *lang = ed.currentLanguage;
    if (lang.length) {
        NSDictionary *lexerMap = @{
            @"c": @"cpp", @"cpp": @"cpp", @"objc": @"cpp", @"swift": @"cpp",
            @"python": @"python", @"javascript": @"cpp", @"typescript": @"cpp",
            @"html": @"hypertext", @"xml": @"xml", @"css": @"css",
            @"bash": @"bash", @"ruby": @"ruby", @"json": @"json",
            @"sql": @"sql", @"lua": @"lua", @"perl": @"perl",
        };
        NSString *lexerStr = lexerMap[lang.lowercaseString] ?: lang;
        Scintilla::ILexer5 *lexer = CreateLexer(lexerStr.UTF8String);
        if (lexer)
            [_mapSci message:SCI_SETILEXER wParam:0 lParam:(sptr_t)lexer];
    }

    [self _syncScroll];
}

- (void)_syncScroll {
    EditorView *ed = _trackedEditor;
    if (!ed) return;

    intptr_t firstVisible = [ed.scintillaView message:SCI_GETFIRSTVISIBLELINE];
    intptr_t totalLines   = [ed.scintillaView message:SCI_GETLINECOUNT];
    if (totalLines <= 0) return;

    intptr_t mapLine = (firstVisible * [_mapSci message:SCI_GETLINECOUNT]) / totalLines;
    [_mapSci message:SCI_SETFIRSTVISIBLELINE wParam:(uptr_t)mapLine];
}

#pragma mark - Cursor notification

- (void)_cursorMoved:(NSNotification *)note {
    if (note.object != _trackedEditor) return;
    [self _scheduleUpdate];
}

#pragma mark - Click to navigate

- (void)mouseDown:(NSEvent *)event {
    NSPoint loc = [_mapSci convertPoint:event.locationInWindow fromView:nil];
    intptr_t line = [_mapSci message:SCI_LINEFROMPOSITION
                              wParam:(uptr_t)[_mapSci message:SCI_POSITIONFROMPOINT
                                                      wParam:(uptr_t)loc.x
                                                      lParam:(sptr_t)loc.y]];
    EditorView *ed = _trackedEditor;
    if (!ed) return;

    // Scale map line back to source line
    intptr_t mapTotal = [_mapSci message:SCI_GETLINECOUNT];
    intptr_t srcTotal = [ed.scintillaView message:SCI_GETLINECOUNT];
    intptr_t srcLine  = mapTotal > 0 ? (line * srcTotal) / mapTotal : line;
    [ed goToLineNumber:(NSInteger)(srcLine + 1)];
    [ed.window makeFirstResponder:ed.scintillaView];
}

@end
