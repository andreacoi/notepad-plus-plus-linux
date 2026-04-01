#import "NppPluginManager.h"
#import "MainWindowController.h"
#import "TabManager.h"
#import "EditorView.h"
#import "ScintillaView.h"

#include <dlfcn.h>
#include <string>
#include <vector>
#include <memory>

#include "Scintilla.h"
#include "NppPluginInterfaceMac.h"

NSNotificationName const NppPluginsDidLoadNotification = @"NppPluginsDidLoadNotification";

// ═══════════════════════════════════════════════════════════════════════════
// ID Allocator — hands out non-overlapping integer ranges
// ═══════════════════════════════════════════════════════════════════════════

class IDAllocator {
public:
    IDAllocator() : _start(0), _current(0), _limit(0) {}
    IDAllocator(int start, int limit)
        : _start(start), _current(start), _limit(limit) {}

    bool allocate(int count, int *outStart) {
        if (_current + count > _limit)
            return false;
        *outStart = _current;
        _current += count;
        return true;
    }

    bool isInRange(int id) const {
        return id >= _start && id < _current;
    }

private:
    int _start;
    int _current;
    int _limit;
};

// ═══════════════════════════════════════════════════════════════════════════
// PluginInfo — one loaded plugin
// ═══════════════════════════════════════════════════════════════════════════

struct PluginInfo {
    void           *handle = nullptr;   // dlopen handle
    std::string     moduleName;         // e.g. "ReverseLines"
    std::string     displayName;        // from getName()

    PFUNCSETINFO         pSetInfo       = nullptr;
    PFUNCGETNAME         pGetName       = nullptr;
    PFUNCGETFUNCSARRAY   pGetFuncsArray = nullptr;
    PBENOTIFIED          pBeNotified    = nullptr;
    PMESSAGEPROC         pMessageProc   = nullptr;

    struct FuncItem     *funcItems      = nullptr;
    int                  nbFuncItems    = 0;

    ~PluginInfo() {
        if (handle)
            dlclose(handle);
    }
};

// ═══════════════════════════════════════════════════════════════════════════
// Forward declaration of the C sendMessage callback
// ═══════════════════════════════════════════════════════════════════════════

static intptr_t nppSendMessageCallback(uintptr_t handle, uint32_t msg,
                                        uintptr_t wParam, intptr_t lParam);

// ═══════════════════════════════════════════════════════════════════════════
// Opaque handle constants
// ═══════════════════════════════════════════════════════════════════════════

static const uintptr_t kHandleNpp            = 0x4E505000;  // "NPP\0"
static const uintptr_t kHandleScintillaMain  = 0x5343490A;  // "SCI\n"
static const uintptr_t kHandleScintillaSub   = 0x5343490B;  // "SCI\v"

// ═══════════════════════════════════════════════════════════════════════════
// Private interface
// ═══════════════════════════════════════════════════════════════════════════

@interface NppPluginManager () {
    __weak MainWindowController *_mwc;

    std::vector<std::unique_ptr<PluginInfo>> _plugins;

    IDAllocator _cmdIDAlloc;
    IDAllocator _markerAlloc;
    IDAllocator _indicatorAlloc;

    BOOL _shutdownFired;
    int  _nextPluginCmdBase;  // base cmdID for next plugin's FuncItems
}
@end

// ═══════════════════════════════════════════════════════════════════════════
// Implementation
// ═══════════════════════════════════════════════════════════════════════════

@implementation NppPluginManager

+ (instancetype)shared {
    static NppPluginManager *inst;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inst = [[NppPluginManager alloc] init];
    });
    return inst;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // ID ranges matching Windows NPP resource.h
        _cmdIDAlloc     = IDAllocator(23000, 24999);
        _markerAlloc    = IDAllocator(1, 15);
        _indicatorAlloc = IDAllocator(9, 20);
        _nextPluginCmdBase = 22000;  // ID_PLUGINS_CMD
        _shutdownFired = NO;
    }
    return self;
}

