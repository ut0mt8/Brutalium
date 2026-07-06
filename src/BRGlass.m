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

// --- Tiling pattern colour -------------------------------------------------
// CALayer.contents can only stretch/crop an image (contentsGravity has no "tile"), so to repeat
// a texture we fill the layer's backgroundColor with a CGPattern-backed colour, which tiles at the
// image's native pixel size. The pattern owns a retained copy of the image via releaseInfo, so the
// colour is a self-contained unit: retain the colour and the image stays alive; release it and both go.
static void BRTileDraw(void *info, CGContextRef ctx) {
    CGImageRef img = (CGImageRef)info;
    CGContextDrawImage(ctx, CGRectMake(0, 0, CGImageGetWidth(img), CGImageGetHeight(img)), img);
}
static void BRTileRelease(void *info) { if (info) CGImageRelease((CGImageRef)info); }

static CGColorRef BRTilePatternColor(CGImageRef img) {   // caller releases the result
    if (!img) return NULL;
    CGFloat w = (CGFloat)CGImageGetWidth(img), h = (CGFloat)CGImageGetHeight(img);
    if (w < 1.0 || h < 1.0) return NULL;
    static const CGPatternCallbacks cb = { 0, &BRTileDraw, &BRTileRelease };
    CGImageRef held = CGImageRetain(img);                // freed by BRTileRelease when the pattern dies
    CGPatternRef pat = CGPatternCreate((void *)held, CGRectMake(0, 0, w, h),
                                       CGAffineTransformIdentity, w, h,
                                       kCGPatternTilingConstantSpacing, true, &cb);
    if (!pat) { CGImageRelease(held); return NULL; }
    CGColorSpaceRef sp = CGColorSpaceCreatePattern(NULL);
    CGFloat alpha = 1.0;
    CGColorRef col = CGColorCreateWithPattern(sp, pat, &alpha);
    CGColorSpaceRelease(sp);
    CGPatternRelease(pat);                               // the colour retains it
    return col;
}

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

        CGImageRef img = gGlassImageEnabled ? BRImageForRole(@"glass") : NULL;
        if (img) {
            CGColorRef pat = BRTilePatternColor(img);    // tiles at the image's native size
            holder.layer.contents        = nil;
            holder.layer.backgroundColor = pat;          // layer retains it
            if (pat) CGColorRelease(pat);
        } else {
            __block CGColorRef cg = NULL;
            NSColor *col = gGlassColorObj ?: [NSColor windowBackgroundColor];
            if (@available(macOS 11.0, *))
                [gv.effectiveAppearance performAsCurrentDrawingAppearance:^{ cg = col.CGColor; }];
            else
                cg = col.CGColor;
            holder.layer.contents = nil;
            holder.layer.backgroundColor = cg;
        }
        holder.layer.cornerRadius    = cr;
        holder.layer.masksToBounds   = (cr > 0.0);
        objc_setAssociatedObject(holder, kBRGlassPainted, @YES, OBJC_ASSOCIATION_RETAIN);
    } else if (objc_getAssociatedObject(holder, kBRGlassPainted)) {
        // feature turned off after we painted — restore the see-through glass
        holder.layer.contents        = nil;
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
