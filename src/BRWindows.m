//
//  BRWindows.m — window corners + expanded toolbar + titlebar removal + borders.
//
//  Squares window corners (apple-sharpener private-API technique), forces the
//  expanded toolbar (with a per-app exclusion list), optionally removes the
//  titlebar entirely for opted-in apps, and draws a configurable border + shadow
//  on every titled window. Reads the shared config cache; the core arms the
//  swizzle group and drives discovery.
//

#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <string.h>
#import "ZKSwizzle.h"
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
#import "BRConfig.h"

// Forward declarations
static BOOL BRIsPopupMenuWindow(NSWindow *w);

#pragma mark - Appliers
// A genuine top-level main window — not a panel, inspector, sheet, popover, or
// child window. Used to scope titlebar removal so auxiliary windows keep theirs.
static BOOL BRWindowIsMain(NSWindow *w) {
    NSWindowStyleMask m = w.styleMask;
    if (!(m & NSWindowStyleMaskTitled))  return NO;
    if (m & NSWindowStyleMaskBorderless) return NO;
    if (w.parentWindow)                  return NO;
    if (!w.canBecomeMainWindow)          return NO;
    if (w.level != NSNormalWindowLevel)  return NO;
    return YES;
}

// Frame-based insetting is only safe on autoresizing content. On Auto-Layout / SwiftUI-hosted
// content (NSHostingView), setting the frame triggers a re-entrant constraint update inside the

//   - Child window: WORKS. Known limitation: alt-tab duplicate in raw CGWindowList enumerators.
// This is the child-window approach. No level tricks, no Transient (both broke Finder).
static void *kBRBorderWindowKey = &kBRBorderWindowKey;