- (void)setMainWindowController:(MainWindowController *)mwc {
    _mwc = mwc;
}

// ── Plugin directory ────────────────────────────────────────────────────

static NSString *pluginBaseDir(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@".notepad++/plugins"];
}

// ── Loading ─────────────────────────────────────────────────────────────

- (void)loadPlugins {
    NSString *baseDir = pluginBaseDir();
    NSFileManager *fm = [NSFileManager defaultManager];

    // Ensure the plugins directory exists
    if (![fm fileExistsAtPath:baseDir]) {
        [fm createDirectoryAtPath:baseDir withIntermediateDirectories:YES attributes:nil error:nil];
        return; // no plugins yet
    }

    // Scan for plugin subdirectories: plugins/PluginName/PluginName.dylib
    NSArray<NSString *> *subdirs = [fm contentsOfDirectoryAtPath:baseDir error:nil];
    if (!subdirs)
        return;

    for (NSString *dirName in subdirs) {
        NSString *dirPath = [baseDir stringByAppendingPathComponent:dirName];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:dirPath isDirectory:&isDir] || !isDir)
            continue;

        NSString *dylibName = [dirName stringByAppendingPathExtension:@"dylib"];
        NSString *dylibPath = [dirPath stringByAppendingPathComponent:dylibName];

        if (![fm fileExistsAtPath:dylibPath]) {
            // Also try .bundle extension
            NSString *bundleName = [dirName stringByAppendingPathExtension:@"bundle"];
            NSString *bundlePath = [dirPath stringByAppendingPathComponent:bundleName];
            if ([fm fileExistsAtPath:bundlePath])
                dylibPath = bundlePath;
            else
                continue;
        }

        [self loadPluginAtPath:dylibPath moduleName:dirName];
    }

    if (_plugins.size() > 0) {
        NSLog(@"[Plugins] Loaded %zu plugin(s)", _plugins.size());
    }
}

- (BOOL)loadPluginAtPath:(NSString *)path moduleName:(NSString *)moduleName {
    void *handle = dlopen(path.UTF8String, RTLD_LAZY | RTLD_LOCAL);
    if (!handle) {
        NSLog(@"[Plugins] Failed to load %@: %s", path, dlerror());
        return NO;
    }

    // Resolve required exports
    auto pSetInfo       = (PFUNCSETINFO)       dlsym(handle, "setInfo");
    auto pGetName       = (PFUNCGETNAME)       dlsym(handle, "getName");
    auto pGetFuncsArray = (PFUNCGETFUNCSARRAY)  dlsym(handle, "getFuncsArray");
    auto pBeNotified    = (PBENOTIFIED)         dlsym(handle, "beNotified");
    auto pMessageProc   = (PMESSAGEPROC)        dlsym(handle, "messageProc");

    if (!pSetInfo || !pGetName || !pGetFuncsArray || !pBeNotified) {
        NSLog(@"[Plugins] %@ is missing required exports — skipping", moduleName);
        dlclose(handle);
        return NO;
    }

    // Build NppData for this plugin
    struct NppData nppData;
    nppData._nppHandle            = kHandleNpp;
    nppData._scintillaMainHandle  = kHandleScintillaMain;
    nppData._scintillaSecondHandle = kHandleScintillaSub;
    nppData._sendMessage          = nppSendMessageCallback;

    // Call setInfo (plugin stores handles and initializes FuncItems)
    @try {
        pSetInfo(nppData);
    } @catch (NSException *e) {
        NSLog(@"[Plugins] %@ crashed in setInfo: %@", moduleName, e);
        dlclose(handle);
        return NO;
    }

    // Get plugin name
    const char *name = nullptr;
    @try {
        name = pGetName();
    } @catch (NSException *e) {
        NSLog(@"[Plugins] %@ crashed in getName: %@", moduleName, e);
        dlclose(handle);
        return NO;
    }

    // Get function items
    int nbFunc = 0;
    struct FuncItem *funcItems = nullptr;
    @try {
        funcItems = pGetFuncsArray(&nbFunc);
    } @catch (NSException *e) {
        NSLog(@"[Plugins] %@ crashed in getFuncsArray: %@", moduleName, e);
        dlclose(handle);
        return NO;
    }

    // Assign command IDs to each FuncItem
    for (int i = 0; i < nbFunc; i++) {
        if (funcItems[i]._pFunc) {
            funcItems[i]._cmdID = _nextPluginCmdBase++;
        }
    }

    // Store plugin info
    auto pi = std::make_unique<PluginInfo>();
    pi->handle         = handle;
    pi->moduleName     = moduleName.UTF8String;
    pi->displayName    = name ? name : moduleName.UTF8String;
    pi->pSetInfo       = pSetInfo;
    pi->pGetName       = pGetName;
    pi->pGetFuncsArray = pGetFuncsArray;
    pi->pBeNotified    = pBeNotified;
    pi->pMessageProc   = pMessageProc;
    pi->funcItems      = funcItems;
    pi->nbFuncItems    = nbFunc;

    NSLog(@"[Plugins] Loaded \"%s\" (%d commands)", pi->displayName.c_str(), nbFunc);
    _plugins.push_back(std::move(pi));
    return YES;
}

