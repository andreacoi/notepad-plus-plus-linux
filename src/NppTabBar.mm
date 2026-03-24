#import "NppTabBar.h"

@interface NppTabBar (ContextMenu)
- (NSMenu *)buildTabContextMenu;
@end

// ── Constants ─────────────────────────────────────────────────────────────────
// Bar layout: barH = kTabTopGap + inactiveTabH + 1(border).
// inactiveTabH = barH - kTabTopGap - 1.  activeTabH = inactiveTabH + kActiveBoost.
// MainWindowController sets the height constraint = barH.
static const CGFloat kTabTopGap    = 4.0;   // dead space at bar top (gap below toolbar)
static const CGFloat kActiveBoost  = 3.0;   // px active tab is taller than inactive
static const CGFloat kTabMinWidth  = 80.0;
static const CGFloat kTabMaxWidth  = 190.0;
static const CGFloat kIconSize     = 16.0;
static const CGFloat kCloseSize    = 14.0;
static const CGFloat kArrowBtnW    = 14.0;  // width of each scroll-arrow button

// ── Colors ────────────────────────────────────────────────────────────────────
static NSColor *tabBarBgColor()    { return [NSColor colorWithRed:0xF0/255.0 green:0xF0/255.0 blue:0xF0/255.0 alpha:1]; }
static NSColor *inactiveTabColor() { return [NSColor colorWithWhite:0.80 alpha:1]; }
static NSColor *activeTabColor()   { return [NSColor colorWithWhite:1.00 alpha:1]; }
static NSColor *hoverTabColor()    { return [NSColor colorWithWhite:0.87 alpha:1]; }
// #fda640 — amber/orange accent on active tab top
static NSColor *accentColor()      { return [NSColor colorWithRed:(253/255.0) green:(166/255.0) blue:(64/255.0) alpha:1]; }
static NSColor *tabBorderColor()   { return [NSColor colorWithWhite:0.58 alpha:1]; }
static NSColor *dividerGray()      { return [NSColor colorWithWhite:0.55 alpha:1]; }
static NSColor *dividerWhite()     { return [NSColor colorWithWhite:0.96 alpha:1]; }

// ── Icon helpers ──────────────────────────────────────────────────────────────
static NSImage *tabIcon(NSString *name) {
    NSString *p = [[NSBundle mainBundle] pathForResource:name ofType:@"png"
                                             inDirectory:@"icons/dark/tabbar"];
    return p ? [[NSImage alloc] initWithContentsOfFile:p] : nil;
}
static NSImage *toolbarIcon(NSString *name) {
    NSString *p = [[NSBundle mainBundle] pathForResource:name ofType:@"png"
                                             inDirectory:@"icons/standard/toolbar"];
    return p ? [[NSImage alloc] initWithContentsOfFile:p] : nil;
}

// ── Windows-style scroll arrow button ────────────────────────────────────────
@interface _NppScrollArrowButton : NSButton {
    BOOL _pointsRight;
    BOOL _hovering;
}
- (instancetype)initPointingRight:(BOOL)right target:(id)tgt action:(SEL)act;
@end

@implementation _NppScrollArrowButton

- (instancetype)initPointingRight:(BOOL)right target:(id)tgt action:(SEL)act {
    self = [super init];
    if (self) {
        _pointsRight = right;
        [self setBordered:NO];
        self.buttonType = NSButtonTypeMomentaryChange;
        self.title  = @"";
        self.target = tgt;
        self.action = act;
        self.hidden = YES;
        NSTrackingArea *ta = [[NSTrackingArea alloc]
            initWithRect:NSZeroRect
                 options:(NSTrackingMouseEnteredAndExited |
                          NSTrackingActiveInActiveApp     |
                          NSTrackingInVisibleRect)
                   owner:self userInfo:nil];
        [self addTrackingArea:ta];
    }
    return self;
}

