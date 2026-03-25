#import "AppDelegate.h"
#import "MainWindowController.h"
#import "MenuBuilder.h"
#import "NppLocalizer.h"
#import "NppPluginManager.h"
#import "PreferencesWindowController.h"
#import "StyleConfiguratorWindowController.h"
#import "UserDefineLangManager.h"

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
    [self.mainWindowController showWindow:nil];

    // ── Plugin system ────────────────────────────────────────────────────
    NppPluginManager *pm = [NppPluginManager shared];
    [pm setMainWindowController:self.mainWindowController];
    [pm loadPlugins];

    // Insert plugin menu items (after loadPlugins populates them)
    if (pm.hasPlugins) {
        [MenuBuilder insertPluginMenuItems:[pm pluginMenuItems]];
    }

    // Fire NPPN_READY + NPPN_TBMODIFICATION after UI is fully set up
    [pm fireReady];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    // Route Cmd+Q through the window close path so saveSession (and save prompts) run.
    NSWindow *win = self.mainWindowController.window;
    if (win && win.isVisible) {
        [win performClose:sender];
        return NSTerminateCancel;   // window-close will re-terminate via lastWindowClosed
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
    // Trigger the import sheet from the configurator
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