// ── Notifications ───────────────────────────────────────────────────────

- (void)fireReady {
    [self notifyPluginsWithCode:NPPN_READY];
    [self notifyPluginsWithCode:NPPN_TBMODIFICATION];

    [[NSNotificationCenter defaultCenter]
        postNotificationName:NppPluginsDidLoadNotification object:self];
}

- (void)shutdown {
    if (_shutdownFired) return;
    _shutdownFired = YES;

    [self notifyPluginsWithCode:NPPN_BEFORESHUTDOWN];
    [self notifyPluginsWithCode:NPPN_SHUTDOWN];

    // Unload all plugins (destructors call dlclose)
    _plugins.clear();
}

- (void)notifyPluginsWithCode:(unsigned int)code {
    [self notifyPluginsWithCode:code bufferID:0];
}

- (void)notifyPluginsWithCode:(unsigned int)code bufferID:(intptr_t)bufferID {
    if (_shutdownFired && code != NPPN_SHUTDOWN)
        return;

    // Build an SCNotification on the stack
    SCNotification scn = {};
    scn.nmhdr.code     = code;
    scn.nmhdr.hwndFrom = (void *)(uintptr_t)kHandleNpp;
    scn.nmhdr.idFrom   = (uptr_t)bufferID;

    for (auto &pi : _plugins) {
        if (!pi->pBeNotified) continue;
        @try {
            pi->pBeNotified(&scn);
        } @catch (NSException *e) {
            NSLog(@"[Plugins] \"%s\" crashed in beNotified (code=%u): %@",
                  pi->displayName.c_str(), code, e);
        }
    }
}

// ── Menu ────────────────────────────────────────────────────────────────

- (BOOL)hasPlugins {
    return _plugins.size() > 0;
}

- (NSInteger)pluginCount {
    return (NSInteger)_plugins.size();
}

- (NSArray<NSMenuItem *> *)pluginMenuItems {
    NSMutableArray *items = [NSMutableArray array];

    for (auto &pi : _plugins) {
        NSString *pluginName = [NSString stringWithUTF8String:pi->displayName.c_str()];
        NSMenu *submenu = [[NSMenu alloc] initWithTitle:pluginName];

        for (int i = 0; i < pi->nbFuncItems; i++) {
            struct FuncItem *fi = &pi->funcItems[i];

            // Separator: _pFunc == NULL and empty name
            if (!fi->_pFunc) {
                [submenu addItem:[NSMenuItem separatorItem]];
                continue;
            }

            NSString *title = [NSString stringWithUTF8String:fi->_itemName];
            NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:title
                                                        action:@selector(pluginMenuAction:)
                                                 keyEquivalent:@""];
            mi.tag = fi->_cmdID;
            mi.target = self;

            if (fi->_init2Check)
                mi.state = NSControlStateValueOn;

            // TODO: wire up keyboard shortcut from _pShKey

            [submenu addItem:mi];
        }

        NSMenuItem *pluginItem = [[NSMenuItem alloc] initWithTitle:pluginName
                                                            action:nil
                                                     keyEquivalent:@""];
        pluginItem.submenu = submenu;
        [items addObject:pluginItem];
    }

    return items;
}

