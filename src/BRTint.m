//
//  BRTint.m — system colour tint (formerly BrutalTint).
//
//  Recolours the whole UI to a configurable background colour (like Light/Dark
//  but any colour), with a separate chrome colour for vibrancy areas and an
//  optional precise text colour that's agnostic of the base colour. Overrides
//  the semantic background AND foreground colours AppKit vends, takes over
//  NSVisualEffectView's layer, forces a coherent base appearance (unless mode
//  none), and drops an opaque backdrop behind each titled window's content so
//  transparent material reads as the tint. Config + gating live in the core;
//  this module just installs the swizzles and paints. No NSWindow swizzle.
//

#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <string.h>
#import "BRState.h"
#import "BRConfig.h"

#pragma mark - Semantic colour overrides (class-method swizzle on NSColor)

typedef NSColor *(*BTColorIMP)(id, SEL);

// SEL → original IMP registry, so shared override imps can call through per selector.
#define BT_MAX_SWIZZLE 24
static struct { SEL sel; BTColorIMP orig; } gBTSw[BT_MAX_SWIZZLE];
static int gBTSwN = 0;

static BTColorIMP BTOrig(SEL sel) {
    for (int i = 0; i < gBTSwN; i++) if (gBTSw[i].sel == sel) return gBTSw[i].orig;
    return NULL;
}
static NSColor *BTCallOrig(id self, SEL _cmd) {
    BTColorIMP o = BTOrig(_cmd);
    return o ? o(self, _cmd) : nil;
}
static void BTSwizzleClassMethod(SEL sel, IMP newImp) {
    Method m = class_getClassMethod([NSColor class], sel);
    if (!m || gBTSwN >= BT_MAX_SWIZZLE) return;
    gBTSw[gBTSwN].sel  = sel;
    gBTSw[gBTSwN].orig = (BTColorIMP)method_getImplementation(m);
    gBTSwN++;
    method_setImplementation(m, newImp);
}

// --- Background overrides ---
static NSColor *imp_windowBg(id self, SEL _cmd) {
    return BRTintActive() ? gTintColorObj : BTCallOrig(self, _cmd);
}
static NSColor *imp_underPage(id self, SEL _cmd) {
    return (BRTintActive() && gTintControls) ? gTintColorObj : BTCallOrig(self, _cmd);
}
static NSColor *imp_controlBg(id self, SEL _cmd) {
    return (BRTintActive() && gTintControls) ? gTintColorObj : BTCallOrig(self, _cmd);
}

// --- Foreground (text / label) overrides — a precise colour, agnostic of the
// base colour and the appearance. Off by default (textAuto) so text follows the
// forced appearance as before; when a colour is set we vend it for the primary
// label/text colours and alpha-reduced variants for the label hierarchy. We
// deliberately leave selection text colours alone (they sit on the accent
// highlight, where a forced foreground would often be unreadable).
static NSColor *gTxtBase, *gTxt55, *gTxt25, *gTxt10;
static void BTEnsureTextCache(void) {
    if (gTxtBase == gTintTextObj) return;       // gTintTextObj is rebuilt on each refresh
    gTxtBase = gTintTextObj;
    gTxt55 = [gTintTextObj colorWithAlphaComponent:0.55];
    gTxt25 = [gTintTextObj colorWithAlphaComponent:0.25];
    gTxt10 = [gTintTextObj colorWithAlphaComponent:0.10];
}
static BOOL BTTextActive(void) { return BRTintActive() && !gTintTextAuto && gTintTextObj != nil; }

static NSColor *imp_textPrimary(id self, SEL _cmd) {
    return BTTextActive() ? gTintTextObj : BTCallOrig(self, _cmd);
}
static NSColor *imp_textSecondary(id self, SEL _cmd) {
    if (!BTTextActive()) return BTCallOrig(self, _cmd);
    BTEnsureTextCache(); return gTxt55;
}
static NSColor *imp_textTertiary(id self, SEL _cmd) {
    if (!BTTextActive()) return BTCallOrig(self, _cmd);
    BTEnsureTextCache(); return gTxt25;
}
static NSColor *imp_textQuaternary(id self, SEL _cmd) {
    if (!BTTextActive()) return BTCallOrig(self, _cmd);
    BTEnsureTextCache(); return gTxt10;
}

