#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#include <math.h>

static BOOL WMusicIsFoobarMainWindow(NSWindow *window) {
    return window != nil && [window.title isEqualToString:@"foobar2000"];
}

static CGFloat WMusicPreferredHeight = -1.0;
static CGFloat WMusicPreferredTop = -1.0;
static CGFloat WMusicAcceptedWidth = -1.0;

typedef NS_ENUM(NSInteger, WMusicResizeMode) {
    WMusicResizeModeNone = 0,
    WMusicResizeModeVertical,
    WMusicResizeModeBottomRight,
};

static __weak NSWindow *WMusicActiveResizeWindow;
static NSRect WMusicActiveResizeStartFrame;
static NSPoint WMusicActiveResizeStartScreenPoint;
static BOOL WMusicActiveResize;
static WMusicResizeMode WMusicActiveResizeMode;
static BOOL WMusicFrameGuardInstalled;
static BOOL WMusicSendEventGuardInstalled;

static NSRect WMusicGuardedFrame(NSWindow *window, NSRect frame) {
    if (WMusicIsFoobarMainWindow(window) &&
        WMusicPreferredHeight >= 0.0 &&
        !WMusicActiveResize &&
        !window.isZoomed &&
        (window.styleMask & NSWindowStyleMaskFullScreen) == 0 &&
        fabs(frame.size.height - WMusicPreferredHeight) > 1.0) {
        frame.size.height = WMusicPreferredHeight;
    }
    return frame;
}

@interface NSWindow (WMusicFrameGuard)
- (void)wmusic_guard_setFrame:(NSRect)frameRect display:(BOOL)displayFlag animate:(BOOL)animateFlag;
- (void)wmusic_guard_setFrame:(NSRect)frameRect display:(BOOL)displayFlag;
@end

@implementation NSWindow (WMusicFrameGuard)

- (void)wmusic_guard_setFrame:(NSRect)frameRect display:(BOOL)displayFlag animate:(BOOL)animateFlag {
    NSRect guardedFrame = WMusicGuardedFrame(self, frameRect);
    [self wmusic_guard_setFrame:guardedFrame display:displayFlag animate:animateFlag];
}

- (void)wmusic_guard_setFrame:(NSRect)frameRect display:(BOOL)displayFlag {
    NSRect guardedFrame = WMusicGuardedFrame(self, frameRect);
    [self wmusic_guard_setFrame:guardedFrame display:displayFlag];
}

@end

static void WMusicInstallFrameGuard(void) {
    if (WMusicFrameGuardInstalled) {
        return;
    }

    Method animatedMethod = class_getInstanceMethod([NSWindow class],
                                                     @selector(setFrame:display:animate:));
    Method animatedGuard = class_getInstanceMethod([NSWindow class],
                                                    @selector(wmusic_guard_setFrame:display:animate:));
    if (animatedMethod != NULL && animatedGuard != NULL) {
        method_exchangeImplementations(animatedMethod, animatedGuard);
    }

    Method plainMethod = class_getInstanceMethod([NSWindow class],
                                                 @selector(setFrame:display:));
    Method plainGuard = class_getInstanceMethod([NSWindow class],
                                                @selector(wmusic_guard_setFrame:display:));
    if (plainMethod != NULL && plainGuard != NULL) {
        method_exchangeImplementations(plainMethod, plainGuard);
    }

    WMusicFrameGuardInstalled = YES;
}