static NSWindow *BRGetBorderWindow(NSWindow *parent) {
    return objc_getAssociatedObject(parent, kBRBorderWindowKey);
}
static void BRSetBorderWindow(NSWindow *parent, NSWindow *bw) {
    objc_setAssociatedObject(parent, kBRBorderWindowKey, bw, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static NSRect BRBorderFrameForWindow(NSWindow *w, CGFloat inset) {
    NSRect pf = w.frame;
    return NSMakeRect(pf.origin.x - inset, pf.origin.y - inset,
                      pf.size.width + 2*inset, pf.size.height + 2*inset);
}

// Border window subclass that disables screen-edge constraining — macOS clamps borderless windows
// to the safe area (below the camera notch), but the main titled window can go above it. Without
// this override the border gets stuck when the main window drags into the notch area.
@interface BRBorderWindow : NSWindow
@end
@implementation BRBorderWindow
- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(NSScreen *)screen {
    return frameRect;   // no constraining — follow the parent exactly
}
@end

static void BRApplyBorder(NSWindow *w) {
    if (!(w.styleMask & NSWindowStyleMaskTitled)) return;
    // Only border normal-level windows. Floating (level 3), desktop (-2147483603), and utility windows
    // don't need borders, and bordering invisible floaters (TFloatingInputWindow) creates ghost rects.
    if (w.level != NSNormalWindowLevel) return;

    NSWindow *bw = BRGetBorderWindow(w);
    if (!BRBorderActive() || !w.isVisible) {
        if (bw) { [w removeChildWindow:bw]; [bw orderOut:nil]; BRSetBorderWindow(w, nil); }
        return;
    }

    CGFloat bs = gBorderSize;
    if (bs <= 0.0) return;
    BOOL activeWin = NSApp.active && (w.isKeyWindow || w.isMainWindow);
    NSColor *bc = activeWin ? gBorderColorObj : gBorderInactiveObj;

    if (!bw) {
        NSRect bf = BRBorderFrameForWindow(w, bs);
        bw = [[BRBorderWindow alloc] initWithContentRect:bf
                 styleMask:NSWindowStyleMaskBorderless
                   backing:NSBackingStoreBuffered defer:NO];
        bw.releasedWhenClosed = NO;
        bw.opaque = NO;
        bw.backgroundColor = [NSColor clearColor];
        bw.hasShadow = NO;
        bw.ignoresMouseEvents = YES;
        // Inherit parent's collection behavior + IgnoresCycle only. No Transient, no FullScreenNone,
        // no Managed stripping — those broke Finder's window lifecycle.
        bw.collectionBehavior = w.collectionBehavior | NSWindowCollectionBehaviorIgnoresCycle;
        NSView *cv = bw.contentView;
        cv.wantsLayer = YES;
        cv.layer.masksToBounds = NO;
        // Child window at level 0 — the only correct approach. Level tricks break z-grouping.
        // Alt-tab duplicate is a known limitation.
        [w addChildWindow:bw ordered:NSWindowBelow];
        BRSetBorderWindow(w, bw);
    }


    NSRect bf = BRBorderFrameForWindow(w, bs);
    [bw setFrame:bf display:NO];

    CALayer *cl = bw.contentView.layer;
    NSView *cv = bw.contentView;
    CGFloat mainRadius = (BRCornersActive() && gCornerRadius <= 0.0) ? 0.0 : gCornerRadius;
    cl.cornerRadius = mainRadius + bs;
    cl.masksToBounds = YES;   // clip overlay sublayers to the rounded outer shape

    static NSString * const edgeKeys[4]   = { @"top", @"right", @"bottom", @"left" };
    static NSString * const cornerKeys[4] = { @"tl", @"tr", @"br", @"bl" };
    // Persistent identity keys for objc_getAssociatedObject — must be the SAME pointer across
    // calls, so static C strings (not freshly-allocated NSStrings) are used as the association key.
    static const char *edgeAssocKeys[4]   = { "br_edge_top", "br_edge_right", "br_edge_bottom", "br_edge_left" };
    static const char *cornerAssocKeys[4] = { "br_corner_tl", "br_corner_tr", "br_corner_br", "br_corner_bl" };

    BOOL anyCustom = NO;
    for (int i = 0; i < 4; i++) if (gBorderEdgeRGBA[i] || gBorderEdgeImageEnabled[i] ||
                                     gBorderCornerRGBA[i] || gBorderCornerImageEnabled[i]) { anyCustom = YES; break; }

    if (!anyCustom) {
        // Simple path (no custom edges/corners): use CALayer's native border stroke — cheapest,
        // and remove any leftover overlay sublayers from a previous "advanced" configuration.
        cl.borderWidth  = bs;
        cl.borderColor  = bc.CGColor;
        for (int i = 0; i < 4; i++) {
            CALayer *el = objc_getAssociatedObject(cv, edgeAssocKeys[i]);
            if (el) { [el removeFromSuperlayer]; objc_setAssociatedObject(cv, edgeAssocKeys[i], nil, OBJC_ASSOCIATION_RETAIN); }
            CALayer *crl = objc_getAssociatedObject(cv, cornerAssocKeys[i]);
            if (crl) { [crl removeFromSuperlayer]; objc_setAssociatedObject(cv, cornerAssocKeys[i], nil, OBJC_ASSOCIATION_RETAIN); }
        }
    } else {
        // Advanced path: disable the native stroke (it paints ON TOP of sublayers and would hide
        // any per-edge/corner customization) and draw the WHOLE ring via 8 sublayers instead —
        // each edge/corner uses its custom colour/image if set, otherwise the uniform border colour.
        // Outer rounding is disabled here: a rounded clip mask larger than the border thickness
        // would crop the flat corner squares away entirely (radius > border size clips the whole
        // square). Custom corners always take priority over rounding in this mode.
        cl.cornerRadius = 0.0;
        cl.borderWidth = 0.0;
        NSRect cb = cv.bounds;
        NSRect edgeRects[4] = {
            NSMakeRect(bs, cb.size.height - bs, cb.size.width - 2*bs, bs),   // top
            NSMakeRect(cb.size.width - bs, bs, bs, cb.size.height - 2*bs),   // right
            NSMakeRect(bs, 0, cb.size.width - 2*bs, bs),                     // bottom
            NSMakeRect(0, bs, bs, cb.size.height - 2*bs),                   // left
        };
        NSRect cornerRects[4] = {
            NSMakeRect(0, cb.size.height - bs, bs, bs),                     // TL
            NSMakeRect(cb.size.width - bs, cb.size.height - bs, bs, bs),    // TR
            NSMakeRect(cb.size.width - bs, 0, bs, bs),                      // BR
            NSMakeRect(0, 0, bs, bs),                                       // BL
        };
        for (int i = 0; i < 4; i++) {
            CALayer *ol = objc_getAssociatedObject(cv, edgeAssocKeys[i]);
            if (!ol) {
                ol = [CALayer layer];
                ol.name = @"BRBorderOverlay";
                [cl addSublayer:ol];
                objc_setAssociatedObject(cv, edgeAssocKeys[i], ol, OBJC_ASSOCIATION_RETAIN);
            }
            ol.frame = edgeRects[i];
            CGImageRef img = gBorderEdgeImageEnabled[i] ? BRImageForRole([NSString stringWithFormat:@"border.edge.%@", edgeKeys[i]]) : NULL;
            ol.contents = img ? (__bridge id)img : nil;
            ol.contentsGravity = kCAGravityResizeAspectFill;
            ol.backgroundColor = gBorderEdgeRGBA[i] ? BRMakeColor(gBorderEdgeRGBA[i]).CGColor : bc.CGColor;
        }
        for (int i = 0; i < 4; i++) {
            CALayer *ol = objc_getAssociatedObject(cv, cornerAssocKeys[i]);
            if (!ol) {
                ol = [CALayer layer];
                ol.name = @"BRBorderOverlay";
                [cl addSublayer:ol];
                objc_setAssociatedObject(cv, cornerAssocKeys[i], ol, OBJC_ASSOCIATION_RETAIN);
            }
            ol.frame = cornerRects[i];
            CGImageRef img = gBorderCornerImageEnabled[i] ? BRImageForRole([NSString stringWithFormat:@"border.corner.%@", cornerKeys[i]]) : NULL;
            ol.contents = img ? (__bridge id)img : nil;
            ol.contentsGravity = kCAGravityResizeAspectFill;
            ol.backgroundColor = gBorderCornerRGBA[i] ? BRMakeColor(gBorderCornerRGBA[i]).CGColor : bc.CGColor;
        }
    }

    if (gBorderShadow) {
        cl.shadowColor   = bc.CGColor;
        cl.shadowOpacity = 0.6;
        cl.shadowRadius  = bs * 2.0;
        cl.shadowOffset  = CGSizeMake(0, -1);
    } else {
        cl.shadowOpacity = 0.0;
    }
}



void BRWindowsApply(NSWindow *w) {
    if (!w) return;
    if (BRCornersActive()) {
        @try {
            [(id)w setValue:@(gCornerRadius) forKey:@"cornerRadius"];
            [w invalidateShadow];
        } @catch (__unused NSException *e) {}
    }
    if (BRToolbarActive()) {
        @try {
            if (w.toolbar && w.toolbarStyle != NSWindowToolbarStyleExpanded) {
                w.toolbarStyle = NSWindowToolbarStyleExpanded; // routed through our override
            }
        } @catch (__unused NSException *e) {}
    }

    // Remove the titlebar for opted-in apps — but only on genuine top-level main
    // windows (not panels/inspectors/sheets), and without losing the toolbar.
    if (BRNoTitlebarActive() && BRWindowIsMain(w)) {
        NSView *tframe = w.contentView.superview;
        // Only standard AppKit windows (NSThemeFrame) can have their titlebar cleanly
        // removed. Custom-frame apps (Chrome/Electron/Thunderbird) draw their own
        // titlebar/tab strip and reserve a fixed leading inset for the window controls
        // that we cannot reclaim — hiding the lights there only leaves an orphan gap —
        // so we leave those windows untouched.
        BOOL standardFrame = tframe && [tframe isKindOfClass:NSClassFromString(@"NSThemeFrame")];
        if (standardFrame) @try {
            w.titlebarAppearsTransparent = YES;
            w.titleVisibility = NSWindowTitleHidden;
            w.styleMask |= NSWindowStyleMaskFullSizeContentView;
            w.movableByWindowBackground = YES;
            // Hide the traffic-light buttons so the result is consistent whether or not
            // the window has a toolbar — otherwise toolbar windows (Finder browser) keep
            // showing the lights + an empty title row while toolbar-less windows look
            // fully clean.
            for (NSWindowButton b = NSWindowCloseButton; b <= NSWindowZoomButton; b++)
                [w standardWindowButton:b].hidden = YES;
            // Keep the toolbar: only collapse the whole titlebar container when there's
            // no toolbar to preserve (Finder's toolbar lives inside that container).
            BOOL hasToolbar = (w.toolbar != nil) && w.toolbar.isVisible;
            for (NSView *sv in tframe.subviews)
                if (strstr(class_getName(object_getClass(sv)), "TitlebarContainer"))
                    sv.hidden = !hasToolbar;
        } @catch (__unused NSException *e) {}
    }

    // Configurable border (owned sublayer) + shadow.
    BRApplyBorder(w);
    // Custom titlebar strip colour (window-manager feature).
    BRTitlebarApplyColor(w);
    // Optional scoped toolbar-item corner squaring.
}

void BRWindowsApplyAll(void) {
    NSApplication *app = NSApp; // never force-create (unsafe in non-GUI procs)
    if (!app) return;
    for (NSWindow *w in app.windows) BRWindowsApply(w);
}

#pragma mark - NSWindow swizzle (grouped — armed only in app processes)


ZKSwizzleInterfaceGroup(BRW_NSWindow, NSWindow, NSResponder, BRUTALIUM_WINDOWS)
@implementation BRW_NSWindow

- (void)setFrame:(NSRect)frameRect display:(BOOL)flag {
    ZKOrig(void, frameRect, flag);
    BRWindowsApply((NSWindow *)self);
}

- (void)setFrame:(NSRect)frameRect display:(BOOL)flag animate:(BOOL)anim {
    ZKOrig(void, frameRect, flag, anim);
    BRWindowsApply((NSWindow *)self);
}

- (void)setFrameOrigin:(NSPoint)point {
    ZKOrig(void, point);
}

- (void)setFrameTopLeftPoint:(NSPoint)point {
    ZKOrig(void, point);
}

- (void)makeKeyAndOrderFront:(id)sender {
    ZKOrig(void, sender);
    BRWindowsApply((NSWindow *)self);
}

- (void)orderFront:(id)sender {
    ZKOrig(void, sender);
    BRWindowsApply((NSWindow *)self);
}

// Private corner plumbing (the apple-sharpener technique). Setting the
// `cornerRadius` KVC alone isn't enough — the system re-applies its rounded
// radius through `_setCornerRadius:`, and the visible clip comes from
// `_cornerMask`, so we handle all three.
- (void)_updateCornerMask {
    if (BRCornersActive()) {
        @try {
            [(id)self setValue:@(gCornerRadius) forKey:@"cornerRadius"];
            [(NSWindow *)self invalidateShadow];
        } @catch (__unused NSException *e) {}
    } else {
        ZKOrig(void);
    }
}

- (void)_setCornerRadius:(CGFloat)radius {
    if (!BRCornersActive()) { ZKOrig(void, radius); return; }
    if (gCornerRadius <= 0.0) { ZKOrig(void, 0); return; } // genuinely square
    CGFloat r = (((NSWindow *)self).styleMask & NSWindowStyleMaskFullScreen) ? 0 : gCornerRadius;
    ZKOrig(void, r);
}

// The piece that squares the visible corner: a 1×1 white mask ⇒ no rounding.
// (A custom radius > 0 keeps the system's rounded mask instead.)
- (id)_cornerMask {
    if (BRCornersActive() && gCornerRadius <= 0.0) {
        NSImage *square = [[NSImage alloc] initWithSize:NSMakeSize(1, 1)];
        [square lockFocus];
        [[NSColor whiteColor] set];
        NSRectFill(NSMakeRect(0, 0, 1, 1));
        [square unlockFocus];
        return square;
    }
    return ZKOrig(id);
}

// Enforce the expanded toolbar unless disabled / this app is excluded.
- (void)setToolbarStyle:(NSWindowToolbarStyle)toolbarStyle {
    if (BRToolbarActive()) ZKOrig(void, NSWindowToolbarStyleExpanded);
    else                   ZKOrig(void, toolbarStyle);
}

@end

#pragma mark - Titlebar decoration (flatter look, tied to the corners toggle)

ZKSwizzleInterfaceGroup(BRW_TitlebarDecorationView, _NSTitlebarDecorationView, NSView, BRUTALIUM_WINDOWS_EXT)
@implementation BRW_TitlebarDecorationView
- (void)viewDidMoveToWindow {
    ZKOrig(void);
    if (BRCornersActive()) ((NSView *)self).hidden = YES;
}
- (void)drawRect:(NSRect)dirtyRect {
    if (BRCornersActive()) return; // suppress decoration drawing
    ZKOrig(void, dirtyRect);
}
@end

// Dumps layer + view ancestry for whatever we just modified. Enable with:
//   brutalium debug tree on   (writes to /tmp/brutalium-tree.log for 30s, no rebuild needed)
static void BRDumpAncestry(CALayer *layer, const char *trigger) {
    static BOOL enabled = NO;
    static CFAbsoluteTime lastCheck = 0, startTime = 0;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - lastCheck > 2.0) {
        lastCheck = now;
        BOOL wasEnabled = enabled;
        id val = (id)CFBridgingRelease(CFPreferencesCopyValue(CFSTR("com.tweak.brutalium.debug.tree"),
            kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
        enabled = [val isKindOfClass:[NSNumber class]] && [val boolValue];
        if (enabled && !wasEnabled) { startTime = now; }   // reset window on re-enable
    }
    if (!enabled) return;
    if (startTime > 0 && now - startTime > 30.0) return;

    NSString *bid = NSBundle.mainBundle.bundleIdentifier ?: @"?";
    NSString *trig = [NSString stringWithUTF8String:trigger];
    NSMutableString *s = [NSMutableString stringWithFormat:@"[%@] %@", bid, trig];

    [s appendString:@" | LAYERS:"];
    int depth = 0;
    for (CALayer *l = layer; l && depth < 8; l = l.superlayer, depth++) {
        id del = l.delegate;
        [s appendFormat:@" > %@(cr=%.1f%@)",
            NSStringFromClass(object_getClass(l)),
            l.cornerRadius,
            (del && [(id)del isKindOfClass:[NSView class]]) ? [NSString stringWithFormat:@" del=%@", NSStringFromClass(object_getClass(del))] : @""];
    }

    NSView *view = nil;
    for (CALayer *l = layer; l; l = l.superlayer) {
        if (l.delegate && [(id)l.delegate isKindOfClass:[NSView class]]) { view = (NSView *)l.delegate; break; }
    }
    if (view) {
        [s appendString:@" | VIEWS:"];
        depth = 0;
        for (NSView *v = view; v && depth < 8; v = v.superview, depth++)
            [s appendFormat:@" > %@", NSStringFromClass(object_getClass(v))];
    }
    [s appendString:@"\n"];

    static FILE *fp = NULL;
    if (!fp) fp = fopen("/tmp/brutalium-tree.log", "a");   // append mode
    if (fp) { fputs(s.UTF8String, fp); fflush(fp); }
}

// Squares every CALayer's corners app-wide (buttons, fields, popovers, menus, everything).
// Off by default, gated by BRSquareElementsActive().

// Skips any layer that's part of the Dock's own glass rendering — corners-elements runs in
// every process including com.apple.dock, and without this it would fight BRDock.m over the
// floor/backdrop/blur layers' radius.
static BOOL BRIsDockRenderLayer(CALayer *layer) {
    if (!BRIsDockProcess()) return NO;
    const char *cn = class_getName(object_getClass(layer));
    return strstr(cn, "Dock") || strstr(cn, "Floor") || strstr(cn, "Backdrop") ||
           strstr(cn, "Portal") || strstr(cn, "SDF") || strstr(cn, "Modern");
}

// Picks the radius a given layer should be squared to: the sidebar-specific radius when this
// layer lives inside sidebar-material chrome AND sidebar corners is explicitly enabled, otherwise
// the general elements radius (unchanged default behaviour).
static CGFloat BRRadiusForLayer(CALayer *layer) {
    if (gSidebarCornersEnabled && BRIsSidebarLayer(layer)) return (CGFloat)gSidebarCornersRadius;
    return BRElementsRadiusEffective();
}
static CGFloat BRRadiusForView(NSView *view) {
    if (gSidebarCornersEnabled && BRIsSidebarView(view)) return (CGFloat)gSidebarCornersRadius;
    return BRElementsRadiusEffective();
}

static BOOL BRIsInsideGlass(CALayer *layer) {
    static Class glassClass = Nil, platterClass = Nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        glassClass = NSClassFromString(@"NSGlassEffectView");
        platterClass = NSClassFromString(@"NSToolbarPlatterView");
    });
    // Only skip the glass view itself and its direct sublayers — NOT the entire ancestor chain
    // (which would exclude everything in apps with a glass toolbar).
    if (glassClass) {
        if (layer.delegate && [(id)layer.delegate isKindOfClass:glassClass]) return YES;
        CALayer *parent = layer.superlayer;
        if (parent && parent.delegate && [(id)parent.delegate isKindOfClass:glassClass]) return YES;
    }
    // Also exclude NSToolbarPlatterView's own layer. Without this, "corners elements" forces the
    // platter's OWN cornerRadius to gElementsRadius while "toolbar slim radius" separately forces
    // the NSGlassEffectView INSIDE it to gSlimRadius — two different layers, two different radii,
    // visibly mismatched (outer capsule shape vs. inner glass fill) whenever the two values differ.
    // The platter's shape should be governed by toolbar slim alone when that feature is active.
    if (platterClass && layer.delegate && [(id)layer.delegate isKindOfClass:platterClass]) return YES;
    return NO;
}

ZKSwizzleInterfaceGroup(BRW_CALayer, CALayer, CALayer, BRUTALIUM_WINDOWS)
@implementation BRW_CALayer
- (void)layoutSublayers {
    { static int hb2 = 0; if (hb2 < 3) { hb2++; NSLog(@"[Brutalium/HB] layoutSublayers alive"); } }
    ZKOrig(void);
    if (BRSquareElementsActive()) {
        @try {
            if ([((CALayer *)self).name isEqualToString:@"BRBorderOverlay"]) goto skip_controls;
            if ([((CALayer *)self).name isEqualToString:@"BRDockBackground"]) goto skip_controls;
            if (BRIsDockRenderLayer((CALayer *)self)) goto skip_controls;
            if (!BRIsInsideGlass((CALayer *)self)) {
                // Exclude border windows + popup menus (menus have their own option).
                CALayer *layer = (CALayer *)self;
                if (layer.delegate && [(id)layer.delegate isKindOfClass:[NSView class]]) {
                    NSWindow *win = ((NSView *)layer.delegate).window;
                    if ([win isKindOfClass:[BRBorderWindow class]]) goto skip_controls;
                    if (BRIsPopupMenuWindow(win)) goto skip_controls;
                }
                CGFloat r = BRRadiusForLayer((CALayer *)self);
                ((CALayer *)self).cornerRadius = r;
                CALayer *m = ((CALayer *)self).mask;
                if (m) m.cornerRadius = r;
                BRDumpAncestry((CALayer *)self, "layout-cr");
            }
        } @catch (__unused NSException *e) {}
        skip_controls:;
    }
}
- (void)setCornerRadius:(CGFloat)radius {
    if (BRSquareElementsActive()) {
        @try {
            if ([((CALayer *)self).name isEqualToString:@"BRBorderOverlay"]) goto skip_setCR;
            if ([((CALayer *)self).name isEqualToString:@"BRDockBackground"]) goto skip_setCR;
            if (BRIsDockRenderLayer((CALayer *)self)) goto skip_setCR;
            if (!BRIsInsideGlass((CALayer *)self)) {
                // Exclude border windows + popup menus (menus have their own option).
                CALayer *layer = (CALayer *)self;
                if (layer.delegate && [(id)layer.delegate isKindOfClass:[NSView class]]) {
                    NSWindow *win = ((NSView *)layer.delegate).window;
                    if ([win isKindOfClass:[BRBorderWindow class]]) goto skip_setCR;
                    if (BRIsPopupMenuWindow(win)) goto skip_setCR;
                }
                if (radius > 0) BRDumpAncestry((CALayer *)self, "setCR");
                ZKOrig(void, BRRadiusForLayer((CALayer *)self)); return;
            }
        } @catch (__unused NSException *e) {}
        skip_setCR:;
    }
    if (BRSquareMenusActive()) {
        @try {
            CALayer *layer = (CALayer *)self;
            NSView *dv = (layer.delegate && [(id)layer.delegate isKindOfClass:[NSView class]])
                         ? (NSView *)layer.delegate : nil;
            if (dv && BRIsPopupMenuWindow(dv.window)) { ZKOrig(void, BRMenuRadiusEffective()); return; }
        } @catch (__unused NSException *e) {}
    }
    ZKOrig(void, radius);
}
@end


#pragma mark - Square popup / context menus

// Popup/context menus are NSPopupMenuWindow instances. When 'corners menus' is on, we square their
// frame layer, strip the CGS corner mask, make them opaque + shadowless, and recursively square every
// subview (cornerConfiguration + materialCornerRadius + cornerRadius + layer.cornerRadius). This is
// the Currumbin technique adapted with a configurable radius and restoration support.

@interface NSCGSWindow : NSObject
+ (instancetype)windowWithWindowID:(unsigned int)windowID;
- (unsigned int)windowID;
- (id)cornerMask;
- (void)setCornerMask:(id)cornerMask;
@end

static BOOL BRIsPopupMenuWindow(NSWindow *w) {
    static Class cls = Nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cls = NSClassFromString(@"NSPopupMenuWindow"); });
    return cls && [w isKindOfClass:cls];
}