#pragma mark - NSVisualEffectView takeover

// Toolbars/sidebars/sheets fill themselves with an NSVisualEffectView whose
// material renders a derived shade; we override its layer update to paint the
// exact opaque chrome colour and suppress the private material sublayers.
// Menus/popovers/tooltips draw their per-item hover highlight inside their own
// vibrant material; taking that material over flattens the highlight, so a hovered
// submenu item stops standing out. Leave those materials (and menu/popover windows)
// native so selection stays visible. Other materials (sidebar/titlebar/etc.) are
// still recoloured.
static BOOL BTSkipEffectView(NSView *v) {
    if ([v respondsToSelector:@selector(material)]) {
        NSVisualEffectMaterial m = ((NSVisualEffectView *)v).material;
        if (m == NSVisualEffectMaterialMenu      || m == NSVisualEffectMaterialPopover ||
            m == NSVisualEffectMaterialSelection || m == NSVisualEffectMaterialToolTip)
            return YES;
    }
    NSWindow *w = v.window;
    if (w) {
        const char *wc = class_getName(object_getClass(w));
        if (strstr(wc, "Menu") || strstr(wc, "Popover")) return YES;
    }
    return NO;
}

static void (*orig_veUpdateLayer)(id, SEL) = NULL;

static void bt_veUpdateLayer(id self, SEL _cmd) {
    if (!BRTintActive() || BTSkipEffectView((NSView *)self)) {
        if (orig_veUpdateLayer) orig_veUpdateLayer(self, _cmd);
        return;
    }
    NSView *v = (NSView *)self;
    @try {
        v.wantsLayer = YES;
        CALayer *host = v.layer;
        host.backgroundColor = gTintChromeObj.CGColor;
        host.contents = nil;
        NSMutableSet *keep = [NSMutableSet set];
        for (NSView *sv in v.subviews)
            if (sv.layer) [keep addObject:[NSValue valueWithNonretainedObject:sv.layer]];
        for (CALayer *s in host.sublayers)
            if (![keep containsObject:[NSValue valueWithNonretainedObject:s]]) s.hidden = YES;
    } @catch (__unused NSException *e) {}
}

static void BTMarkEffectViews(NSView *v) {
    if (!v) return;
    if ([v isKindOfClass:NSClassFromString(@"NSVisualEffectView")] && !BTSkipEffectView(v)) {
        v.needsDisplay = YES;
        v.layer.backgroundColor = BRTintActive() ? gTintChromeObj.CGColor : NULL;
    }
    for (NSView *s in v.subviews) BTMarkEffectViews(s);
}

#pragma mark - Toolbar icon tint (contentTintColor on template images)

// Recolour template-image icons by setting contentTintColor (via KVC so it works
// for NSButton AND NSImageView). nil restores the default. Full-colour (non-template)
// icons are unaffected — that's an AppKit rule, not a choice here.
static void BTIconWalk(NSView *v, NSColor *c) {
    for (NSView *sv in v.subviews) {
        if ([sv isKindOfClass:[NSButton class]] || [sv isKindOfClass:[NSImageView class]]) {
            @try { [sv setValue:c forKey:@"contentTintColor"]; } @catch (__unused NSException *e) {}
        }
        BTIconWalk(sv, c);
    }
}

// Find the toolbar container(s) by class name and tint only their subtree, so we
// never touch the traffic-light widgets (those live under NSTitlebarView, not a
// toolbar view, and are owned by the lights module).
static void BTTintToolbars(NSView *v, NSColor *c) {
    const char *n = class_getName(object_getClass(v));
    if (strstr(n, "Toolbar")) { BTIconWalk(v, c); return; }
    for (NSView *sv in v.subviews) BTTintToolbars(sv, c);
}