static void WMusicResizeWindow(NSWindow *window,
                               WMusicResizeMode mode,
                               NSRect startFrame,
                               NSPoint startScreenPoint,
                               NSPoint currentScreenPoint) {
    if (!WMusicIsFoobarMainWindow(window)) {
        return;
    }
    if (mode == WMusicResizeModeNone) {
        return;
    }

    // Keep the top edge fixed while the bottom edge follows the pointer.
    // This makes the gesture feel like a native bottom-edge resize even when
    // Foobar's content view consumes the normal AppKit resize hit-test.
    CGFloat heightDelta = startScreenPoint.y - currentScreenPoint.y;
    CGFloat minimumHeight = MAX(360.0, window.minSize.height);
    CGFloat maximumHeight = MAX(minimumHeight, MIN(10000.0, window.maxSize.height));
    CGFloat height = startFrame.size.height + heightDelta;
    height = MIN(MAX(height, minimumHeight), maximumHeight);

    CGFloat width = startFrame.size.width;
    if (mode == WMusicResizeModeBottomRight) {
        CGFloat widthDelta = currentScreenPoint.x - startScreenPoint.x;
        CGFloat minimumWidth = MAX(540.0, window.minSize.width);
        CGFloat maximumWidth = MAX(minimumWidth, MIN(10000.0, window.maxSize.width));
        width = MIN(MAX(startFrame.size.width + widthDelta, minimumWidth), maximumWidth);
    }

    NSRect frame = startFrame;
    frame.size.width = width;
    frame.size.height = height;
    // Preserve the visual top-left anchor. The AppKit frame origin is at the
    // bottom-left, so only origin.y changes as the bottom edge moves.
    frame.origin.x = startFrame.origin.x;
    frame.origin.y = NSMaxY(startFrame) - height;
    WMusicPreferredHeight = height;
    WMusicPreferredTop = NSMaxY(startFrame);
    WMusicAcceptedWidth = startFrame.size.width;
    [window setFrame:frame display:YES animate:NO];
    NSRect actualFrame = window.frame;
    if (fabs(actualFrame.size.height - height) <= 2.0) {
        WMusicPreferredHeight = actualFrame.size.height;
    }
    WMusicAcceptedWidth = actualFrame.size.width;
}

static void WMusicSchedulePreferredHeightReassert(NSWindow *window);
static void WMusicFinishActiveResize(NSWindow *window);
static WMusicResizeMode WMusicResizeModeForPoint(NSWindow *window, NSPoint screenPoint);

@interface WMusicResizeHandleView : NSView
@property(nonatomic, weak) NSWindow *targetWindow;
@property(nonatomic) BOOL resizing;
@property(nonatomic) WMusicResizeMode resizeMode;
@property(nonatomic) NSRect startFrame;
@property(nonatomic) NSPoint startScreenPoint;
@end

@implementation WMusicResizeHandleView

- (BOOL)isOpaque {
    return NO;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)becomeFirstResponder {
    return YES;
}

- (NSView *)hitTest:(NSPoint)point {
    if (!NSPointInRect(point, self.bounds) || point.x < 20.0) {
        return nil;
    }
    return self;
}

- (BOOL)mouseDownCanMoveWindow {
    return NO;
}

- (BOOL)shouldDelayWindowOrderingForEvent:(NSEvent *)event {
    return YES;
}

- (void)resetCursorRects {
    CGFloat cornerWidth = MIN(28.0, self.bounds.size.width);
    NSRect cornerRect = NSMakeRect(NSMaxX(self.bounds) - cornerWidth,
                                   NSMinY(self.bounds),
                                   cornerWidth,
                                   self.bounds.size.height);
    NSRect verticalRect = NSMakeRect(20.0,
                                     NSMinY(self.bounds),
                                     MAX(0.0, self.bounds.size.width - 20.0 - cornerWidth),
                                     self.bounds.size.height);
    [self addCursorRect:verticalRect cursor:[NSCursor resizeUpDownCursor]];
    [self addCursorRect:cornerRect cursor:[NSCursor resizeLeftRightCursor]];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    // A small, low-contrast grip makes the otherwise transparent hit area
    // discoverable without adding a permanent toolbar-like control.
    NSRect grip = NSMakeRect(NSMidX(self.bounds) - 22.0,
                             NSMidY(self.bounds) - 1.0,
                             44.0,
                             2.0);
    [[NSColor colorWithWhite:0.85 alpha:0.26] setFill];
    NSRectFillUsingOperation(grip, NSCompositingOperationSourceOver);

    // Three short diagonals mark the bottom-right two-axis resize target.
    NSBezierPath *corner = [NSBezierPath bezierPath];
    corner.lineWidth = 1.0;
    for (CGFloat offset = 0.0; offset <= 8.0; offset += 4.0) {
        [corner moveToPoint:NSMakePoint(NSMaxX(self.bounds) - 5.0 - offset,
                                        NSMinY(self.bounds) + 3.0)];
        [corner lineToPoint:NSMakePoint(NSMaxX(self.bounds) - 3.0,
                                        NSMinY(self.bounds) + 5.0 + offset)];
    }
    [[NSColor colorWithWhite:0.85 alpha:0.34] setStroke];
    [corner stroke];
}

