//
//  BRState.h — sandbox-safe configuration transport for Brutalium.
//
//  Carries config over Darwin notify state (readable by sandboxed apps). Covers
//  both feature areas: window corners/toolbar and the traffic-light buttons.
//

#ifndef BRSTATE_H
#define BRSTATE_H

#import <Foundation/Foundation.h>
#include <notify.h>
#include <math.h>

#define BR_NOTIFY_CHANGED "com.tweak.brutalium.prefs.changed"
#define BR_ST_WIN     "com.tweak.brutalium.st.win"     // master|corners|toolbar|radius
#define BR_ST_EXCL0   "com.tweak.brutalium.st.excl0"   // toolbar-exclusion bloom lo
#define BR_ST_EXCL1   "com.tweak.brutalium.st.excl1"   // toolbar-exclusion bloom hi
#define BR_ST_TEXCL0  "com.tweak.brutalium.st.texcl0"  // tint-exclusion bloom lo
#define BR_ST_TEXCL1  "com.tweak.brutalium.st.texcl1"  // tint-exclusion bloom hi
#define BR_ST_NTB0    "com.tweak.brutalium.st.ntb0"    // no-titlebar app bloom lo
#define BR_ST_NTB1    "com.tweak.brutalium.st.ntb1"    // no-titlebar app bloom hi
#define BR_ST_BORDER  "com.tweak.brutalium.st.border"  // window border: enabled|shadow|size
#define BR_ST_BCOLOR  "com.tweak.brutalium.st.bcolor"  // 0xRRGGBBAA border colour (active)
#define BR_ST_BCOLORI "com.tweak.brutalium.st.bcolori" // 0xRRGGBBAA border colour (inactive; 0 ⇒ use active)
#define BR_ST_LFLAGS  "com.tweak.brutalium.st.lflags"  // lights: enabled|radius|size
#define BR_ST_LCLOSE  "com.tweak.brutalium.st.lclose"  // 0xRRGGBBAA
#define BR_ST_LMIN    "com.tweak.brutalium.st.lmin"
#define BR_ST_LZOOM   "com.tweak.brutalium.st.lzoom"
#define BR_ST_LINACT  "com.tweak.brutalium.st.linact"  // RGBA, or BR_AUTO_STATE
#define BR_ST_LGLYPH  "com.tweak.brutalium.st.lglyph"
#define BR_ST_TFLAGS  "com.tweak.brutalium.st.tflags"   // tint: enabled|mode|controls|wallpaper|chromeAuto
#define BR_ST_TCOLOR  "com.tweak.brutalium.st.tcolor"   // 0xRRGGBBAA — main background
#define BR_ST_TCHROME "com.tweak.brutalium.st.tchrome"  // 0xRRGGBBAA — sidebar/titlebar/toolbar
#define BR_ST_TTEXT   "com.tweak.brutalium.st.ttext"    // 0xRRGGBBAA — precise text/label colour

#define BR_SUITE      @"com.tweak.brutalium"
#define BR_AUTO_STATE (1ULL << 32)

// Tint appearance mode.
enum { BR_MODE_AUTO = 0, BR_MODE_LIGHT = 1, BR_MODE_DARK = 2, BR_MODE_NONE = 3 };

#pragma mark - Window flags

// bit63 valid · bit0 master · bit1 corners · bit2 toolbar · bits 8..23 radius q8
static inline uint64_t BRPackWin(BOOL master, BOOL corners, BOOL toolbar, double radius) {
    uint64_t v = (1ULL << 63);
    if (master)  v |= 1ULL;
    if (corners) v |= 2ULL;
    if (toolbar) v |= 4ULL;
    uint16_t rq = (uint16_t)lround(fmax(0.0, radius) * 256.0);
    v |= ((uint64_t)rq) << 8;
    return v;
}
static inline void BRUnpackWin(uint64_t v, bool *valid, bool *master,
                               bool *corners, bool *toolbar, double *radius) {
    *valid = (v >> 63) & 1ULL; *master = v & 1ULL;
    *corners = (v >> 1) & 1ULL; *toolbar = (v >> 2) & 1ULL;
    *radius = (double)((v >> 8) & 0xFFFF) / 256.0;
}

