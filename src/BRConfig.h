//
//  BRConfig.h — shared runtime config cache (filled by the core from notify
//  state) and the entry points each feature module exposes to the core.
//

#ifndef BRCONFIG_H
#define BRCONFIG_H

#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <string.h>

// Windows module config
extern BOOL     gMaster;        // master on/off for the whole tweak
extern BOOL     gCorners;       // square window corners
extern BOOL     gSquareMenus;   // square popup/context menus (opaque, shadowless, sharp)
extern BOOL     gSquareElements; // square text inputs, toggles, buttons, menu selection
extern BOOL     gMenuShadow;    // keep menu shadow when squaring (default: strip)
extern uint32_t gMenuSelectRGBA; // custom menu selection colour (0 = system default)
extern double   gElementsRadius; // radius for corners elements (0 = square)
extern double   gMenuRadius;     // radius for corners menus (0 = square)
extern BOOL     gToolbar;       // force expanded toolbar
extern BOOL     gSlimToolbar;   // reduce toolbar + button sizes
extern double   gSlimToolbarHeight; // target toolbar strip height (default 36, was 52)
extern double   gSlimRadius;    // glass capsule corner radius when slim is on (default 5)

// Dock flat background + corner radius (only ever active inside com.apple.dock)
extern BOOL     gDockFlat;
extern uint32_t gDockColorRGBA;
extern double   gDockRadius;
extern BOOL     gDockBorderEnabled;
extern uint32_t gDockBorderRGBA;
extern double   gDockBorderSize;

// Sidebar-specific tint + squaring (independent overrides of the general tint/elements settings)
extern BOOL     gSidebarTintEnabled;
extern uint32_t gSidebarTintRGBA;
extern BOOL     gSidebarTintAuto;      // "auto" = no override, follow general chrome tint
extern BOOL     gSidebarCornersEnabled;
extern double   gSidebarCornersRadius;

// Shared detection: is this view part of the sidebar — either the sidebar itself, something
// inside it, or something wrapping it?
// Two different sidebar implementations exist across macOS versions/apps:
//   - classic: an NSVisualEffectView with material == NSVisualEffectMaterialSidebar
//   - modern (Solarium): a glass-based container, e.g. Finder's TSidebarScrollView sitting
//     INSIDE NSContainerConcentricGlassEffectView — no NSVisualEffectView involved at all
// A caller might hand us either end of that relationship: a control inside the sidebar (needs an
// upward walk to find the sidebar container), or the glass container itself, which wraps the
// sidebar scroll view as a CHILD (needs a downward walk instead — walking up from the container
// would never find a class name that only exists further down the tree). So we check both
// directions: self, ancestors, and a shallow search of descendants.
static inline BOOL BRClassNameHasSidebar(NSView *v) {
    if (!v) return NO;
    if ([v respondsToSelector:@selector(material)] &&
        ((NSVisualEffectView *)v).material == NSVisualEffectMaterialSidebar)
        return YES;
    const char *cn = class_getName(object_getClass(v));
    return strstr(cn, "Sidebar") != NULL;
}
static inline BOOL BRSubtreeHasSidebar(NSView *v, int depthRemaining) {
    if (!v || depthRemaining < 0) return NO;
    if (BRClassNameHasSidebar(v)) return YES;
    for (NSView *sv in v.subviews) {
        if (BRSubtreeHasSidebar(sv, depthRemaining - 1)) return YES;
    }
    return NO;
}
static inline BOOL BRIsSidebarView(NSView *v) {
    NSView *cur = v;
    int depth = 0;
    while (cur && depth < 12) {
        if (BRClassNameHasSidebar(cur)) return YES;
        cur = cur.superview;
        depth++;
    }
    // not found going up — check a few levels down too (covers being handed the glass
    // container that WRAPS the sidebar, rather than the sidebar or something inside it)
    return BRSubtreeHasSidebar(v, 4);
}
static inline BOOL BRIsSidebarLayer(CALayer *layer) {
    if (layer.delegate && [(id)layer.delegate isKindOfClass:[NSView class]])
        return BRIsSidebarView((NSView *)layer.delegate);
    CALayer *parent = layer.superlayer;
    if (parent && parent.delegate && [(id)parent.delegate isKindOfClass:[NSView class]])
        return BRIsSidebarView((NSView *)parent.delegate);
    return NO;
}
extern double   gCornerRadius;  // 0 == fully square
extern BOOL     gSelfExcluded;  // this app is on the toolbar exclusion list
extern BOOL     gTintSelfExcluded;      // this app is on the tint exclusion list
extern BOOL     gSelfNoTitlebar;        // remove this app's titlebar entirely
extern BOOL     gBorderEnabled, gBorderShadow;
extern double   gBorderSize;            // border width in points (0 = none)
extern uint32_t gBorderRGBA, gBorderInactiveRGBA;
extern NSColor *gBorderColorObj;        // active-window border colour (cached)
extern NSColor *gBorderInactiveObj;     // inactive-window border colour (cached)