- (void)mouseDown:(NSEvent *)event {
    NSWindow *window = self.targetWindow ?: self.window;
    if (!WMusicIsFoobarMainWindow(window)) {
        [super mouseDown:event];
        return;
    }

    NSPoint screenPoint = [window convertPointToScreen:event.locationInWindow];
    self.resizeMode = WMusicResizeModeForPoint(window, screenPoint);
    self.resizing = self.resizeMode != WMusicResizeModeNone;
    if (!self.resizing) {
        return;
    }
    self.startFrame = window.frame;
    self.startScreenPoint = screenPoint;
    WMusicActiveResize = YES;
    WMusicActiveResizeMode = self.resizeMode;
    WMusicActiveResizeWindow = window;
    WMusicActiveResizeStartFrame = self.startFrame;
    WMusicActiveResizeStartScreenPoint = self.startScreenPoint;
}

- (void)mouseDragged:(NSEvent *)event {
    if (!self.resizing) {
        return;
    }

    NSWindow *window = self.targetWindow ?: self.window;
    NSPoint currentScreenPoint = [window convertPointToScreen:event.locationInWindow];
    WMusicResizeWindow(window,
                       self.resizeMode,
                       self.startFrame,
                       self.startScreenPoint,
                       currentScreenPoint);
}

- (void)mouseUp:(NSEvent *)event {
    self.resizing = NO;
    self.resizeMode = WMusicResizeModeNone;

    NSWindow *window = self.targetWindow ?: self.window;
    if (WMusicIsFoobarMainWindow(window)) {
        WMusicFinishActiveResize(window);
    }
    [self.window invalidateCursorRectsForView:self];
}

@end

static id WMusicResizeEventMonitor;
static char WMusicResizeHandleKey;

static void WMusicFinishActiveResize(NSWindow *window) {
    if (!WMusicIsFoobarMainWindow(window)) {
        WMusicActiveResize = NO;
        WMusicActiveResizeMode = WMusicResizeModeNone;
        WMusicActiveResizeWindow = nil;
        return;
    }

    WMusicActiveResize = NO;
    WMusicActiveResizeMode = WMusicResizeModeNone;
    WMusicSchedulePreferredHeightReassert(window);
    NSString *frameName = window.frameAutosaveName;
    if (frameName.length == 0) {
        frameName = @"foobar2000.mainwindow";
    }
    [window saveFrameUsingName:frameName];
    WMusicActiveResizeWindow = nil;
}

static void WMusicInstallResizeHandle(NSWindow *window) {
    NSView *contentView = window.contentView;
    if (!WMusicIsFoobarMainWindow(window) || contentView == nil) {
        return;
    }

    WMusicResizeHandleView *handle = objc_getAssociatedObject(window, &WMusicResizeHandleKey);
    if (![handle isKindOfClass:[WMusicResizeHandleView class]]) {
        handle = [[WMusicResizeHandleView alloc] initWithFrame:NSZeroRect];
        objc_setAssociatedObject(window, &WMusicResizeHandleKey, handle, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    handle.targetWindow = window;
    handle.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    handle.frame = NSMakeRect(0.0, 0.0, contentView.bounds.size.width, 24.0);
    if (handle.superview != contentView) {
        [handle removeFromSuperview];
        [contentView addSubview:handle positioned:NSWindowAbove relativeTo:nil];
    }
    [handle setNeedsDisplay:YES];
}

static void WMusicReassertPreferredHeight(NSWindow *window) {
    if (!WMusicIsFoobarMainWindow(window) ||
        WMusicPreferredHeight < 0.0 ||
        WMusicActiveResize ||
        window.isZoomed ||
        (window.styleMask & NSWindowStyleMaskFullScreen) != 0) {
        return;
    }

    NSRect currentFrame = window.frame;
    if (fabs(currentFrame.size.height - WMusicPreferredHeight) <= 1.0) {
        return;
    }

    NSRect frame = currentFrame;
    frame.size.height = WMusicPreferredHeight;
    frame.origin.y = WMusicPreferredTop - WMusicPreferredHeight;
    [window setFrame:frame display:YES animate:NO];
}

static void WMusicSchedulePreferredHeightReassert(NSWindow *window) {
    if (window == nil) {
        return;
    }

    NSArray<NSNumber *> *delays = @[@0.0, @0.05, @0.2, @0.5];
    for (NSNumber *delay in delays) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                      (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            WMusicReassertPreferredHeight(window);
        });
    }
}