- (void)mouseEntered:(NSEvent *)e { _hovering = YES;  [self setNeedsDisplay:YES]; }
- (void)mouseExited:(NSEvent *)e  { _hovering = NO;   [self setNeedsDisplay:YES]; }

- (void)drawRect:(NSRect)dirtyRect {
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;

    // Background — slightly brighter on hover
    NSColor *bg = _hovering ? [NSColor colorWithWhite:0.91 alpha:1]
                             : [NSColor colorWithWhite:0.83 alpha:1];
    [bg setFill];
    NSRectFill(self.bounds);

    // 1px border
    [[NSColor colorWithWhite:0.50 alpha:1] setStroke];
    NSBezierPath *border = [NSBezierPath bezierPathWithRect:NSInsetRect(self.bounds, 0.5, 0.5)];
    border.lineWidth = 0.5;
    [border stroke];

    // Small solid triangle centered in the button
    CGFloat aw = 4.0, ah = 7.0;
    CGFloat ax = floor((w - aw) / 2.0);
    CGFloat ay = floor((h - ah) / 2.0);

    NSBezierPath *tri = [NSBezierPath bezierPath];
    if (_pointsRight) {
        [tri moveToPoint:NSMakePoint(ax,      ay)];
        [tri lineToPoint:NSMakePoint(ax + aw, ay + ah / 2.0)];
        [tri lineToPoint:NSMakePoint(ax,      ay + ah)];
    } else {
        [tri moveToPoint:NSMakePoint(ax + aw, ay)];
        [tri lineToPoint:NSMakePoint(ax,      ay + ah / 2.0)];
        [tri lineToPoint:NSMakePoint(ax + aw, ay + ah)];
    }
    [tri closePath];
    [[NSColor colorWithWhite:0.18 alpha:1] setFill];
    [tri fill];
}
@end

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
    if (self) { self.wantsLayer = YES; }
    return self;
}

- (CGFloat)preferredWidth {
    NSDictionary *attrs = @{NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightRegular]};
    CGFloat tw       = [_title sizeWithAttributes:attrs].width;
    CGFloat closeGap = _isPinned ? 0 : (4 + kCloseSize + 4);
    return MAX(kTabMinWidth, MIN(kTabMaxWidth, 8 + kIconSize + 4 + tw + closeGap + 8));
}

