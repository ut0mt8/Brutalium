//
//  BRLights.m — square traffic-light buttons (formerly FlatLights).
//
//  Per-instance isa-swizzles ONLY a window's three standard control buttons and
//  repaints them as squares with configurable colours + a hover glyph. Reads the
//  shared config cache; the core arms the swizzle group and drives discovery.
//

#import <AppKit/AppKit.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#import "ZKSwizzle.h"
#import "BRConfig.h"

typedef NS_ENUM(NSInteger, FLType) { FLTypeNone = 0, FLTypeClose, FLTypeMin, FLTypeZoom };

#pragma mark - Identity

static FLType FLTypeOf(NSView *v) {
    NSWindow *w = v.window;
    if (!w) return FLTypeNone;
    if (v == [w standardWindowButton:NSWindowCloseButton])       return FLTypeClose;
    if (v == [w standardWindowButton:NSWindowMiniaturizeButton]) return FLTypeMin;
    if (v == [w standardWindowButton:NSWindowZoomButton])        return FLTypeZoom;
    return FLTypeNone;
}

#pragma mark - Hover state

static void *kFLHoverKey = &kFLHoverKey;

static BOOL FLHoverForWindow(NSWindow *w) {
    if (!w) return NO;
    return [objc_getAssociatedObject(w, kFLHoverKey) boolValue];
}

static NSRect FLGroupRect(NSWindow *w, NSView *space) {
    NSWindowButton types[3] = { NSWindowCloseButton, NSWindowMiniaturizeButton, NSWindowZoomButton };
    NSRect group = NSZeroRect;
    BOOL has = NO;
    for (int i = 0; i < 3; i++) {
        NSButton *b = [w standardWindowButton:types[i]];
        if (!b || b.isHidden) continue;
        NSRect f = [b convertRect:b.bounds toView:space];
        group = has ? NSUnionRect(group, f) : f;
        has = YES;
    }
    if (!has) return NSZeroRect;
    return NSInsetRect(group, -10.0, -10.0);
}

#pragma mark - Colours

static NSColor *FLColor(int r, int g, int b) {
    return [NSColor colorWithSRGBRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
}

static NSColor *FLColorFromRGBA(uint32_t v) {
    return [NSColor colorWithSRGBRed:((v >> 24) & 255) / 255.0
                               green:((v >> 16) & 255) / 255.0
                                blue:((v >> 8)  & 255) / 255.0
                               alpha: (v        & 255) / 255.0];
}

static BOOL FLIsDark(NSView *v) {
    NSAppearanceName name =
        [v.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua,
                                                                   NSAppearanceNameDarkAqua]];
    return [name isEqualToString:NSAppearanceNameDarkAqua];
}

static NSColor *FLGlyphColor(void) {
    return FLColorFromRGBA(gLGlyphRGBA);
}

static NSColor *FLFillColor(NSButton *btn, FLType type, BOOL hover) {
    NSWindow *w = btn.window;
    BOOL key = w.isMainWindow || w.isKeyWindow;

    if (!key && !hover) {
        if (gLInactiveAuto) return FLIsDark(btn) ? FLColor(90, 90, 94) : FLColor(206, 206, 206);
        return FLColorFromRGBA(gLInactiveRGBA);
    }

    uint32_t rgba;
    switch (type) {
        case FLTypeClose: rgba = gLCloseRGBA; break;
        case FLTypeMin:   rgba = gLMinRGBA;   break;
        case FLTypeZoom:  rgba = gLZoomRGBA;  break;
        default:          rgba = 0xA0A0A0FF;  break;
    }
    NSColor *c = FLColorFromRGBA(rgba);

    BOOL pressed = NO;
    @try { pressed = btn.cell.isHighlighted; } @catch (__unused NSException *e) {}
    if (pressed) c = [c blendedColorWithFraction:0.20 ofColor:[NSColor blackColor]];
    return c;
}

#pragma mark - Glyphs

