#import "NppTabBar.h"

// Forward-declare the context menu builder so _NppTabItem can call it.
@interface NppTabBar (ContextMenu)
- (NSMenu *)buildTabContextMenu;
@end

static const CGFloat kTabHeight    = 22.0;
static const CGFloat kTabMinWidth  = 80.0;
static const CGFloat kTabMaxWidth  = 190.0;
static const CGFloat kIconSize     = 16.0;
static const CGFloat kCloseSize    = 14.0;

// Colors matching Windows Notepad++ tab bar style
static NSColor *inactiveTabColor()  { return [NSColor colorWithWhite:(0xC2/255.0) alpha:1]; } // #c2c2c2
static NSColor *activeTabColor()    { return [NSColor controlBackgroundColor]; }
static NSColor *hoverTabColor()     { return [NSColor colorWithRed:0.82 green:0.82 blue:0.88 alpha:1]; }
static NSColor *tabBarBgColor()     { return [NSColor windowBackgroundColor]; }

static NSImage *tabIcon(NSString *name) {
    // Tab bar icons: dark/tabbar/ (32px native — sharp on Retina)
    NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"png"
                                                inDirectory:@"icons/dark/tabbar"];
    return path ? [[NSImage alloc] initWithContentsOfFile:path] : nil;
}

static NSImage *toolbarIcon(NSString *name) {
    NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"png"
                                                inDirectory:@"icons/standard/toolbar"];
    return path ? [[NSImage alloc] initWithContentsOfFile:path] : nil;
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - _NppTabItem (private)

@interface _NppTabItem : NSView {
    BOOL _hovered;
    BOOL _closeHovered;
    NSTrackingArea *_trackingArea;
}
@property (nonatomic) NSInteger tabIndex;
@property (nonatomic, copy) NSString *title;
@property (nonatomic) BOOL isSelected;
@property (nonatomic) BOOL isModified;
@property (nonatomic) BOOL isPinned;
@property (nonatomic, weak) id target;
@property (nonatomic) SEL selectAction;
@property (nonatomic) SEL closeAction;
- (CGFloat)preferredWidth;
@end

@implementation _NppTabItem

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
    }
    return self;
}

- (CGFloat)preferredWidth {
    NSDictionary *attrs = @{NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightRegular]};
    CGFloat tw = [_title sizeWithAttributes:attrs].width;
    // left pad + icon + gap + text + right pad (no close button gap when pinned)
    CGFloat closeGap = _isPinned ? 0 : (4 + kCloseSize + 4);
    return MAX(kTabMinWidth, MIN(kTabMaxWidth, 8 + kIconSize + 4 + tw + closeGap + 8));
}