static void BRSquareViewTree(NSView *v, CGFloat r, int depth) {
    if (!v || depth > 12) return;
    @try {
        // Layer-level squaring — safe across macOS versions. Also recurse into sublayers to catch
        // selection highlights and other system-drawn rounded rects that don't have their own NSView.
        if (v.layer) { v.layer.cornerRadius = r; v.layer.masksToBounds = YES;
            for (CALayer *sl in v.layer.sublayers) { sl.cornerRadius = r; sl.masksToBounds = YES; }
        }
        SEL selCR = NSSelectorFromString(@"setCornerRadius:");
        if ([v respondsToSelector:selCR])
            ((void (*)(id, SEL, CGFloat))objc_msgSend)(v, selCR, r);
    } @catch (__unused NSException *e) {}
    for (NSView *s in v.subviews) BRSquareViewTree(s, r, depth + 1);
}

static void BRApplyMenuAppearance(NSWindow *w) {
    if (!BRIsPopupMenuWindow(w)) return;
    if (!BRSquareMenusActive()) return;
    NSView *frame = w.contentView.superview;
    CALayer *fl = frame.layer;
    CGFloat r = BRMenuRadiusEffective();
    @try {
        // Strip the native CGS corner mask (rounded window server corners).
        NSCGSWindow *cgs = [NSClassFromString(@"NSCGSWindow")
                            windowWithWindowID:(unsigned int)w.windowNumber];
        if (cgs) cgs.cornerMask = nil;

        w.hasShadow = gMenuShadow;        // optional: keep or strip the shadow
        w.opaque = YES;
        w.backgroundColor = NSColor.windowBackgroundColor;
        if (fl) {
            fl.backgroundColor = NSColor.windowBackgroundColor.CGColor;
            fl.cornerRadius = r;
            fl.masksToBounds = YES;
            fl.borderWidth = 0.0;
            if (!gMenuShadow) fl.shadowOpacity = 0.0;
        }
        BRSquareViewTree(frame, r, 0);
    } @catch (__unused NSException *e) {}
}

