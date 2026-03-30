#import "AppDelegate.h"
#import "NppApplication.h"
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

    // ── Build recordable selectors for macro recording ────────────────
    [(NppApplication *)NSApp buildRecordableSelectorsFromMenu];

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

    // ── Background update check (non-blocking, after 5 second delay) ────
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self checkForUpdateUserInitiated:NO];
    });
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

    // Helper block to apply a shortcut override to a menu item
    void (^applyOverride)(NSXMLElement *, NSMenuItem *) = ^(NSXMLElement *sc, NSMenuItem *mi) {
        BOOL hasCtrl  = [[[sc attributeForName:@"Ctrl"]  stringValue] isEqualToString:@"yes"];
        BOOL hasAlt   = [[[sc attributeForName:@"Alt"]   stringValue] isEqualToString:@"yes"];
        BOOL hasShift = [[[sc attributeForName:@"Shift"] stringValue] isEqualToString:@"yes"];
        BOOL hasCmd   = [[[sc attributeForName:@"Cmd"]   stringValue] isEqualToString:@"yes"];
        NSUInteger keyCode = [[[sc attributeForName:@"Key"] stringValue] integerValue];

        if (!hasCmd && hasCtrl && ![sc attributeForName:@"Cmd"]) {
            hasCmd = YES; hasCtrl = NO;
        }

        if (keyCode == 0) {
            mi.keyEquivalent = @"";
            mi.keyEquivalentModifierMask = 0;
        } else {
            NSEventModifierFlags mods = 0;
            if (hasCmd)   mods |= NSEventModifierFlagCommand;
            if (hasCtrl)  mods |= NSEventModifierFlagControl;
            if (hasAlt)   mods |= NSEventModifierFlagOption;
            if (hasShift) mods |= NSEventModifierFlagShift;

            NSString *key = @"";
            if (keyCode >= 'A' && keyCode <= 'Z')
                key = [[NSString stringWithFormat:@"%c", (char)keyCode] lowercaseString];
            else if (keyCode >= '0' && keyCode <= '9')
                key = [NSString stringWithFormat:@"%c", (char)keyCode];
            else if (keyCode >= 112 && keyCode <= 123) {
                unichar fk = NSF1FunctionKey + (keyCode - 112);
                key = [NSString stringWithCharacters:&fk length:1];
            } else
                key = [[NSString stringWithFormat:@"%c", (char)keyCode] lowercaseString];

            mi.keyEquivalent = key;
            mi.keyEquivalentModifierMask = mods;
        }
    };

    NSInteger totalApplied = 0;

    // ── InternalCommands (main menu shortcuts) ──
    for (NSXMLElement *sc in [doc nodesForXPath:@"//InternalCommands/Shortcut" error:nil]) {
        NSString *selectorName = [[sc attributeForName:@"id"] stringValue];
        if (!selectorName.length) continue;
        SEL sel = NSSelectorFromString(selectorName);
        NSMenuItem *mi = [self _findMenuItemWithAction:sel inMenu:[NSApp mainMenu]];
        if (!mi) { NSLog(@"[Shortcuts] WARNING: not found '%@'", selectorName); continue; }
        applyOverride(sc, mi);
        totalApplied++;
    }

    // ── PluginCommands ──
    for (NSXMLElement *pc in [doc nodesForXPath:@"//PluginCommands/PluginCommand" error:nil]) {
        NSString *pluginName = [[pc attributeForName:@"moduleName"] stringValue];
        NSInteger internalID = [[[pc attributeForName:@"internalID"] stringValue] integerValue];
        // Find the plugin menu item by walking Plugins menu
        NSMenu *mainMenu = [NSApp mainMenu];
        for (NSMenuItem *topItem in mainMenu.itemArray) {
            NSString *menuTitle = topItem.submenu.title ?: topItem.title;
            if (![menuTitle isEqualToString:@"Plugins"]) continue;
            for (NSMenuItem *pluginItem in topItem.submenu.itemArray) {
                if (![pluginItem.title isEqualToString:pluginName]) continue;
                if (!pluginItem.submenu) continue;
                NSInteger cmdIdx = 0;
                for (NSMenuItem *cmdItem in pluginItem.submenu.itemArray) {
                    if (cmdItem.isSeparatorItem || !cmdItem.action) continue;
                    if (cmdItem.tag == internalID || cmdIdx == internalID) {
                        applyOverride(pc, cmdItem);
                        totalApplied++;
                        goto nextPlugin;
                    }
                    cmdIdx++;
                }
            }
            break;
        }
        nextPlugin:;
    }

    // ── Macro shortcuts ──
    for (NSXMLElement *mc in [doc nodesForXPath:@"//Macros/Macro" error:nil]) {
        NSString *macroName = [[mc attributeForName:@"name"] stringValue];
        NSUInteger keyCode = [[[mc attributeForName:@"Key"] stringValue] integerValue];
        if (keyCode == 0) continue;
        // Find macro menu item by title
        NSMenu *mainMenu = [NSApp mainMenu];
        for (NSMenuItem *topItem in mainMenu.itemArray) {
            NSString *menuTitle = topItem.submenu.title ?: topItem.title;
            if (![menuTitle isEqualToString:@"Macro"]) continue;
            for (NSMenuItem *mi in topItem.submenu.itemArray) {
                if ([mi.title isEqualToString:macroName]) {
                    applyOverride(mc, mi);
                    totalApplied++;
                    break;
                }
            }
            break;
        }
    }

    // ── Run Commands (UserDefinedCommands) ──
    for (NSXMLElement *rc in [doc nodesForXPath:@"//UserDefinedCommands/Command" error:nil]) {
        NSString *cmdName = [[rc attributeForName:@"name"] stringValue];
        NSUInteger keyCode = [[[rc attributeForName:@"Key"] stringValue] integerValue];
        if (keyCode == 0 || !cmdName.length) continue;
        NSMenu *mainMenu = [NSApp mainMenu];
        for (NSMenuItem *topItem in mainMenu.itemArray) {
            NSString *menuTitle = topItem.submenu.title ?: topItem.title;
            if (![menuTitle isEqualToString:@"Run"]) continue;
            for (NSMenuItem *mi in topItem.submenu.itemArray) {
                if ([mi.title isEqualToString:cmdName]) {
                    applyOverride(rc, mi);
                    totalApplied++;
                    break;
                }
            }
            break;
        }
    }

    NSLog(@"[Shortcuts] Applied %ld shortcut override(s) from shortcuts.xml", (long)totalApplied);
}