// Window border: bit63 valid · bit0 enabled · bit1 shadow · bits 8..15 size (whole points)
static inline uint64_t BRPackBorder(BOOL enabled, BOOL shadow, double size) {
    uint64_t v = (1ULL << 63);
    if (enabled) v |= 1ULL;
    if (shadow)  v |= 2ULL;
    long pts = lround(fmax(0.0, fmin(255.0, size)));
    v |= ((uint64_t)(pts & 0xFF)) << 8;
    return v;
}
static inline void BRUnpackBorder(uint64_t v, bool *valid, bool *enabled, bool *shadow, double *size) {
    *valid = (v >> 63) & 1ULL;
    *enabled = v & 1ULL;
    *shadow = (v >> 1) & 1ULL;
    *size = (double)((v >> 8) & 0xFF);
}

#pragma mark - Lights flags

// bit63 valid · bit0 enabled · bits 1..16 radius q8 · bits 17..32 size signed q8
static inline uint64_t BRPackLFlags(BOOL enabled, double radius, double size) {
    uint64_t v = (1ULL << 63);
    if (enabled) v |= 1ULL;
    uint16_t rq = (uint16_t)lround(fmax(0.0, radius) * 256.0);
    int16_t  sq = (int16_t)lround(size * 256.0);
    v |= ((uint64_t)rq) << 1;
    v |= ((uint64_t)(uint16_t)sq) << 17;
    return v;
}
static inline void BRUnpackLFlags(uint64_t v, bool *valid, bool *enabled,
                                  double *radius, double *size) {
    *valid = (v >> 63) & 1ULL; *enabled = v & 1ULL;
    uint16_t rq = (uint16_t)((v >> 1) & 0xFFFF);
    int16_t  sq = (int16_t)((v >> 17) & 0xFFFF);
    *radius = rq / 256.0; *size = sq / 256.0;
}

#pragma mark - Tint flags

// bit63 valid · bit0 enabled · bits 1..2 mode · bit3 controls · bit4 wallpaper · bit5 chromeAuto · bit6 textAuto · bit7 icons
static inline uint64_t BRPackTFlags(BOOL enabled, int mode, BOOL controls, BOOL wallpaper, BOOL chromeAuto, BOOL textAuto, BOOL icons) {
    uint64_t v = (1ULL << 63);
    if (enabled)    v |= 1ULL;
    v |= ((uint64_t)(mode & 0x3)) << 1;
    if (controls)   v |= (1ULL << 3);
    if (wallpaper)  v |= (1ULL << 4);
    if (chromeAuto) v |= (1ULL << 5);
    if (textAuto)   v |= (1ULL << 6);
    if (icons)      v |= (1ULL << 7);
    return v;
}
static inline void BRUnpackTFlags(uint64_t v, bool *valid, bool *enabled, int *mode,
                                  bool *controls, bool *wallpaper, bool *chromeAuto, bool *textAuto, bool *icons) {
    *valid = (v >> 63) & 1ULL;
    *enabled = v & 1ULL;
    *mode = (int)((v >> 1) & 0x3);
    *controls = (v >> 3) & 1ULL;
    *wallpaper = (v >> 4) & 1ULL;
    *chromeAuto = (v >> 5) & 1ULL;
    *textAuto = (v >> 6) & 1ULL;
    *icons = (v >> 7) & 1ULL;
}

static inline int BRModeFromString(NSString *s) {
    if ([s caseInsensitiveCompare:@"light"] == NSOrderedSame) return BR_MODE_LIGHT;
    if ([s caseInsensitiveCompare:@"dark"]  == NSOrderedSame) return BR_MODE_DARK;
    if ([s caseInsensitiveCompare:@"none"]  == NSOrderedSame) return BR_MODE_NONE;
    return BR_MODE_AUTO;
}

#pragma mark - Hex + Bloom

static inline BOOL BRHexToRGBA(NSString *s, uint32_t *out) {
    if (![s isKindOfClass:[NSString class]]) return NO;
    NSString *c = [[s stringByReplacingOccurrencesOfString:@"#" withString:@""] uppercaseString];
    NSUInteger n = c.length;
    if (n != 6 && n != 8) return NO;
    unsigned comp[4] = {0, 0, 0, 255};
    for (NSUInteger i = 0; i < n / 2; i++) {
        unsigned v = 0;
        NSScanner *sc = [NSScanner scannerWithString:[c substringWithRange:NSMakeRange(i * 2, 2)]];
        if (![sc scanHexInt:&v]) return NO;
        comp[i] = v;
    }
    *out = ((uint32_t)comp[0] << 24) | ((uint32_t)comp[1] << 16) |
           ((uint32_t)comp[2] << 8)  |  (uint32_t)comp[3];
    return YES;
}