// Hook NSPopupMenuWindow's orderFront/orderFrontRegardless for initial squaring.
ZKSwizzleInterfaceGroup(BRW_NSPopupMenuWindow, NSPopupMenuWindow, NSPanel, BRUTALIUM_WINDOWS_EXT)
@implementation BRW_NSPopupMenuWindow
- (void)orderFront:(id)sender {
    ZKOrig(void, sender);
    BRApplyMenuAppearance((NSWindow *)self);
}
- (void)orderFrontRegardless {
    ZKOrig(void);
    BRApplyMenuAppearance((NSWindow *)self);
}
// Continuously square during menu interaction: the system redraws the selection highlight (with
// rounded corners) every time you hover a new item. Intercept the frame update to re-square.
- (void)updateWindowFrameTo:(NSRect)newFrame offset:(NSPoint)offset animated:(BOOL)animated completion:(id)completion {
    ZKOrig(void, newFrame, offset, animated, completion);
    if (BRSquareMenusActive()) {
        NSView *frame = ((NSWindow *)self).contentView.superview;
        if (frame) BRSquareViewTree(frame, BRMenuRadiusEffective(), 0);
    }
}
@end

// Also intercept NSCGSWindow setCornerMask: to block the system re-rounding popup corners.
ZKSwizzleInterfaceGroup(BRW_NSCGSWindow, NSCGSWindow, NSObject, BRUTALIUM_WINDOWS_EXT)
@implementation BRW_NSCGSWindow
- (void)setCornerMask:(id)mask {
    if (BRSquareMenusActive()) {
        NSWindow *popup = nil;
        @try {
            unsigned int wid = (unsigned int)[(NSCGSWindow *)self windowID];
            for (NSWindow *w in NSApp.windows) if ((unsigned int)w.windowNumber == wid && BRIsPopupMenuWindow(w)) { popup = w; break; }
        } @catch (__unused NSException *e) {}
        if (popup) { ZKOrig(void, (id)nil); return; }
    }
    ZKOrig(void, mask);
}
@end