static void BTApplyIcons(NSWindow *w) {
    NSView *frame = w.contentView.superview;
    if (!frame) return;
    NSColor *c = (BRTintActive() && gTintIcons) ? gTintTextObj : nil; // nil = restore
    @try { BTTintToolbars(frame, c); } @catch (__unused NSException *e) {}
}

#pragma mark - Backdrop + appearance

@interface BTBackdrop : NSView
@end
@implementation BTBackdrop
- (BOOL)allowsVibrancy { return NO; }
- (NSView *)hitTest:(NSPoint)point { return nil; } // never intercept clicks
@end

static void *kBTBackdropKey    = &kBTBackdropKey;
static void *kBTSavedOpaqueKey = &kBTSavedOpaqueKey; // NSNumber(BOOL): window.opaque before we tinted
static void *kBTSavedBgKey     = &kBTSavedBgKey;     // NSColor: window.backgroundColor before we tinted

static NSAppearanceName BRTintAppearanceName(void) {
    if (!BRTintActive()) return nil; // restore system
    switch (gTintMode) {
        case BR_MODE_LIGHT: return NSAppearanceNameAqua;
        case BR_MODE_DARK:  return NSAppearanceNameDarkAqua;
        case BR_MODE_NONE:  return nil; // don't touch appearance, just tint
        case BR_MODE_AUTO:
        default: return BRColorIsLight(gTintColorRGBA) ? NSAppearanceNameAqua : NSAppearanceNameDarkAqua;
    }
}

