#import "TabManager.h"
#import "EditorView.h"

// ── NppDropView ──────────────────────────────────────────────────────────────
@implementation NppDropView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Register both modern (file URL) and legacy (filenames) pasteboard types
        // so drops from Finder work on all macOS 11+ versions.
        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL, NSFilenamesPboardType]];
    }
    return self;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    NSDictionary *opts = @{NSPasteboardURLReadingFileURLsOnlyKey: @YES};
    if ([sender.draggingPasteboard canReadObjectForClasses:@[[NSURL class]] options:opts])
        return NSDragOperationCopy;
    return NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
    return [self draggingEntered:sender];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];

    // Modern path: NSPasteboardTypeFileURL (macOS 10.13+)
    NSDictionary *opts = @{NSPasteboardURLReadingFileURLsOnlyKey: @YES};
    NSArray<NSURL *> *urls = [sender.draggingPasteboard
        readObjectsForClasses:@[[NSURL class]] options:opts];
    for (NSURL *url in urls) if (url.isFileURL) [paths addObject:url.path];

    // Legacy fallback: NSFilenamesPboardType (array of path strings)
    if (!paths.count) {
        NSArray *names = [sender.draggingPasteboard propertyListForType:NSFilenamesPboardType];
        if ([names isKindOfClass:[NSArray class]])
            [paths addObjectsFromArray:names];
    }

    if (paths.count && _dropHandler) { _dropHandler(paths); return YES; }
    return NO;
}

@end

// ── TabManager ───────────────────────────────────────────────────────────────
@implementation TabManager {
    NppTabBar                  *_tabBar;
    NSView                     *_contentView;
    NSMutableArray<EditorView *> *_editors;
    NSInteger                   _selectedIndex;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _editors = [NSMutableArray array];
        _selectedIndex = -1;

        _tabBar = [[NppTabBar alloc] initWithFrame:NSZeroRect];
        _tabBar.delegate = self;

        _contentView = [[NppDropView alloc] initWithFrame:NSZeroRect];
        _contentView.wantsLayer = YES;
    }
    return self;
}

#pragma mark - Public API

- (EditorView *)addNewTab {
    EditorView *editor = [[EditorView alloc] initWithFrame:_contentView.bounds];
    editor.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // Mirrors NPP: reuse the lowest available untitled index rather than always incrementing.
    // e.g. if "new 1" and "new 3" are open, next tab is "new 2" (fills the gap).
    NSMutableSet<NSNumber *> *used = [NSMutableSet set];
    for (EditorView *ed in _editors)
        if (!ed.filePath) [used addObject:@(ed.untitledIndex)];
    NSInteger idx = 1;
    while ([used containsObject:@(idx)]) idx++;
    [editor restoreUntitledIndex:idx];

    [self insertEditor:editor title:editor.displayName modified:NO];
    return editor;
}

- (nullable EditorView *)openFileAtPath:(NSString *)path {
    // Focus existing tab if already open
    for (NSInteger i = 0; i < (NSInteger)_editors.count; i++) {
        if ([_editors[i].filePath isEqualToString:path]) {
            [self activateTabAtIndex:i];
            return _editors[i];
        }
    }

    EditorView *editor = [[EditorView alloc] initWithFrame:_contentView.bounds];
    editor.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    NSError *error;
    if (![editor loadFileAtPath:path error:&error]) {
        [[NSAlert alertWithError:error] runModal];
        return nil;
    }

    [self insertEditor:editor title:editor.displayName modified:NO];
    return editor;
}

- (void)closeCurrentTab {
    if (_selectedIndex >= 0) {
        [self closeEditor:_editors[_selectedIndex]];
    }
}

- (void)closeEditor:(EditorView *)editor {
    // Only prompt for named files with unsaved changes.
    // Untitled tabs are backed up automatically — no prompt needed.
    if (editor.isModified) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = [NSString stringWithFormat:@"Save changes to \"%@\"?", editor.displayName];
        alert.informativeText = @"Your changes will be lost if you don't save them.";
        [alert addButtonWithTitle:@"Save"];
        [alert addButtonWithTitle:@"Don't Save"];
        [alert addButtonWithTitle:@"Cancel"];
        NSModalResponse resp = [alert runModal];

        if (resp == NSAlertFirstButtonReturn) {
            if (!editor.filePath) {
                [self runSavePanelForEditor:editor completion:^(BOOL saved) {
                    if (saved) [self removeEditor:editor];
                }];
                return;
            }
            NSError *err;
            [editor saveError:&err];
        } else if (resp == NSAlertThirdButtonReturn) {
            return;
        }
    }
    [self removeEditor:editor];
}

- (void)evictEditor:(EditorView *)editor {
    NSInteger idx = [_editors indexOfObject:editor];
    if (idx == NSNotFound) return;
    [editor removeFromSuperview];
    [_editors removeObjectAtIndex:idx];
    [_tabBar removeTabAtIndex:idx];
    if (_editors.count > 0) {
        NSInteger nextIdx = MIN(idx, (NSInteger)_editors.count - 1);
        [self activateTabAtIndex:nextIdx];
    }
    [_delegate tabManager:self didCloseEditor:editor];
}