static WMusicResizeMode WMusicResizeModeForPoint(NSWindow *window, NSPoint screenPoint) {
    if (!WMusicIsFoobarMainWindow(window)) {
        return WMusicResizeModeNone;
    }

    NSRect frame = window.frame;
    CGFloat distanceFromBottom = screenPoint.y - NSMinY(frame);
    CGFloat distanceFromLeft = screenPoint.x - NSMinX(frame);
    CGFloat distanceFromRight = NSMaxX(frame) - screenPoint.x;

    if (distanceFromBottom < -2.0 || distanceFromBottom > 24.0 ||
        distanceFromLeft < 20.0 || distanceFromRight < -2.0) {
        return WMusicResizeModeNone;
    }

    // Own the lower-right corner explicitly so Foobar cannot interpret that
    // gesture as moving the window. Keep the lower-left corner untouched.
    if (distanceFromRight <= 28.0) {
        return WMusicResizeModeBottomRight;
    }
    return WMusicResizeModeVertical;
}

@interface NSWindow (WMusicResizeEventGuard)
- (void)wmusic_guard_sendEvent:(NSEvent *)event;
@end

@implementation NSWindow (WMusicResizeEventGuard)

- (void)wmusic_guard_sendEvent:(NSEvent *)event {
    WMusicResizeMode mode = WMusicResizeModeForPoint(self,
                                                     [self convertPointToScreen:event.locationInWindow]);
    if (event.type == NSEventTypeLeftMouseDown &&
        !WMusicActiveResize &&
        mode != WMusicResizeModeNone) {
        WMusicActiveResize = YES;
        WMusicActiveResizeMode = mode;
        WMusicActiveResizeWindow = self;
        WMusicActiveResizeStartFrame = self.frame;
        WMusicActiveResizeStartScreenPoint = [self convertPointToScreen:event.locationInWindow];
        return;
    }

    if (WMusicActiveResize && WMusicActiveResizeWindow == self) {
        if (event.type == NSEventTypeLeftMouseDragged) {
            NSPoint point = [self convertPointToScreen:event.locationInWindow];
            WMusicResizeWindow(self,
                               WMusicActiveResizeMode,
                               WMusicActiveResizeStartFrame,
                               WMusicActiveResizeStartScreenPoint,
                               point);
            return;
        }

        if (event.type == NSEventTypeLeftMouseUp) {
            WMusicFinishActiveResize(self);
            return;
        }
    }

    [self wmusic_guard_sendEvent:event];
}

@end

static void WMusicInstallSendEventGuard(void) {
    if (WMusicSendEventGuardInstalled) {
        return;
    }

    Method eventMethod = class_getInstanceMethod([NSWindow class], @selector(sendEvent:));
    Method eventGuard = class_getInstanceMethod([NSWindow class], @selector(wmusic_guard_sendEvent:));
    if (eventMethod != NULL && eventGuard != NULL) {
        method_exchangeImplementations(eventMethod, eventGuard);
        WMusicSendEventGuardInstalled = YES;
    }
}

static void WMusicInstallResizeEventMonitor(void) {
    if (WMusicResizeEventMonitor != nil) {
        return;
    }

    NSEventMask mask = NSEventMaskLeftMouseDown |
                       NSEventMaskLeftMouseDragged |
                       NSEventMaskLeftMouseUp;
    WMusicResizeEventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:mask
                                                                        handler:^NSEvent *(NSEvent *event) {
        if (event.type == NSEventTypeLeftMouseDown) {
            NSWindow *window = event.window;
            WMusicResizeMode mode = WMusicResizeModeForPoint(window,
                                                             [window convertPointToScreen:event.locationInWindow]);
            if (mode != WMusicResizeModeNone) {
                WMusicActiveResize = YES;
                WMusicActiveResizeMode = mode;
                WMusicActiveResizeWindow = window;
                WMusicActiveResizeStartFrame = window.frame;
                WMusicActiveResizeStartScreenPoint = [window convertPointToScreen:event.locationInWindow];
                return nil;
            }
        } else if (WMusicActiveResize) {
            NSWindow *window = WMusicActiveResizeWindow;
            if (event.type == NSEventTypeLeftMouseDragged) {
                if (window != nil) {
                    NSPoint point = [window convertPointToScreen:event.locationInWindow];
                    WMusicResizeWindow(window,
                                       WMusicActiveResizeMode,
                                       WMusicActiveResizeStartFrame,
                                       WMusicActiveResizeStartScreenPoint,
                                       point);
                }
                return nil;
            }

            if (event.type == NSEventTypeLeftMouseUp) {
                WMusicFinishActiveResize(window);
                return nil;
            }
        }

        return event;
    }];
}

@interface WMusicWindowDelegateProxy : NSObject <NSWindowDelegate>
@property(nonatomic, weak) id originalDelegate;
- (instancetype)initWithOriginalDelegate:(id)delegate;
@end

@implementation WMusicWindowDelegateProxy

