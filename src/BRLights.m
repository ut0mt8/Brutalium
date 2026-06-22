//
//  BRLights.m — square traffic-light buttons (formerly FlatLights).
//
//  Repaints a window's three standard control buttons as squares with
//  configurable colours + a hover glyph. Done with a ONE-TIME class-level method
//  swizzle of the three private widget classes (_NSThemeCloseWidget / _NSThemeWidget
//  / _NSThemeZoomWidget) — never a per-instance isa change, so it coexists with
//  the NSKVONotifying_ subclasses and Swift property system AppKit puts on these
//  buttons under Solarium. Reads the shared config cache; the core arms the
//  swizzle and drives per-window discovery (hover + prompt repaint).
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

#pragma mark - Class-level install (no isa changes — KVO / Swift-cast safe)

// We method-swizzle the three private window-button classes ONCE, instead of
// per-instance isa-swizzling. Under Solarium AppKit installs an NSKVONotifying_
// subclass on these buttons and drives the titlebar through a Swift property
// system; reclassing an instance clobbers that chain and crashes the next
// titlebar update in swift_dynamicCast. Leaving every instance's isa untouched
// keeps KVO and the Swift cast happy. The captured original IMP is called
// through when the feature is off or the view isn't a standard window button.

typedef struct { Class cls; IMP origDraw; IMP origUpdate; } FLEntry;
static FLEntry gFLEntries[4];
static int     gFLEntryCount = 0;

static FLEntry *FLEntryForClass(Class c) {
    for (int i = 0; i < gFLEntryCount; i++) if (gFLEntries[i].cls == c) return &gFLEntries[i];
    return NULL;
}
static FLEntry *FLEntryForInstance(id self) {
    // self's class is the NSKVONotifying_ subclass; walk up to our swizzled class.
    for (Class c = object_getClass(self); c; c = class_getSuperclass(c)) {
        FLEntry *e = FLEntryForClass(c);
        if (e) return e;
    }
    return NULL;
}

static void FLDrawRectIMP(id self, SEL _cmd, NSRect dirty) {
    BOOL handled = NO;
    if (BRLightsActive() && [NSThread isMainThread]) {
        @try {
            FLType t = FLTypeOf((NSView *)self);
            if (t != FLTypeNone) { FLDraw((NSButton *)self, t); handled = YES; }
        } @catch (__unused NSException *e) { handled = NO; }
    }
    if (!handled) {
        FLEntry *e = FLEntryForInstance(self);
        if (e && e->origDraw) ((void (*)(id, SEL, NSRect))e->origDraw)(self, _cmd, dirty);
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
        FLEntry *e = FLEntryForInstance(self);
        if (e && e->origUpdate) ((void (*)(id, SEL))e->origUpdate)(self, _cmd);
    }
}

