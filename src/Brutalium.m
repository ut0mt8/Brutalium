//
//  Brutalium.m — core
//
//  Brutalist macOS for every app: square window corners, force the expanded
//  toolbar, square the traffic-light buttons, and recolour the whole UI to a
//  configurable tint. Merges the former UIFixer (windows), FlatLights (traffic
//  lights) and BrutalTint (system tint) into one tweak with a shared config
//  transport and a single CLI.
//
//  The core owns the config cache + constructor + window discovery; the feature
//  modules (BRWindows.m, BRLights.m, BRTint.m) own their swizzles and rendering.
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

BOOL     gTintEnabled = NO;
int      gTintMode = BR_MODE_AUTO;
BOOL     gTintControls = YES, gTintWallpaper = NO;
BOOL     gTintIsWallpaperProc = NO, gTintExcluded = NO;
BOOL     gTintChromeAuto = YES;
BOOL     gTintTextAuto = YES;
BOOL     gTintIcons = NO;
uint32_t gTintColorRGBA = 0x1E1E28FF, gTintChromeRGBA = 0x2C2C3CFF, gTintTextRGBA = 0xE6E6E6FF;
NSColor *gTintColorObj = nil, *gTintChromeObj = nil, *gTintTextObj = nil;
uint64_t gTintExcl0 = 0, gTintExcl1 = 0;
BOOL     gTintSelfExcluded = NO;
uint64_t gNoTB0 = 0, gNoTB1 = 0;
BOOL     gSelfNoTitlebar = NO;
BOOL     gBorderEnabled = NO, gBorderShadow = YES;
double   gBorderSize = 1.0;
uint32_t gBorderRGBA = 0x000000FF, gBorderInactiveRGBA = 0x000000FF;
NSColor *gBorderColorObj = nil, *gBorderInactiveObj = nil;

static int gTokWin, gTokExcl0, gTokExcl1,
           gTokLFlags, gTokLClose, gTokLMin, gTokLZoom, gTokLInact, gTokLGlyph,
           gTokTFlags, gTokTColor, gTokTChrome, gTokTText, gTokTExcl0, gTokTExcl1,
           gTokNTB0, gTokNTB1, gTokBorder, gTokBColor, gTokBColorI;

static void BRRecomputeSelfExclusion(void) {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    const char *b = bid.UTF8String;
    gSelfExcluded     = b ? BRBloomTest(b, gExcl0, gExcl1)         : NO;
    gTintSelfExcluded = b ? BRBloomTest(b, gTintExcl0, gTintExcl1) : NO;
    gSelfNoTitlebar   = b ? BRBloomTest(b, gNoTB0, gNoTB1)         : NO;
}

static void BRRefreshConfig(void) {
    uint64_t w = 0; notify_get_state(gTokWin, &w);
    bool valid = false, m = false, c = false, t = false; double rad = 0;
    BRUnpackWin(w, &valid, &m, &c, &t, &rad);
    if (valid) { gMaster = m; gCorners = c; gToolbar = t; gCornerRadius = rad; }
    else       { gMaster = YES; gCorners = YES; gToolbar = YES; gCornerRadius = 0.0; }

    gExcl0 = 0; notify_get_state(gTokExcl0, &gExcl0);
    gExcl1 = 0; notify_get_state(gTokExcl1, &gExcl1);
    gTintExcl0 = 0; notify_get_state(gTokTExcl0, &gTintExcl0);
    gTintExcl1 = 0; notify_get_state(gTokTExcl1, &gTintExcl1);
    gNoTB0 = 0; notify_get_state(gTokNTB0, &gNoTB0);
    gNoTB1 = 0; notify_get_state(gTokNTB1, &gNoTB1);
    BRRecomputeSelfExclusion();

    uint64_t bf = 0; notify_get_state(gTokBorder, &bf);
    bool bvalid = false, ben = false, bsh = true; double bsz = 1.0;
    BRUnpackBorder(bf, &bvalid, &ben, &bsh, &bsz);
    if (bvalid) { gBorderEnabled = ben; gBorderShadow = bsh; gBorderSize = bsz; }
    else        { gBorderEnabled = NO; gBorderShadow = YES; gBorderSize = 1.0; }
    uint64_t bc = 0; notify_get_state(gTokBColor, &bc);
    gBorderRGBA = bc ? (uint32_t)bc : 0x000000FF;
    gBorderColorObj = BRMakeColor(gBorderRGBA);
    uint64_t bci = 0; notify_get_state(gTokBColorI, &bci);
    gBorderInactiveRGBA = bci ? (uint32_t)bci : gBorderRGBA; // 0 ⇒ same as active
    gBorderInactiveObj = BRMakeColor(gBorderInactiveRGBA);

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

    uint64_t tf = 0; notify_get_state(gTokTFlags, &tf);
    bool tvalid = false, ten = false, tctl = false, twp = false, tca = false, tta = false, tic = false; int tmode = BR_MODE_AUTO;
    BRUnpackTFlags(tf, &tvalid, &ten, &tmode, &tctl, &twp, &tca, &tta, &tic);
    if (tvalid) { gTintEnabled = ten; gTintMode = tmode; gTintControls = tctl; gTintWallpaper = twp; gTintChromeAuto = tca; gTintTextAuto = tta; gTintIcons = tic; }
    else        { gTintEnabled = NO;  gTintMode = BR_MODE_AUTO; gTintControls = YES; gTintWallpaper = NO; gTintChromeAuto = YES; gTintTextAuto = YES; gTintIcons = NO; }

    uint64_t tc = 0; notify_get_state(gTokTColor, &tc);
    gTintColorRGBA = tc ? (uint32_t)tc : 0x1E1E28FF;
    uint64_t tcc = 0; notify_get_state(gTokTChrome, &tcc);
    uint64_t ttx = 0; notify_get_state(gTokTText, &ttx);

    // Backgrounds are solid: ignore alpha, force fully opaque.
    uint32_t mainOpaque = (gTintColorRGBA & 0xFFFFFF00) | 0xFF;
    gTintColorObj = BRMakeColor(mainOpaque);
    gTintChromeRGBA = (gTintChromeAuto || tcc == 0) ? BRDeriveChrome(mainOpaque)
                                                    : (((uint32_t)tcc & 0xFFFFFF00) | 0xFF);
    gTintChromeObj = BRMakeColor(gTintChromeRGBA);

    // Precise text colour (opaque); only applied when textAuto is off.
    gTintTextRGBA = ttx ? (((uint32_t)ttx & 0xFFFFFF00) | 0xFF) : 0xE6E6E6FF;
    gTintTextObj = BRMakeColor(gTintTextRGBA);
}