- (void)pluginMenuAction:(NSMenuItem *)sender {
    [self runPluginCommandWithID:(int)sender.tag];
}

- (NSArray<NSDictionary *> *)allPluginActions {
    NSMutableArray *actions = [NSMutableArray array];
    // Collect cmdIDs that have registered toolbar icons
    NSMutableSet *toolbarCmdIDs = [NSMutableSet set];
    for (NSDictionary *pti in [_mwc valueForKey:@"_pluginToolbarItems"])
        if (pti[@"cmdID"]) [toolbarCmdIDs addObject:pti[@"cmdID"]];

    for (auto &pi : _plugins) {
        NSString *pluginName = [NSString stringWithUTF8String:pi->displayName.c_str()];
        for (int i = 0; i < pi->nbFuncItems; i++) {
            struct FuncItem *fi = &pi->funcItems[i];
            if (!fi->_pFunc) continue; // skip separators
            NSString *actionName = [NSString stringWithUTF8String:fi->_itemName];
            BOOL hasIcon = [toolbarCmdIDs containsObject:@(fi->_cmdID)];
            [actions addObject:@{
                @"pluginName": pluginName,
                @"actionName": actionName,
                @"cmdID": @(fi->_cmdID),
                @"hasToolbarIcon": @(hasIcon)
            }];
        }
    }
    return actions;
}

- (void)runPluginCommandWithID:(int)cmdID {
    for (auto &pi : _plugins) {
        for (int i = 0; i < pi->nbFuncItems; i++) {
            if (pi->funcItems[i]._cmdID == cmdID && pi->funcItems[i]._pFunc) {
                @try {
                    pi->funcItems[i]._pFunc();
                } @catch (NSException *e) {
                    NSLog(@"[Plugins] \"%s\" crashed running command %d: %@",
                          pi->displayName.c_str(), cmdID, e);
                    NSAlert *alert = [[NSAlert alloc] init];
                    alert.messageText = @"Plugin Error";
                    alert.informativeText = [NSString stringWithFormat:
                        @"Plugin \"%s\" encountered an error running command \"%s\".\n\n%@",
                        pi->displayName.c_str(), pi->funcItems[i]._itemName, e.reason];
                    alert.alertStyle = NSAlertStyleWarning;
                    [alert runModal];
                }
                return;
            }
        }
    }
}

// ── NPPM_* message dispatch ─────────────────────────────────────────────