#pragma mark - Square glass capsules (NSGlassEffectView)

// When 'corners glass' is on, force NSGlassEffectView.cornerRadius to the configured radius —
// but ONLY for glass views inside an NSToolbarPlatterView (toolbar capsules). Glass views used
// elsewhere (Chrome profile picker, panels, etc.) are left alone.


// Square the platter itself (the container around the glass). Its layer shadow produces the
// hover/press glow that stays rounded if we only square the glass inside it.

#pragma mark - Square controls (text inputs, toggles, buttons, menu selection)

// Square the rounded corners on standard AppKit controls: text fields, search fields, segmented
// controls, switches/toggles, buttons, and the menu-item selection highlight. Uses the glass radius
// so everything is consistent with the capsule squaring.
ZKSwizzleInterfaceGroup(BRW_NSTextField, NSTextField, NSControl, BRUTALIUM_WINDOWS)
@implementation BRW_NSTextField
- (void)layout {
    ZKOrig(void);
    if (BRSquareElementsActive()) {
        @try {
            ((NSView *)self).wantsLayer = YES;
            ((NSView *)self).layer.cornerRadius = BRRadiusForView((NSView *)self);
            ((NSView *)self).layer.masksToBounds = YES;
        } @catch (__unused NSException *e) {}
    }
}
@end