- (void)drawRect:(NSRect)dirtyRect {
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGFloat r = 2.0;

    // ── Tab shape: rounded top corners, flat bottom ───────────────────────────
    NSBezierPath *tabPath = [NSBezierPath bezierPath];
    [tabPath moveToPoint:NSMakePoint(0, 0)];
    [tabPath lineToPoint:NSMakePoint(0, h - r)];
    [tabPath appendBezierPathWithArcWithCenter:NSMakePoint(r, h - r)
                                         radius:r startAngle:180 endAngle:90 clockwise:YES];
    [tabPath lineToPoint:NSMakePoint(w - r, h)];
    [tabPath appendBezierPathWithArcWithCenter:NSMakePoint(w - r, h - r)
                                         radius:r startAngle:90 endAngle:0 clockwise:YES];
    [tabPath lineToPoint:NSMakePoint(w, 0)];
    [tabPath closePath];

    // ── Fill ──────────────────────────────────────────────────────────────────
    if (_isSelected) {
        [activeTabColor() setFill];
        [tabPath fill];
    } else {
        NSColor *top    = _hovered ? [NSColor colorWithWhite:0.90 alpha:1]
                                   : [NSColor colorWithWhite:0.86 alpha:1];
        NSColor *bottom = _hovered ? hoverTabColor() : inactiveTabColor();
        NSGradient *g = [[NSGradient alloc] initWithStartingColor:top endingColor:bottom];
        [NSGraphicsContext saveGraphicsState];
        [tabPath addClip];
        [g drawInRect:self.bounds angle:270];
        [NSGraphicsContext restoreGraphicsState];
    }

    // ── Border ────────────────────────────────────────────────────────────────
    [tabBorderColor() setStroke];
    tabPath.lineWidth = 0.5;
    [tabPath stroke];

    // ── Active tab: #fda640 3px accent at top, clipped to shape ──────────────
    if (_isSelected) {
        [NSGraphicsContext saveGraphicsState];
        [tabPath addClip];
        [accentColor() setFill];
        NSRectFill(NSMakeRect(0, h - 3, w, 3));
        [NSGraphicsContext restoreGraphicsState];
    }

    // ── 2px right divider: dark gray + white highlight ────────────────────────
    [dividerGray() setFill];
    NSRectFill(NSMakeRect(w - 2, 1, 1, h - 3));
    [dividerWhite() setFill];
    NSRectFill(NSMakeRect(w - 1, 1, 1, h - 3));

    // ── Floppy icon ───────────────────────────────────────────────────────────
    NSImage *icon = _isModified ? toolbarIcon(@"saveFileRed") : toolbarIcon(@"saveFile");
    if (icon) {
        CGFloat sz  = kIconSize * 0.8;
        NSRect  ir  = NSMakeRect(8 + (kIconSize - sz) / 2.0, (h - sz) / 2.0, sz, sz);
        [icon drawInRect:ir fromRect:NSZeroRect
               operation:NSCompositingOperationSourceOver fraction:1.0];
    }

    // ── Title ─────────────────────────────────────────────────────────────────
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.lineBreakMode = NSLineBreakByTruncatingMiddle;
    NSColor *textColor = _isSelected ? [NSColor labelColor]
                                     : [NSColor colorWithWhite:0.15 alpha:1];
    NSFont  *font      = _isSelected ? [NSFont systemFontOfSize:12 weight:NSFontWeightMedium]
                                     : [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    NSDictionary *attrs = @{NSFontAttributeName: font,
                             NSForegroundColorAttributeName: textColor,
                             NSParagraphStyleAttributeName: ps};
    CGFloat textX = 8 + kIconSize + 4;
    CGFloat textW = w - textX - (_isPinned ? 18 : kCloseSize + 8);
    CGFloat textY = (h - font.pointSize - 2) / 2.0;
    [_title drawInRect:NSMakeRect(textX, textY, textW, font.pointSize + 4)
        withAttributes:attrs];

    // ── Pin / close ───────────────────────────────────────────────────────────
    if (_isPinned) {
        NSDictionary *pa = @{NSFontAttributeName: [NSFont systemFontOfSize:10]};
        [@"📌" drawAtPoint:NSMakePoint(w - 18, (h - 14) / 2.0) withAttributes:pa];
    } else {
        CGFloat cx = w - kCloseSize - 6;
        CGFloat cy = (h - kCloseSize) / 2.0;
        if (_isSelected || _hovered) {
            NSImage *closeImg = nil;
            if (_closeHovered)    closeImg = tabIcon(@"closeTabButton_hoverIn");
            else if (_isSelected) closeImg = tabIcon(@"closeTabButton");
            else                  closeImg = tabIcon(@"closeTabButton_hoverOnTab");
            if (closeImg) { closeImg.size = NSMakeSize(32, 32);
                [closeImg drawInRect:NSMakeRect(cx, cy, kCloseSize, kCloseSize)
                           fromRect:NSZeroRect
                          operation:NSCompositingOperationSourceOver fraction:1.0];
            } else {
                NSDictionary *xa = @{NSFontAttributeName: [NSFont systemFontOfSize:11],
                                      NSForegroundColorAttributeName: textColor};
                [@"×" drawAtPoint:NSMakePoint(cx + 1, cy - 1) withAttributes:xa];
            }
        }
    }
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) [self removeTrackingArea:_trackingArea];
    _trackingArea = [[NSTrackingArea alloc]
        initWithRect:self.bounds
             options:(NSTrackingMouseEnteredAndExited |
                      NSTrackingMouseMoved            |
                      NSTrackingActiveInKeyWindow)
               owner:self userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)mouseEntered:(NSEvent *)e { _hovered = YES;  [self setNeedsDisplay:YES]; }
- (void)mouseExited:(NSEvent *)e  { _hovered = NO; _closeHovered = NO; [self setNeedsDisplay:YES]; }
- (void)mouseMoved:(NSEvent *)e {
    NSPoint p  = [self convertPoint:e.locationInWindow fromView:nil];
    CGFloat cx = self.bounds.size.width - kCloseSize - 6;
    BOOL oc    = p.x >= cx && p.x <= cx + kCloseSize;
    if (oc != _closeHovered) { _closeHovered = oc; [self setNeedsDisplay:YES]; }
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint p  = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat cx = self.bounds.size.width - kCloseSize - 6;
    BOOL overClose = !_isPinned && (_isSelected || _hovered)
                     && p.x >= cx && p.x <= cx + kCloseSize;
    SEL action = overClose ? _closeAction : _selectAction;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [_target performSelector:action withObject:self];
#pragma clang diagnostic pop
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
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
    NSScrollView                  *_scrollView;
    NSView                        *_containerView;
    NSMutableArray<_NppTabItem *> *_items;
    NSInteger                      _selectedIndex;
    BOOL                           _wrapMode;
    _NppScrollArrowButton         *_scrollLeftBtn;
    _NppScrollArrowButton         *_scrollRightBtn;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _items         = [NSMutableArray array];
        _selectedIndex = -1;
        [self _buildUI];
    }
    return self;
}

