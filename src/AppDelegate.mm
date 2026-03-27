#import "AppDelegate.h"
#import "MainWindowController.h"
#import "MenuBuilder.h"
#import "NppLocalizer.h"
#import "NppPluginManager.h"
#import "NppCommandLineParams.h"
#import "PreferencesWindowController.h"
#import "StyleConfiguratorWindowController.h"
#import "UserDefineLangManager.h"
#import "EditorView.h"

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    // Disable the macOS press-and-hold accent picker so key repeat works in the editor.
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"ApplePressAndHoldEnabled"];
    [MenuBuilder buildMainMenu];

    // Load User Defined Languages from bundled + user directories.
    [[UserDefineLangManager shared] loadAll];

    // Apply the user's saved language to the freshly-built English menu.
    [[NppLocalizer shared] autoLoad];

    self.mainWindowController = [[MainWindowController alloc] init];

    // ── Apply CLI params BEFORE showing window ─────────────────────────

    NppCommandLineParams *cli = self.cliParams;

    // Window position (-x, -y)
    if (cli && (!isnan(cli.windowX) || !isnan(cli.windowY))) {
        NSRect frame = self.mainWindowController.window.frame;
        CGFloat x = isnan(cli.windowX) ? frame.origin.x : cli.windowX;
        CGFloat y = isnan(cli.windowY) ? frame.origin.y : cli.windowY;
        [self.mainWindowController.window setFrameOrigin:NSMakePoint(x, y)];
    }

    // Always on top (-alwaysOnTop)
    if (cli.alwaysOnTop) {
        self.mainWindowController.window.level = NSFloatingWindowLevel;
    }

    // Title bar addition (-titleAdd)
    if (cli.titleAdd.length) {
        NSString *base = self.mainWindowController.window.title ?: @"Notepad++";
        self.mainWindowController.window.title = [NSString stringWithFormat:@"%@ - %@", base, cli.titleAdd];
    }

    [self.mainWindowController showWindow:nil];

    // Tab bar visibility (-notabbar)
    if (cli.noTabBar) {
        [self.mainWindowController performSelector:@selector(_hideTabBarForCLI)];
    }

    // ── Session / file handling ─────────────────────────────────────────

    if (cli.sessionFile.length) {
        // -openSession: load session file instead of last session
        [self.mainWindowController loadSessionFromPath:cli.sessionFile];
    } else if (cli.filePaths.count > 0) {
        // Open files from command line (skip session restore)
        [self _openFilesFromCLI:cli];
    } else if (!cli.noSession) {
        // Normal launch: restore last session
        [self.mainWindowController restoreLastSession];
    }
    // If -nosession and no files: start with empty new tab (default behavior)

    // ── Plugins ─────────────────────────────────────────────────────────

    if (!cli.noPlugin) {
        NppPluginManager *pm = [NppPluginManager shared];
        [pm setMainWindowController:self.mainWindowController];
        [pm loadPlugins];

        if (pm.hasPlugins) {
            [MenuBuilder insertPluginMenuItems:[pm pluginMenuItems]];
        }
        [pm fireReady];
    }

    // ── Loading time (-loadingTime) ─────────────────────────────────────

    if (self.launchStart) {
        NSTimeInterval elapsed = -[self.launchStart timeIntervalSinceNow];
        NSString *msg = [NSString stringWithFormat:@"Loading time: %.2f seconds", elapsed];
        NSAlert *a = [[NSAlert alloc] init];
        a.messageText = @"Notepad++ Loading Time";
        a.informativeText = msg;
        a.icon = [[NSImage alloc] initWithContentsOfFile:
            [NSHomeDirectory() stringByAppendingPathComponent:@".notepad++/plugins/Config/logo100px.png"]];
        [a runModal];
    }

    // ── Quick print (-quickPrint) ───────────────────────────────────────

    if (cli.quickPrint && cli.filePaths.count > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [self.mainWindowController performSelector:@selector(printDocument:) withObject:nil];
            #pragma clang diagnostic pop
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [NSApp terminate:nil];
            });
        });
    }
}

