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
#include <string.h>
#import "ZKSwizzle.h"
#import "BRConfig.h"

#pragma mark - Appliers

// Square only the toolbar items' corners (a scoped alternative to the global
// `corners layers` swizzle): find the toolbar container by class name and zero the
// cornerRadius on every layer in its subtree. Re-applied on each window event.
static void BRSquareLayerCorners(CALayer *l) {
    if (!l) return;
    if (l.cornerRadius > 0.0) l.cornerRadius = 0.0;
    if (l.mask && l.mask.cornerRadius > 0.0) l.mask.cornerRadius = 0.0;
    for (CALayer *s in l.sublayers) BRSquareLayerCorners(s);
}
static void BRSquareViewSubtree(NSView *v) {
    for (NSView *sv in v.subviews) {
        if (sv.layer) BRSquareLayerCorners(sv.layer);
        BRSquareViewSubtree(sv);
    }
}
static void BRSquareToolbars(NSView *v) {
    if (strstr(class_getName(object_getClass(v)), "Toolbar")) { BRSquareViewSubtree(v); return; }
    for (NSView *sv in v.subviews) BRSquareToolbars(sv);
}
static void BRApplyToolbarCorners(NSWindow *w) {
    if (!BRSquareToolbarActive()) return;
    NSView *frame = w.contentView.superview;
    if (!frame) return;
    @try { BRSquareToolbars(frame); } @catch (__unused NSException *e) {}
}

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
// window's layout pass — which macOS 27 rejects by throwing in _postWindowNeedsUpdateConstraints,
// aborting the app (observed crashing System Settings). Detect that and skip: the border still
// draws on the frame layer, it just doesn't reserve space (draws over the content edge instead).
static BOOL BRContentIsConstraintDriven(NSView *content) {
    if (!content) return YES;                                   // unknown → be safe
    if (!content.translatesAutoresizingMaskIntoConstraints) return YES;
    const char *cn = class_getName(object_getClass(content));
    if (strstr(cn, "HostingView") || strstr(cn, "HostingController")) return YES;
    for (NSView *sv in content.subviews) {
        const char *sn = class_getName(object_getClass(sv));
        if (strstr(sn, "HostingView") || strstr(sn, "ConstraintBasedLayoutHostingView")) return YES;
    }
    return NO;
}

// Reserve space for the border instead of drawing over content. A CALayer border is drawn
// INWARD from the layer edge, so a thick border on the frame overlaps the content view. To keep
// content visible we inset the titlebar container + content view inward by the border width; the
// frame layer's border then sits in the exposed margin. Re-applied on every window event so it
// tracks live resizes; restores the natural layout when the border is off. Standard NSThemeFrame
// windows only; Auto-Layout / SwiftUI-hosted windows are skipped (see above).
static void BRLayoutForBorder(NSWindow *w) {
    NSView *frame = w.contentView.superview;
    if (!frame || ![frame isKindOfClass:NSClassFromString(@"NSThemeFrame")]) return;
    NSView *content = w.contentView;
    if (!content) return;
    if (BRContentIsConstraintDriven(content)) return;           // never frame-inset SwiftUI content

    NSView *cont = nil;
    for (NSView *sv in frame.subviews)
        if (strstr(class_getName(object_getClass(sv)), "TitlebarContainer")) { cont = sv; break; }

    NSRect fb = frame.bounds;
    CGFloat W = NSWidth(fb), H = NSHeight(fb);
    CGFloat b = BRBorderActive() ? gBorderSize : 0.0;
    if (b < 0.0) b = 0.0;
    if (b * 2.0 >= W - 40.0 || b * 2.0 >= H - 40.0) b = 0.0;
    CGFloat top = cont ? NSHeight(cont.frame) : 0.0;
    BOOL fullSize = (w.styleMask & NSWindowStyleMaskFullSizeContentView) != 0;

    @try {
        if (cont) {
            NSRect ct = NSMakeRect(b, H - b - top, W - 2.0*b, top);
            if (!NSEqualRects(cont.frame, ct)) cont.frame = ct;
        }
        NSRect cv = fullSize ? NSMakeRect(b, b, W - 2.0*b, H - 2.0*b)
                             : NSMakeRect(b, b, W - 2.0*b, (H - b - top) - b);
        if (cv.size.width > 1.0 && cv.size.height > 1.0 && !NSEqualRects(content.frame, cv))
            content.frame = cv;
    } @catch (__unused NSException *e) {}
}

// Border drawn on the window frame's own layer, re-coloured on focus changes.
static void BRApplyBorder(NSWindow *w) {
    if (!(w.styleMask & NSWindowStyleMaskTitled)) return;
    NSView *frame = w.contentView.superview;
    if (!frame) return;
    @try {
        if (!BRBorderActive()) {
            if (frame.layer && frame.layer.borderWidth > 0.0) frame.layer.borderWidth = 0.0;
            BRLayoutForBorder(w);      // restore natural layout
            return;
        }
        frame.wantsLayer = YES;
        BOOL activeWin = NSApp.active && (w.isKeyWindow || w.isMainWindow);
        frame.layer.borderWidth  = gBorderSize;
        frame.layer.borderColor  = (activeWin ? gBorderColorObj : gBorderInactiveObj).CGColor;
        frame.layer.cornerRadius = (BRCornersActive() && gCornerRadius <= 0.0) ? 0.0 : gCornerRadius;
        w.hasShadow = gBorderShadow;
        BRLayoutForBorder(w);          // inset content so the border doesn't cover it
    } @catch (__unused NSException *e) {}
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
    BRApplyToolbarCorners(w);
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

ZKSwizzleInterfaceGroup(BRW_TitlebarDecorationView, _NSTitlebarDecorationView, NSView, BRUTALIUM_WINDOWS)
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

// Square (or round) EVERY CALayer's corners app-wide (aggressive — buttons, fields, popovers,
// menus, etc.). Off by default; gated by BRSquareLayersActive(). Forces each layer to
// `corners.layers.radius` (default 0 → an imperceptible 1e-7 that reads as square while defeating
// apps that re-round), overriding any radius an app tries to set. When off, both methods behave
// exactly like the originals.
ZKSwizzleInterfaceGroup(BRW_CALayer, CALayer, CALayer, BRUTALIUM_WINDOWS)
@implementation BRW_CALayer
- (void)layoutSublayers {
    ZKOrig(void);
    if (BRSquareLayersActive()) {
        CGFloat lr = BRLayerRadiusEffective();
        ((CALayer *)self).cornerRadius = lr;
        CALayer *m = ((CALayer *)self).mask;
        if (m) m.cornerRadius = lr;
    }
}
- (void)setCornerRadius:(CGFloat)radius {
    ZKOrig(void, BRSquareLayersActive() ? BRLayerRadiusEffective() : radius);
}
@end

#pragma mark - Arm

void BRWindowsArm(void) {
    ZKSwizzleGroup(BRUTALIUM_WINDOWS);
}