- (intptr_t)handleNppMessage:(uint32_t)msg wParam:(uintptr_t)wParam lParam:(intptr_t)lParam {
    switch (msg) {

        // ── Editor / view queries ──────────────────────────────────────
        case NPPM_GETCURRENTSCINTILLA: {
            // Write 0 (main) or 1 (sub) to *lParam
            // For now, always return 0 (primary view)
            if (lParam) {
                int *result = (int *)lParam;
                *result = MAIN_VIEW;
            }
            return 0;
        }

        case NPPM_GETCURRENTVIEW: {
            return MAIN_VIEW;
        }

        case NPPM_GETCURRENTBUFFERID: {
            // Use the EditorView pointer as a buffer ID
            MainWindowController *mwc = _mwc;
            if (!mwc) return 0;
            EditorView *ed = [mwc currentEditor];
            return (intptr_t)(__bridge void *)ed;
        }

        case NPPM_GETFULLPATHFROMBUFFERID: {
            // wParam = bufferID (EditorView*), lParam = char* buffer to fill
            EditorView *ed = (__bridge EditorView *)(void *)wParam;
            char *buf = (char *)lParam;
            if (ed && ed.filePath && buf) {
                strlcpy(buf, ed.filePath.UTF8String, 1024);
                return (intptr_t)strlen(buf);
            }
            if (buf) buf[0] = '\0';
            return 0;
        }

        case NPPM_GETNBOPENFILES: {
            MainWindowController *mwc = _mwc;
            if (!mwc) return 0;
            // wParam unused, lParam: 0=all, 1=primary, 2=secondary
            // For now just count primary tabs
            EditorView *ed = [mwc currentEditor];
            (void)ed;
            // We need access to allEditors — for now return a simple count
            // TODO: access tab managers properly
            return 1;
        }

        case NPPM_GETNPPVERSION: {
            // Return version as (major << 16) | minor
            // Our macOS port version: 0.1.0 → we'll report as 8.7 for compat
            return (8 << 16) | 7;
        }

        case NPPM_GETPLUGINHOMEPATH: {
            // Write the plugins directory path to (char*)lParam
            char *buf = (char *)lParam;
            if (buf) {
                NSString *path = pluginBaseDir();
                strlcpy(buf, path.UTF8String, 1024);
                return (intptr_t)strlen(buf);
            }
            return 0;
        }

        case NPPM_GETPLUGINSCONFIGDIR: {
            char *buf = (char *)lParam;
            if (buf) {
                NSString *path = [pluginBaseDir() stringByAppendingPathComponent:@"Config"];
                // Ensure it exists
                [[NSFileManager defaultManager] createDirectoryAtPath:path
                                         withIntermediateDirectories:YES attributes:nil error:nil];
                strlcpy(buf, path.UTF8String, 1024);
                return (intptr_t)strlen(buf);
            }
            return 0;
        }

        case NPPM_GETNPPSETTINGSDIRPATH: {
            char *buf = (char *)lParam;
            if (buf) {
                NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@".notepad++"];
                strlcpy(buf, path.UTF8String, 1024);
                return (intptr_t)strlen(buf);
            }
            return 0;
        }

        // ── File operations ──────────────────────────────────────────
        case NPPM_DOOPEN: {
            // lParam = const char* filePath (UTF-8)
            const char *path = (const char *)lParam;
            if (path) {
                MainWindowController *mwc = _mwc;
                if (mwc) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [mwc openFileAtPath:[NSString stringWithUTF8String:path]];
                    });
                    return 1;
                }
            }
            return 0;
        }

        case NPPM_SAVECURRENTFILE: {
            MainWindowController *mwc = _mwc;
            if (mwc) {
                EditorView *ed = [mwc currentEditor];
                if (ed) {
                    NSError *err = nil;
                    return [ed saveError:&err] ? 1 : 0;
                }
            }
            return 0;
        }

        // ── Menu ────────────────────────────────────────────────────
        case NPPM_SETMENUITEMCHECK: {
            // wParam = cmdID, lParam = checked (BOOL)
            // Find the menu item by tag and set its state
            int cmdID = (int)wParam;
            BOOL checked = (BOOL)lParam;
            NSMenu *pluginsMenu = [self findPluginsMenu];
            if (pluginsMenu) {
                NSMenuItem *item = [self findMenuItemWithTag:cmdID inMenu:pluginsMenu];
                if (item) {
                    item.state = checked ? NSControlStateValueOn : NSControlStateValueOff;
                }
            }
            return 0;
        }

        // ── ID allocation ───────────────────────────────────────────
        case NPPM_ALLOCATECMDID: {
            int count = (int)wParam;
            int *start = (int *)lParam;
            return _cmdIDAlloc.allocate(count, start) ? TRUE : FALSE;
        }

        case NPPM_ALLOCATEMARKER: {
            int count = (int)wParam;
            int *start = (int *)lParam;
            return _markerAlloc.allocate(count, start) ? TRUE : FALSE;
        }

        case NPPM_ALLOCATEINDICATOR: {
            int count = (int)wParam;
            int *start = (int *)lParam;
            return _indicatorAlloc.allocate(count, start) ? TRUE : FALSE;
        }

        case NPPM_GETBOOKMARKID: {
            // Scintilla bookmark marker ID (same as Windows NPP default)
            return 24;  // MARK_BOOKMARK in NPP
        }

        // ── Dark mode ──────────────────────────────────────────────
        case NPPM_ISDARKMODEENABLED: {
            if (@available(macOS 10.14, *)) {
                NSAppearanceName name = [NSApp.effectiveAppearance
                    bestMatchFromAppearancesWithNames:@[
                        NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
                return [name isEqualToString:NSAppearanceNameDarkAqua] ? 1 : 0;
            }
            return 0;
        }

        case NPPM_DARKMODESUBCLASSANDTHEME: {
            // On macOS, dark mode is automatic via NSAppearance. No-op.
            return 1;
        }

        // ── Menu command dispatch ────────────────────────────────────
        case NPPM_MENUCOMMAND: {
            // lParam = IDM_* command ID
            int idm = (int)lParam;
            MainWindowController *mwc = _mwc;
            if (!mwc) return 0;

            SEL action = nil;
            switch (idm) {
                case 41001: action = @selector(newDocument:);    break; // IDM_FILE_NEW
                case 41002: action = @selector(openDocument:);   break; // IDM_FILE_OPEN
                case 41006: action = @selector(saveDocument:);   break; // IDM_FILE_SAVE
                case 41003: action = @selector(closeCurrentTab:); break; // IDM_FILE_CLOSE
                default:
                    NSLog(@"[Plugins] Unhandled NPPM_MENUCOMMAND IDM=%d", idm);
                    return 0;
            }
            if (action && [mwc respondsToSelector:action]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    // Use performSelector for action methods defined in .mm only
                    #pragma clang diagnostic push
                    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    [mwc performSelector:action withObject:nil];
                    #pragma clang diagnostic pop
                });
                return 1;
            }
            return 0;
        }

        // ── Toolbar icon registration ───────────────────────────────
        case NPPM_ADDTOOLBARICON_FORDARKMODE: {
            // wParam = cmdID assigned to a FuncItem
            int cmdID = (int)wParam;

            // Find which plugin owns this cmdID and load its toolbar.png
            std::string pluginDirName;
            std::string pluginDisplayName;
            for (auto &pi : _plugins) {
                for (int i = 0; i < pi->nbFuncItems; i++) {
                    if (pi->funcItems[i]._cmdID == cmdID) {
                        pluginDirName = pi->moduleName;
                        pluginDisplayName = pi->displayName;
                        break;
                    }
                }
                if (!pluginDirName.empty()) break;
            }

            if (pluginDirName.empty()) {
                NSLog(@"[Plugins] ADDTOOLBARICON: no plugin owns cmdID %d", cmdID);
                return 0;
            }

            NSString *iconPath = [NSString stringWithFormat:@"%@/%s/toolbar.png",
                                  pluginBaseDir(), pluginDirName.c_str()];
            NSImage *icon = [[NSImage alloc] initWithContentsOfFile:iconPath];
            if (!icon) {
                NSLog(@"[Plugins] ADDTOOLBARICON: toolbar.png not found at %@", iconPath);
                return 0;
            }
            icon.size = NSMakeSize(16, 16);

            MainWindowController *mwc = _mwc;
            if (mwc) {
                NSString *tooltip = [NSString stringWithUTF8String:pluginDisplayName.c_str()];
                // Find the FuncItem name for a more specific tooltip
                for (auto &pi : _plugins) {
                    for (int i = 0; i < pi->nbFuncItems; i++) {
                        if (pi->funcItems[i]._cmdID == cmdID) {
                            tooltip = [NSString stringWithFormat:@"%s",
                                       pi->funcItems[i]._itemName];
                            break;
                        }
                    }
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    [mwc addPluginToolbarIcon:icon tooltip:tooltip cmdID:cmdID];
                });
            }
            return 1;
        }

        // ── Stubs for messages plugins query but don't critically need ─
        case NPPM_GETWINDOWSVERSION:
            return 0;  // Not Windows

        case NPPM_GETAPPDATAPLUGINSALLOWED:
            return 1;  // Always allow

        case NPPM_ISDARKMODEENABLED + 1:  // NPPM_GETCURRENTCMDLINE
        case NPPM_ISTABBARHIDDEN:
        case NPPM_ISTOOLBARHIDDEN:
        case NPPM_ISMENUHIDDEN:
        case NPPM_ISSTATUSBARHIDDEN:
            return 0;

        case NPPM_GETMENUHANDLE:
            return 0;  // No HMENU on macOS

        // ── Inter-plugin communication ──────────────────────────────
        case NPPM_MSGTOPLUGIN: {
            const char *destModule = (const char *)wParam;
            struct CommunicationInfo *ci = (struct CommunicationInfo *)lParam;
            if (!destModule || !ci) return 0;

            for (auto &pi : _plugins) {
                if (pi->moduleName == destModule && pi->pMessageProc) {
                    @try {
                        return pi->pMessageProc(NPPM_MSGTOPLUGIN, 0, (intptr_t)ci);
                    } @catch (NSException *e) {
                        NSLog(@"[Plugins] \"%s\" crashed in messageProc: %@",
                              pi->displayName.c_str(), e);
                        return 0;
                    }
                }
            }
            return 0;
        }

        // ── RUNCOMMAND_USER submessages ─────────────────────────────
        case NPPM_GETFULLCURRENTPATH: {
            char *buf = (char *)lParam;
            if (buf) {
                MainWindowController *mwc = _mwc;
                EditorView *ed = mwc ? [mwc currentEditor] : nil;
                if (ed && ed.filePath) {
                    strlcpy(buf, ed.filePath.UTF8String, 1024);
                } else {
                    buf[0] = '\0';
                }
            }
            return 0;
        }

        case NPPM_GETCURRENTDIRECTORY: {
            char *buf = (char *)lParam;
            if (buf) {
                MainWindowController *mwc = _mwc;
                EditorView *ed = mwc ? [mwc currentEditor] : nil;
                if (ed && ed.filePath) {
                    NSString *dir = [ed.filePath stringByDeletingLastPathComponent];
                    strlcpy(buf, dir.UTF8String, 1024);
                } else {
                    buf[0] = '\0';
                }
            }
            return 0;
        }

        case NPPM_GETFILENAME: {
            char *buf = (char *)lParam;
            if (buf) {
                MainWindowController *mwc = _mwc;
                EditorView *ed = mwc ? [mwc currentEditor] : nil;
                if (ed && ed.filePath) {
                    NSString *name = [ed.filePath lastPathComponent];
                    strlcpy(buf, name.UTF8String, 1024);
                } else {
                    buf[0] = '\0';
                }
            }
            return 0;
        }

        case NPPM_GETNAMEPART: {
            char *buf = (char *)lParam;
            if (buf) {
                MainWindowController *mwc = _mwc;
                EditorView *ed = mwc ? [mwc currentEditor] : nil;
                if (ed && ed.filePath) {
                    NSString *name = [[ed.filePath lastPathComponent] stringByDeletingPathExtension];
                    strlcpy(buf, name.UTF8String, 1024);
                } else {
                    buf[0] = '\0';
                }
            }
            return 0;
        }

        case NPPM_GETEXTPART: {
            char *buf = (char *)lParam;
            if (buf) {
                MainWindowController *mwc = _mwc;
                EditorView *ed = mwc ? [mwc currentEditor] : nil;
                if (ed && ed.filePath) {
                    NSString *ext = [ed.filePath pathExtension];
                    strlcpy(buf, ext.UTF8String, 1024);
                } else {
                    buf[0] = '\0';
                }
            }
            return 0;
        }

        case NPPM_GETNPPDIRECTORY: {
            char *buf = (char *)lParam;
            if (buf) {
                NSString *path = [[NSBundle mainBundle] bundlePath];
                strlcpy(buf, path.UTF8String, 1024);
            }
            return 0;
        }

        case NPPM_GETCURRENTLINE: {
            MainWindowController *mwc = _mwc;
            EditorView *ed = mwc ? [mwc currentEditor] : nil;
            if (ed && ed.scintillaView) {
                return [ed.scintillaView message:SCI_LINEFROMPOSITION
                                          wParam:[ed.scintillaView message:SCI_GETCURRENTPOS wParam:0 lParam:0]
                                          lParam:0];
            }
            return 0;
        }

        case NPPM_GETCURRENTCOLUMN: {
            MainWindowController *mwc = _mwc;
            EditorView *ed = mwc ? [mwc currentEditor] : nil;
            if (ed && ed.scintillaView) {
                return [ed.scintillaView message:SCI_GETCOLUMN
                                          wParam:[ed.scintillaView message:SCI_GETCURRENTPOS wParam:0 lParam:0]
                                          lParam:0];
            }
            return 0;
        }

        default:
            // Log unimplemented messages (but not too verbosely)
            if (msg >= (uint32_t)NPPMSG && msg <= (uint32_t)(NPPMSG + 200)) {
                static NSMutableSet *logged;
                static dispatch_once_t once;
                dispatch_once(&once, ^{ logged = [NSMutableSet set]; });
                NSNumber *key = @(msg);
                if (![logged containsObject:key]) {
                    [logged addObject:key];
                    NSLog(@"[Plugins] Unimplemented NPPM message: %u (NPPMSG+%u)",
                          msg, msg - (uint32_t)NPPMSG);
                }
            }
            return 0;
    }
}