- (void)_buildUI {
    _containerView = [[NSView alloc] initWithFrame:NSZeroRect];

    _scrollView                       = [[NSScrollView alloc] initWithFrame:self.bounds];
    _scrollView.autoresizingMask      = NSViewNotSizable;   // managed in relayout
    _scrollView.hasHorizontalScroller = NO;
    _scrollView.hasVerticalScroller   = NO;
    _scrollView.drawsBackground       = NO;
    _scrollView.documentView          = _containerView;
    [self addSubview:_scrollView];

    _scrollLeftBtn  = [[_NppScrollArrowButton alloc] initPointingRight:NO
                                                                target:self
                                                                action:@selector(_scrollLeft:)];
    _scrollRightBtn = [[_NppScrollArrowButton alloc] initPointingRight:YES
                                                                target:self
                                                                action:@selector(_scrollRight:)];
    [self addSubview:_scrollLeftBtn];
    [self addSubview:_scrollRightBtn];
}

// Legacy alias — kept so any external caller still compiles.
- (void)buildScrollView { /* init already called _buildUI */ }

- (void)drawRect:(NSRect)dirtyRect {
    [tabBarBgColor() setFill];
    NSRectFill(self.bounds);
    [[NSColor separatorColor] setFill];
    NSRectFill(NSMakeRect(0, 0, self.bounds.size.width, 1));
}

// Called by Auto Layout whenever the view is sized — use this to guarantee
// relayout runs with correct bounds (fixes arrow visibility without window resize).
- (void)layout {
    [super layout];
    [self relayout];
}

- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size];
    [self relayout];
}

#pragma mark - Public API

- (void)addTabWithTitle:(NSString *)title modified:(BOOL)modified {
    _NppTabItem *item  = [[_NppTabItem alloc] initWithFrame:NSZeroRect];
    item.title         = title;
    item.isModified    = modified;
    item.isSelected    = NO;
    item.tabIndex      = _items.count;
    item.target        = self;
    item.selectAction  = @selector(tabItemSelected:);
    item.closeAction   = @selector(tabItemClosed:);
    [_items addObject:item];
    [_containerView addSubview:item];
    [self relayout];
    [self setNeedsLayout:YES];   // schedule Auto Layout pass → layout → relayout
}

