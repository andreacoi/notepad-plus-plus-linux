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

- (instancetype)init {
    self = [super init];
    if (self) {
        _windowControllers = [NSMutableArray array];
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    // Disable the macOS press-and-hold accent picker so key repeat works in the editor.
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"ApplePressAndHoldEnabled"];
    [MenuBuilder buildMainMenu];

    // Apply saved shortcut overrides from shortcuts.xml <InternalCommands>
    [self _loadShortcutOverrides];

    // Load User Defined Languages from bundled + user directories.
    [[UserDefineLangManager shared] loadAll];

    // Apply the user's saved language to the freshly-built English menu.
    [[NppLocalizer shared] autoLoad];

    // Create the primary window
    self.mainWindowController = [[MainWindowController alloc] init];
    [_windowControllers addObject:self.mainWindowController];

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

    BOOL hasContent = NO;
    if (cli.sessionFile.length) {
        [self.mainWindowController loadSessionFromPath:cli.sessionFile];
        hasContent = YES;
    } else if (cli.filePaths.count > 0) {
        [self _openFilesFromCLI:cli inController:self.mainWindowController];
        hasContent = YES;
    } else if (!cli.noSession) {
        hasContent = [self.mainWindowController restoreLastSession];
    }
    // If nothing was opened, create an empty tab (first launch or -nosession with no files)
    if (!hasContent) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self.mainWindowController performSelector:@selector(newDocument:) withObject:nil];
        #pragma clang diagnostic pop
    }

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

    // ── Multi-instance (-multiInst): open a second empty window ─────────

    if (cli.multiInstance) {
        [self openNewWindow];
    }
}

// ── New Window ──────────────────────────────────────────────────────────────

- (MainWindowController *)openNewWindow {
    MainWindowController *mwc = [[MainWindowController alloc] init];
    [_windowControllers addObject:mwc];

    // Offset from the primary window so they don't stack exactly
    NSRect primaryFrame = self.mainWindowController.window.frame;
    NSRect newFrame = NSOffsetRect(primaryFrame, 30, -30);
    [mwc.window setFrame:newFrame display:NO];

    [mwc showWindow:nil];

    // Observe close to remove from our array
    [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification
                                                      object:mwc.window
                                                       queue:nil
                                                  usingBlock:^(NSNotification *note) {
        [self.windowControllers removeObject:mwc];
    }];

    return mwc;
}

// ── Open files from CLI ─────────────────────────────────────────────────────