// Per-edge / per-corner overrides (0 RGBA = not set, use the uniform border colour above).
// Edge order: 0=top 1=right 2=bottom 3=left. Corner order: 0=TL 1=TR 2=BR 3=BL.
extern uint32_t gBorderEdgeRGBA[4];
extern BOOL     gBorderEdgeImageEnabled[4];
extern uint32_t gBorderCornerRGBA[4];
extern BOOL     gBorderCornerImageEnabled[4];

// Lights module config
extern BOOL     gLEnabled;
extern double   gLRadius, gLSize;
extern uint32_t gLCloseRGBA, gLMinRGBA, gLZoomRGBA, gLGlyphRGBA;
extern BOOL     gLInactiveAuto;
extern BOOL     gLightsImageEnabled;  // YES ⇒ paint buttons with light.* images
extern uint32_t gLInactiveRGBA;

// Tint module config
extern BOOL     gTintEnabled;
extern int      gTintMode;           // BR_MODE_*
extern BOOL     gTintControls;
extern BOOL     gTintWallpaper;
extern BOOL     gTintIsWallpaperProc; // Dock / WallpaperAgent (computed once)
extern BOOL     gTintExcluded;        // screenshot UI (computed once)
extern BOOL     gTintChromeAuto;
extern BOOL     gTintTextAuto;         // YES ⇒ text follows the appearance (don't override)
extern BOOL     gTintIcons;            // tint toolbar template-image icons with the text colour
extern uint32_t gTintColorRGBA, gTintChromeRGBA, gTintTextRGBA;
extern NSColor *gTintColorObj;        // main background (cached, opaque)
extern NSColor *gTintChromeObj;       // sidebar/titlebar/toolbar (cached, opaque)
extern NSColor *gTintTextObj;         // precise text/label colour (cached, opaque)
extern NSColor *gTintAccentObj;       // accent/selection (nil ⇒ auto: leave the system accent)

// Glass module config (de-glass NSGlassEffectView)
extern BOOL     gGlassFlatten;        // YES ⇒ flatten glass panels to an opaque fill
extern BOOL     gGlassColorAuto;      // YES ⇒ use windowBackgroundColor; NO ⇒ gGlassColorObj
extern BOOL     gGlassImageEnabled;   // YES ⇒ paint glass surfaces with the "glass" role image
extern uint32_t gGlassColorRGBA;      // fixed fill colour (when !auto)
extern NSColor *gGlassColorObj;       // cached fixed fill colour (nil ⇒ auto)
extern BOOL     gGlassSelfExcluded;   // this app is on the glass exclusion list

// Titlebar strip colour
extern BOOL     gTitlebarColorEnabled;
extern BOOL     gTitlebarImageEnabled;
extern uint32_t gTitlebarColorRGBA;
extern NSColor *gTitlebarColorObj;


// Effective gates (master AND the per-feature toggle).
static inline BOOL BRCornersActive(void) { return gMaster && gCorners; }
static inline BOOL BRSquareMenusActive(void) { return gMaster && gSquareMenus; }
static inline BOOL BRSquareElementsActive(void) { return gMaster && gSquareElements; }
static inline BOOL BRSlimToolbarActive(void) { return gMaster && gSlimToolbar; }
static inline CGFloat BRSlimPlatterHeight(void) {
    CGFloat h = (CGFloat)gSlimToolbarHeight - 8.0;   // same 8pt relationship as SlimBar (36-28=8)
    return h < 16.0 ? 16.0 : h;
}

static inline CGFloat BRMenuRadiusEffective(void) {
    return (gMenuRadius > 0.0) ? (CGFloat)gMenuRadius : (CGFloat)0.0;
}
static inline CGFloat BRElementsRadiusEffective(void) {
    return (gElementsRadius > 0.0) ? (CGFloat)gElementsRadius : (CGFloat)0.0;
}


// The value the 'corners layers' feature forces onto each CALayer. 0 keeps the historical
// imperceptible-but-nonzero radius (1e-7) that reads as square while defeating apps re-rounding;
// any configured value > 0 rounds every layer to that radius instead.
static inline BOOL BRToolbarActive(void) { return gMaster && gToolbar && !gSelfExcluded; }
static inline BOOL BRLightsActive(void)  { return gMaster && gLEnabled; }
static inline BOOL BRNoTitlebarActive(void) { return gMaster && gSelfNoTitlebar; }
static inline BOOL BRBorderActive(void)  { return gMaster && gBorderEnabled; }
// De-glass applies everywhere the feature is on, except apps on the glass exclude list.
static inline BOOL BRGlassActive(void) { return gMaster && gGlassFlatten && !gGlassSelfExcluded; }
// Titlebar strip colour applies to standard windows whenever enabled.
static inline BOOL BRTitlebarColorActive(void) { return gMaster && gTitlebarColorEnabled; }
// Tint stays out of the screenshot UI, and out of the wallpaper process unless opted in.
static inline BOOL BRTintActive(void) {
    return gMaster && gTintEnabled && !gTintExcluded && !gTintSelfExcluded &&
           (gTintWallpaper || !gTintIsWallpaperProc);
}