static void FLDrawGlyph(FLType type, NSRect sq) {
    [FLGlyphColor() set];
    NSBezierPath *p = [NSBezierPath bezierPath];
    p.lineWidth = fmax(1.0, sq.size.width * 0.10);
    p.lineCapStyle = NSLineCapStyleRound;
    CGFloat cx = NSMidX(sq), cy = NSMidY(sq);
    CGFloat r  = sq.size.width * 0.26;
    switch (type) {
        case FLTypeClose:
            [p moveToPoint:NSMakePoint(cx - r, cy - r)]; [p lineToPoint:NSMakePoint(cx + r, cy + r)];
            [p moveToPoint:NSMakePoint(cx - r, cy + r)]; [p lineToPoint:NSMakePoint(cx + r, cy - r)];
            break;
        case FLTypeMin:
            [p moveToPoint:NSMakePoint(cx - r, cy)]; [p lineToPoint:NSMakePoint(cx + r, cy)];
            break;
        case FLTypeZoom:
            [p moveToPoint:NSMakePoint(cx - r, cy)]; [p lineToPoint:NSMakePoint(cx + r, cy)];
            [p moveToPoint:NSMakePoint(cx, cy - r)]; [p lineToPoint:NSMakePoint(cx, cy + r)];
            break;
        default: return;
    }
    [p stroke];
}

#pragma mark - Square renderer (shared by both draw paths)

static void FLDrawContent(NSButton *btn, FLType type, BOOL hover, NSRect b) {
    CGFloat adjust = gLSize;
    CGFloat side = floor(fmin(b.size.width, b.size.height)) + adjust;
    if (side < 2.0) side = 2.0;
    NSRect sq = NSMakeRect(NSMinX(b) + (b.size.width  - side) / 2.0,
                           NSMinY(b) + (b.size.height - side) / 2.0, side, side);
    CGFloat radius = gLRadius;
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:sq xRadius:radius yRadius:radius];
    [FLFillColor(btn, type, hover) setFill];
    [path fill];
    if (hover) FLDrawGlyph(type, sq);
}

static void FLDraw(NSButton *btn, FLType type) {
    FLDrawContent(btn, type, FLHoverForWindow(btn.window), btn.bounds);
}

#pragma mark - Per-instance install (scoped — never touches NSButton globally)

static Class FLSuperOf(id self);

static void FLDrawRectIMP(id self, SEL _cmd, NSRect dirty) {
    BOOL handled = NO;
    if (BRLightsActive() && [NSThread isMainThread]) {
        @try {
            FLType t = FLTypeOf((NSView *)self);
            if (t != FLTypeNone) { FLDraw((NSButton *)self, t); handled = YES; }
        } @catch (__unused NSException *e) { handled = NO; }
    }
    if (!handled) {
        struct objc_super sup = { self, FLSuperOf(self) };
        ((void (*)(struct objc_super *, SEL, NSRect))objc_msgSendSuper)(&sup, _cmd, dirty);
    }
}

static void FLDrawLayer(NSButton *btn, FLType type) {
    CALayer *host = btn.layer;
    if (!host) return;
    NSRect b = btn.bounds;
    if (b.size.width < 1 || b.size.height < 1) return;
    BOOL hover = FLHoverForWindow(btn.window);
    NSImage *img = [NSImage imageWithSize:b.size flipped:NO
                           drawingHandler:^BOOL(NSRect dstRect) {
        FLDrawContent(btn, type, hover, dstRect);
        return YES;
    }];
    host.contents = img;
    host.contentsGravity = kCAGravityResize;
    for (CALayer *s in host.sublayers) s.hidden = YES;
}

static Class FLSuperOf(id self) {
    Class flClass = object_getClass(self);
    while (flClass && strncmp(class_getName(flClass), "FL_", 3) != 0) {
        flClass = class_getSuperclass(flClass);
    }
    return class_getSuperclass(flClass ? flClass : object_getClass(self));
}

static void FLUpdateLayerIMP(id self, SEL _cmd) {
    BOOL handled = NO;
    if (BRLightsActive() && [NSThread isMainThread]) {
        @try {
            FLType t = FLTypeOf((NSView *)self);
            if (t != FLTypeNone) { FLDrawLayer((NSButton *)self, t); handled = YES; }
        } @catch (__unused NSException *e) { handled = NO; }
    }
    if (!handled) {
        CALayer *host = ((NSView *)self).layer;
        host.contents = nil;
        for (CALayer *s in host.sublayers) s.hidden = NO;
        struct objc_super sup = { self, FLSuperOf(self) };
        ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, _cmd);
    }
}

static Class FLSubclassFor(Class orig) {
    char name[256];
    snprintf(name, sizeof(name), "FL_%s", class_getName(orig));
    Class sub = objc_getClass(name);
    if (sub) return sub;
    sub = objc_allocateClassPair(orig, name, 0);
    if (!sub) return Nil;
    Method m = class_getInstanceMethod(orig, @selector(drawRect:));
    const char *types = m ? method_getTypeEncoding(m)
                          : "v@:{CGRect={CGPoint=dd}{CGSize=dd}}";
    class_addMethod(sub, @selector(drawRect:),   (IMP)FLDrawRectIMP,    types);
    class_addMethod(sub, @selector(updateLayer), (IMP)FLUpdateLayerIMP, "v@:");
    objc_registerClassPair(sub);
    return sub;
}