static inline uint64_t br_fnv(const char *s, uint64_t seed) {
    uint64_t h = 1469598103934665603ULL ^ seed;
    while (*s) { h ^= (unsigned char)*s++; h *= 1099511628211ULL; }
    return h;
}
static inline void br_indices(const char *s, unsigned idx[3]) {
    uint64_t h1 = br_fnv(s, 0), h2 = br_fnv(s, 0x9E3779B97F4A7C15ULL);
    idx[0] = (unsigned)(h1 % 128); idx[1] = (unsigned)((h1 >> 32) % 128); idx[2] = (unsigned)(h2 % 128);
}
static inline void BRBloomAdd(const char *s, uint64_t *lo, uint64_t *hi) {
    if (!s || !*s) return;
    unsigned idx[3]; br_indices(s, idx);
    for (int i = 0; i < 3; i++) { unsigned b = idx[i]; if (b < 64) *lo |= (1ULL << b); else *hi |= (1ULL << (b - 64)); }
}
static inline BOOL BRBloomTest(const char *s, uint64_t lo, uint64_t hi) {
    if (!s || !*s) return NO;
    unsigned idx[3]; br_indices(s, idx);
    for (int i = 0; i < 3; i++) {
        unsigned b = idx[i];
        BOOL set = (b < 64) ? ((lo >> b) & 1ULL) : ((hi >> (b - 64)) & 1ULL);
        if (!set) return NO;
    }
    return YES;
}

#pragma mark - Publishing

static inline void BRSetState(const char *name, uint64_t val) {
    int t;
    if (notify_register_check(name, &t) == NOTIFY_STATUS_OK) { notify_set_state(t, val); notify_cancel(t); }
}

static inline uint32_t br_defColor(NSUserDefaults *d, NSString *key, uint32_t fallback) {
    uint32_t v;
    return BRHexToRGBA([d stringForKey:key], &v) ? v : fallback;
}