static void BTApplyToWindow(NSWindow *w, NSAppearance *appr) {
    if (!w) return;
    if (!gTintWallpaper && w.level < NSNormalWindowLevel) return; // leave desktop alone

    @try {
        BOOL on = BRTintActive();
        BOOL titled = (w.styleMask & NSWindowStyleMaskTitled) != 0;
        BTBackdrop *bg = objc_getAssociatedObject(w, kBTBackdropKey);

        if (on) {
            if (appr) w.appearance = appr;

            if (titled) {
                // Capture the window's original opacity + background ONCE, before our
                // first modification, so disabling or excluding tint can fully restore
                // it (otherwise a transparent-background app stays opaque with a solid
                // colour after we let go of it).
                if (!objc_getAssociatedObject(w, kBTSavedOpaqueKey)) {
                    objc_setAssociatedObject(w, kBTSavedOpaqueKey, @(w.opaque), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    objc_setAssociatedObject(w, kBTSavedBgKey, w.backgroundColor ?: [NSColor clearColor], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                w.opaque = YES;
                NSView *content = w.contentView;
                if (content) {
                    if (!bg) {
                        bg = [[BTBackdrop alloc] initWithFrame:content.bounds];
                        bg.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
                        bg.wantsLayer = YES;
                        objc_setAssociatedObject(w, kBTBackdropKey, bg, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    }
                    if (bg.superview != content || content.subviews.firstObject != bg) {
                        [bg removeFromSuperview];
                        [content addSubview:bg positioned:NSWindowBelow relativeTo:nil];
                        bg.frame = content.bounds;
                    }
                    bg.layer.backgroundColor = gTintColorObj.CGColor;
                }
                w.backgroundColor = [NSColor windowBackgroundColor]; // our (swizzled) colour
            }
        } else {
            if (bg) {
                [bg removeFromSuperview];
                objc_setAssociatedObject(w, kBTBackdropKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            // Restore the captured originals (fixes a previously-tinted, now-excluded
            // or disabled window — especially one that wants a transparent background).
            NSNumber *savedOpaque = objc_getAssociatedObject(w, kBTSavedOpaqueKey);
            if (savedOpaque) {
                w.opaque = savedOpaque.boolValue;
                NSColor *savedBg = objc_getAssociatedObject(w, kBTSavedBgKey);
                if (savedBg) w.backgroundColor = savedBg;
                objc_setAssociatedObject(w, kBTSavedOpaqueKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(w, kBTSavedBgKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }

        BTMarkEffectViews(w.contentView);
        BTApplyIcons(w);
        [w.contentView setNeedsDisplay:YES];
        [w invalidateShadow];
    } @catch (__unused NSException *e) {}
}

#pragma mark - Exposed entry points

void BRTintArm(void) {
    if (gTintExcluded) return; // stay entirely out of the screenshot UI

    BTSwizzleClassMethod(@selector(windowBackgroundColor),    (IMP)imp_windowBg);
    BTSwizzleClassMethod(@selector(underPageBackgroundColor), (IMP)imp_underPage);
    BTSwizzleClassMethod(@selector(controlBackgroundColor),   (IMP)imp_controlBg);

    // Foreground / text — precise, base-agnostic. No-ops while textAuto is on.
    // NOTE: we deliberately do NOT override the selection text colours
    // (selectedTextColor / selectedControlTextColor / selectedMenuItemTextColor /
    // alternateSelectedControlTextColor) — forcing those removes the contrast that
    // makes a hovered/selected menu item or table row stand out.
    SEL primary[] = {
        @selector(labelColor), @selector(textColor), @selector(controlTextColor),
        @selector(headerTextColor), @selector(windowFrameTextColor), @selector(linkColor),
    };
    for (size_t i = 0; i < sizeof(primary)/sizeof(*primary); i++)
        BTSwizzleClassMethod(primary[i], (IMP)imp_textPrimary);
    BTSwizzleClassMethod(@selector(secondaryLabelColor),      (IMP)imp_textSecondary);
    BTSwizzleClassMethod(@selector(tertiaryLabelColor),       (IMP)imp_textTertiary);
    BTSwizzleClassMethod(@selector(placeholderTextColor),     (IMP)imp_textTertiary);
    BTSwizzleClassMethod(@selector(disabledControlTextColor), (IMP)imp_textTertiary);
    BTSwizzleClassMethod(@selector(quaternaryLabelColor),     (IMP)imp_textQuaternary);

    Class ve = NSClassFromString(@"NSVisualEffectView");
    SEL sel = @selector(updateLayer);
    Method m = ve ? class_getInstanceMethod(ve, sel) : NULL;
    if (m) {
        const char *types = method_getTypeEncoding(m);
        IMP inherited = method_getImplementation(m);
        if (class_addMethod(ve, sel, (IMP)bt_veUpdateLayer, types)) {
            orig_veUpdateLayer = (void (*)(id, SEL))inherited;
        } else {
            Method own = class_getInstanceMethod(ve, sel);
            orig_veUpdateLayer = (void (*)(id, SEL))method_getImplementation(own);
            method_setImplementation(own, (IMP)bt_veUpdateLayer);
        }
    }
}

void BRTintApply(NSWindow *w) {
    if (![NSThread isMainThread]) return;
    NSAppearanceName name = BRTintAppearanceName();
    BTApplyToWindow(w, (name && gTintMode != BR_MODE_NONE) ? [NSAppearance appearanceNamed:name] : nil);
}

// Does the actual work; must run on the main queue. Deliberately does NOT re-check the thread or
// re-dispatch — see BRTintRefreshAll. Bails when there's no GUI app (headless daemon: nothing to do).
static void BRTintApplyMain(void) {
    NSApplication *app = NSApp;
    if (!app) return;

    NSAppearanceName name = BRTintAppearanceName();
    NSAppearance *appr = name ? [NSAppearance appearanceNamed:name] : nil;

    // nil restores the system appearance (mode none / disabled).
    if (gTintMode != BR_MODE_NONE || !BRTintActive()) app.appearance = appr;

    for (NSWindow *w in app.windows)
        BTApplyToWindow(w, (gTintMode != BR_MODE_NONE) ? appr : nil);
}

void BRTintRefreshAll(void) {
    // NB: in headless processes the main queue is drained by a dispatch WORKER thread, so
    // +[NSThread isMainThread] is false even on the main queue. The block must therefore call the
    // worker directly — NOT BRTintRefreshAll — or an off-"main" caller re-dispatches itself forever
    // (100% CPU). Dispatching once and running the worker there is harmless: NSApp is nil, so it no-ops.
    if ([NSThread isMainThread]) { BRTintApplyMain(); return; }
    dispatch_async(dispatch_get_main_queue(), ^{ BRTintApplyMain(); });
}