#pragma mark - Tint colour helpers

static inline NSColor *BRMakeColor(uint32_t v) {
    return [NSColor colorWithSRGBRed:((v >> 24) & 255) / 255.0
                               green:((v >> 16) & 255) / 255.0
                                blue:((v >> 8)  & 255) / 255.0
                               alpha: (v        & 255) / 255.0];
}
// Relative luminance (sRGB weights) → pick light vs dark base appearance.
static inline BOOL BRColorIsLight(uint32_t v) {
    double r = ((v >> 24) & 255) / 255.0, g = ((v >> 16) & 255) / 255.0, b = ((v >> 8) & 255) / 255.0;
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) > 0.5;
}
// Derive a chrome shade from the main colour: lighten dark / darken light.
static inline uint32_t BRDeriveChrome(uint32_t m) {
    double r = ((m >> 24) & 255), g = ((m >> 16) & 255), b = ((m >> 8) & 255);
    double lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
    double f = (lum > 0.5) ? -0.14 : 0.14;
    double nr, ng, nb;
    if (f > 0) { nr = r + (255 - r) * f; ng = g + (255 - g) * f; nb = b + (255 - b) * f; }
    else       { double k = 1.0 + f; nr = r * k; ng = g * k; nb = b * k; }
    uint32_t R = (uint32_t)(nr < 0 ? 0 : nr > 255 ? 255 : nr);
    uint32_t G = (uint32_t)(ng < 0 ? 0 : ng > 255 ? 255 : ng);
    uint32_t B = (uint32_t)(nb < 0 ? 0 : nb > 255 ? 255 : nb);
    return (R << 24) | (G << 16) | (B << 8) | 0xFF;
}
// Derive a legible text colour: light text on a dark base, dark text on a light base.
static inline uint32_t BRDeriveText(uint32_t m) {
    return BRColorIsLight(m) ? 0x1A1A1AFF : 0xE6E6E6FF;
}
// Derive a vivid accent from the base (same hue, high saturation/brightness). Grey bases get a
// default blue so selections still pop. Uses HSB via NSColor.
static inline uint32_t BRDeriveAccent(uint32_t m) {
    NSColor *c = [BRMakeColor(m) colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    CGFloat h = 0, s = 0, b = 0, a = 0;
    [c getHue:&h saturation:&s brightness:&b alpha:&a];
    if (s < 0.15) h = 0.60;                 // near-grey base → blue accent
    s = s < 0.65 ? 0.65 : s;
    b = 0.92;
    NSColor *acc = [[NSColor colorWithHue:h saturation:s brightness:b alpha:1.0]
                       colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    uint32_t R = (uint32_t)round(acc.redComponent   * 255);
    uint32_t G = (uint32_t)round(acc.greenComponent * 255);
    uint32_t B = (uint32_t)round(acc.blueComponent  * 255);
    return (R << 24) | (G << 16) | (B << 8) | 0xFF;
}

// Windows module (BRWindows.m)
void BRWindowsArm(void);                 // activate the swizzle group
void BRWindowsApply(NSWindow *w);        // apply corners + toolbar to one window
void BRWindowsApplyAll(void);

// Lights module (BRLights.m)
void BRLightsArm(void);                  // activate the swizzle group
void BRLightsInstallOnWindow(NSWindow *w, BOOL forceRedraw);
void BRLightsRefreshAll(BOOL forceRedraw);

// Tint module (BRTint.m)
void BRTintArm(void);                    // install NSColor + NSVisualEffectView overrides
void BRTintApply(NSWindow *w);           // appearance + opaque backdrop for one window
void BRTintRefreshAll(void);

// Glass module (BRGlass.m)
void BRGlassArm(void);                   // hook -[NSGlassEffectView layout]
void BRGlassRefreshAll(void);            // re-apply/restore across live windows

// Dock module (BRDock.m) — inert outside com.apple.dock
void BRDockArm(void);
void BRDockForceRelayout(void);
BOOL BRIsDockProcess(void);

// Titlebar module (BRTitlebar.m)
void BRTitlebarApplyColor(NSWindow *w);   // colour/image the titlebar strip (or restore) for one window

// Image registry (BRImages.m) — shared decoded images by role
void       BRImagesRefresh(void);         // reconcile the cache from the global-domain registry
CGImageRef BRImageForRole(NSString *role);// cached CGImage for a role, or NULL

#endif /* BRCONFIG_H */
