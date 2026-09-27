//
//  BRDock.m — flat background + corner radius for the Dock.
//  Ported from the standalone BrutalDock tweak. Only active in com.apple.dock.
//

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "ZKSwizzle.h"
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
#import "BRConfig.h"

#pragma mark - Private Dock classes

// Solarium's floor layer, Swift name mangled. If this stops matching after an OS
// update, grep class_copyClassList in the Dock process for "Floor".
@interface _TtC8DockCore16ModernFloorLayer : CALayer
@end

// Pre-Solarium fallback.
@interface FloorLayer : CALayer
@end

#pragma mark - Config

static inline BOOL BRDockFlatActive(void) { return gMaster && gDockFlat; }

BOOL BRIsDockProcess(void) {
    NSString *bid = [NSBundle mainBundle].bundleIdentifier;
    return [bid isEqualToString:@"com.apple.dock"];
}

#pragma mark - Background

// Dumps the floor's own geometry plus a few ancestor levels. Fires once per launch.
// Useful when the background lands offset (e.g. right-side Dock) — the numbers beat guessing.
static void BRDockProbeGeometry(CALayer *floor) {
    static BOOL probed = NO;
    if (probed) return;
    probed = YES;
    FILE *fp = fopen("/tmp/brutalium-dock-probe.log", "w");
    if (!fp) return;

    fprintf(fp, "floor class=%s\n", class_getName(object_getClass(floor)));
    fprintf(fp, "floor frame=(%.1f,%.1f %.1fx%.1f) bounds=(%.1f,%.1f %.1fx%.1f) position=(%.1f,%.1f) anchorPoint=(%.2f,%.2f)\n",
            floor.frame.origin.x, floor.frame.origin.y, floor.frame.size.width, floor.frame.size.height,
            floor.bounds.origin.x, floor.bounds.origin.y, floor.bounds.size.width, floor.bounds.size.height,
            floor.position.x, floor.position.y, floor.anchorPoint.x, floor.anchorPoint.y);

    fprintf(fp, "floor.sublayers (%lu):\n", (unsigned long)floor.sublayers.count);
    for (CALayer *sub in floor.sublayers) {
        fprintf(fp, "  sub class=%s frame=(%.1f,%.1f %.1fx%.1f) cornerRadius=%.1f masksToBounds=%d\n",
                class_getName(object_getClass(sub)),
                sub.frame.origin.x, sub.frame.origin.y, sub.frame.size.width, sub.frame.size.height,
                sub.cornerRadius, sub.masksToBounds);
    }

    CALayer *parent = floor.superlayer;
    if (parent) {
        fprintf(fp, "floor's siblings, parent class=%s bounds=(%.1f,%.1f %.1fx%.1f) (%lu children):\n",
                class_getName(object_getClass(parent)),
                parent.bounds.origin.x, parent.bounds.origin.y, parent.bounds.size.width, parent.bounds.size.height,
                (unsigned long)parent.sublayers.count);
        for (CALayer *sib in parent.sublayers) {
            fprintf(fp, "  sib%s class=%s frame=(%.1f,%.1f %.1fx%.1f)\n",
                    sib == floor ? " (=floor)" : "", class_getName(object_getClass(sib)),
                    sib.frame.origin.x, sib.frame.origin.y, sib.frame.size.width, sib.frame.size.height);
        }
    }

    CALayer *p = floor.superlayer;
    for (int i = 0; i < 5 && p; i++) {
        fprintf(fp, "  ancestor[%d] class=%s frame=(%.1f,%.1f %.1fx%.1f) bounds=(%.1f,%.1f %.1fx%.1f)\n",
                i, class_getName(object_getClass(p)),
                p.frame.origin.x, p.frame.origin.y, p.frame.size.width, p.frame.size.height,
                p.bounds.origin.x, p.bounds.origin.y, p.bounds.size.width, p.bounds.size.height);
        p = p.superlayer;
    }

    NSString *orientation = [[NSUserDefaults standardUserDefaults] stringForKey:@"orientation"];
    fprintf(fp, "dock orientation pref = %s\n", orientation ? orientation.UTF8String : "(unknown)");
    fflush(fp);
    fclose(fp);
}

