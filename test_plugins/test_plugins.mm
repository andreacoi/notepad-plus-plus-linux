/*
 * test_plugins.mm — Plugin load-test harness for Notepad++ macOS
 *
 * Scans ~/.notepad++/plugins/ and verifies each plugin:
 *   1. dylib loads (dlopen)
 *   2. All 5 required exports resolve (dlsym)
 *   3. getName() returns a valid string
 *   4. getFuncsArray() returns valid menu items
 *
 * Build:  cmake -S test_plugins -B test_plugins/build && cmake --build test_plugins/build
 * Run:    ./test_plugins/build/test_plugins [optional_plugins_dir]
 */

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

// ── Minimal types from NppPluginInterfaceMac.h ─────────────────────────────

typedef uintptr_t NppHandle;
typedef intptr_t (*NppSendMessageFunc)(uintptr_t handle, uint32_t msg,
                                       uintptr_t wParam, intptr_t lParam);

struct NppData {
    NppHandle _nppHandle;
    NppHandle _scintillaMainHandle;
    NppHandle _scintillaSecondHandle;
    NppSendMessageFunc _sendMessage;
};

struct ShortcutKey {
    bool _isCtrl, _isAlt, _isShift, _isCmd;
    unsigned char _key;
};

typedef void (*PFUNCPLUGINCMD)(void);

struct FuncItem {
    char            _itemName[64];
    PFUNCPLUGINCMD  _pFunc;
    int             _cmdID;
    bool            _init2Check;
    ShortcutKey    *_pShKey;
};

// Function pointer types
typedef const char *     (*PFUNCGETNAME)(void);
typedef void             (*PFUNCSETINFO)(NppData);
typedef FuncItem *       (*PFUNCGETFUNCSARRAY)(int *);
typedef void             (*PBENOTIFIED)(void *);
typedef intptr_t         (*PMESSAGEPROC)(uint32_t, uintptr_t, intptr_t);

// ── Stub sendMessage (returns 0 for everything) ───────────────────────────

static intptr_t stubSendMessage(uintptr_t, uint32_t, uintptr_t, intptr_t) {
    return 0;
}

// ── Test result ───────────────────────────────────────────────────────────

struct TestResult {
    std::string pluginDir;
    bool loaded;
    bool hasGetName;
    bool hasSetInfo;
    bool hasGetFuncsArray;
    bool hasBeNotified;
    bool hasMessageProc;
    bool getNameOk;
    bool getFuncsOk;
    bool setInfoOk;
    std::string displayName;
    int menuItemCount;
    std::vector<std::string> menuItems;
    std::string error;
};

// ── ANSI colors ───────────────────────────────────────────────────────────

#define GREEN  "\033[32m"
#define RED    "\033[31m"
#define YELLOW "\033[33m"
#define DIM    "\033[2m"
#define RESET  "\033[0m"

// ── Test one plugin ───────────────────────────────────────────────────────

TestResult testPlugin(NSString *pluginsBaseDir, NSString *dirName) {
    TestResult r;
    r.pluginDir = dirName.UTF8String;
    r.loaded = r.hasGetName = r.hasSetInfo = r.hasGetFuncsArray = false;
    r.hasBeNotified = r.hasMessageProc = false;
    r.getNameOk = r.getFuncsOk = r.setInfoOk = false;
    r.menuItemCount = 0;

    NSString *dylibPath = [NSString stringWithFormat:@"%@/%@/%@.dylib",
                           pluginsBaseDir, dirName, dirName];

    // 1. dlopen
    void *handle = dlopen(dylibPath.UTF8String, RTLD_LAZY | RTLD_LOCAL);
    if (!handle) {
        r.error = dlerror() ?: "unknown dlopen error";
        return r;
    }
    r.loaded = true;

    // 2. Resolve exports
    auto pGetName       = (PFUNCGETNAME)      dlsym(handle, "getName");
    auto pSetInfo       = (PFUNCSETINFO)      dlsym(handle, "setInfo");
    auto pGetFuncsArray = (PFUNCGETFUNCSARRAY) dlsym(handle, "getFuncsArray");
    auto pBeNotified    = (PBENOTIFIED)        dlsym(handle, "beNotified");
    auto pMessageProc   = (PMESSAGEPROC)       dlsym(handle, "messageProc");

    r.hasGetName       = (pGetName != nullptr);
    r.hasSetInfo       = (pSetInfo != nullptr);
    r.hasGetFuncsArray = (pGetFuncsArray != nullptr);
    r.hasBeNotified    = (pBeNotified != nullptr);
    r.hasMessageProc   = (pMessageProc != nullptr);

    // 3. Call getName()
    if (pGetName) {
        @try {
            const char *name = pGetName();
            if (name && strlen(name) > 0 && strlen(name) < 256) {
                r.getNameOk = true;
                r.displayName = name;
            } else {
                r.error = "getName() returned null or invalid string";
            }
        } @catch (NSException *e) {
            r.error = "getName() crashed: " + std::string(e.reason.UTF8String);
        }
    }

    // 4. Call setInfo() with stub handles
    if (pSetInfo) {
        @try {
            NppData data = {};
            data._nppHandle = 0xDEAD0001;
            data._scintillaMainHandle = 0xDEAD0002;
            data._scintillaSecondHandle = 0xDEAD0003;
            data._sendMessage = stubSendMessage;
            pSetInfo(data);
            r.setInfoOk = true;
        } @catch (NSException *e) {
            r.error = "setInfo() crashed: " + std::string(e.reason.UTF8String);
        }
    }

    // 5. Call getFuncsArray()
    if (pGetFuncsArray) {
        @try {
            int nbFunc = 0;
            FuncItem *items = pGetFuncsArray(&nbFunc);
            if (items && nbFunc > 0 && nbFunc < 200) {
                r.getFuncsOk = true;
                r.menuItemCount = nbFunc;
                for (int i = 0; i < nbFunc; i++) {
                    if (items[i]._itemName[0] != '\0') {
                        r.menuItems.push_back(items[i]._itemName);
                    } else {
                        r.menuItems.push_back("---");  // separator
                    }
                }
            } else {
                r.error = "getFuncsArray() returned null or invalid count (" +
                          std::to_string(nbFunc) + ")";
            }
        } @catch (NSException *e) {
            r.error = "getFuncsArray() crashed: " + std::string(e.reason.UTF8String);
        }
    }

    dlclose(handle);
    return r;
}

