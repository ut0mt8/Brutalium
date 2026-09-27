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
#import <mach-o/dyld.h>
#import "BRState.h"
#import "BRConfig.h"

#pragma mark - Config cache (defined here, declared extern in BRConfig.h)

BOOL     gMaster = YES, gCorners = YES, gToolbar = YES;
BOOL     gSlimToolbar = NO;
double   gSlimToolbarHeight = 36.0;
double   gSlimRadius = 5.0;
BOOL     gDockFlat = NO;
uint32_t gDockColorRGBA = 0x1C1C1EE6;
double   gDockRadius = 0.0;
BOOL     gDockBorderEnabled = NO;
uint32_t gDockBorderRGBA = 0xFFFFFFFF;
double   gDockBorderSize = 1.0;
BOOL     gSidebarTintEnabled = NO;
uint32_t gSidebarTintRGBA = 0x1E1E28FF;
BOOL     gSidebarTintAuto = YES;
BOOL     gSidebarCornersEnabled = NO;
double   gSidebarCornersRadius = 0.0;
BOOL     gSquareMenus = NO;
BOOL     gSquareElements = NO;
BOOL     gMenuShadow = NO;          // keep menu shadow when squaring (default: strip)
uint32_t gMenuSelectRGBA = 0;       // custom menu selection colour (0 = system default)
double   gElementsRadius = 0.0;     // radius for corners elements (0 = square)
double   gMenuRadius = 0.0;         // radius for corners menus (0 = square)
double   gCornerRadius = 0.0;
BOOL     gSelfExcluded = NO;

BOOL     gLEnabled = YES, gLightsImageEnabled = NO;
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
NSColor *gTintColorObj = nil, *gTintChromeObj = nil, *gTintTextObj = nil, *gTintAccentObj = nil;

BOOL     gGlassFlatten = NO, gGlassColorAuto = YES, gGlassImageEnabled = NO;
uint32_t gGlassColorRGBA = 0xFFFFFFFF;
NSColor *gGlassColorObj = nil;
BOOL     gGlassSelfExcluded = NO;

BOOL     gTitlebarColorEnabled = NO;
BOOL     gTitlebarImageEnabled = NO;
uint32_t gTitlebarColorRGBA = 0x1E1E28FF;
NSColor *gTitlebarColorObj = nil;
BOOL     gTintSelfExcluded = NO;
BOOL     gSelfNoTitlebar = NO;
BOOL     gBorderEnabled = NO, gBorderShadow = YES;
double   gBorderSize = 1.0;
uint32_t gBorderRGBA = 0x000000FF, gBorderInactiveRGBA = 0x000000FF;
NSColor *gBorderColorObj = nil, *gBorderInactiveObj = nil;
uint32_t gBorderEdgeRGBA[4] = {0,0,0,0};
BOOL     gBorderEdgeImageEnabled[4] = {NO,NO,NO,NO};
uint32_t gBorderCornerRGBA[4] = {0,0,0,0};
BOOL     gBorderCornerImageEnabled[4] = {NO,NO,NO,NO};

static int gTokWin,
           gTokLFlags, gTokLClose, gTokLMin, gTokLZoom, gTokLInact, gTokLGlyph,
           gTokTFlags, gTokTColor, gTokTChrome, gTokTText, gTokTAccent,
           gTokBorder, gTokBColor, gTokBColorI, gTokGlass, gTokTbar;

