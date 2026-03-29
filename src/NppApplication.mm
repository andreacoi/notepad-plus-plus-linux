#import "NppApplication.h"
#import "MainWindowController.h"
#import "AppDelegate.h"
#import "EditorView.h"
#import "ScintillaView.h"
#import "Scintilla.h"

@implementation NppApplication {
    NSSet<NSString *> *_recordableSelectors;
}

// ── Build the recordable selectors set ──────────────────────────────────────

- (void)buildRecordableSelectorsFromMenu {
    // Walk the entire menu tree and collect all leaf item selectors
    NSMutableSet<NSString *> *allSelectors = [NSMutableSet set];
    [self _collectSelectorsFrom:[self mainMenu] into:allSelectors];

    // Blacklist: actions that should NEVER be recorded in a macro.
    // Everything else from the menu tree IS recordable.
    // On macOS, keyboard shortcuts go through the menu system (not Scintilla's
    // keyDown:), so even basic actions like selectAll:/cut:/paste:/undo: must
    // be recorded as type-2 menu commands. We suppress Scintilla's
    // SCN_MACRORECORD during execution to prevent double-recording.
    NSSet<NSString *> *blacklist = [NSSet setWithArray:@[
        // ── Macro recording controls (would cause infinite loops) ──
        @"startMacroRecording:",
        @"stopMacroRecording:",
        @"toggleMacroRecording:",
        @"runMacro:",
        @"runMacroMultiple:",
        @"runMacroMultipleTimes:",
        @"saveCurrentMacro:",
        @"runSavedMacro:",

        // ── Dialog/window openers (not document operations) ──
        @"showPreferences:",
        @"showStyleConfigurator:",
        @"importStyleTheme:",
        @"showAboutPanel:",
        @"showShortcutMapper:",
        @"showShortcutMapperMacros:",
        @"showShortcutMapperRunCmds:",
        @"showDefineLanguage:",
        @"showPluginsAdmin:",
        @"showWindowsList:",
        @"showRunDialog:",
        @"showMarkDialog:",
        @"showSummary:",
        @"showGoToLinePanel:",
        @"showColumnEditor:",
        @"showFindInFiles:",
        @"showCLIHelp:",
        @"checkForUpdates:",
        @"showUpdaterProxyStub:",
        @"showMacroManager:",
        @"editPopupContextMenu:",
        @"toggleFindPanel:",
        @"toggleIncrementalSearch:",

        // ── Panel show/toggle (UI-only, don't modify document) ──
        @"showDocumentMap:",
        @"showDocumentList:",
        @"showFunctionList:",
        @"showFolderAsWorkspace:",

        // ── View toggles / panels (UI-only, don't modify document) ──
        @"toggleToolbar:",
        @"toggleStatusBar:",
        @"toggleTabBarWrap:",
        @"togglePostItMode:",
        @"toggleDistractionFreeMode:",
        @"toggleDocumentList:",
        @"toggleClipboardHistory:",
        @"toggleFunctionList:",
        @"toggleDocumentMap:",
        @"toggleProjectPanel:",
        @"toggleCharacterPanel:",
        @"toggleFolderTree:",
        @"toggleGitPanel:",
        @"toggleSyncVerticalScrolling:",
        @"toggleSyncHorizontalScrolling:",
        @"toggleWordWrap:",
        @"toggleShowAllChars:",
        @"toggleIndentGuides:",
        @"toggleLineNumbers:",

        // ── Zoom (view-only, not document content) ──
        @"zoomIn:",
        @"zoomOut:",
        @"zoomRestore:",
        @"focusOnAnotherView:",
        @"toggleFullScreen:",
        @"toggleAlwaysOnTop:",

        // ── Split view management ──
        @"moveToOtherVerticalView:",
        @"cloneToOtherVerticalView:",
        @"moveToOtherHorizontalView:",
        @"cloneToOtherHorizontalView:",
        @"resetSplitView:",

        // ── External operations (open browser, file picker) ──
        @"viewInFirefox:",
        @"viewInChrome:",
        @"viewInSafari:",
        @"viewInCustomBrowser:",
        @"hashFilesMD5:",
        @"hashFilesSHA1:",
        @"hashFilesSHA256:",
        @"hashFilesSHA512:",
        @"openInDefaultViewer:",
        @"openFolderAsWorkspace:",
        @"openSelectedFileInNewInstance:",

        // ── Session management ──
        @"loadSession:",
        @"saveSessionAs:",

        // ── Language/encoding (set lexer, don't modify content) ──
        @"setLanguage:",
        @"setEncodingUTF8:",
        @"setEncodingUTF8BOM:",
        @"setEncodingUTF16LE:",
        @"setEncodingUTF16BE:",
        @"setEncodingANSI:",
        @"setEncodingLatin2:",

        // ── Monitoring / tab management ──
        @"toggleMonitoring:",
        @"pinCurrentTab:",
        @"lockCurrentTab:",

        // ── Window management ──
        @"openNewWindow:",
        @"printDocument:",
    ]];

    [allSelectors minusSet:blacklist];
    _recordableSelectors = [allSelectors copy];
    NSLog(@"[NppApplication] Built recordable selectors: %lu items (blacklisted %lu)",
          (unsigned long)_recordableSelectors.count, (unsigned long)blacklist.count);
}

- (void)_collectSelectorsFrom:(NSMenu *)menu into:(NSMutableSet<NSString *> *)selectors {
    for (NSMenuItem *item in menu.itemArray) {
        if (item.isSeparatorItem) continue;
        if (item.submenu) {
            [self _collectSelectorsFrom:item.submenu into:selectors];
        } else if (item.action) {
            [selectors addObject:NSStringFromSelector(item.action)];
        }
    }
}

// ── Intercept menu actions during recording ─────────────────────────────────

- (BOOL)sendAction:(SEL)action to:(id)target from:(id)sender {
    // Check if this is a recordable action during active recording.
    // Accept both NSMenuItem (menu clicks) and NSToolbarItem (toolbar clicks).
    BOOL fromUI = [sender isKindOfClass:[NSMenuItem class]] ||
                  [sender isKindOfClass:[NSToolbarItem class]];
    BOOL shouldRecord = (_recordableSelectors &&
                         !self.playingBackMacro &&
                         fromUI &&
                         [_recordableSelectors containsObject:NSStringFromSelector(action)]);

    EditorView *editor = shouldRecord ? [self _activeRecordingEditor] : nil;
    if (!editor) shouldRecord = NO;

    if (shouldRecord) {
        // Suppress Scintilla's SCN_MACRORECORD while the menu command runs.
        // Without this, operations like "Convert to Uppercase" would record
        // all underlying SCI_REPLACESEL calls (dumping entire text content).
        // We record only the menu command (type 2), matching Windows NPP behavior.
        [editor.scintillaView message:SCI_STOPRECORD];
    }

    BOOL result = [super sendAction:action to:target from:sender];

    if (shouldRecord) {
        // Resume Scintilla recording and record the menu command
        [editor.scintillaView message:SCI_STARTRECORD];
        [editor recordMenuCommand:NSStringFromSelector(action)];
    }

    return result;
}

/// Find the currently active editor that is recording a macro.
- (nullable EditorView *)_activeRecordingEditor {
    AppDelegate *appDel = (AppDelegate *)self.delegate;
    for (MainWindowController *wc in appDel.windowControllers) {
        EditorView *ed = [wc currentEditor];
        if (ed && ed.isRecordingMacro) return ed;
    }
    return nil;
}

@end