ZKSwizzleInterfaceGroup(BRW_NSSegmentedControl, NSSegmentedControl, NSControl, BRUTALIUM_WINDOWS)
@implementation BRW_NSSegmentedControl
- (void)layout {
    ZKOrig(void);
    if (BRSquareElementsActive()) {
        @try {
            ((NSView *)self).wantsLayer = YES;
            ((NSView *)self).layer.cornerRadius = BRRadiusForView((NSView *)self);
            ((NSView *)self).layer.masksToBounds = YES;
        } @catch (__unused NSException *e) {}
    }
}
@end

ZKSwizzleInterfaceGroup(BRW_NSButton, NSButton, NSControl, BRUTALIUM_WINDOWS)
@implementation BRW_NSButton
- (void)layout {
    ZKOrig(void);
    if (BRSquareElementsActive()) {
        @try {
            ((NSView *)self).wantsLayer = YES;
            ((NSView *)self).layer.cornerRadius = BRRadiusForView((NSView *)self);
            // Also square the layer shadow (hover/press glow) so it matches.
            if (((NSView *)self).layer.shadowPath) {
                CGRect b = ((NSView *)self).layer.bounds;
                ((NSView *)self).layer.shadowPath = CGPathCreateWithRect(b, NULL);
            }
        } @catch (__unused NSException *e) {}
    }
}
@end

// Aggressively strip ALL rounding from a view: cornerRadius, mask, sublayer radii, cornerConfiguration.
static void BRStripRounding(NSView *v) {
    CGFloat r = BRRadiusForView(v);
    v.wantsLayer = YES;
    CALayer *l = v.layer;
    if (!l) return;
    l.cornerRadius = r;
    if (l.mask) { l.mask.cornerRadius = r; if ([l.mask isKindOfClass:NSClassFromString(@"CAShapeLayer")]) l.mask = nil; }
    for (CALayer *sl in l.sublayers) { sl.cornerRadius = r; if (sl.mask) sl.mask.cornerRadius = r; }
    // Also try the private cornerConfiguration (safe: respondsToSelector gated).
    SEL selCC = NSSelectorFromString(@"setCornerConfiguration:");
    if ([v respondsToSelector:selCC])
        ((void (*)(id, SEL, id))objc_msgSend)(v, selCC, nil);
    BRDumpAncestry(l, "strip");
}

ZKSwizzleInterfaceGroup(BRW_NSSwitch, NSSwitch, NSControl, BRUTALIUM_WINDOWS)
@implementation BRW_NSSwitch
- (void)layout {
    ZKOrig(void);
    if (BRSquareElementsActive()) { @try { BRStripRounding((NSView *)self); } @catch (__unused NSException *e) {} }
}
- (void)updateLayer {
    ZKOrig(void);
    if (BRSquareElementsActive()) { @try { BRStripRounding((NSView *)self); } @catch (__unused NSException *e) {} }
}
@end

ZKSwizzleInterfaceGroup(BRW_NSScrollView, NSScrollView, NSView, BRUTALIUM_WINDOWS)
@implementation BRW_NSScrollView
- (void)layout {
    ZKOrig(void);
    if (BRSquareElementsActive()) {
        @try {
            BRStripRounding((NSView *)self);
            NSClipView *clip = ((NSScrollView *)self).contentView;
            if (clip) BRStripRounding((NSView *)clip);
            // Strip the glass container above us (NSContainerConcentricGlassEffectView) that clips
            // the sidebar to a rounded shape. Walk up max 4 ancestors.
            int d = 0;
            for (NSView *sv = ((NSView *)self).superview; sv && d < 4; sv = sv.superview, d++) {
                NSString *cn = NSStringFromClass(object_getClass(sv));
                if ([cn containsString:@"GlassEffect"] || [cn containsString:@"Concentric"]) {
                    BRStripRounding(sv);
                }
            }
        } @catch (__unused NSException *e) {}
    }
}
- (void)updateLayer {
    ZKOrig(void);
    if (BRSquareElementsActive()) {
        @try {
            BRStripRounding((NSView *)self);
            NSClipView *clip = ((NSScrollView *)self).contentView;
            if (clip) BRStripRounding((NSView *)clip);
            int d = 0;
            for (NSView *sv = ((NSView *)self).superview; sv && d < 4; sv = sv.superview, d++) {
                NSString *cn = NSStringFromClass(object_getClass(sv));
                if ([cn containsString:@"GlassEffect"] || [cn containsString:@"Concentric"]) {
                    BRStripRounding(sv);
                }
            }
        } @catch (__unused NSException *e) {}
    }
}
@end

ZKSwizzleInterfaceGroup(BRW_NSTableRowView, NSTableRowView, NSView, BRUTALIUM_WINDOWS)
@implementation BRW_NSTableRowView
- (void)layout {
    ZKOrig(void);
    if (BRSquareElementsActive()) { @try { BRStripRounding((NSView *)self); } @catch (__unused NSException *e) {} }
}
- (void)updateLayer {
    ZKOrig(void);
    if (BRSquareElementsActive()) { @try { BRStripRounding((NSView *)self); } @catch (__unused NSException *e) {} }
}
@end

