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
#define BR_ST_LFLAGS  "com.tweak.brutalium.st.lflags"  // lights: enabled|radius|size
#define BR_ST_LCLOSE  "com.tweak.brutalium.st.lclose"  // 0xRRGGBBAA
#define BR_ST_LMIN    "com.tweak.brutalium.st.lmin"
#define BR_ST_LZOOM   "com.tweak.brutalium.st.lzoom"
#define BR_ST_LINACT  "com.tweak.brutalium.st.linact"  // RGBA, or BR_AUTO_STATE
#define BR_ST_LGLYPH  "com.tweak.brutalium.st.lglyph"

#define BR_SUITE      @"com.tweak.brutalium"
#define BR_AUTO_STATE (1ULL << 32)

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
    notify_post(BR_NOTIFY_CHANGED);
}

#endif /* BRSTATE_H */