// Swizzle drawRect:/updateLayer on one widget class, scoped to that class only
// (never its superclass). Call on derived classes BEFORE base classes so a
// derived class never captures our own IMP as its "original".
static void FLSwizzleClass(const char *clsName) {
    Class cls = objc_getClass(clsName);
    if (!cls || FLEntryForClass(cls) ||
        gFLEntryCount >= (int)(sizeof(gFLEntries) / sizeof(gFLEntries[0]))) return;
    FLEntry *e = &gFLEntries[gFLEntryCount];
    e->cls = cls;

    Method dm = class_getInstanceMethod(cls, @selector(drawRect:));
    e->origDraw = dm ? method_getImplementation(dm) : NULL;
    const char *dtypes = dm ? method_getTypeEncoding(dm) : "v@:{CGRect={CGPoint=dd}{CGSize=dd}}";
    if (!class_addMethod(cls, @selector(drawRect:), (IMP)FLDrawRectIMP, dtypes))
        e->origDraw = method_setImplementation(class_getInstanceMethod(cls, @selector(drawRect:)),
                                               (IMP)FLDrawRectIMP);

    Method um = class_getInstanceMethod(cls, @selector(updateLayer));
    e->origUpdate = um ? method_getImplementation(um) : NULL;
    const char *utypes = um ? method_getTypeEncoding(um) : "v@:";
    if (!class_addMethod(cls, @selector(updateLayer), (IMP)FLUpdateLayerIMP, utypes))
        e->origUpdate = method_setImplementation(class_getInstanceMethod(cls, @selector(updateLayer)),
                                                 (IMP)FLUpdateLayerIMP);

    gFLEntryCount++;
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

// Traffic lights live only on genuine top-level main windows. Restricting to
// those keeps us off auxiliary/custom windows (Chrome render-host surfaces,
// popups, status bubbles, overlays, panels) where the standard buttons were
// never created — calling -standardWindowButton: on those forces AppKit's lazy
// _NSViewStandardButtonSearch to walk a custom frame view tree and can crash.
static BOOL FLWindowEligible(NSWindow *w) {
    NSWindowStyleMask m = w.styleMask;
    if (!(m & NSWindowStyleMaskTitled))  return NO;   // needs a titlebar
    if (m & NSWindowStyleMaskBorderless) return NO;
    if (w.parentWindow)                  return NO;   // child / attached windows
    if (!w.canBecomeMainWindow)          return NO;   // panels, popovers, overlays
    if (w.level != NSNormalWindowLevel)  return NO;   // floating / overlay levels
    return YES;
}

// The class swizzle already makes every standard window button paint as a square
// on its own. This just nudges an existing window to repaint immediately and
// installs the hover watcher for the glyph; it changes no classes.
static void FLInstallOnWindow(NSWindow *w, BOOL forceRedraw) {
    if (!w || ![NSThread isMainThread]) return;
    BRLightsArm();   // no-op once armed; retries if AppKit wasn't ready at launch
    if (!FLWindowEligible(w)) return;
    if (!forceRedraw && objc_getAssociatedObject(w, kFLWindowDoneKey)) return;

    NSWindowButton types[3] = { NSWindowCloseButton, NSWindowMiniaturizeButton, NSWindowZoomButton };
    BOOL anyButton = NO;
    for (int i = 0; i < 3; i++) {
        NSButton *b = [w standardWindowButton:types[i]];
        if (!b) continue;
        anyButton = YES;
        [b setNeedsDisplay:YES];
    }
    BOOL hoverReady = anyButton ? FLInstallHover(w) : YES;
    if (anyButton && hoverReady)
        objc_setAssociatedObject(w, kFLWindowDoneKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - Exposed entry points

void BRLightsInstallOnWindow(NSWindow *w, BOOL forceRedraw) { FLInstallOnWindow(w, forceRedraw); }

void BRLightsRefreshAll(BOOL forceRedraw) {
    NSApplication *app = NSApp;
    if (!app) return;
    for (NSWindow *w in app.windows) FLInstallOnWindow(w, forceRedraw);
}

// Discovery is driven by the core's NSWindow notifications (which call
// BRLightsInstallOnWindow). The squaring itself is a one-time class-level
// method swizzle of the three private window-button classes — no NSWindow
// swizzle (the windows module owns that) and no per-instance isa changes.
void BRLightsArm(void) {
    static BOOL armed = NO;
    if (armed) return;
    // AppKit's private widget classes. Derived (close/zoom) before base (the
    // minimize button is the base _NSThemeWidget) so captured originals are real.
    Class close = objc_getClass("_NSThemeCloseWidget");
    Class zoom  = objc_getClass("_NSThemeZoomWidget");
    Class base  = objc_getClass("_NSThemeWidget");
    if (!close || !zoom || !base) return;   // AppKit not ready yet — retry next call
    FLSwizzleClass("_NSThemeCloseWidget");
    FLSwizzleClass("_NSThemeZoomWidget");
    FLSwizzleClass("_NSThemeWidget");
    armed = YES;
}
