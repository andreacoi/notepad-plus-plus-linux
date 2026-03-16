#import "GitHelper.h"

@implementation GitHelper

// ── Private: run git synchronously, return stdout string ─────────────────────

+ (NSString *)_run:(NSArray<NSString *> *)args dir:(NSString *)dir {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/git";
    task.arguments = args;
    task.currentDirectoryPath = dir;
    NSPipe *outPipe = [NSPipe pipe];
    NSPipe *errPipe = [NSPipe pipe];
    task.standardOutput = outPipe;
    task.standardError  = errPipe;
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *) {
        return @"";
    }
    NSData *data = outPipe.fileHandleForReading.readDataToEndOfFile;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

// ── Public API ────────────────────────────────────────────────────────────────

+ (nullable NSString *)gitRootForPath:(NSString *)path {
    // path may be a file or directory; normalize to directory
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir]) return nil;
    NSString *dir = isDir ? path : path.stringByDeletingLastPathComponent;

    NSString *result = [self _run:@[@"rev-parse", @"--show-toplevel"] dir:dir];
    result = [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return result.length ? result : nil;
}

+ (nullable NSString *)currentBranchAtRoot:(NSString *)root {
    NSString *result = [self _run:@[@"rev-parse", @"--abbrev-ref", @"HEAD"] dir:root];
    result = [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return result.length ? result : nil;
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)statusAtRoot:(NSString *)root {
    NSString *out = [self _run:@[@"status", @"--porcelain", @"-u"] dir:root];
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *line in [out componentsSeparatedByString:@"\n"]) {
        if (line.length < 4) continue;
        NSString *xy   = [line substringToIndex:2];
        NSString *path = [[line substringFromIndex:3]
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        // Handle rename format "old -> new"
        NSRange arrow = [path rangeOfString:@" -> "];
        if (arrow.location != NSNotFound)
            path = [path substringFromIndex:arrow.location + arrow.length];
        if (path.length) [items addObject:@{@"xy": xy, @"path": path}];
    }
    return items;
}

+ (nullable NSString *)diffForFile:(NSString *)path root:(NSString *)root {
    NSString *result = [self _run:@[@"diff", @"HEAD", @"--", path] dir:root];
    return result.length ? result : nil;
}

+ (void)stageFile:(NSString *)path root:(NSString *)root completion:(void (^)(BOOL))cb {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [self _run:@[@"add", @"--", path] dir:root];
        dispatch_async(dispatch_get_main_queue(), ^{ if (cb) cb(YES); });
    });
}

+ (void)unstageFile:(NSString *)path root:(NSString *)root completion:(void (^)(BOOL))cb {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [self _run:@[@"restore", @"--staged", @"--", path] dir:root];
        dispatch_async(dispatch_get_main_queue(), ^{ if (cb) cb(YES); });
    });
}

+ (void)commitMessage:(NSString *)msg root:(NSString *)root
           completion:(void (^)(BOOL, NSString *_Nullable))cb {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSTask *task = [[NSTask alloc] init];
        task.launchPath = @"/usr/bin/git";
        task.arguments = @[@"commit", @"-m", msg];
        task.currentDirectoryPath = root;
        NSPipe *outPipe = [NSPipe pipe];
        NSPipe *errPipe = [NSPipe pipe];
        task.standardOutput = outPipe;
        task.standardError  = errPipe;
        @try { [task launch]; [task waitUntilExit]; } @catch (NSException *) {}
        int status = task.terminationStatus;
        NSData *errData = errPipe.fileHandleForReading.readDataToEndOfFile;
        NSString *errMsg = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (cb) cb(status == 0, status == 0 ? nil : errMsg);
        });
    });
}

@end