- (instancetype)initWithOriginalDelegate:(id)delegate {
    self = [super init];
    if (self != nil) {
        _originalDelegate = delegate;
    }
    return self;
}

- (BOOL)respondsToSelector:(SEL)selector {
    if (selector == @selector(windowWillResize:toSize:)) {
        return YES;
    }
    return [super respondsToSelector:selector] || [self.originalDelegate respondsToSelector:selector];
}

- (id)forwardingTargetForSelector:(SEL)selector {
    if (selector == @selector(windowWillResize:toSize:)) {
        return nil;
    }
    return self.originalDelegate;
}

- (NSSize)windowWillResize:(NSWindow *)window toSize:(NSSize)size {
    if ([window.title isEqualToString:@"foobar2000"]) {
        return size;
    }
    if ([self.originalDelegate respondsToSelector:_cmd]) {
        return [self.originalDelegate windowWillResize:window toSize:size];
    }
    return size;
}

- (void)windowDidResize:(NSNotification *)notification {
    NSWindow *window = notification.object;
    BOOL isFoobarWindow = WMusicIsFoobarMainWindow(window);
    BOOL hasPreferredHeight = isFoobarWindow && WMusicPreferredHeight >= 0.0;
    BOOL widthChanged = hasPreferredHeight &&
                        (WMusicAcceptedWidth < 0.0 ||
                         fabs(window.frame.size.width - WMusicAcceptedWidth) > 1.0);

    if (isFoobarWindow && WMusicActiveResize) {
        WMusicAcceptedWidth = window.frame.size.width;
        return;
    }

    // Foobar's original resize callback restores the old fixed height. Once
    // the user has chosen a vertical size, suppress only those callbacks that
    // belong to our vertical frame update. Native horizontal resizing still
    // reaches the original delegate because the width changed.
    if (!hasPreferredHeight || widthChanged) {
        if ([self.originalDelegate respondsToSelector:_cmd]) {
            [self.originalDelegate windowDidResize:notification];
        }
        if (widthChanged) {
            WMusicAcceptedWidth = window.frame.size.width;
        }
    }

}

@end

static char WMusicDelegateProxyKey;

static void WMusicInstallResizeDelegateProxy(NSWindow *window) {
    id currentDelegate = window.delegate;
    if ([currentDelegate isKindOfClass:[WMusicWindowDelegateProxy class]]) {
        return;
    }

    WMusicWindowDelegateProxy *proxy = [[WMusicWindowDelegateProxy alloc] initWithOriginalDelegate:currentDelegate];
    objc_setAssociatedObject(window, &WMusicDelegateProxyKey, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    window.delegate = proxy;
}

static void WMusicMakeMainWindowResizable(NSWindow *window) {
    if (!WMusicIsFoobarMainWindow(window)) {
        return;
    }

    NSWindowStyleMask style = window.styleMask;
    window.styleMask = style | NSWindowStyleMaskResizable;

    // Keep the compact layout usable while allowing the player to grow with
    // the album art and playlist. The upper bound is intentionally generous;
    // AppKit still limits the window to the visible screen area.
    window.minSize = NSMakeSize(540.0, 360.0);
    window.maxSize = NSMakeSize(10000.0, 10000.0);
    window.contentMinSize = NSMakeSize(540.0, 360.0);
    window.contentMaxSize = NSMakeSize(10000.0, 10000.0);
    window.contentAspectRatio = NSMakeSize(0.0, 0.0);
    window.resizeIncrements = NSMakeSize(1.0, 1.0);
    // Foobar treats content clicks as movable-window-background gestures.
    // Keep title-bar moving intact, but make the bottom grip an unambiguous
    // resize-only region instead of allowing the whole window to float.
    window.movableByWindowBackground = NO;
    WMusicInstallResizeDelegateProxy(window);
    WMusicInstallResizeHandle(window);
}

static void WMusicRefreshMainWindow(void) {
    for (NSWindow *window in NSApp.windows) {
        WMusicMakeMainWindowResizable(window);
        WMusicReassertPreferredHeight(window);
    }
}

__attribute__((constructor))
static void WMusicWindowResizeHookInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        WMusicInstallFrameGuard();
        WMusicInstallSendEventGuard();
        WMusicInstallResizeEventMonitor();
        WMusicRefreshMainWindow();
        [NSTimer scheduledTimerWithTimeInterval:0.5
                                         repeats:YES
                                           block:^(__unused NSTimer *timer) {
            WMusicRefreshMainWindow();
        }];
    });
}
