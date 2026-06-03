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
extern BOOL     gToolbar;       // force expanded toolbar
extern double   gCornerRadius;  // 0 == fully square
extern uint64_t gExcl0, gExcl1; // toolbar-exclusion bloom filter
extern BOOL     gSelfExcluded;  // this app is on the toolbar exclusion list

// Lights module config
extern BOOL     gLEnabled;
extern double   gLRadius, gLSize;
extern uint32_t gLCloseRGBA, gLMinRGBA, gLZoomRGBA, gLGlyphRGBA;
extern BOOL     gLInactiveAuto;
extern uint32_t gLInactiveRGBA;

// Effective gates (master AND the per-feature toggle).
static inline BOOL BRCornersActive(void) { return gMaster && gCorners; }
static inline BOOL BRToolbarActive(void) { return gMaster && gToolbar && !gSelfExcluded; }
static inline BOOL BRLightsActive(void)  { return gMaster && gLEnabled; }

// Windows module (BRWindows.m)
void BRWindowsArm(void);                 // activate the swizzle group
void BRWindowsApply(NSWindow *w);        // apply corners + toolbar to one window
void BRWindowsApplyAll(void);

// Lights module (BRLights.m)
void BRLightsArm(void);                  // activate the swizzle group
void BRLightsInstallOnWindow(NSWindow *w, BOOL forceRedraw);
void BRLightsRefreshAll(BOOL forceRedraw);

#endif /* BRCONFIG_H */