static const void *kBRDockBackgroundKey = &kBRDockBackgroundKey;

static void BRDockApplyBackground(CALayer *floor) {
    if (!floor || !BRIsDockProcess()) return;

    CALayer *bg = objc_getAssociatedObject(floor, kBRDockBackgroundKey);

    if (!BRDockFlatActive()) {
        if (bg) {
            [bg removeFromSuperlayer];
            objc_setAssociatedObject(floor, kBRDockBackgroundKey, nil, OBJC_ASSOCIATION_RETAIN);
        }
        // put the native glass back if we'd hidden it
        for (CALayer *sub in floor.sublayers) {
            if (fabs(sub.frame.size.height - floor.bounds.size.height) < 1.0 && sub.frame.size.width > 10.0)
                sub.hidden = NO;
        }
        return;
    }

    CGRect bounds = floor.bounds;
    if (CGRectIsEmpty(bounds)) return;   // not laid out yet

    BRDockProbeGeometry(floor);

    // floor.bounds doesn't line up with where the glass actually renders — Solarium's real
    // glass/blur layers sit inset within it. Find the narrowest full-height sublayer (the
    // crisp glass fill, not the wider blur bleed) and align + hide against that instead.
    CGRect targetFrame = bounds;
    CGFloat bestWidth = CGFLOAT_MAX;
    for (CALayer *sub in floor.sublayers) {
        if (sub == bg) continue;
        if (fabs(sub.frame.size.height - bounds.size.height) < 1.0 && sub.frame.size.width > 10.0) {
            sub.hidden = YES;
            if (sub.frame.size.width < bestWidth) {
                bestWidth = sub.frame.size.width;
                targetFrame = sub.frame;
            }
        }
    }

    if (!bg) {
        bg = [CALayer layer];
        bg.name = @"BRDockBackground";   // lets corners-elements recognise and skip this layer
        objc_setAssociatedObject(floor, kBRDockBackgroundKey, bg, OBJC_ASSOCIATION_RETAIN);
    }

    bg.frame = targetFrame;
    bg.backgroundColor = BRMakeColor(gDockColorRGBA).CGColor;
    bg.cornerRadius = (CGFloat)gDockRadius;
    bg.cornerCurve = (gDockRadius <= 0.0) ? kCACornerCurveCircular : kCACornerCurveContinuous;
    bg.masksToBounds = YES;   // clip the background only, never the floor — keeps bouncing icons visible
    bg.borderWidth = gDockBorderEnabled ? (CGFloat)gDockBorderSize : 0.0;
    bg.borderColor = BRMakeColor(gDockBorderRGBA).CGColor;

    // the floor's own radius also needs to match, since some native glass layers clip to it directly
    floor.cornerRadius = (CGFloat)gDockRadius;

    if (![floor.sublayers containsObject:bg]) {
        [floor insertSublayer:bg atIndex:0];
    } else if (floor.sublayers.firstObject != bg) {
        [bg removeFromSuperlayer];
        [floor insertSublayer:bg atIndex:0];
    }
}

#pragma mark - Swizzles

ZKSwizzleInterfaceGroup(BRDock_ModernFloorLayer, _TtC8DockCore16ModernFloorLayer, CALayer, BRUTALIUM_DOCK)
@implementation BRDock_ModernFloorLayer
- (void)layoutSublayers {
    ZKOrig(void);
    BRDockApplyBackground((CALayer *)self);
}
@end

ZKSwizzleInterfaceGroup(BRDock_FloorLayer, FloorLayer, CALayer, BRUTALIUM_DOCK)
@implementation BRDock_FloorLayer
- (void)layoutSublayers {
    ZKOrig(void);
    BRDockApplyBackground((CALayer *)self);
}
@end

#pragma mark - Arm

void BRDockArm(void) {
    if (!BRIsDockProcess()) return;
    ZKSwizzleGroup(BRUTALIUM_DOCK);
}

void BRDockForceRelayout(void) {
    if (!BRIsDockProcess()) return;
    for (NSWindow *w in NSApp.windows) {
        if (w.contentView.layer) [w.contentView.layer setNeedsLayout];
    }
}