- (void)removeTabAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_items.count) return;
    [_items[index] removeFromSuperview];
    [_items removeObjectAtIndex:index];
    for (NSInteger i = index; i < (NSInteger)_items.count; i++)
        _items[i].tabIndex = i;
    if (_selectedIndex >= (NSInteger)_items.count)
        _selectedIndex = (NSInteger)_items.count - 1;
    if (_selectedIndex >= 0)
        _items[_selectedIndex].isSelected = YES;
    [self relayout];
    [self setNeedsLayout:YES];
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
    _selectedIndex                = index;
    _items[index].isSelected      = YES;
    [_items[index] setNeedsDisplay:YES];
    [self relayout];
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
    CGFloat barW = self.bounds.size.width;
    CGFloat barH = self.bounds.size.height;
    if (barW < 1 || barH < 1) return;  // not yet sized — skip

    CGFloat inactiveH = barH - kTabTopGap - 1;            // visible inactive tab height
    CGFloat activeH   = inactiveH + kActiveBoost;          // active tab is slightly taller

    if (_wrapMode) {
        _scrollLeftBtn.hidden  = YES;
        _scrollRightBtn.hidden = YES;
        _scrollView.frame = NSMakeRect(0, 0, barW, barH);

        CGFloat x = 0, y = 1;
        for (_NppTabItem *item in _items) {
            CGFloat w = item.preferredWidth;
            if (x + w > barW && x > 0) { x = 0; y += (inactiveH + 1); }
            item.frame = NSMakeRect(x, y, w, inactiveH);
            x += w;
        }
        CGFloat totalH = y + inactiveH + 1;
        _containerView.frame = NSMakeRect(0, 0, barW, totalH);

        NSRect f = self.frame;
        if (f.size.height != totalH) {
            f.size.height = totalH;
            NSView *sv = self.superview;
            if (sv) f.origin.y = sv.bounds.size.height - totalH;
            [super setFrame:f];
        }
        return;
    }

    // ── Non-wrap: calculate total tab width, decide if arrows needed ──────────
    CGFloat totalTabsW = 0;
    for (_NppTabItem *item in _items) totalTabsW += item.preferredWidth;

    BOOL    needsArrows = (totalTabsW > barW);
    CGFloat arrowsW     = needsArrows ? (2.0 * kArrowBtnW) : 0.0;
    CGFloat scrollW     = barW - arrowsW;

    _scrollView.frame = NSMakeRect(0, 0, scrollW, barH);

    _scrollLeftBtn.hidden  = !needsArrows;
    _scrollRightBtn.hidden = !needsArrows;
    if (needsArrows) {
        _scrollLeftBtn.frame  = NSMakeRect(scrollW,              0, kArrowBtnW, barH);
        _scrollRightBtn.frame = NSMakeRect(scrollW + kArrowBtnW, 0, kArrowBtnW, barH);
    }

    // Position tabs: inactive at y=1; active at y=1 but taller (raised look)
    CGFloat x = 0;
    for (_NppTabItem *item in _items) {
        CGFloat w  = item.preferredWidth;
        BOOL    sel = (item.tabIndex == _selectedIndex);
        item.frame  = NSMakeRect(x, 1, w, sel ? activeH : inactiveH);
        x += w;
    }
    _containerView.frame = NSMakeRect(0, 0, MAX(x, scrollW), barH);
    [self setNeedsDisplay:YES];
}

// Minimal-scroll: only move the viewport if the tab isn't already fully visible.
// New tabs added at right edge scroll into view from the right — never push
// existing tabs off the left.
- (void)scrollTabToVisible:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_items.count) return;
    NSRect     tab = _items[index].frame;
    NSClipView *cv = _scrollView.contentView;
    CGFloat     cx = cv.bounds.origin.x;
    CGFloat     sw = _scrollView.bounds.size.width;
    CGFloat     nx = cx;

    if (NSMinX(tab) < cx)           // tab is off the left edge
        nx = NSMinX(tab);
    else if (NSMaxX(tab) > cx + sw) // tab is off the right edge
        nx = NSMaxX(tab) - sw;

    if (nx != cx) {
        [cv scrollToPoint:NSMakePoint(MAX(0, nx), 0)];
        [_scrollView reflectScrolledClipView:cv];
    }
}

