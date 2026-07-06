//
//  BRTitlebar.m — colour the titlebar strip (custom-titlebar / window-manager feature).
//
//  From probing: the titlebar background is glass; the title + traffic-light widgets are
//  the frontmost subviews of NSTitlebarView, and a bottom titlebar accessory (toolbar /
//  format bar) occupies the lower part. We insert an opaque BRBar into NSTitlebarView
//  BELOW the title field — in front of every backdrop/glass view, behind the controls —
//  sized to just the STRIP above any accessory, so the toolbar keeps its own look. BRBar
//  is a window-drag region. Applied per-window from BRWindowsApply; removed when disabled.
//

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "BRConfig.h"

@interface BRBar : NSView @end
@implementation BRBar
- (BOOL)mouseDownCanMoveWindow { return YES; }   // drag the whole bar to move the window
- (BOOL)isOpaque { return YES; }
- (BOOL)allowsVibrancy { return NO; }             // literal colour — don't blend with the vibrant titlebar
@end



static NSView *FindByClass(NSView *v, const char *exact) {
    for (NSView *s in v.subviews) { const char *n = class_getName([s class]); if (n && strcmp(n, exact) == 0) return s; }
    return nil;
}
static NSView *FindContaining(NSView *v, const char *needle) {
    for (NSView *s in v.subviews) { const char *n = class_getName([s class]); if (n && strstr(n, needle)) return s; }
    return nil;
}
static NSView *FindDeep(NSView *v, const char *needle) {
    for (NSView *s in v.subviews) {
        const char *n = class_getName([s class]);
        if (n && strstr(n, needle)) return s;
        NSView *r = FindDeep(s, needle);
        if (r) return r;
    }
    return nil;
}

// Strip = just the title row (traffic lights + title), not the toolbar/format bar below.
// Derive it from the traffic-light row, which exists in BOTH Solarium and classic (Solarium
// off) rendering: the lights are vertically centred in the title row, so the gap above them
// mirrors to the gap below, giving the row height without depending on how the toolbar is
// built. Falls back to any titlebar accessory, then to the full titlebar.
static NSRect BRStripRect(NSWindow *w, NSView *titlebar) {
    NSRect strip = titlebar.bounds;
    CGFloat H = NSHeight(strip);

    NSButton *btn = [w standardWindowButton:NSWindowCloseButton] ?: [w standardWindowButton:NSWindowZoomButton];
    if (btn && btn.superview) {
        NSRect r = [btn convertRect:btn.bounds toView:titlebar];
        CGFloat above  = H - NSMaxY(r);          // gap from the lights' top to the titlebar top
        CGFloat bottom = NSMinY(r) - above;      // mirror it below → title-row bottom edge
        if (bottom > 0.5 && bottom < H) { strip.origin.y = bottom; strip.size.height = H - bottom; return strip; }
    }

    NSView *acc = FindDeep(titlebar, "AccessoryClipView");   // fallback: exclude a Solarium accessory
    if (acc && !acc.isHidden && acc.frame.size.height > 0.0) {
        NSRect r = [acc convertRect:acc.bounds toView:titlebar];
        CGFloat top = NSMaxY(r);
        if (top > 0.0 && top < H) { strip.origin.y = top; strip.size.height = H - top; }
    }
    return strip;
}

void BRTitlebarApplyColor(NSWindow *w) {
    if (!w) return;
    NSView *frame = w.contentView.superview;
    if (!frame) return;
    const char *fn = class_getName([frame class]);
    if (!fn || !strstr(fn, "ThemeFrame")) return;               // standard windows only

    NSView *container = FindContaining(frame, "TitlebarContainer");
    if (!container) return;
    NSView *titlebar = FindByClass(container, "NSTitlebarView");
    if (!titlebar) return;

    static const void *kBar = &kBar;
    BRBar *bar = objc_getAssociatedObject(titlebar, kBar);

    if (!BRTitlebarColorActive()) {                             // disabled → restore
        if (bar) { [bar removeFromSuperview]; objc_setAssociatedObject(titlebar, kBar, nil, OBJC_ASSOCIATION_RETAIN); }
        return;
    }

    NSRect strip = BRStripRect(w, titlebar);
    if (!bar) {
        bar = [[BRBar alloc] initWithFrame:strip];
        bar.wantsLayer = YES;
        bar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;   // full width, pinned to top strip
        NSView *title = FindByClass(titlebar, "NSTextField");           // in front of all backdrops
        if (title) [titlebar addSubview:bar positioned:NSWindowBelow relativeTo:title];
        else {
            NSView *bg = FindContaining(titlebar, "TitlebarBackground");
            if (bg) [titlebar addSubview:bar positioned:NSWindowAbove relativeTo:bg];
            else    [titlebar addSubview:bar positioned:NSWindowBelow relativeTo:nil];
        }
        objc_setAssociatedObject(titlebar, kBar, bar, OBJC_ASSOCIATION_RETAIN);
    }
    bar.frame = strip;
    CGImageRef tbimg = BRImageForRole(@"titlebar");
    if (gTitlebarImageEnabled && tbimg) {
        bar.layer.contents = (__bridge id)tbimg;
        bar.layer.contentsGravity = kCAGravityResizeAspectFill;   // fill the strip, crop overflow
        bar.layer.contentsScale = w.backingScaleFactor > 0.0 ? w.backingScaleFactor : 2.0;
        bar.layer.masksToBounds = YES;
        bar.layer.backgroundColor = gTitlebarColorObj.CGColor;     // shows through any transparency
    } else {
        bar.layer.contents = nil;
        bar.layer.backgroundColor = gTitlebarColorObj.CGColor;
    }
}