- (void)drawRect:(NSRect)dirtyRect {
    NSColor *bg = _isSelected ? activeTabColor() : (_hovered ? hoverTabColor() : inactiveTabColor());
    [bg setFill];
    NSRectFill(self.bounds);

    // Orange 4px top accent line on the active tab
    if (_isSelected) {
        [[NSColor colorWithRed:1.0 green:0.50 blue:0.0 alpha:1.0] setFill];
        NSRectFill(NSMakeRect(0, self.bounds.size.height - 4, self.bounds.size.width, 4));
    }

    // Bottom border: none on active (active merges with content), subtle on inactive
    if (!_isSelected) {
        [[NSColor colorWithWhite:0 alpha:0.12] setFill];
        NSRectFill(NSMakeRect(0, 0, self.bounds.size.width, 1));
    }

    // Right separator between tabs
    [[NSColor colorWithWhite:0 alpha:0.15] setFill];
    NSRectFill(NSMakeRect(self.bounds.size.width - 1, 2, 1, self.bounds.size.height - 2));

    // Floppy icon (left side): red = unsaved, blue = saved
    NSImage *icon = _isModified ? toolbarIcon(@"saveFileRed") : toolbarIcon(@"saveFile");
    if (icon) {
        CGFloat sz = kIconSize * 0.8;
        NSRect iconRect = NSMakeRect(8 + (kIconSize - sz) / 2.0,
                                     (self.bounds.size.height - sz) / 2.0, sz, sz);
        [icon drawInRect:iconRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
    }

    // Title text
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.lineBreakMode = NSLineBreakByTruncatingMiddle;
    NSColor *textColor = _isSelected ? [NSColor labelColor] : [NSColor colorWithWhite:0.15 alpha:1];
    NSFont *font = _isSelected ? [NSFont systemFontOfSize:12 weight:NSFontWeightMedium]
                               : [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    NSDictionary *attrs = @{NSFontAttributeName: font,
                             NSForegroundColorAttributeName: textColor,
                             NSParagraphStyleAttributeName: ps};
    CGFloat textX = 8 + kIconSize + 4;
    CGFloat textW = self.bounds.size.width - textX - kCloseSize - 8;
    CGFloat textY = (self.bounds.size.height - font.pointSize - 2) / 2.0;
    [_title drawInRect:NSMakeRect(textX, textY, textW, font.pointSize + 4) withAttributes:attrs];

    if (_isPinned) {
        // Draw a small pin indicator instead of close button
        NSString *pin = @"📌";
        NSDictionary *pa = @{NSFontAttributeName: [NSFont systemFontOfSize:10]};
        CGFloat px = self.bounds.size.width - 18;
        CGFloat py = (self.bounds.size.height - 14) / 2.0;
        [pin drawAtPoint:NSMakePoint(px, py) withAttributes:pa];
    } else {
        // Close button area
        CGFloat cx = self.bounds.size.width - kCloseSize - 6;
        CGFloat cy = (self.bounds.size.height - kCloseSize) / 2.0;
        NSRect closeRect = NSMakeRect(cx, cy, kCloseSize, kCloseSize);

        if (_isSelected || _hovered) {
            NSImage *closeImg;
            if (_closeHovered) {
                closeImg = tabIcon(@"closeTabButton_hoverIn");
            } else if (_isSelected) {
                closeImg = tabIcon(@"closeTabButton");
            } else {
                closeImg = tabIcon(@"closeTabButton_hoverOnTab");
            }
            if (closeImg) closeImg.size = NSMakeSize(32, 32);
            if (!closeImg) {
                NSString *x = @"×";
                NSDictionary *xa = @{NSFontAttributeName: [NSFont systemFontOfSize:11],
                                      NSForegroundColorAttributeName: textColor};
                [x drawAtPoint:NSMakePoint(cx + 1, cy - 1) withAttributes:xa];
            } else {
                [closeImg drawInRect:closeRect fromRect:NSZeroRect
                           operation:NSCompositingOperationSourceOver fraction:1.0];
            }
        }
    }
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) [self removeTrackingArea:_trackingArea];
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
        options:(NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveInKeyWindow)
          owner:self userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)mouseEntered:(NSEvent *)event { _hovered = YES;  [self setNeedsDisplay:YES]; }
- (void)mouseExited:(NSEvent *)event  { _hovered = NO; _closeHovered = NO; [self setNeedsDisplay:YES]; }

- (void)mouseMoved:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat cx = self.bounds.size.width - kCloseSize - 6;
    BOOL overClose = p.x >= cx && p.x <= cx + kCloseSize;
    if (overClose != _closeHovered) {
        _closeHovered = overClose;
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat cx = self.bounds.size.width - kCloseSize - 6;
    BOOL overClose = !_isPinned && (_isSelected || _hovered) && p.x >= cx && p.x <= cx + kCloseSize;

    if (overClose) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [_target performSelector:_closeAction withObject:self];
#pragma clang diagnostic pop
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [_target performSelector:_selectAction withObject:self];
#pragma clang diagnostic pop
    }
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    // Select the right-clicked tab before showing the menu so all actions
    // operate on the correct (now-current) document.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [_target performSelector:_selectAction withObject:self];
#pragma clang diagnostic pop
    return [(NppTabBar *)_target buildTabContextMenu];
}

@end

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - NppTabBar

@implementation NppTabBar {
    NSScrollView               *_scrollView;
    NSView                     *_containerView;
    NSMutableArray<_NppTabItem *> *_items;
    NSInteger                   _selectedIndex;
    BOOL                        _wrapMode;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _items = [NSMutableArray array];
        _selectedIndex = -1;
        [self buildScrollView];
    }
    return self;
}

- (void)buildScrollView {
    _containerView = [[NSView alloc] initWithFrame:NSZeroRect];

    _scrollView = [[NSScrollView alloc] initWithFrame:self.bounds];
    _scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _scrollView.hasHorizontalScroller = NO;
    _scrollView.hasVerticalScroller   = NO;
    _scrollView.drawsBackground = NO;
    _scrollView.documentView = _containerView;
    [self addSubview:_scrollView];
}