// ── Scintilla message routing ───────────────────────────────────────────

- (intptr_t)handleScintillaMessage:(uint32_t)msg
                          forHandle:(uintptr_t)handle
                             wParam:(uintptr_t)wParam
                             lParam:(intptr_t)lParam {
    MainWindowController *mwc = _mwc;
    if (!mwc) return 0;

    EditorView *ed = [mwc currentEditor];
    if (!ed) return 0;

    // Route to the appropriate ScintillaView
    // For now, both main and sub handles route to the current editor.
    // TODO: when split views have tabs, route sub handle to secondary editor
    ScintillaView *sv = ed.scintillaView;
    if (!sv) return 0;

    return [sv message:msg wParam:wParam lParam:lParam];
}

// ── Menu helpers ────────────────────────────────────────────────────────

- (nullable NSMenu *)findPluginsMenu {
    NSMenu *mainMenu = [NSApp mainMenu];
    for (NSMenuItem *item in mainMenu.itemArray) {
        if ([item.title isEqualToString:@"Plugins"])
            return item.submenu;
    }
    return nil;
}

- (nullable NSMenuItem *)findMenuItemWithTag:(int)tag inMenu:(NSMenu *)menu {
    for (NSMenuItem *item in menu.itemArray) {
        if (item.tag == tag)
            return item;
        if (item.submenu) {
            NSMenuItem *found = [self findMenuItemWithTag:tag inMenu:item.submenu];
            if (found) return found;
        }
    }
    return nil;
}

@end

// ═══════════════════════════════════════════════════════════════════════════
// C callback — the function pointer stored in NppData._sendMessage
// ═══════════════════════════════════════════════════════════════════════════

static intptr_t nppSendMessageCallback(uintptr_t handle, uint32_t msg,
                                        uintptr_t wParam, intptr_t lParam) {
    NppPluginManager *mgr = [NppPluginManager shared];

    if (handle == kHandleNpp) {
        // Route to NPPM_* message handler
        return [mgr handleNppMessage:msg wParam:wParam lParam:lParam];
    }

    if (handle == kHandleScintillaMain || handle == kHandleScintillaSub) {
        // Route to Scintilla
        return [mgr handleScintillaMessage:msg forHandle:handle wParam:wParam lParam:lParam];
    }

    NSLog(@"[Plugins] sendMessage called with unknown handle: 0x%lx", (unsigned long)handle);
    return 0;
}