// ── Main ──────────────────────────────────────────────────────────────────

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *pluginsDir;
        if (argc > 1) {
            pluginsDir = [NSString stringWithUTF8String:argv[1]];
        } else {
            pluginsDir = [NSHomeDirectory() stringByAppendingPathComponent:
                          @".notepad++/plugins"];
        }

        printf("\n  Plugin Load-Test Harness\n");
        printf("  Scanning: %s\n\n", pluginsDir.UTF8String);

        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray<NSString *> *entries = [[fm contentsOfDirectoryAtPath:pluginsDir error:nil]
                                        sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];

        int total = 0, passed = 0, warned = 0, failed = 0;
        std::vector<TestResult> results;

        for (NSString *dirName in entries) {
            NSString *dirPath = [pluginsDir stringByAppendingPathComponent:dirName];
            BOOL isDir = NO;
            if (![fm fileExistsAtPath:dirPath isDirectory:&isDir] || !isDir)
                continue;

            // Skip non-plugin dirs (like Config)
            NSString *dylibPath = [NSString stringWithFormat:@"%@/%@.dylib", dirPath, dirName];
            if (![fm fileExistsAtPath:dylibPath])
                continue;

            total++;
            TestResult r = testPlugin(pluginsDir, dirName);
            results.push_back(r);

            bool allExports = r.hasGetName && r.hasSetInfo && r.hasGetFuncsArray &&
                              r.hasBeNotified && r.hasMessageProc;
            bool fullPass = r.loaded && allExports && r.getNameOk && r.getFuncsOk && r.setInfoOk;

            if (fullPass) {
                passed++;
                printf(GREEN "  [PASS]" RESET " %-35s — \"%s\" (%d menu items)\n",
                       r.pluginDir.c_str(), r.displayName.c_str(), r.menuItemCount);
                // Print menu items dimmed
                for (auto &mi : r.menuItems) {
                    printf(DIM "           %s\n" RESET, mi.c_str());
                }
            } else if (r.loaded && r.getNameOk) {
                warned++;
                printf(YELLOW "  [WARN]" RESET " %-35s — \"%s\"",
                       r.pluginDir.c_str(), r.displayName.c_str());
                if (!r.hasSetInfo)       printf(" [missing setInfo]");
                if (!r.hasGetFuncsArray) printf(" [missing getFuncsArray]");
                if (!r.hasBeNotified)    printf(" [missing beNotified]");
                if (!r.hasMessageProc)   printf(" [missing messageProc]");
                if (!r.getFuncsOk)       printf(" [getFuncsArray failed]");
                if (!r.setInfoOk)        printf(" [setInfo failed]");
                if (!r.error.empty())    printf(" (%s)", r.error.c_str());
                printf("\n");
            } else {
                failed++;
                printf(RED "  [FAIL]" RESET " %-35s", r.pluginDir.c_str());
                if (!r.loaded) {
                    printf(" — dlopen: %s", r.error.c_str());
                } else {
                    if (!r.hasGetName) printf(" [missing getName]");
                    if (!r.error.empty()) printf(" (%s)", r.error.c_str());
                }
                printf("\n");
            }
        }

        printf("\n  ─────────────────────────────────────────────\n");
        printf("  Total: %d  ", total);
        printf(GREEN "Passed: %d" RESET "  ", passed);
        if (warned > 0) printf(YELLOW "Warned: %d" RESET "  ", warned);
        if (failed > 0) printf(RED "Failed: %d" RESET, failed);
        printf("\n\n");

        return failed > 0 ? 1 : 0;
    }
}