- (void)drawRect:(NSRect)dirtyRect {
    [tabBarBgColor() setFill];
    NSRectFill(self.bounds);
    // Bottom border
    [[NSColor separatorColor] setFill];
    NSRectFill(NSMakeRect(0, 0, self.bounds.size.width, 1));
}

- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size];
    [self relayout];
}

#pragma mark - Public API

- (void)addTabWithTitle:(NSString *)title modified:(BOOL)modified {
    _NppTabItem *item = [[_NppTabItem alloc] initWithFrame:NSZeroRect];
    item.title       = title;
    item.isModified  = modified;
    item.isSelected  = NO;
    item.tabIndex    = _items.count;
    item.target      = self;
    item.selectAction = @selector(tabItemSelected:);
    item.closeAction  = @selector(tabItemClosed:);
    [_items addObject:item];
    [_containerView addSubview:item];
    [self relayout];
}

- (void)removeTabAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_items.count) return;
    _NppTabItem *item = _items[index];
    [item removeFromSuperview];
    [_items removeObjectAtIndex:index];
    // Re-index remaining items
    for (NSInteger i = index; i < (NSInteger)_items.count; i++) {
        _items[i].tabIndex = i;
    }
    if (_selectedIndex >= (NSInteger)_items.count) {
        _selectedIndex = (NSInteger)_items.count - 1;
    }
    if (_selectedIndex >= 0) {
        _items[_selectedIndex].isSelected = YES;
    }
    [self relayout];
}

- (void)setTitle:(NSString *)title modified:(BOOL)modified atIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_items.count) return;
    _items[index].title      = title;
    _items[index].isModified = modified;
    [_items[index] setNeedsDisplay:YES];
}

- (void)selectTabAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_items.count) return;
    if (_selectedIndex >= 0 && _selectedIndex < (NSInteger)_items.count) {
        _items[_selectedIndex].isSelected = NO;
        [_items[_selectedIndex] setNeedsDisplay:YES];
    }
    _selectedIndex = index;
    _items[index].isSelected = YES;
    [_items[index] setNeedsDisplay:YES];
    [self scrollTabToVisible:index];
}

- (NSInteger)tabCount { return (NSInteger)_items.count; }

- (void)pinTabAtIndex:(NSInteger)index toggle:(BOOL)toggle {
    if (index < 0 || index >= (NSInteger)_items.count) return;
    _items[index].isPinned = toggle;
    [_items[index] setNeedsDisplay:YES];
    [self relayout];
}

- (BOOL)wrapMode { return _wrapMode; }
- (void)setWrapMode:(BOOL)wrap {
    if (_wrapMode == wrap) return;
    _wrapMode = wrap;
    _scrollView.hasHorizontalScroller = !wrap;
    [self relayout];
    [self setNeedsDisplay:YES];
}

- (BOOL)isTabPinnedAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_items.count) return NO;
    return _items[index].isPinned;
}

#pragma mark - Tab item callbacks

- (void)tabItemSelected:(_NppTabItem *)item {
    if (item.tabIndex == _selectedIndex) return;
    [self selectTabAtIndex:item.tabIndex];
    [_delegate tabBar:self didSelectTabAtIndex:item.tabIndex];
}

- (void)tabItemClosed:(_NppTabItem *)item {
    [_delegate tabBar:self didCloseTabAtIndex:item.tabIndex];
}

#pragma mark - Layout

- (void)relayout {
    CGFloat rowH = kTabHeight - 1; // row height, leaving 1px for bottom border
    if (_wrapMode) {
        CGFloat barW = MAX(self.bounds.size.width, 1);
        CGFloat x = 0, y = 1;
        for (_NppTabItem *item in _items) {
            CGFloat w = item.preferredWidth;
            if (x + w > barW && x > 0) { x = 0; y += kTabHeight; }
            item.frame = NSMakeRect(x, y, w, rowH);
            x += w;
        }
        CGFloat totalH = y + kTabHeight;
        _containerView.frame = NSMakeRect(0, 0, barW, totalH);
        // Grow/shrink the bar itself to fit all rows.
        NSRect f = self.frame;
        if (f.size.height != totalH) {
            f.size.height = totalH;
            // Adjust origin so bar grows upward (it sits at top of container).
            NSView *sv = self.superview;
            if (sv) {
                f.origin.y = sv.bounds.size.height - totalH;
            }
            [super setFrame:f];
        }
    } else {
        CGFloat h = self.bounds.size.height - 1;
        CGFloat x = 0;
        for (_NppTabItem *item in _items) {
            CGFloat w = item.preferredWidth;
            item.frame = NSMakeRect(x, 1, w, h);
            x += w;
        }
        _containerView.frame = NSMakeRect(0, 0, MAX(x, self.bounds.size.width), self.bounds.size.height);
    }
}