// NOTE: NSVisualEffectView rounding is handled by BRTint's updateLayer takeover +
// BRStripRounding in the view-level hooks above. No separate swizzle needed here.

// Menu selection highlight colour: override +[NSColor selectedContentBackgroundColor] when a custom
// colour is set, so the selection row in popup menus follows the user's chosen colour.
static NSColor *(*orig_selectedContentBg)(id, SEL) = NULL;
static NSColor *br_selectedContentBg(id self, SEL _cmd) {
    if (gMenuSelectRGBA != 0) return BRMakeColor(gMenuSelectRGBA);
    return orig_selectedContentBg ? orig_selectedContentBg(self, _cmd) : nil;
}

#pragma mark - Slim toolbar (ported from the standalone SlimBar experiment)

// Ported from the standalone SlimBar tweak — same technique (raw method_setImplementation on
// setFrameSize:/layout, synchronous clamping), not the deferred dispatch_async approach tried
// earlier in Brutalium, which never stuck (Auto Layout overrides plain frame changes on views
// with their own Required constraints; the mutation has to happen synchronously to win). Every
// hook checks BRSlimToolbarActive() so this stays toggleable, unlike the original.

// Attempt 1 (SlimBar): force the small toolbar size mode. Confirmed to take effect (sizeMode reads
// back as small) but Solarium ignores it for capsule/toolbar height — kept only for completeness.
static NSToolbarSizeMode (*orig_sizeMode)(id, SEL) = NULL;
static NSToolbarSizeMode br_slim_sizeMode(id self, SEL _cmd) {
    if (BRSlimToolbarActive()) return NSToolbarSizeModeSmall;
    return orig_sizeMode ? orig_sizeMode(self, _cmd) : NSToolbarSizeModeRegular;
}

// Clamp the glass capsule (NSToolbarPlatterView) height — the glass fills the platter, so it shrinks
// along with it.
static void (*orig_platterSetFrameSize)(id, SEL, NSSize) = NULL;
static void br_slim_platterSetFrameSize(id self, SEL _cmd, NSSize size) {
    if (BRSlimToolbarActive() && size.height > BRSlimPlatterHeight()) size.height = BRSlimPlatterHeight();
    if (orig_platterSetFrameSize) orig_platterSetFrameSize(self, _cmd, size);
}

// Clamp the toolbar strip itself so there's no dead space around the shrunken platters.
static void (*orig_toolbarViewSetFrameSize)(id, SEL, NSSize) = NULL;
static void br_slim_toolbarViewSetFrameSize(id self, SEL _cmd, NSSize size) {
    if (BRSlimToolbarActive() && size.height > (CGFloat)gSlimToolbarHeight) size.height = (CGFloat)gSlimToolbarHeight;
    if (orig_toolbarViewSetFrameSize) orig_toolbarViewSetFrameSize(self, _cmd, size);
}

// Clamp the full-width glass underlay (NSGlassContainerView) to match the toolbar strip.
static void (*orig_glassContainerSetFrameSize)(id, SEL, NSSize) = NULL;
static void br_slim_glassContainerSetFrameSize(id self, SEL _cmd, NSSize size) {
    if (BRSlimToolbarActive() && size.height > (CGFloat)gSlimToolbarHeight) size.height = (CGFloat)gSlimToolbarHeight;
    if (orig_glassContainerSetFrameSize) orig_glassContainerSetFrameSize(self, _cmd, size);
}

// Content re-centering here was removed after a crash: reading -intrinsicContentSize (or setting
// any child's .frame) from inside NSToolbarItemViewer's own layout pass triggers a constraint
// update that AppKit refuses mid-layout, throwing on macOS 27.0. No known safe way to reposition
// content from this callback, so content may sit squished/offset in a shrunk capsule.
static void (*orig_viewerLayout)(id, SEL) = NULL;
static void br_slim_viewerLayout(id self, SEL _cmd) {
    if (orig_viewerLayout) orig_viewerLayout(self, _cmd);
    // no-op — see comment above
}

// Traffic-light re-centering: the close/minimize/zoom buttons are positioned relative to the native
// (larger) toolbar height. When shrunk, they sit too high. After the toolbar view lays out, find the
// window's standard buttons and centre them within the new toolbar height — but ONLY when the
// titlebar is actually merged into the toolbar (unified mode); when they're separate, the traffic
// lights live in the titlebar and must not be touched.
static void (*orig_toolbarViewLayout)(id, SEL) = NULL;
static void br_slim_toolbarViewLayout(id self, SEL _cmd) {
    if (orig_toolbarViewLayout) orig_toolbarViewLayout(self, _cmd);
    if (!BRSlimToolbarActive()) return;
    NSView *tv = (NSView *)self;
    NSWindow *w = tv.window;
    if (!w) return;

    NSButton *closeBtn = [w standardWindowButton:NSWindowCloseButton];
    if (!closeBtn) return;
    NSRect tvInWindow = [tv convertRect:tv.bounds toView:nil];
    NSRect closeInWindow = [closeBtn convertRect:closeBtn.bounds toView:nil];
    if (NSMaxY(closeInWindow) < NSMinY(tvInWindow) || NSMinY(closeInWindow) > NSMaxY(tvInWindow))
        return;   // traffic lights are outside the toolbar strip — separate titlebar, leave alone

    NSWindowButton btns[] = { NSWindowCloseButton, NSWindowMiniaturizeButton, NSWindowZoomButton };
    for (int i = 0; i < 3; i++) {
        NSButton *b = [w standardWindowButton:btns[i]];
        if (!b) continue;
        NSView *sup = b.superview;
        if (!sup) continue;
        CGFloat btnH = b.frame.size.height;
        CGFloat targetMidY = tvInWindow.origin.y + floor(tvInWindow.size.height / 2.0);
        NSPoint midInSup = [sup convertPoint:NSMakePoint(0, targetMidY) fromView:nil];
        CGFloat newY = floor(midInSup.y - btnH / 2.0);
        NSRect bf = b.frame;
        if (fabs(bf.origin.y - newY) > 0.5) { bf.origin.y = newY; b.frame = bf; }
    }
}

