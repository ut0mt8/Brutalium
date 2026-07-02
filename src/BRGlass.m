//
//  BRGlass.m — flatten NSGlassEffectView (Tahoe "Liquid Glass") to an opaque panel.
//
//  From probing: NSGlassEffectView is NOT layer-backed (self.layer == nil). Its glass is
//  rendered by a _NSCoreHostingView sibling that also lenses the content through the
//  glass — so hiding it drops the content. The content's source views live in a
//  "ContentHolderView" sibling that DOES have a plain CALayer. Painting that layer opaque
//  at the view's own cornerRadius yields a solid rounded panel while the content keeps
//  rendering. Public API only: no private material knobs, no hidden renderer.
//
//  We hook -[NSGlassEffectView layout] once at the class level (method_setImplementation,
//  same idiom as BRLights) and re-apply after each layout. Toggling the feature off
//  clears the fill we added, restoring the glass.
//

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "BRConfig.h"

static IMP gGlassOrigLayout = NULL;
static const void *kBRGlassPainted = &kBRGlassPainted;

// Apply (or restore) the opaque fill on one NSGlassEffectView-like view.
static void BRGlassApplyToView(NSView *gv) {
    if (!gv) return;

    NSView *holder = nil;
    for (NSView *sv in gv.subviews) {
        const char *n = class_getName([sv class]);
        if (n && strstr(n, "ContentHolderView")) { holder = sv; break; }
    }
    if (!holder || !holder.layer) return;

    if (BRGlassActive()) {
        double cr = 0;
        @try { cr = [[gv valueForKey:@"cornerRadius"] doubleValue]; } @catch (__unused NSException *e) {}

        __block CGColorRef cg = NULL;
        NSColor *col = gGlassColorObj ?: [NSColor windowBackgroundColor];
        if (@available(macOS 11.0, *))
            [gv.effectiveAppearance performAsCurrentDrawingAppearance:^{ cg = col.CGColor; }];
        else
            cg = col.CGColor;

        holder.layer.backgroundColor = cg;
        holder.layer.cornerRadius    = cr;
        holder.layer.masksToBounds   = (cr > 0.0);
        objc_setAssociatedObject(holder, kBRGlassPainted, @YES, OBJC_ASSOCIATION_RETAIN);
    } else if (objc_getAssociatedObject(holder, kBRGlassPainted)) {
        // feature turned off after we painted — restore the see-through glass
        holder.layer.backgroundColor = NULL;
        holder.layer.masksToBounds   = NO;
        objc_setAssociatedObject(holder, kBRGlassPainted, nil, OBJC_ASSOCIATION_RETAIN);
    }
}

static void BRGlassLayout(NSView *self, SEL _cmd) {
    if (gGlassOrigLayout) ((void (*)(id, SEL))gGlassOrigLayout)(self, _cmd);  // original first
    @try { BRGlassApplyToView(self); } @catch (__unused NSException *e) {}
}

void BRGlassArm(void) {
    static BOOL armed = NO;
    if (armed) return;
    Class c = objc_getClass("NSGlassEffectView");   // subclasses inherit this -layout
    if (!c) return;
    Method m = class_getInstanceMethod(c, @selector(layout));
    if (!m) return;
    gGlassOrigLayout = method_setImplementation(m, (IMP)BRGlassLayout);
    armed = YES;
}

static void BRGlassWalk(NSView *v, Class glassCls) {
    if (!v) return;
    if ([v isKindOfClass:glassCls]) { [v setNeedsLayout:YES]; BRGlassApplyToView(v); }
    for (NSView *s in v.subviews) BRGlassWalk(s, glassCls);
}

void BRGlassRefreshAll(void) {
    Class glassCls = objc_getClass("NSGlassEffectView");
    if (!glassCls) return;
    @try {
        for (NSWindow *w in [NSApp windows]) {
            NSView *root = w.contentView.superview ?: w.contentView;   // include titlebar area
            BRGlassWalk(root, glassCls);
        }
    } @catch (__unused NSException *e) {}
}