- (void)_openFilesFromCLI:(NppCommandLineParams *)cli inController:(MainWindowController *)mwc {
    NSFileManager *fm = [NSFileManager defaultManager];
    EditorView *lastEditor = nil;

    for (NSString *path in cli.filePaths) {
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:path isDirectory:&isDir]) {
            if (cli.openFoldersAsWorkspace) continue;
        }

        if (isDir && cli.openFoldersAsWorkspace) {
            [mwc performSelector:@selector(showFolderAsWorkspace:) withObject:nil];
            continue;
        }

        if (isDir && cli.recursive) {
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

    if (lastEditor) {
        if (cli.language.length) [lastEditor setLanguage:cli.language];
        if (cli.udlName.length) [lastEditor setLanguage:cli.udlName];
        if (cli.readOnly) [lastEditor.scintillaView message:SCI_SETREADONLY wParam:1 lParam:0];
        if (cli.monitorFiles) lastEditor.monitoringMode = YES;

        if (cli.bytePosition >= 0) {
            [lastEditor.scintillaView message:SCI_GOTOPOS wParam:(uptr_t)cli.bytePosition lParam:0];
            [lastEditor.scintillaView message:SCI_SCROLLCARET wParam:0 lParam:0];
        } else if (cli.lineNumber > 0) {
            if (cli.columnNumber > 0) {
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
}

// ── App lifecycle ───────────────────────────────────────────────────────────

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    // Close all windows — each will save session and prompt for unsaved files.
    // Process in reverse so removals from the array don't skip entries.
    for (NSInteger i = (NSInteger)_windowControllers.count - 1; i >= 0; i--) {
        MainWindowController *mwc = _windowControllers[i];
        NSWindow *win = mwc.window;
        if (win) {
            // Call windowShouldClose: directly (synchronous)
            if ([(id<NSWindowDelegate>)mwc windowShouldClose:win]) {
                [_windowControllers removeObjectAtIndex:i];
                // Use close (not orderOut) so windowWillClose: fires and timers are cleaned up
                [win close];
            } else {
                // User cancelled — abort termination
                return NSTerminateCancel;
            }
        }
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
    // Route to the key window's controller, or primary if no key window
    MainWindowController *mwc = [self _activeWindowController];
    [mwc openFileAtPath:filename];
    return YES;
}

- (void)application:(NSApplication *)sender openFiles:(NSArray<NSString *> *)filenames {
    MainWindowController *mwc = [self _activeWindowController];
    for (NSString *path in filenames) {
        [mwc openFileAtPath:path];
    }
}

/// Returns the window controller for the key window, or mainWindowController as fallback.
- (MainWindowController *)_activeWindowController {
    NSWindow *key = [NSApp keyWindow];
    for (MainWindowController *mwc in _windowControllers) {
        if (mwc.window == key) return mwc;
    }
    return self.mainWindowController;
}

// ── Preferences / About ─────────────────────────────────────────────────────

/// Load shortcut overrides from shortcuts.xml <InternalCommands> and apply to live menu items.
- (void)_loadShortcutOverrides {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@".notepad++/shortcuts.xml"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        NSLog(@"[Shortcuts] No shortcuts.xml found at %@ — skipping overrides", path);
        return;
    }

    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:data options:0 error:nil];
    if (!doc) return;

    NSArray *overrides = [doc nodesForXPath:@"//InternalCommands/Shortcut" error:nil];
    if (!overrides.count) return;

    for (NSXMLElement *sc in overrides) {
        NSString *selectorName = [[sc attributeForName:@"id"] stringValue];
        if (!selectorName.length) continue;

        SEL sel = NSSelectorFromString(selectorName);
        NSMenuItem *mi = [self _findMenuItemWithAction:sel inMenu:[NSApp mainMenu]];
        if (!mi) continue;

        BOOL hasCtrl  = [[[sc attributeForName:@"Ctrl"]  stringValue] isEqualToString:@"yes"];
        BOOL hasAlt   = [[[sc attributeForName:@"Alt"]   stringValue] isEqualToString:@"yes"];
        BOOL hasShift = [[[sc attributeForName:@"Shift"] stringValue] isEqualToString:@"yes"];
        NSUInteger keyCode = [[[sc attributeForName:@"Key"] stringValue] integerValue];

        if (keyCode == 0) {
            mi.keyEquivalent = @"";
            mi.keyEquivalentModifierMask = 0;
        } else {
            NSEventModifierFlags mods = 0;
            // Map Windows Ctrl → macOS Cmd
            if (hasCtrl) mods |= NSEventModifierFlagCommand;
            if (hasAlt)  mods |= NSEventModifierFlagOption;
            if (hasShift) mods |= NSEventModifierFlagShift;

            NSString *key = @"";
            if (keyCode >= 'A' && keyCode <= 'Z') {
                key = [[NSString stringWithFormat:@"%c", (char)keyCode] lowercaseString];
            } else if (keyCode >= '0' && keyCode <= '9') {
                key = [NSString stringWithFormat:@"%c", (char)keyCode];
            } else if (keyCode >= 112 && keyCode <= 123) {
                unichar fk = NSF1FunctionKey + (keyCode - 112);
                key = [NSString stringWithCharacters:&fk length:1];
            } else {
                key = [[NSString stringWithFormat:@"%c", (char)keyCode] lowercaseString];
            }
            mi.keyEquivalent = key;
            mi.keyEquivalentModifierMask = mods;
        }
    }
    NSLog(@"[Shortcuts] Applied %lu shortcut override(s) from shortcuts.xml", (unsigned long)overrides.count);
}

- (nullable NSMenuItem *)_findMenuItemWithAction:(SEL)action inMenu:(NSMenu *)menu {
    for (NSMenuItem *mi in menu.itemArray) {
        if (mi.action == action) return mi;
        if (mi.submenu) {
            NSMenuItem *found = [self _findMenuItemWithAction:action inMenu:mi.submenu];
            if (found) return found;
        }
    }
    return nil;
}

- (void)openNewWindow:(id)sender {
    [self openNewWindow];
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
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.0.0";

#if defined(__arm64__)
    NSString *archStr = @"ARM 64-bit";
#elif defined(__x86_64__)
    NSString *archStr = @"64-bit";
#else
    NSString *archStr = @"unknown";
#endif

    NSAlert *about = [[NSAlert alloc] init];
    about.messageText = [NSString stringWithFormat:@"Notepad++ macOS v%@     (%@)", version, archStr];

    NSString *license =
        @"GNU General Public Licence\n\n"
        @"This program is free software; you can redistribute it and/or "
        @"modify it under the terms of the GNU General Public License "
        @"as published by the Free Software Foundation; either version 3 "
        @"of the License, or at your option any later version.\n\n"
        @"This program is distributed in the hope that it will be useful, "
        @"but WITHOUT ANY WARRANTY; without even the implied warranty of "
        @"MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the "
        @"GNU General Public License for more details.\n\n"
        @"You should have received a copy of the GNU General Public "
        @"License along with this program. If not, see\n"
        @"<https://www.gnu.org/licenses/>.";

    about.informativeText = [NSString stringWithFormat:
        @"Build time: %s - %s\n\n"
        @"Home: https://notepad-plus-plus-mac.org\n\n"
        @"%@", __DATE__, __TIME__, license];

    // Use our logo
    NSImage *logo = [[NSImage alloc] initWithContentsOfFile:
        [NSHomeDirectory() stringByAppendingPathComponent:@".notepad++/plugins/Config/logo100px.png"]];
    if (!logo) {
        // Fallback: try bundle resource
        NSString *logoPath = [[NSBundle mainBundle] pathForResource:@"logo100px" ofType:@"png"
                                                        inDirectory:@"icons/standard/about"];
        if (logoPath) logo = [[NSImage alloc] initWithContentsOfFile:logoPath];
    }
    if (logo) about.icon = logo;

    [about addButtonWithTitle:@"OK"];
    [about runModal];
}

@end