static inline void BRPublishFromDefaults(NSUserDefaults *d) {
    BOOL master  = [d objectForKey:@"enabled"]         ? [d boolForKey:@"enabled"]         : YES;
    BOOL corners = [d objectForKey:@"corners.enabled"] ? [d boolForKey:@"corners.enabled"] : YES;
    BOOL toolbar = [d objectForKey:@"toolbar.enabled"] ? [d boolForKey:@"toolbar.enabled"] : YES;
    double cradius = [d floatForKey:@"corners.radius"];

    uint64_t lo = 0, hi = 0;
    NSArray *excl = [d arrayForKey:@"toolbar.exclude"];
    if ([excl isKindOfClass:[NSArray class]]) {
        for (id b in excl) if ([b isKindOfClass:[NSString class]]) BRBloomAdd([b UTF8String], &lo, &hi);
    }

    BOOL lenabled = [d objectForKey:@"lights.enabled"] ? [d boolForKey:@"lights.enabled"] : YES;
    double lradius = [d floatForKey:@"lights.radius"];
    double lsize   = [d floatForKey:@"lights.size"];

    uint32_t close = br_defColor(d, @"lights.colorClose", 0xFF5F57FF);
    uint32_t mn    = br_defColor(d, @"lights.colorMin",   0xFEBC2EFF);
    uint32_t zoom  = br_defColor(d, @"lights.colorZoom",  0x28C840FF);
    uint32_t glyph = br_defColor(d, @"lights.colorGlyph", 0x0000008C);

    uint64_t inact;
    NSString *ia = [d stringForKey:@"lights.colorInactive"];
    uint32_t iv;
    if (!ia || [ia caseInsensitiveCompare:@"auto"] == NSOrderedSame) inact = BR_AUTO_STATE;
    else if (BRHexToRGBA(ia, &iv))                                   inact = iv;
    else                                                             inact = BR_AUTO_STATE;

    BRSetState(BR_ST_WIN,    BRPackWin(master, corners, toolbar, cradius));
    BRSetState(BR_ST_EXCL0,  lo);
    BRSetState(BR_ST_EXCL1,  hi);
    BRSetState(BR_ST_LFLAGS, BRPackLFlags(lenabled, lradius, lsize));
    BRSetState(BR_ST_LCLOSE, close);
    BRSetState(BR_ST_LMIN,   mn);
    BRSetState(BR_ST_LZOOM,  zoom);
    BRSetState(BR_ST_LINACT, inact);
    BRSetState(BR_ST_LGLYPH, glyph);

    // Tint
    BOOL tEnabled  = [d objectForKey:@"tint.enabled"]  ? [d boolForKey:@"tint.enabled"]  : NO;
    int  tMode     = BRModeFromString([d stringForKey:@"tint.mode"] ?: @"auto");
    BOOL tControls = [d objectForKey:@"tint.controls"] ? [d boolForKey:@"tint.controls"] : YES;
    BOOL tWall     = [d objectForKey:@"tint.wallpaper"]? [d boolForKey:@"tint.wallpaper"]: NO;

    NSString *chromeStr = [d stringForKey:@"tint.chrome"] ?: @"auto";
    BOOL tChromeAuto = [chromeStr caseInsensitiveCompare:@"auto"] == NSOrderedSame;

    NSString *textStr = [d stringForKey:@"tint.text"] ?: @"auto";
    BOOL tTextAuto = [textStr caseInsensitiveCompare:@"auto"] == NSOrderedSame;
    BOOL tIcons = [d objectForKey:@"tint.icons"] ? [d boolForKey:@"tint.icons"] : NO;

    uint32_t tColor, tChrome = 0, tText = 0xE6E6E6FF;
    if (!BRHexToRGBA([d stringForKey:@"tint.color"], &tColor)) tColor = 0x1E1E28FF; // deep slate
    if (!tChromeAuto && !BRHexToRGBA(chromeStr, &tChrome))     tChrome = 0x2C2C3CFF;
    if (!tTextAuto)   BRHexToRGBA(textStr, &tText);            // keep default if malformed

    BRSetState(BR_ST_TFLAGS,  BRPackTFlags(tEnabled, tMode, tControls, tWall, tChromeAuto, tTextAuto, tIcons));
    BRSetState(BR_ST_TCOLOR,  tColor);
    BRSetState(BR_ST_TCHROME, tChrome); // 0 + chromeAuto flag ⇒ derive in the dylib
    BRSetState(BR_ST_TTEXT,   tText);   // applied only when textAuto is off

    uint64_t telo = 0, tehi = 0;
    NSArray *texcl = [d arrayForKey:@"tint.exclude"];
    if ([texcl isKindOfClass:[NSArray class]])
        for (id b in texcl) if ([b isKindOfClass:[NSString class]]) BRBloomAdd([b UTF8String], &telo, &tehi);
    BRSetState(BR_ST_TEXCL0, telo);
    BRSetState(BR_ST_TEXCL1, tehi);

    uint64_t ntlo = 0, nthi = 0;
    NSArray *ntb = [d arrayForKey:@"titlebar.hide"];
    if ([ntb isKindOfClass:[NSArray class]])
        for (id b in ntb) if ([b isKindOfClass:[NSString class]]) BRBloomAdd([b UTF8String], &ntlo, &nthi);
    BRSetState(BR_ST_NTB0, ntlo);
    BRSetState(BR_ST_NTB1, nthi);

    BOOL bEnabled = [d objectForKey:@"border.enabled"] ? [d boolForKey:@"border.enabled"] : NO;
    BOOL bShadow  = [d objectForKey:@"border.shadow"]  ? [d boolForKey:@"border.shadow"]  : YES;
    double bSize  = [d objectForKey:@"border.size"]    ? [d doubleForKey:@"border.size"]   : 1.0;
    uint32_t bColor;
    if (!BRHexToRGBA([d stringForKey:@"border.color"], &bColor)) bColor = 0x000000FF; // black
    BRSetState(BR_ST_BORDER, BRPackBorder(bEnabled, bShadow, bSize));
    BRSetState(BR_ST_BCOLOR, bColor);
    uint32_t bColorI = 0; // 0 ⇒ dylib falls back to the active colour
    NSString *biStr = [d stringForKey:@"border.colorInactive"];
    if (biStr) BRHexToRGBA(biStr, &bColorI);
    BRSetState(BR_ST_BCOLORI, bColorI);
    notify_post(BR_NOTIFY_CHANGED);
}

#endif /* BRSTATE_H */
