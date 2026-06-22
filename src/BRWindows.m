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

// Border drawn directly on the window frame's own layer. An earlier version used a
// separate full-window sublayer, but a covering sublayer intercepts clicks in some
// windows (Catalyst apps, sheets), so we use the frame's own layer border instead —
// it never blocks events, follows the squared/rounded shape, and we re-apply the
// active/inactive colour on every focus/activation change so it stays correct.
static void BRApplyBorder(NSWindow *w) {
    if (!(w.styleMask & NSWindowStyleMaskTitled)) return;
    NSView *frame = w.contentView.superview;
    if (!frame) return;
    @try {
        if (!BRBorderActive()) {
            if (frame.layer && frame.layer.borderWidth > 0.0) frame.layer.borderWidth = 0.0;
            return;
        }
        frame.wantsLayer = YES;
        BOOL activeWin = NSApp.active && (w.isKeyWindow || w.isMainWindow);
        frame.layer.borderWidth  = gBorderSize;
        frame.layer.borderColor  = (activeWin ? gBorderColorObj : gBorderInactiveObj).CGColor;
        frame.layer.cornerRadius = (BRCornersActive() && gCornerRadius <= 0.0) ? 0.0 : gCornerRadius;
        w.hasShadow = gBorderShadow;
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
        @try {
            w.titlebarAppearsTransparent = YES;
            w.titleVisibility = NSWindowTitleHidden;
            w.styleMask |= NSWindowStyleMaskFullSizeContentView;
            w.movableByWindowBackground = YES;
            // Hide the traffic-light buttons so the result is consistent whether or not
            // the window has a toolbar — otherwise toolbar windows (Finder browser) keep
            // showing the lights + an empty title row while toolbar-less windows look
            // fully clean. (Safe here: gated to genuine main windows with standard frames.)
            for (NSWindowButton b = NSWindowCloseButton; b <= NSWindowZoomButton; b++)
                [w standardWindowButton:b].hidden = YES;
            // Keep the toolbar: only collapse the whole titlebar container when there's
            // no toolbar to preserve (Finder's toolbar lives inside that container).
            BOOL hasToolbar = (w.toolbar != nil) && w.toolbar.isVisible;
            NSView *frame = w.contentView.superview;
            for (NSView *sv in frame.subviews)
                if (strstr(class_getName(object_getClass(sv)), "TitlebarContainer"))
                    sv.hidden = !hasToolbar;
        } @catch (__unused NSException *e) {}
    }

    // Configurable border (owned sublayer) + shadow.
    BRApplyBorder(w);
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

#pragma mark - Arm

void BRWindowsArm(void) {
    ZKSwizzleGroup(BRUTALIUM_WINDOWS);
}