- (void)scrollTabToVisible:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_items.count) return;
    NSRect tabFrame = _items[index].frame;
    [_scrollView.contentView scrollToPoint:NSMakePoint(
        MAX(0, NSMidX(tabFrame) - _scrollView.bounds.size.width / 2), 0)];
    [_scrollView reflectScrolledClipView:_scrollView.contentView];
}

#pragma mark - Context menu (right-click)

- (NSMenu *)buildTabContextMenu {
    // Helper to create a plain menu item targeting the responder chain.
    NSMenu * (^sub)(NSString *) = ^NSMenu *(NSString *t) {
        return [[NSMenu alloc] initWithTitle:t];
    };
    NSMenuItem * (^it)(NSString *, SEL) = ^NSMenuItem *(NSString *t, SEL s) {
        return [[NSMenuItem alloc] initWithTitle:t action:s keyEquivalent:@""];
    };
    NSMenuItem * (^withSub)(NSString *, NSMenu *) = ^NSMenuItem *(NSString *t, NSMenu *m) {
        NSMenuItem *i = [[NSMenuItem alloc] initWithTitle:t action:nil keyEquivalent:@""];
        i.submenu = m;
        return i;
    };

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];

    [menu addItem:it(@"Pin Tab",           @selector(pinCurrentTab:))];
    [menu addItem:it(@"Close",             @selector(closeCurrentTab:))];

    NSMenu *closeMultMenu = sub(@"Close Multiple Tabs");
    [closeMultMenu addItem:it(@"Close All But This",     @selector(closeAllButCurrent:))];
    [closeMultMenu addItem:it(@"Close All to the Left",  @selector(closeAllToLeft:))];
    [closeMultMenu addItem:it(@"Close All to the Right", @selector(closeAllToRight:))];
    [closeMultMenu addItem:it(@"Close All Unchanged",    @selector(closeAllUnchanged:))];
    [menu addItem:withSub(@"Close Multiple Tabs", closeMultMenu)];

    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:it(@"Save",     @selector(saveDocument:))];
    [menu addItem:it(@"Save As…", @selector(saveDocumentAs:))];
    [menu addItem:it(@"Rename…",  @selector(renameDocument:))];

    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:it(@"Reload from Disk", @selector(reloadFromDisk:))];
    [menu addItem:it(@"Move to Trash",    @selector(moveToTrash:))];
    [menu addItem:it(@"Print…",           @selector(printDocument:))];

    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:it(@"Read-Only in Notepad++", @selector(toggleReadOnly:))];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenu *copyMenu = sub(@"Copy to Clipboard");
    [copyMenu addItem:it(@"Copy Full File Path",         @selector(copyFullFilePath:))];
    [copyMenu addItem:it(@"Copy File Name",              @selector(copyFileName:))];
    [copyMenu addItem:it(@"Copy Current Directory Path", @selector(copyCurrentDirectoryPath:))];
    [menu addItem:withSub(@"Copy to Clipboard", copyMenu)];

    NSMenu *moveMenu = sub(@"Move Document");
    [moveMenu addItem:it(@"Move to Other Vertical View",    @selector(moveToOtherVerticalView:))];
    [moveMenu addItem:it(@"Clone to Other Vertical View",   @selector(cloneToOtherVerticalView:))];
    [moveMenu addItem:[NSMenuItem separatorItem]];
    [moveMenu addItem:it(@"Move to Other Horizontal View",  @selector(moveToOtherHorizontalView:))];
    [moveMenu addItem:it(@"Clone to Other Horizontal View", @selector(cloneToOtherHorizontalView:))];
    [moveMenu addItem:[NSMenuItem separatorItem]];
    [moveMenu addItem:it(@"Reset View",                     @selector(resetView:))];
    [menu addItem:withSub(@"Move Document", moveMenu)];

    return menu;
}

@end