- (void)adoptEditor:(EditorView *)editor {
    [self insertEditor:editor title:editor.displayName modified:editor.isModified];
}

- (void)refreshCurrentTabTitle {
    if (_selectedIndex < 0) return;
    EditorView *editor = _editors[_selectedIndex];
    [_tabBar setTitle:editor.displayName modified:editor.isModified atIndex:_selectedIndex];
}

- (void)selectTabAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_editors.count) return;
    [self activateTabAtIndex:index];
    [_delegate tabManager:self didSelectEditor:_editors[index]];
}

#pragma mark - NppTabBarDelegate

- (void)tabBar:(NppTabBar *)bar didSelectTabAtIndex:(NSInteger)index {
    [self activateTabAtIndex:index];
    [_delegate tabManager:self didSelectEditor:_editors[index]];
}

- (void)tabBar:(NppTabBar *)bar didCloseTabAtIndex:(NSInteger)index {
    // NPP behavior: can't close the last tab when it's already clean and untitled
    if (_editors.count == 1 && !_editors[0].isModified && !_editors[0].filePath) return;
    [self closeEditor:_editors[index]];
}

#pragma mark - Accessors

- (NppTabBar *)tabBar    { return _tabBar; }
- (NSView *)contentView  { return _contentView; }

- (EditorView *)currentEditor {
    if (_selectedIndex < 0 || _selectedIndex >= (NSInteger)_editors.count) return nil;
    return _editors[_selectedIndex];
}

- (NSArray<EditorView *> *)allEditors { return [_editors copy]; }

#pragma mark - Private

- (void)insertEditor:(EditorView *)editor title:(NSString *)title modified:(BOOL)modified {
    [_editors addObject:editor];
    [_contentView addSubview:editor];
    [_tabBar addTabWithTitle:title modified:modified];
    [self activateTabAtIndex:(NSInteger)_editors.count - 1];
}

- (void)activateTabAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_editors.count) return;

    // Hide previously active editor
    if (_selectedIndex >= 0 && _selectedIndex < (NSInteger)_editors.count) {
        _editors[_selectedIndex].hidden = YES;
    }

    _selectedIndex = index;
    EditorView *editor = _editors[index];
    editor.hidden = NO;
    editor.frame = _contentView.bounds;
    [_tabBar selectTabAtIndex:index];
    [_contentView setNeedsLayout:YES];
}

- (void)removeEditor:(EditorView *)editor {
    NSInteger idx = [_editors indexOfObject:editor];
    if (idx == NSNotFound) return;

    [editor removeFromSuperview];
    [_editors removeObjectAtIndex:idx];
    [_tabBar removeTabAtIndex:idx];

    // Always keep at least one tab
    if (_editors.count == 0) {
        [self addNewTab];
        return;
    }

    NSInteger nextIdx = MIN(idx, (NSInteger)_editors.count - 1);
    [self activateTabAtIndex:nextIdx];
    [_delegate tabManager:self didCloseEditor:editor];
}

- (void)reorderEditors:(NSArray<EditorView *> *)orderedEditors {
    if (orderedEditors.count != _editors.count) return;

    EditorView *current = self.currentEditor;

    // Save pinned state keyed by editor identity before rebuilding.
    NSMutableDictionary<NSValue *, NSNumber *> *pinnedMap = [NSMutableDictionary dictionary];
    for (NSInteger i = 0; i < (NSInteger)_editors.count; i++) {
        NSValue *key = [NSValue valueWithNonretainedObject:_editors[i]];
        pinnedMap[key] = @([_tabBar isTabPinnedAtIndex:i]);
    }

    // Replace _editors with the sorted order.
    [_editors removeAllObjects];
    [_editors addObjectsFromArray:orderedEditors];

    // Rebuild the tab bar: remove all items then re-add in new order.
    while (_tabBar.tabCount > 0) [_tabBar removeTabAtIndex:0];
    for (NSInteger i = 0; i < (NSInteger)_editors.count; i++) {
        EditorView *ed = _editors[i];
        [_tabBar addTabWithTitle:ed.displayName modified:ed.isModified];
        NSValue *key = [NSValue valueWithNonretainedObject:ed];
        if ([pinnedMap[key] boolValue])
            [_tabBar pinTabAtIndex:i toggle:YES];
    }

    // Restore the previously active editor.
    NSInteger newSel = [_editors indexOfObject:current];
    if (newSel == NSNotFound) newSel = 0;
    _selectedIndex = -1;
    [self activateTabAtIndex:newSel];
}

- (void)runSavePanelForEditor:(EditorView *)editor completion:(void(^)(BOOL))completion {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = editor.displayName;
    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSError *err;
            [editor saveToPath:panel.URL.path error:&err];
            completion(YES);
        } else {
            completion(NO);
        }
    }];
}

@end