#pragma mark - Scroll actions

- (void)_scrollLeft:(id)sender {
    NSClipView *cv  = _scrollView.contentView;
    CGFloat     cur = cv.bounds.origin.x;
    [cv scrollToPoint:NSMakePoint(MAX(0, cur - kTabMinWidth), 0)];
    [_scrollView reflectScrolledClipView:cv];
}

- (void)_scrollRight:(id)sender {
    NSClipView *cv   = _scrollView.contentView;
    CGFloat     cur  = cv.bounds.origin.x;
    CGFloat     maxX = MAX(0, _containerView.frame.size.width - _scrollView.bounds.size.width);
    [cv scrollToPoint:NSMakePoint(MIN(maxX, cur + kTabMinWidth), 0)];
    [_scrollView reflectScrolledClipView:cv];
}

#pragma mark - Context menu

- (NSMenu *)buildTabContextMenu {
    NSMenu * (^sub)(NSString *) = ^NSMenu *(NSString *t) { return [[NSMenu alloc] initWithTitle:t]; };
    NSMenuItem * (^it)(NSString *, SEL) = ^NSMenuItem *(NSString *t, SEL s) {
        return [[NSMenuItem alloc] initWithTitle:t action:s keyEquivalent:@""];
    };
    NSMenuItem * (^withSub)(NSString *, NSMenu *) = ^NSMenuItem *(NSString *t, NSMenu *m) {
        NSMenuItem *i = [[NSMenuItem alloc] initWithTitle:t action:nil keyEquivalent:@""];
        i.submenu = m; return i;
    };

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    [menu addItem:it(@"Pin Tab",  @selector(pinCurrentTab:))];
    [menu addItem:it(@"Close",    @selector(closeCurrentTab:))];

    NSMenu *cm = sub(@"Close Multiple Tabs");
    [cm addItem:it(@"Close All But This",     @selector(closeAllButCurrent:))];
    [cm addItem:it(@"Close All to the Left",  @selector(closeAllToLeft:))];
    [cm addItem:it(@"Close All to the Right", @selector(closeAllToRight:))];
    [cm addItem:it(@"Close All Unchanged",    @selector(closeAllUnchanged:))];
    [menu addItem:withSub(@"Close Multiple Tabs", cm)];

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
    NSMenu *cp = sub(@"Copy to Clipboard");
    [cp addItem:it(@"Copy Full File Path",         @selector(copyFullFilePath:))];
    [cp addItem:it(@"Copy File Name",              @selector(copyFileName:))];
    [cp addItem:it(@"Copy Current Directory Path", @selector(copyCurrentDirectoryPath:))];
    [menu addItem:withSub(@"Copy to Clipboard", cp)];

    NSMenu *mv = sub(@"Move Document");
    [mv addItem:it(@"Move to Other Vertical View",    @selector(moveToOtherVerticalView:))];
    [mv addItem:it(@"Clone to Other Vertical View",   @selector(cloneToOtherVerticalView:))];
    [mv addItem:[NSMenuItem separatorItem]];
    [mv addItem:it(@"Move to Other Horizontal View",  @selector(moveToOtherHorizontalView:))];
    [mv addItem:it(@"Clone to Other Horizontal View", @selector(cloneToOtherHorizontalView:))];
    [mv addItem:[NSMenuItem separatorItem]];
    [mv addItem:it(@"Reset View",                     @selector(resetView:))];
    [menu addItem:withSub(@"Move Document", mv)];

    return menu;
}

@end
