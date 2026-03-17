#import "AppDelegate.h"
#import "MainWindowController.h"
#import "MenuBuilder.h"
#import "PreferencesWindowController.h"
#import "StyleConfiguratorWindowController.h"

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    // Disable the macOS press-and-hold accent picker so key repeat works in the editor.
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"ApplePressAndHoldEnabled"];
    [MenuBuilder buildMainMenu];

    self.mainWindowController = [[MainWindowController alloc] init];
    [self.mainWindowController showWindow:nil];
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
