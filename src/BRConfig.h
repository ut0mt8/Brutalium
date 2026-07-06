//
//  BRConfig.h — shared runtime config cache (filled by the core from notify
//  state) and the entry points each feature module exposes to the core.
//

#ifndef BRCONFIG_H
#define BRCONFIG_H

#import <AppKit/AppKit.h>

// Windows module config
extern BOOL     gMaster;        // master on/off for the whole tweak
extern BOOL     gCorners;       // square window corners
extern BOOL     gSquareLayers;  // square EVERY CALayer's corners (app-wide, aggressive)
extern BOOL     gSquareToolbar; // square only toolbar-item corners (scoped)
extern BOOL     gToolbar;       // force expanded toolbar
extern double   gCornerRadius;  // 0 == fully square
extern BOOL     gSelfExcluded;  // this app is on the toolbar exclusion list
extern BOOL     gTintSelfExcluded;      // this app is on the tint exclusion list
extern BOOL     gSelfNoTitlebar;        // remove this app's titlebar entirely
extern BOOL     gBorderEnabled, gBorderShadow;
extern double   gBorderSize;            // border width in points (0 = none)
extern uint32_t gBorderRGBA, gBorderInactiveRGBA;
extern NSColor *gBorderColorObj;        // active-window border colour (cached)
extern NSColor *gBorderInactiveObj;     // inactive-window border colour (cached)

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

// Glass module config (de-glass NSGlassEffectView)
extern BOOL     gGlassFlatten;        // YES ⇒ flatten glass panels to an opaque fill
extern BOOL     gGlassColorAuto;      // YES ⇒ use windowBackgroundColor; NO ⇒ gGlassColorObj
extern BOOL     gGlassImageEnabled;   // YES ⇒ paint glass surfaces with the "glass" role image
extern uint32_t gGlassColorRGBA;      // fixed fill colour (when !auto)
extern NSColor *gGlassColorObj;       // cached fixed fill colour (nil ⇒ auto)
extern BOOL     gGlassSelfExcluded;   // this app is on the glass exclusion list

// Titlebar strip colour (custom-titlebar / window-manager feature)
extern BOOL     gTitlebarColorEnabled;
extern BOOL     gTitlebarImageEnabled;   // paint a background image instead of a flat colour
extern uint32_t gTitlebarColorRGBA;
extern NSColor *gTitlebarColorObj;    // cached fill colour for the titlebar strip

// Effective gates (master AND the per-feature toggle).
static inline BOOL BRCornersActive(void) { return gMaster && gCorners; }
static inline BOOL BRSquareLayersActive(void) { return gMaster && gSquareLayers; }
static inline BOOL BRSquareToolbarActive(void) { return gMaster && gSquareToolbar; }
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

// Titlebar module (BRTitlebar.m)
void BRTitlebarApplyColor(NSWindow *w);   // colour/image the titlebar strip (or restore) for one window

// Image registry (BRImages.m) — shared decoded images by role
void       BRImagesRefresh(void);         // reconcile the cache from the global-domain registry
CGImageRef BRImageForRole(NSString *role);// cached CGImage for a role, or NULL

#endif /* BRCONFIG_H */