// Scoped to glass views inside a toolbar ancestor — NSGlassEffectView is used everywhere in the
// Liquid Glass UI (sidebar, popovers, menus), so an unscoped override here forces gSlimRadius onto
// every glass surface in the app the moment toolbar slim turns on, not just the toolbar capsules
// (confirmed by testing).
static BOOL BRSlimIsToolbarGlass(NSView *v) {
    NSView *cur = v;
    int depth = 0;
    while (cur && depth < 8) {
        const char *cn = class_getName(object_getClass(cur));
        if (strstr(cn, "NSToolbarPlatterView") || strstr(cn, "NSToolbarItemViewer") ||
            strstr(cn, "NSToolbarView") || strstr(cn, "NSGlassContainerView"))
            return YES;
        cur = cur.superview;
        depth++;
    }
    return NO;
}
static CGFloat (*orig_glassRadiusGet)(id, SEL) = NULL;
static CGFloat br_slim_glassRadiusGet(id self, SEL _cmd) {
    if (BRSlimToolbarActive() && [(id)self isKindOfClass:[NSView class]] && BRSlimIsToolbarGlass((NSView *)self))
        return (CGFloat)gSlimRadius;
    return orig_glassRadiusGet ? orig_glassRadiusGet(self, _cmd) : 0.0;
}
static void (*orig_glassRadiusSet)(id, SEL, CGFloat) = NULL;
static void br_slim_glassRadiusSet(id self, SEL _cmd, CGFloat r) {
    if (BRSlimToolbarActive() && [(id)self isKindOfClass:[NSView class]] && BRSlimIsToolbarGlass((NSView *)self))
        r = (CGFloat)gSlimRadius;
    if (orig_glassRadiusSet) orig_glassRadiusSet(self, _cmd, r);
}

static void BRSlimSwizzleSetFrameSize(const char *clsName, void (**origSlot)(id, SEL, NSSize), IMP newImp) {
    Class c = objc_getClass(clsName);
    if (!c) return;
    SEL sel = @selector(setFrameSize:);
    Method m = class_getInstanceMethod(c, sel);
    if (!m) return;
    const char *types = method_getTypeEncoding(m);
    IMP inherited = method_getImplementation(m);
    if (class_addMethod(c, sel, newImp, types)) *origSlot = (void (*)(id, SEL, NSSize))inherited;
    else { Method own = class_getInstanceMethod(c, sel);
           *origSlot = (void (*)(id, SEL, NSSize))method_getImplementation(own);
           method_setImplementation(own, newImp); }
}

static void BRSlimSwizzleLayout(const char *clsName, void (**origSlot)(id, SEL), IMP newImp) {
    Class c = objc_getClass(clsName);
    if (!c) return;
    SEL sel = @selector(layout);
    Method m = class_getInstanceMethod(c, sel);
    if (!m) return;
    const char *types = method_getTypeEncoding(m);
    IMP inherited = method_getImplementation(m);
    if (class_addMethod(c, sel, newImp, types)) *origSlot = (void (*)(id, SEL))inherited;
    else { Method own = class_getInstanceMethod(c, sel);
           *origSlot = (void (*)(id, SEL))method_getImplementation(own);
           method_setImplementation(own, newImp); }
}

static void BRSlimToolbarArm(void) {
    Method m = class_getInstanceMethod([NSToolbar class], @selector(sizeMode));
    if (m) {
        orig_sizeMode = (NSToolbarSizeMode (*)(id, SEL))method_getImplementation(m);
        method_setImplementation(m, (IMP)br_slim_sizeMode);
    }
    BRSlimSwizzleSetFrameSize("NSToolbarPlatterView", &orig_platterSetFrameSize, (IMP)br_slim_platterSetFrameSize);
    BRSlimSwizzleSetFrameSize("NSToolbarView", &orig_toolbarViewSetFrameSize, (IMP)br_slim_toolbarViewSetFrameSize);
    BRSlimSwizzleSetFrameSize("NSGlassContainerView", &orig_glassContainerSetFrameSize, (IMP)br_slim_glassContainerSetFrameSize);
    BRSlimSwizzleLayout("NSToolbarItemViewer", &orig_viewerLayout, (IMP)br_slim_viewerLayout);
    BRSlimSwizzleLayout("NSToolbarView", &orig_toolbarViewLayout, (IMP)br_slim_toolbarViewLayout);

    Class g = objc_getClass("NSGlassEffectView");
    if (g) {
        Method mg = class_getInstanceMethod(g, @selector(cornerRadius));
        if (mg) { orig_glassRadiusGet = (CGFloat (*)(id, SEL))method_getImplementation(mg);
                  method_setImplementation(mg, (IMP)br_slim_glassRadiusGet); }
        Method ms = class_getInstanceMethod(g, @selector(setCornerRadius:));
        if (ms) { orig_glassRadiusSet = (void (*)(id, SEL, CGFloat))method_getImplementation(ms);
                  method_setImplementation(ms, (IMP)br_slim_glassRadiusSet); }
    }
}

#pragma mark - Arm

void BRWindowsArm(void) {
    ZKSwizzleGroup(BRUTALIUM_WINDOWS);
    ZKSwizzleGroup(BRUTALIUM_WINDOWS_EXT);  // private/conditional classes — can fail independently
    BRSlimToolbarArm();   // slim toolbar (raw method replacement, matches proven SlimBar mechanism)
    // Menu selection highlight colour override.
    Method msc = class_getClassMethod([NSColor class], @selector(selectedContentBackgroundColor));
    if (msc) {
        orig_selectedContentBg = (NSColor *(*)(id, SEL))method_getImplementation(msc);
        method_setImplementation(msc, (IMP)br_selectedContentBg);
    }
    // Re-apply borders on app activation changes so active/inactive colours update.
    for (NSNotificationName nn in @[ NSApplicationDidBecomeActiveNotification,
                                     NSApplicationDidResignActiveNotification ]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:nn object:nil queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *n) { BRWindowsApplyAll(); }];
    }
}