- (nullable NSMenuItem *)_findMenuItemWithAction:(SEL)action inMenu:(NSMenu *)menu {
    for (NSMenuItem *mi in menu.itemArray) {
        if (mi.action == action) return mi;
        if (mi.submenu) {
            [mi.submenu update]; // force populate nested submenus
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

// ── Update check (GitHub Releases API) ──────────────────────────────────────

static NSString *const kGitHubReleasesAPI = @"https://api.github.com/repos/nppmss/notepad-plus-plus-macos/releases/latest";
static NSString *const kUpdateMenuItemTag = @"checkForUpdatesMenuItem";

/// Find the "Check for Updates..." menu item in the app menu.
- (nullable NSMenuItem *)_updateMenuItem {
    NSMenu *appMenu = [NSApp mainMenu].itemArray.firstObject.submenu;
    for (NSMenuItem *mi in appMenu.itemArray) {
        if (mi.action == @selector(checkForUpdates:)) return mi;
    }
    return nil;
}

- (void)checkForUpdates:(id)sender {
    [self checkForUpdateUserInitiated:YES];
}

- (void)checkForUpdateUserInitiated:(BOOL)userInitiated {
    NSString *currentVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0.0.0";

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kGitHubReleasesAPI]];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [req setValue:@"notepad-plus-plus-macos" forHTTPHeaderField:@"User-Agent"];
    req.timeoutInterval = 15.0;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || !data) {
                if (userInitiated) {
                    NSAlert *a = [[NSAlert alloc] init];
                    a.messageText = @"Unable to Check for Updates";
                    a.informativeText = error.localizedDescription ?: @"No response from server.";
                    [a runModal];
                }
                return;
            }

            NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
            if (statusCode != 200) {
                if (userInitiated) {
                    NSAlert *a = [[NSAlert alloc] init];
                    a.messageText = @"Unable to Check for Updates";
                    a.informativeText = [NSString stringWithFormat:
                        @"Server returned status %ld. The repository may be private.", (long)statusCode];
                    [a runModal];
                }
                return;
            }

            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (!json) return;

            NSString *tagName = json[@"tag_name"]; // e.g. "v1.1.0"
            if (!tagName.length) return;

            // Strip leading 'v' if present
            NSString *latestVersion = tagName;
            if ([latestVersion hasPrefix:@"v"])
                latestVersion = [latestVersion substringFromIndex:1];

            NSComparisonResult cmp = [latestVersion compare:currentVersion options:NSNumericSearch];

            if (cmp == NSOrderedDescending) {
                // Update available — badge the menu item
                NSMenuItem *mi = [self _updateMenuItem];
                if (mi) {
                    mi.title = [NSString stringWithFormat:@"🟢 Update Available (v%@)", latestVersion];
                }

                if (userInitiated) {
                    [self _showUpdateAlertForVersion:latestVersion
                                       releaseNotes:json[@"body"]
                                          htmlURL:json[@"html_url"]
                                           assets:json[@"assets"]];
                }
            } else {
                if (userInitiated) {
                    NSAlert *a = [[NSAlert alloc] init];
                    a.messageText = @"You're Up to Date";
                    a.informativeText = [NSString stringWithFormat:
                        @"Notepad++ %@ is the latest version.", currentVersion];
                    [a runModal];
                }
            }
        });
    }];
    [task resume];
}

- (void)_showUpdateAlertForVersion:(NSString *)version
                      releaseNotes:(NSString *)notes
                         htmlURL:(NSString *)htmlURL
                          assets:(NSArray *)assets {
    NSString *currentVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0.0.0";

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Notepad++ v%@ is Available", version];
    alert.informativeText = [NSString stringWithFormat:
        @"You are currently running v%@.\n\n%@",
        currentVersion,
        (notes.length > 500) ? [[notes substringToIndex:500] stringByAppendingString:@"…"] : (notes ?: @"")];
    [alert addButtonWithTitle:@"Download"];
    [alert addButtonWithTitle:@"Release Page"];
    [alert addButtonWithTitle:@"Later"];

    NSModalResponse resp = [alert runModal];

    if (resp == NSAlertFirstButtonReturn) {
        // Find DMG asset in release assets
        NSString *downloadURL = nil;
        for (NSDictionary *asset in assets) {
            NSString *name = asset[@"name"];
            if ([name.lowercaseString hasSuffix:@".dmg"]) {
                downloadURL = asset[@"browser_download_url"];
                break;
            }
        }
        if (!downloadURL) downloadURL = htmlURL; // fallback to release page
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:downloadURL]];
    } else if (resp == NSAlertSecondButtonReturn) {
        if (htmlURL.length)
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:htmlURL]];
    }
}

@end