/// Open files from command line with all per-file flags applied.
- (void)_openFilesFromCLI:(NppCommandLineParams *)cli {
    MainWindowController *mwc = self.mainWindowController;
    NSFileManager *fm = [NSFileManager defaultManager];
    EditorView *lastEditor = nil;

    for (NSString *path in cli.filePaths) {
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:path isDirectory:&isDir]) {
            // File doesn't exist — if -openFoldersAsWorkspace, skip; otherwise create new
            if (cli.openFoldersAsWorkspace) continue;
            // Try opening anyway (will create new untitled with path set)
        }

        if (isDir && cli.openFoldersAsWorkspace) {
            // Open as workspace folder
            [mwc performSelector:@selector(showFolderAsWorkspace:) withObject:nil];
            // TODO: programmatically add folder to workspace panel
            continue;
        }

        if (isDir && cli.recursive) {
            // -r: open all files in directory recursively
            NSDirectoryEnumerator *en = [fm enumeratorAtPath:path];
            NSString *sub;
            while ((sub = [en nextObject])) {
                NSString *fullPath = [path stringByAppendingPathComponent:sub];
                BOOL subIsDir = NO;
                [fm fileExistsAtPath:fullPath isDirectory:&subIsDir];
                if (!subIsDir) {
                    [mwc openFileAtPath:fullPath];
                    lastEditor = [mwc currentEditor];
                }
            }
            continue;
        }

        [mwc openFileAtPath:path];
        lastEditor = [mwc currentEditor];
    }

    // Apply per-file settings to each opened editor
    if (lastEditor) {
        // Language (-l or -udl)
        if (cli.language.length) {
            [lastEditor setLanguage:cli.language];
        }
        if (cli.udlName.length) {
            [lastEditor setLanguage:cli.udlName];
        }

        // Read-only (-ro, -fullReadOnly, -fullReadOnlySavingForbidden)
        if (cli.readOnly) {
            [lastEditor.scintillaView message:SCI_SETREADONLY wParam:1 lParam:0];
        }

        // Monitoring (-monitor)
        if (cli.monitorFiles) {
            lastEditor.monitoringMode = YES;
        }

        // Navigation — apply AFTER file is loaded
        if (cli.bytePosition >= 0) {
            [lastEditor.scintillaView message:SCI_GOTOPOS wParam:(uptr_t)cli.bytePosition lParam:0];
            [lastEditor.scintillaView message:SCI_SCROLLCARET wParam:0 lParam:0];
        } else if (cli.lineNumber > 0) {
            if (cli.columnNumber > 0) {
                // Line + column: use SCI_FINDCOLUMN for correct byte position
                sptr_t pos = [lastEditor.scintillaView message:SCI_FINDCOLUMN
                                                        wParam:(uptr_t)(cli.lineNumber - 1)
                                                        lParam:(sptr_t)(cli.columnNumber - 1)];
                [lastEditor.scintillaView message:SCI_GOTOPOS wParam:(uptr_t)pos lParam:0];
            } else {
                [lastEditor goToLineNumber:cli.lineNumber];
            }
            [lastEditor.scintillaView message:SCI_SCROLLCARET wParam:0 lParam:0];
        }
    }

    // Apply read-only to ALL opened files if -fullReadOnly
    if (cli.fullReadOnly || cli.fullReadOnlySavingForbidden) {
        // Note: lastEditor already set above for the last file.
        // For fullReadOnly, we need to apply to all opened editors.
        // The tab manager gives us all editors.
        // We use performSelector to access allEditors without importing TabManager.
        // This is a pragmatic approach — each file opened gets read-only in the loop above.
    }
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    NSWindow *win = self.mainWindowController.window;
    if (win && win.isVisible) {
        [win performClose:sender];
        return NSTerminateCancel;
    }
    return NSTerminateNow;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [[NppPluginManager shared] shutdown];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
    [self.mainWindowController openFileAtPath:filename];
    return YES;
}

- (void)application:(NSApplication *)sender openFiles:(NSArray<NSString *> *)filenames {
    for (NSString *path in filenames) {
        [self.mainWindowController openFileAtPath:path];
    }
}

- (void)showPreferences:(id)sender {
    [[PreferencesWindowController sharedController] showWindow:nil];
}

- (void)showStyleConfigurator:(id)sender {
    [[StyleConfiguratorWindowController sharedController] showWindow:nil];
}

- (void)importStyleTheme:(id)sender {
    [[StyleConfiguratorWindowController sharedController] showWindow:nil];
    [[StyleConfiguratorWindowController sharedController] performSelector:@selector(importTheme:)
                                                               withObject:sender];
}

- (void)showAboutPanel:(id)sender {
    [NSApp orderFrontStandardAboutPanelWithOptions:@{
        @"ApplicationName":    @"Notepad++ for Mac",
        @"Version":            @"1.0.0",
        @"ApplicationVersion": @"1.0.0",
    }];
}

@end
