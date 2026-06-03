//
//  Brutalium.m — core
//
//  Brutalist macOS: square window corners, force the expanded toolbar, and
//  square the traffic-light buttons — for every app. Merges the former UIFixer
//  (windows) and FlatLights (traffic lights) into one tweak with a shared
//  config transport and a single CLI.
//
//  The core owns the config cache + constructor; the two feature modules
//  (BRWindows.m, BRLights.m) own their swizzles and rendering.
//

#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <notify.h>
#import "BRState.h"
#import "BRConfig.h"

#pragma mark - Config cache (defined here, declared extern in BRConfig.h)

BOOL     gMaster = YES, gCorners = YES, gToolbar = YES;
double   gCornerRadius = 0.0;
uint64_t gExcl0 = 0, gExcl1 = 0;
BOOL     gSelfExcluded = NO;

BOOL     gLEnabled = YES;
double   gLRadius = 0.0, gLSize = 0.0;
uint32_t gLCloseRGBA = 0xFF5F57FF, gLMinRGBA = 0xFEBC2EFF,
         gLZoomRGBA  = 0x28C840FF, gLGlyphRGBA = 0x0000008C;
BOOL     gLInactiveAuto = YES;
uint32_t gLInactiveRGBA = 0x9B9B9BFF;

static int gTokWin, gTokExcl0, gTokExcl1,
           gTokLFlags, gTokLClose, gTokLMin, gTokLZoom, gTokLInact, gTokLGlyph;

static void BRRecomputeSelfExclusion(void) {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    gSelfExcluded = bid ? BRBloomTest(bid.UTF8String, gExcl0, gExcl1) : NO;
}

static void BRRefreshConfig(void) {
    uint64_t w = 0; notify_get_state(gTokWin, &w);
    bool valid = false, m = false, c = false, t = false; double rad = 0;
    BRUnpackWin(w, &valid, &m, &c, &t, &rad);
    if (valid) { gMaster = m; gCorners = c; gToolbar = t; gCornerRadius = rad; }
    else       { gMaster = YES; gCorners = YES; gToolbar = YES; gCornerRadius = 0.0; }

    gExcl0 = 0; notify_get_state(gTokExcl0, &gExcl0);
    gExcl1 = 0; notify_get_state(gTokExcl1, &gExcl1);
    BRRecomputeSelfExclusion();

    uint64_t lf = 0; notify_get_state(gTokLFlags, &lf);
    bool lvalid = false, len = false; double lrad = 0, lsz = 0;
    BRUnpackLFlags(lf, &lvalid, &len, &lrad, &lsz);
    if (lvalid) {
        gLEnabled = len; gLRadius = lrad; gLSize = lsz;
        uint64_t v = 0;
        notify_get_state(gTokLClose, &v); gLCloseRGBA = (uint32_t)v;
        v = 0; notify_get_state(gTokLMin,  &v); gLMinRGBA  = (uint32_t)v;
        v = 0; notify_get_state(gTokLZoom, &v); gLZoomRGBA = (uint32_t)v;
        v = 0; notify_get_state(gTokLGlyph,&v); gLGlyphRGBA = (uint32_t)v;
        uint64_t iv = 0; notify_get_state(gTokLInact, &iv);
        if (iv & BR_AUTO_STATE) gLInactiveAuto = YES;
        else { gLInactiveAuto = NO; gLInactiveRGBA = (uint32_t)iv; }
    } else {
        gLEnabled = YES; gLRadius = 0.0; gLSize = 0.0;
        gLCloseRGBA = 0xFF5F57FF; gLMinRGBA = 0xFEBC2EFF; gLZoomRGBA = 0x28C840FF;
        gLGlyphRGBA = 0x0000008C; gLInactiveAuto = YES; gLInactiveRGBA = 0x9B9B9BFF;
    }
}

#pragma mark - Discovery

static void BROnWindow(NSWindow *w) {
    if (!w) return;
    BRWindowsApply(w);
    BRLightsInstallOnWindow(w, NO);
}

static void BRApplyAll(BOOL forceLightsRedraw) {
    BRWindowsApplyAll();
    BRLightsRefreshAll(forceLightsRedraw);
}

#pragma mark - Process gating

static BOOL BRIsChildProcess(void) {
    @autoreleasepool {
        for (NSString *arg in [NSProcessInfo processInfo].arguments) {
            if ([arg hasPrefix:@"--type="]) return YES;
        }
    }
    return NO;
}

#pragma mark - Entry point

__attribute__((constructor))
static void BRSetup(void) {
    if (BRIsChildProcess()) return; // inert in Chromium/Electron helpers

    notify_register_check(BR_ST_WIN,    &gTokWin);
    notify_register_check(BR_ST_EXCL0,  &gTokExcl0);
    notify_register_check(BR_ST_EXCL1,  &gTokExcl1);
    notify_register_check(BR_ST_LFLAGS, &gTokLFlags);
    notify_register_check(BR_ST_LCLOSE, &gTokLClose);
    notify_register_check(BR_ST_LMIN,   &gTokLMin);
    notify_register_check(BR_ST_LZOOM,  &gTokLZoom);
    notify_register_check(BR_ST_LINACT, &gTokLInact);
    notify_register_check(BR_ST_LGLYPH, &gTokLGlyph);
    BRRefreshConfig();

    // Arm both feature swizzle groups — ONLY here, i.e. only in app processes.
    BRWindowsArm();
    BRLightsArm();

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    void (^onWindow)(NSNotification *) = ^(NSNotification *n) {
        if ([n.object isKindOfClass:[NSWindow class]]) BROnWindow((NSWindow *)n.object);
    };
    for (NSNotificationName name in @[ NSWindowDidBecomeKeyNotification,
                                       NSWindowDidBecomeMainNotification,
                                       NSWindowDidUpdateNotification ]) {
        [nc addObserverForName:name object:nil queue:nil usingBlock:onWindow];
    }

    int token = 0;
    notify_register_dispatch(BR_NOTIFY_CHANGED, &token, dispatch_get_main_queue(),
                             ^(int __unused t) {
        BRRefreshConfig();
        BRApplyAll(YES);
    });

    dispatch_async(dispatch_get_main_queue(), ^{ BRApplyAll(NO); });
}