static BOOL FLInstallOnButton(NSButton *btn) {
    if (!btn || ![NSThread isMainThread]) return NO;
    Class cur = object_getClass(btn);
    if (strncmp(class_getName(cur), "FL_", 3) == 0) return NO;
    Class sub = FLSubclassFor(cur);
    if (sub && sub != cur) { object_setClass(btn, sub); return YES; }
    return NO;
}

static void *kFLWindowDoneKey = &kFLWindowDoneKey;
static void *kFLWatcherKey    = &kFLWatcherKey;
static void *kFLTrackingKey   = &kFLTrackingKey;

#pragma mark - Hover watcher

@interface FLHoverWatcher : NSObject
@property (weak) NSWindow *flWindow;
@end
@implementation FLHoverWatcher
- (void)flSetHover:(BOOL)hover {
    NSWindow *w = self.flWindow;
    if (!w) return;
    if ([objc_getAssociatedObject(w, kFLHoverKey) boolValue] == hover) return;
    objc_setAssociatedObject(w, kFLHoverKey, @(hover), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSWindowButton t[3] = { NSWindowCloseButton, NSWindowMiniaturizeButton, NSWindowZoomButton };
    for (int i = 0; i < 3; i++) [[w standardWindowButton:t[i]] setNeedsDisplay:YES];
}
- (void)mouseEntered:(NSEvent *)e { [self flSetHover:YES]; }
- (void)mouseMoved:(NSEvent *)e   { [self flSetHover:YES]; }
- (void)mouseExited:(NSEvent *)e  { [self flSetHover:NO];  }
@end

static BOOL FLInstallHover(NSWindow *w) {
    if (objc_getAssociatedObject(w, kFLWatcherKey)) return YES;
    NSButton *close = [w standardWindowButton:NSWindowCloseButton];
    NSView *container = close.superview;
    if (!container) return NO;
    NSRect group = FLGroupRect(w, container);
    if (NSIsEmptyRect(group)) return NO;

    FLHoverWatcher *watcher = [FLHoverWatcher new];
    watcher.flWindow = w;
    NSTrackingArea *ta = [[NSTrackingArea alloc]
        initWithRect:group
             options:(NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveAlways)
               owner:watcher userInfo:nil];
    [container addTrackingArea:ta];
    objc_setAssociatedObject(w, kFLWatcherKey,  watcher, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(w, kFLTrackingKey, ta,      OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}

static void FLInstallOnWindow(NSWindow *w, BOOL forceRedraw) {
    if (!w || ![NSThread isMainThread]) return;
    if (!forceRedraw && objc_getAssociatedObject(w, kFLWindowDoneKey)) return;

    NSWindowButton types[3] = { NSWindowCloseButton, NSWindowMiniaturizeButton, NSWindowZoomButton };
    BOOL stillNeeds = NO, anyButton = NO;
    for (int i = 0; i < 3; i++) {
        NSButton *b = [w standardWindowButton:types[i]];
        if (!b) continue;
        anyButton = YES;
        BOOL installed = FLInstallOnButton(b);
        if (installed || forceRedraw) [b setNeedsDisplay:YES];
        if (strncmp(class_getName(object_getClass(b)), "FL_", 3) != 0) stillNeeds = YES;
    }
    BOOL hoverReady = YES;
    if (anyButton) hoverReady = FLInstallHover(w);
    if (!stillNeeds && hoverReady) {
        objc_setAssociatedObject(w, kFLWindowDoneKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

#pragma mark - Exposed entry points

void BRLightsInstallOnWindow(NSWindow *w, BOOL forceRedraw) { FLInstallOnWindow(w, forceRedraw); }

void BRLightsRefreshAll(BOOL forceRedraw) {
    NSApplication *app = NSApp;
    if (!app) return;
    for (NSWindow *w in app.windows) FLInstallOnWindow(w, forceRedraw);
}

// Discovery is driven by the core's NSWindow notifications (which call
// BRLightsInstallOnWindow), so the lights module doesn't swizzle NSWindow's
// show methods — that would double-hook the same methods the windows module
// already swizzles. The actual squaring is per-instance isa-swizzling of the
// three buttons, done in FLInstallOnWindow.
void BRLightsArm(void) { /* no group swizzle needed */ }