static void BRRecomputeSelfExclusion(void) {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    gSelfExcluded = gTintSelfExcluded = gSelfNoTitlebar = NO;
    gGlassSelfExcluded = NO;
    if (!bid) return;    // Per-app lists live in the global domain (see BRPublishFromDefaults) — readable by
    // sandboxed apps at launch. Sync first so a change announced via the notify signal
    // is re-read rather than served stale from cache.
    CFPreferencesAppSynchronize(kCFPreferencesAnyApplication);
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("com.tweak.brutalium.lists"),
        kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSDictionary *lists = (__bridge_transfer NSDictionary *)v;
    if ([lists isKindOfClass:[NSDictionary class]]) {
        id tb = lists[@"toolbar"], ti = lists[@"tint"], nt = lists[@"titlebar"], gl = lists[@"glass"];
        gSelfExcluded     = [tb isKindOfClass:[NSArray class]] && [tb containsObject:bid];
        gTintSelfExcluded = [ti isKindOfClass:[NSArray class]] && [ti containsObject:bid];
        gSelfNoTitlebar   = [nt isKindOfClass:[NSArray class]] && [nt containsObject:bid];
        gGlassSelfExcluded = [gl isKindOfClass:[NSArray class]] && [gl containsObject:bid];
    }
    // Menu appearance options (read from global defaults alongside the lists).
    id msObj = (id)CFBridgingRelease(CFPreferencesCopyValue(CFSTR("com.tweak.brutalium.menu.shadow"),
        kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    gMenuShadow = [msObj isKindOfClass:[NSNumber class]] && [msObj boolValue];
    id mcObj = (id)CFBridgingRelease(CFPreferencesCopyValue(CFSTR("com.tweak.brutalium.menu.selectcolor"),
        kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    gMenuSelectRGBA = [mcObj isKindOfClass:[NSNumber class]] ? (uint32_t)[mcObj unsignedIntValue] : 0;
    id crObj = (id)CFBridgingRelease(CFPreferencesCopyValue(CFSTR("com.tweak.brutalium.elements.radius"),
        kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    gElementsRadius = [crObj isKindOfClass:[NSNumber class]] ? [crObj doubleValue] : 0.0;
    id mrObj = (id)CFBridgingRelease(CFPreferencesCopyValue(CFSTR("com.tweak.brutalium.menus.radius"),
        kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    gMenuRadius = [mrObj isKindOfClass:[NSNumber class]] ? [mrObj doubleValue] : 0.0;
    // Slim toolbar
    id stObj = (id)CFBridgingRelease(CFPreferencesCopyValue(CFSTR("com.tweak.brutalium.toolbar.slim"),
        kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    gSlimToolbar = [stObj isKindOfClass:[NSNumber class]] && [stObj boolValue];
    id sthObj = (id)CFBridgingRelease(CFPreferencesCopyValue(CFSTR("com.tweak.brutalium.toolbar.slim.height"),
        kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    gSlimToolbarHeight = [sthObj isKindOfClass:[NSNumber class]] ? [sthObj doubleValue] : 36.0;
    if (gSlimToolbarHeight < 24.0) gSlimToolbarHeight = 24.0;
    if (gSlimToolbarHeight > 52.0) gSlimToolbarHeight = 52.0;
    id srObj = (id)CFBridgingRelease(CFPreferencesCopyValue(CFSTR("com.tweak.brutalium.toolbar.slim.radius"),
        kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    gSlimRadius = [srObj isKindOfClass:[NSNumber class]] ? [srObj doubleValue] : 5.0;
    if (gSlimRadius < 0.0) gSlimRadius = 0.0;

    // Dock flat background + corner radius
    id dfObj = (id)CFBridgingRelease(CFPreferencesCopyValue(CFSTR("com.tweak.brutalium.dock.flat"),
        kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    gDockFlat = [dfObj isKindOfClass:[NSNumber class]] && [dfObj boolValue];
    id dcObj = (id)CFBridgingRelease(CFPreferencesCopyValue(CFSTR("com.tweak.brutalium.dock.color"),
        kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    gDockColorRGBA = [dcObj isKindOfClass:[NSNumber class]] ? (uint32_t)[dcObj unsignedLongLongValue] : 0x1C1C1EE6;
    id drObj = (id)CFBridgingRelease(CFPreferencesCopyValue(CFSTR("com.tweak.brutalium.dock.radius"),
        kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    gDockRadius = [drObj isKindOfClass:[NSNumber class]] ? [drObj doubleValue] : 0.0;
    if (gDockRadius < 0.0) gDockRadius = 0.0;
    id dbeObj = (id)CFBridgingRelease(CFPreferencesCopyValue(CFSTR("com.tweak.brutalium.dock.border"),
        kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    gDockBorderEnabled = [dbeObj isKindOfClass:[NSNumber class]] && [dbeObj boolValue];
    id dbcObj = (id)CFBridgingRelease(CFPreferencesCopyValue(CFSTR("com.tweak.brutalium.dock.border.color"),
        kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    gDockBorderRGBA = [dbcObj isKindOfClass:[NSNumber class]] ? (uint32_t)[dbcObj unsignedLongLongValue] : 0xFFFFFFFF;
    id dbsObj = (id)CFBridgingRelease(CFPreferencesCopyValue(CFSTR("com.tweak.brutalium.dock.border.size"),
        kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    gDockBorderSize = [dbsObj isKindOfClass:[NSNumber class]] ? [dbsObj doubleValue] : 1.0;
    if (gDockBorderSize < 0.0) gDockBorderSize = 0.0;

    // Sidebar tint + squaring
    id steObj = (id)CFBridgingRelease(CFPreferencesCopyValue(CFSTR("com.tweak.brutalium.sidebar.tint"),
        kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    gSidebarTintEnabled = [steObj isKindOfClass:[NSNumber class]] && [steObj boolValue];
    id stcObj = (id)CFBridgingRelease(CFPreferencesCopyValue(CFSTR("com.tweak.brutalium.sidebar.tint.color"),
        kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    if ([stcObj isKindOfClass:[NSNumber class]]) {
        gSidebarTintRGBA = (uint32_t)[stcObj unsignedLongLongValue];
        gSidebarTintAuto = NO;
    } else {
        gSidebarTintAuto = YES;
    }
    id sceObj = (id)CFBridgingRelease(CFPreferencesCopyValue(CFSTR("com.tweak.brutalium.sidebar.corners"),
        kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    gSidebarCornersEnabled = [sceObj isKindOfClass:[NSNumber class]] && [sceObj boolValue];
    id scrObj = (id)CFBridgingRelease(CFPreferencesCopyValue(CFSTR("com.tweak.brutalium.sidebar.corners.radius"),
        kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    gSidebarCornersRadius = [scrObj isKindOfClass:[NSNumber class]] ? [scrObj doubleValue] : 0.0;
    if (gSidebarCornersRadius < 0.0) gSidebarCornersRadius = 0.0;
}

static void BRRefreshConfig(void) {
    uint64_t w = BRReadStateWord(gTokWin, BR_ST_WIN);
    bool valid = false, m = false, c = false, t = false, sm = false, se = false; double rad = 0;
    BRUnpackWin(w, &valid, &m, &c, &t, &sm, &se, &rad);
    if (valid) { gMaster = m; gCorners = c; gToolbar = t; gSquareMenus = sm; gSquareElements = se; gCornerRadius = rad; }
    else       { gMaster = YES; gCorners = YES; gToolbar = YES; gSquareMenus = NO; gSquareElements = NO; gCornerRadius = 0.0; }

    BRRecomputeSelfExclusion();

    uint64_t bf = BRReadStateWord(gTokBorder, BR_ST_BORDER);
    bool bvalid=false, ben=false, bsh=true; double bsz=1.0;
    BRUnpackBorder(bf, &bvalid, &ben, &bsh, &bsz);
    if (bvalid) { gBorderEnabled = ben; gBorderShadow = bsh; gBorderSize = bsz; }
    else        { gBorderEnabled = NO; gBorderShadow = YES; gBorderSize = 1.0; }

    uint64_t gf = BRReadStateWord(gTokGlass, BR_ST_GLASS);
    bool gvalid = false, gfl = false, gauto = true, gimg = false; uint32_t grgba = 0xFFFFFFFF;
    BRUnpackGlass(gf, &gvalid, &gfl, &gauto, &gimg, &grgba);
    if (gvalid) { gGlassFlatten = gfl; gGlassColorAuto = gauto; gGlassImageEnabled = gimg; gGlassColorRGBA = grgba; }
    else        { gGlassFlatten = NO; gGlassColorAuto = YES; gGlassImageEnabled = NO; gGlassColorRGBA = 0xFFFFFFFF; }
    gGlassColorObj = gGlassColorAuto ? nil : BRMakeColor(gGlassColorRGBA);

    uint64_t tb = BRReadStateWord(gTokTbar, BR_ST_TBAR);
    bool tbvalid = false, tben = false, tbimg = false; uint32_t tbrgba = 0x1E1E28FF;
    BRUnpackTbar(tb, &tbvalid, &tben, &tbimg, &tbrgba);
    if (tbvalid) { gTitlebarColorEnabled = tben; gTitlebarImageEnabled = tbimg; gTitlebarColorRGBA = tbrgba; }
    else         { gTitlebarColorEnabled = NO;   gTitlebarImageEnabled = NO;    gTitlebarColorRGBA = 0x1E1E28FF; }
    gTitlebarColorObj = BRMakeColor(gTitlebarColorRGBA);


    // Decode/refresh all feature images (titlebar, glass, …) from the shared global-domain registry.
    BRImagesRefresh();
    uint64_t bc = BRReadStateWord(gTokBColor, BR_ST_BCOLOR);
    gBorderRGBA = bc ? (uint32_t)bc : 0x000000FF;
    gBorderColorObj = BRMakeColor(gBorderRGBA);
    uint64_t bci = BRReadStateWord(gTokBColorI, BR_ST_BCOLORI);
    gBorderInactiveRGBA = bci ? (uint32_t)bci : gBorderRGBA; // 0 ⇒ same as active
    gBorderInactiveObj = BRMakeColor(gBorderInactiveRGBA);

    // Per-edge / per-corner border overrides (transported via global defaults — small, infrequent).
    {
        static NSString * const edgeKeys[4]   = { @"top", @"right", @"bottom", @"left" };
        static NSString * const cornerKeys[4] = { @"tl", @"tr", @"br", @"bl" };
        for (int i = 0; i < 4; i++) {
            NSString *ek = [NSString stringWithFormat:@"com.tweak.brutalium.border.edge.%@", edgeKeys[i]];
            id ev = (id)CFBridgingRelease(CFPreferencesCopyValue((__bridge CFStringRef)ek,
                kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
            gBorderEdgeRGBA[i] = [ev isKindOfClass:[NSNumber class]] ? (uint32_t)[ev unsignedLongLongValue] : 0;
            NSString *eik = [NSString stringWithFormat:@"com.tweak.brutalium.border.edge.%@.image", edgeKeys[i]];
            id eiv = (id)CFBridgingRelease(CFPreferencesCopyValue((__bridge CFStringRef)eik,
                kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
            gBorderEdgeImageEnabled[i] = [eiv isKindOfClass:[NSNumber class]] && [eiv boolValue];

            NSString *ck = [NSString stringWithFormat:@"com.tweak.brutalium.border.corner.%@", cornerKeys[i]];
            id cv = (id)CFBridgingRelease(CFPreferencesCopyValue((__bridge CFStringRef)ck,
                kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
            gBorderCornerRGBA[i] = [cv isKindOfClass:[NSNumber class]] ? (uint32_t)[cv unsignedLongLongValue] : 0;
            NSString *cik = [NSString stringWithFormat:@"com.tweak.brutalium.border.corner.%@.image", cornerKeys[i]];
            id civ = (id)CFBridgingRelease(CFPreferencesCopyValue((__bridge CFStringRef)cik,
                kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
            gBorderCornerImageEnabled[i] = [civ isKindOfClass:[NSNumber class]] && [civ boolValue];
        }
    }

    uint64_t lf = BRReadStateWord(gTokLFlags, BR_ST_LFLAGS);
    bool lvalid = false, len = false, limg = false; double lrad = 0, lsz = 0;
    BRUnpackLFlags(lf, &lvalid, &len, &limg, &lrad, &lsz);
    if (lvalid) {
        gLEnabled = len; gLightsImageEnabled = limg; gLRadius = lrad; gLSize = lsz;
        uint64_t v = BRReadStateWord(gTokLClose, BR_ST_LCLOSE); gLCloseRGBA = (uint32_t)v;
        v = BRReadStateWord(gTokLMin, BR_ST_LMIN); gLMinRGBA  = (uint32_t)v;
        v = BRReadStateWord(gTokLZoom, BR_ST_LZOOM); gLZoomRGBA = (uint32_t)v;
        v = BRReadStateWord(gTokLGlyph, BR_ST_LGLYPH); gLGlyphRGBA = (uint32_t)v;
        uint64_t iv = BRReadStateWord(gTokLInact, BR_ST_LINACT);
        if (iv & BR_AUTO_STATE) gLInactiveAuto = YES;
        else { gLInactiveAuto = NO; gLInactiveRGBA = (uint32_t)iv; }
    } else {
        gLEnabled = YES; gLightsImageEnabled = NO; gLRadius = 0.0; gLSize = 0.0;
        gLCloseRGBA = 0xFF5F57FF; gLMinRGBA = 0xFEBC2EFF; gLZoomRGBA = 0x28C840FF;
        gLGlyphRGBA = 0x0000008C; gLInactiveAuto = YES; gLInactiveRGBA = 0x9B9B9BFF;
    }

    uint64_t tf = BRReadStateWord(gTokTFlags, BR_ST_TFLAGS);
    bool tvalid = false, ten = false, tctl = false, twp = false, tca = false, tta = false, tic = false; int tmode = BR_MODE_AUTO;
    BRUnpackTFlags(tf, &tvalid, &ten, &tmode, &tctl, &twp, &tca, &tta, &tic);
    if (tvalid) { gTintEnabled = ten; gTintMode = tmode; gTintControls = tctl; gTintWallpaper = twp; gTintChromeAuto = tca; gTintTextAuto = tta; gTintIcons = tic; }
    else        { gTintEnabled = NO;  gTintMode = BR_MODE_AUTO; gTintControls = YES; gTintWallpaper = NO; gTintChromeAuto = YES; gTintTextAuto = YES; gTintIcons = NO; }

    uint64_t tc = BRReadStateWord(gTokTColor, BR_ST_TCOLOR);
    gTintColorRGBA = tc ? (uint32_t)tc : 0x1E1E28FF;
    uint64_t tcc = BRReadStateWord(gTokTChrome, BR_ST_TCHROME);
    uint64_t ttx = BRReadStateWord(gTokTText, BR_ST_TTEXT);
    uint64_t tac = BRReadStateWord(gTokTAccent, BR_ST_TACCENT);

    // Backgrounds are solid: ignore alpha, force fully opaque.
    uint32_t mainOpaque = (gTintColorRGBA & 0xFFFFFF00) | 0xFF;
    gTintColorObj = BRMakeColor(mainOpaque);
    gTintChromeRGBA = (gTintChromeAuto || tcc == 0) ? BRDeriveChrome(mainOpaque)
                                                    : (((uint32_t)tcc & 0xFFFFFF00) | 0xFF);
    gTintChromeObj = BRMakeColor(gTintChromeRGBA);

    // Text: explicit override, else derive a legible contrast from the base.
    gTintTextRGBA = ttx ? (((uint32_t)ttx & 0xFFFFFF00) | 0xFF) : BRDeriveText(mainOpaque);
    gTintTextObj = BRMakeColor(gTintTextRGBA);
    // Accent: explicit override, else derive a vivid accent from the base (never nil ⇒ we own the
    // accent rather than deferring to the system, so selections/active controls follow the palette).
    gTintAccentObj = BRMakeColor(tac ? (((uint32_t)tac & 0xFFFFFF00) | 0xFF) : BRDeriveAccent(mainOpaque));
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
    BRGlassRefreshAll();
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

// Brutalium only styles GUI apps — broad injectors also load us into headless daemons/agents with
// no windows, which is pure waste. Decide from the executable path (dyld), not NSBundle, since
// mainBundle can be nil this early and wrongly excluded real apps like Dock/Chrome. GUI apps launch
// from <Bundle>.app/Contents/MacOS/…; daemons don't. Fail open on a read error, never skip a real app.
static BOOL BRIsGUIApp(void) {
    char buf[4096]; uint32_t sz = (uint32_t)sizeof(buf);
    if (_NSGetExecutablePath(buf, &sz) != 0) return YES;
    NSString *exe = [NSString stringWithUTF8String:buf] ?: @"";
    return [exe rangeOfString:@".app/Contents/"].location != NSNotFound;
}

static BOOL BRIsScreenshotProcess(NSString *bid) {
    if ([bid rangeOfString:@"screencapture" options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    if ([bid rangeOfString:@"screenshot"    options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    return NO;
}

__attribute__((constructor))
static void BRSetup(void) {
    if (BRIsChildProcess()) return;
    if (!BRIsGUIApp())      return;

    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        gTintExcluded = BRIsScreenshotProcess(bid);
        gTintIsWallpaperProc = [bid isEqualToString:@"com.apple.dock"] ||
            [bid rangeOfString:@"wallpaper" options:NSCaseInsensitiveSearch].location != NSNotFound;
    }

    notify_register_check(BR_ST_WIN,    &gTokWin);
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
    notify_register_check(BR_ST_TACCENT, &gTokTAccent);
    notify_register_check(BR_ST_BORDER, &gTokBorder);
    notify_register_check(BR_ST_BCOLOR, &gTokBColor);
    notify_register_check(BR_ST_BCOLORI, &gTokBColorI);
    notify_register_check(BR_ST_GLASS,   &gTokGlass);
    notify_register_check(BR_ST_TBAR,    &gTokTbar);
    BRRefreshConfig();

    // Arm every feature's swizzles — ONLY here, i.e. only in app processes.
    BRWindowsArm();
    BRLightsArm();
    BRTintArm();
    BRGlassArm();
    BRDockArm();   // inert everywhere except com.apple.dock

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
        BRDockForceRelayout();   // no-op outside com.apple.dock
    });

    dispatch_async(dispatch_get_main_queue(), ^{
        BRApplyAll(NO);
        BRDockForceRelayout();
    });
}