#pragma mark - Discovery

static void BROnWindow(NSWindow *w) {
    if (!w) return;
    BRWindowsApply(w);
    BRTintApply(w);
    // Defer the lights install out of the synchronous becomeKey/notification
    // callout so we never introspect a window's view tree while it's still
    // mid-transition. Which windows actually get lights is decided by
    // FLWindowEligible() (real top-level main windows only).
    dispatch_async(dispatch_get_main_queue(), ^{ BRLightsInstallOnWindow(w, NO); });
}

static void BRApplyAll(BOOL forceLightsRedraw) {
    BRWindowsApplyAll();
    BRTintRefreshAll();
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

// The screenshot UI relies on vibrancy the tint takeover would break, so tint
// stays out of it. (Corners/lights are harmless there but irrelevant.)
static BOOL BRIsScreenshotProcess(NSString *bid) {
    if ([bid rangeOfString:@"screencapture" options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    if ([bid rangeOfString:@"screenshot"    options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    return NO;
}

#pragma mark - Entry point

__attribute__((constructor))
static void BRSetup(void) {
    if (BRIsChildProcess()) return; // inert in Chromium/Electron helpers

    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        gTintExcluded = BRIsScreenshotProcess(bid);
        gTintIsWallpaperProc = [bid isEqualToString:@"com.apple.dock"] ||
            [bid rangeOfString:@"wallpaper" options:NSCaseInsensitiveSearch].location != NSNotFound;
    }

    notify_register_check(BR_ST_WIN,    &gTokWin);
    notify_register_check(BR_ST_EXCL0,  &gTokExcl0);
    notify_register_check(BR_ST_EXCL1,  &gTokExcl1);
    notify_register_check(BR_ST_LFLAGS, &gTokLFlags);
    notify_register_check(BR_ST_LCLOSE, &gTokLClose);
    notify_register_check(BR_ST_LMIN,   &gTokLMin);
    notify_register_check(BR_ST_LZOOM,  &gTokLZoom);
    notify_register_check(BR_ST_LINACT, &gTokLInact);
    notify_register_check(BR_ST_LGLYPH, &gTokLGlyph);
    notify_register_check(BR_ST_TFLAGS, &gTokTFlags);
    notify_register_check(BR_ST_TCOLOR, &gTokTColor);
    notify_register_check(BR_ST_TCHROME, &gTokTChrome);
    notify_register_check(BR_ST_TTEXT,  &gTokTText);
    notify_register_check(BR_ST_TEXCL0, &gTokTExcl0);
    notify_register_check(BR_ST_TEXCL1, &gTokTExcl1);
    notify_register_check(BR_ST_NTB0,   &gTokNTB0);
    notify_register_check(BR_ST_NTB1,   &gTokNTB1);
    notify_register_check(BR_ST_BORDER, &gTokBorder);
    notify_register_check(BR_ST_BCOLOR, &gTokBColor);
    notify_register_check(BR_ST_BCOLORI, &gTokBColorI);
    BRRefreshConfig();

    // Arm every feature's swizzles — ONLY here, i.e. only in app processes.
    BRWindowsArm();
    BRLightsArm();
    BRTintArm();

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    void (^onWindow)(NSNotification *) = ^(NSNotification *n) {
        if ([n.object isKindOfClass:[NSWindow class]]) BROnWindow((NSWindow *)n.object);
    };
    for (NSNotificationName name in @[ NSWindowDidBecomeKeyNotification,
                                       NSWindowDidBecomeMainNotification,
                                       NSWindowDidResignKeyNotification,
                                       NSWindowDidResignMainNotification,
                                       NSWindowDidUpdateNotification ]) {
        [nc addObserverForName:name object:nil queue:nil usingBlock:onWindow];
    }

    // App-level active/inactive: per-window resign notifications don't reliably fire
    // when another *app* takes focus, so re-apply to every window here. This is what
    // flips the border between its active and inactive colours on app switch.
    for (NSNotificationName name in @[ NSApplicationDidResignActiveNotification,
                                       NSApplicationDidBecomeActiveNotification ]) {
        [nc addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *n) {
            (void)n;
            dispatch_async(dispatch_get_main_queue(), ^{ BRWindowsApplyAll(); });
        }];
    }

    int token = 0;
    notify_register_dispatch(BR_NOTIFY_CHANGED, &token, dispatch_get_main_queue(),
                             ^(int __unused t) {
        BRRefreshConfig();
        BRApplyAll(YES);
    });

    dispatch_async(dispatch_get_main_queue(), ^{ BRApplyAll(NO); });
}
