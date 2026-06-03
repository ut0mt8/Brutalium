//
//  BRWindows.m — window corners + expanded toolbar (formerly UIFixer).
//
//  Squares window corners (apple-sharpener private-API technique) and forces
//  the expanded toolbar, with a per-app toolbar exclusion list. Reads the shared
//  config cache; the core arms the swizzle group and drives discovery.
//

#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "ZKSwizzle.h"
#import "BRConfig.h"

#pragma mark - Appliers

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
