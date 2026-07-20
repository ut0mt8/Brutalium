//
//  clitool.m — `brutalium` unified CLI (windows + lights + tint).
//

#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#import "BRState.h"
#import "BRThemes.h"
#import "BRTintThemes.h"

// Load an image file, downscale so its longest side is <= maxPx, re-encode as PNG, and
// return base64. Runs in the CLI (unsandboxed), so arbitrary paths are readable here; the
// small result travels to injected apps via the global-domain key. Returns nil on failure.
static NSString *BRImageFileToBase64PNG(NSString *path, int maxPx) {
    NSURL *url = [NSURL fileURLWithPath:path];
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!src) return nil;
    NSDictionary *opt = @{ (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                           (id)kCGImageSourceCreateThumbnailWithTransform:   @YES,
                           (id)kCGImageSourceThumbnailMaxPixelSize:          @(maxPx) };
    CGImageRef thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opt);
    CFRelease(src);
    if (!thumb) return nil;

    NSMutableData *png = [NSMutableData data];
    CGImageDestinationRef dst = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)png,
                                                                 CFSTR("public.png"), 1, NULL);
    if (!dst) { CGImageRelease(thumb); return nil; }
    CGImageDestinationAddImage(dst, thumb, NULL);
    bool ok = CGImageDestinationFinalize(dst);
    CFRelease(dst);
    CGImageRelease(thumb);
    if (!ok || png.length == 0) return nil;
    return [png base64EncodedStringWithOptions:0];
}

// Store (or clear) an image role in the shared `images` registry dict + remember its path.
static void BRSetImageRole(NSUserDefaults *d, NSString *role, NSString *b64OrNil, NSString *pathOrNil) {
    NSMutableDictionary *imgs  = [[d dictionaryForKey:@"images"]      mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *paths = [[d dictionaryForKey:@"images.paths"] mutableCopy] ?: [NSMutableDictionary dictionary];
    if (b64OrNil.length) { imgs[role] = b64OrNil; paths[role] = pathOrNil ?: @"(set)"; }
    else                 { [imgs removeObjectForKey:role]; [paths removeObjectForKey:role]; }
    [d setObject:imgs  forKey:@"images"];
    [d setObject:paths forKey:@"images.paths"];
}

static void usage(void) {
    fprintf(stderr,
        "Brutalium — square corners, expanded toolbar, square traffic lights, system tint\n"
        "\n"
        "Usage: brutalium <command>\n"
        "\n"
        "  on | off | toggle              Master enable\n"
        "\n"
        "  corners on | off               Square window corners\n"
        "  corners radius <value>         0 = fully square\n"
        "  corners layers on | off        Square EVERY layer's corners (aggressive)\n"
        "  corners layers radius <value>  Radius 'corners layers' applies (0 = square, default)\n"
        "  corners toolbar on | off       Square only toolbar-item corners (scoped)\n"
        "\n"
        "  toolbar on | off               Force expanded toolbar\n"
        "  toolbar exclude add <bundleid> Don't force toolbar for this app\n"
        "  toolbar exclude remove <bundleid>\n"
        "  toolbar exclude list\n"
        "\n"
        "  titlebar hide <bundleid>       Remove the titlebar entirely for this app\n"
        "  titlebar show <bundleid>       Stop removing it\n"
        "  titlebar list\n"
        "  titlebar color <#RRGGBB|off>   Colour the titlebar strip (leaves the toolbar alone)\n"
        "  titlebar image <path|off>      Use an image as the titlebar-strip background\n"
        "\n"
        "  border on | off                Draw a border on every window\n"
        "  border size <points>           Border width\n"
        "  border color <#RRGGBB|#RRGGBBAA>          Active-window border colour\n"
        "  border inactive <#RRGGBB|#RRGGBBAA|auto>  Inactive-window colour (auto = same as active)\n"
        "  border shadow on | off         Window drop shadow\n"
        "\n"
        "  lights on | off                Square the traffic-light buttons\n"
        "  lights radius <value>          Traffic-light corner radius\n"
        "  lights size <delta>            Adjust square size in points\n"
        "  lights color <slot> <value>    slot = close|min|zoom|inactive|glyph\n"
        "  lights image <close|min|zoom> <path|off>   Use an image per button (off = disable image mode)\n"
        "                                 value = #RRGGBB / #RRGGBBAA (inactive: auto)\n"
        "  lights theme <name> | list     Apply a colour preset\n"
        "\n"
        "  tint on | off                  Recolour the whole UI background\n"
        "  tint color <#RRGGBB>           Main background colour\n"
        "  tint chrome <#RRGGBB|auto>     Sidebar/titlebar/toolbar colour\n"
        "  tint text <#RRGGBB|auto>       Precise text colour (auto = follow appearance)\n"
        "  tint mode auto|light|dark|none Base appearance for controls/vibrancy\n"
        "  tint controls on | off         Also tint control backgrounds\n"
        "  tint icons on | off            Tint toolbar (template) icons with the text colour\n"
        "  tint wallpaper on | off        Also tint the desktop/wallpaper process\n"
        "  tint theme <name> | list       Apply a main+chrome preset\n"
        "  tint exclude add <bundleid>    Don't tint this app at all\n"
        "  tint exclude remove <bundleid>\n"
        "  tint exclude list\n"
        "\n"
        "  glass off|on                   Flatten Liquid Glass to an opaque panel (off = flatten)\n"
        "  glass color <#RRGGBB|auto>     Fill colour (auto = window background)\n"
        "  glass image <path|off>         Paint glass surfaces with an image (tileable texture reads best)\n"
        "  glass exclude add <bundleid>   Leave this app's glass alone\n"
        "  glass exclude remove <bundleid>\n"
        "  glass exclude list\n"
        "\n"
        "  status\n"
        "  publish\n");
}

static BOOL validColor(const char *slot, NSString *value) {
    if (strcmp(slot, "inactive") == 0 && [value caseInsensitiveCompare:@"auto"] == NSOrderedSame) return YES;
    uint32_t v; return BRHexToRGBA(value, &v);
}
static NSString *keyForSlot(const char *slot) {
    if (strcmp(slot, "close")    == 0) return @"lights.colorClose";
    if (strcmp(slot, "min")      == 0) return @"lights.colorMin";
    if (strcmp(slot, "zoom")     == 0) return @"lights.colorZoom";
    if (strcmp(slot, "inactive") == 0) return @"lights.colorInactive";
    if (strcmp(slot, "glyph")    == 0) return @"lights.colorGlyph";
    return nil;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) { usage(); return 1; }
        const char *cmd = argv[1];
        NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:BR_SUITE];

        // Seed defaults on first use.
        if (![d objectForKey:@"enabled"]) {
            [d setBool:YES forKey:@"enabled"];
            [d setBool:YES forKey:@"corners.enabled"];
            [d setFloat:0.0f forKey:@"corners.radius"];
            [d setBool:NO forKey:@"corners.layers"];
            [d setFloat:0.0f forKey:@"corners.layers.radius"];
            [d setBool:NO forKey:@"corners.toolbar"];
            [d setBool:YES forKey:@"toolbar.enabled"];
            [d setObject:@[] forKey:@"toolbar.exclude"];
            [d setBool:YES forKey:@"lights.enabled"];
            [d setFloat:0.0f forKey:@"lights.radius"];
            [d setFloat:0.0f forKey:@"lights.size"];
            [d setObject:@"#FF5F57" forKey:@"lights.colorClose"];
            [d setObject:@"#FEBC2E" forKey:@"lights.colorMin"];
            [d setObject:@"#28C840" forKey:@"lights.colorZoom"];
            [d setObject:@"auto"    forKey:@"lights.colorInactive"];
            [d setObject:@"#0000008C" forKey:@"lights.colorGlyph"];
            [d setObject:@"classic" forKey:@"lights.theme"];
            [d setBool:NO     forKey:@"tint.enabled"];
            [d setObject:@"#1E1E28" forKey:@"tint.color"];
            [d setObject:@"auto"    forKey:@"tint.chrome"];
            [d setObject:@"auto"    forKey:@"tint.text"];
            [d setObject:@"auto"    forKey:@"tint.mode"];
            [d setBool:YES    forKey:@"tint.controls"];
            [d setBool:NO     forKey:@"tint.icons"];
            [d setBool:NO     forKey:@"tint.wallpaper"];
            [d setObject:@"derive"  forKey:@"tint.theme"];
            [d setObject:@[]        forKey:@"tint.exclude"];
            [d setObject:@[]        forKey:@"titlebar.hide"];
            [d setBool:NO     forKey:@"border.enabled"];
            [d setFloat:1.0f  forKey:@"border.size"];
            [d setObject:@"#000000" forKey:@"border.color"];
            [d setBool:YES    forKey:@"border.shadow"];
            [d setBool:NO       forKey:@"glass.flatten"];
            [d setObject:@"auto" forKey:@"glass.color"];
            [d setObject:@[]     forKey:@"glass.exclude"];
            [d setBool:NO       forKey:@"titlebar.color.enabled"];
            [d setObject:@"#1E1E28" forKey:@"titlebar.color"];
            [d setBool:NO       forKey:@"titlebar.image.enabled"];
        }

        BOOL changed = YES;

        if (strcmp(cmd, "on") == 0)        [d setBool:YES forKey:@"enabled"];
        else if (strcmp(cmd, "off") == 0)  [d setBool:NO  forKey:@"enabled"];
        else if (strcmp(cmd, "toggle") == 0) [d setBool:![d boolForKey:@"enabled"] forKey:@"enabled"];

        else if (strcmp(cmd, "corners") == 0 && argc >= 3) {
            if (strcmp(argv[2], "radius") == 0 && argc >= 4) [d setFloat:(float)atof(argv[3]) forKey:@"corners.radius"];
            else if (strcmp(argv[2], "layers") == 0 && argc >= 4) {
                if (strcmp(argv[3], "radius") == 0 && argc >= 5)
                    [d setFloat:(float)atof(argv[4]) forKey:@"corners.layers.radius"];
                else
                    [d setBool:(strcmp(argv[3], "on") == 0) forKey:@"corners.layers"];
            }
            else if (strcmp(argv[2], "toolbar") == 0 && argc >= 4) [d setBool:(strcmp(argv[3], "on") == 0) forKey:@"corners.toolbar"];
            else [d setBool:(strcmp(argv[2], "on") == 0) forKey:@"corners.enabled"];
        }

        else if (strcmp(cmd, "toolbar") == 0 && argc >= 3) {
            if (strcmp(argv[2], "exclude") == 0) {
                NSMutableArray *list = [[d arrayForKey:@"toolbar.exclude"] mutableCopy] ?: [NSMutableArray array];
                if (argc >= 3 && strcmp(argv[2], "exclude") == 0 && argc >= 4 && strcmp(argv[3], "list") == 0) {
                    printf("Toolbar exclusions:\n");
                    if (list.count == 0) printf("  (none)\n");
                    for (NSString *b in list) printf("  %s\n", b.UTF8String);
                    return 0;
                }
                if (argc < 5) { fprintf(stderr, "error: toolbar exclude add|remove|list <bundleid>\n"); return 1; }
                NSString *bid = [NSString stringWithUTF8String:argv[4]];
                if (strcmp(argv[3], "add") == 0)         { if (![list containsObject:bid]) [list addObject:bid]; }
                else if (strcmp(argv[3], "remove") == 0) { [list removeObject:bid]; }
                else { fprintf(stderr, "error: toolbar exclude add|remove|list\n"); return 1; }
                [d setObject:list forKey:@"toolbar.exclude"];
            } else {
                [d setBool:(strcmp(argv[2], "on") == 0) forKey:@"toolbar.enabled"];
            }
        }

        else if (strcmp(cmd, "titlebar") == 0 && argc >= 3) {
            if (strcmp(argv[2], "color") == 0 && argc >= 4) {
                if (strcmp(argv[3], "off") == 0) {
                    [d setBool:NO forKey:@"titlebar.color.enabled"];
                } else {
                    NSString *val = [NSString stringWithUTF8String:argv[3]];
                    uint32_t v;
                    if (!BRHexToRGBA(val, &v)) { fprintf(stderr, "error: titlebar color must be #RRGGBB or off\n"); return 1; }
                    [d setBool:YES forKey:@"titlebar.color.enabled"];
                    [d setObject:val forKey:@"titlebar.color"];
                }
            } else if (strcmp(argv[2], "image") == 0 && argc >= 4) {
                if (strcmp(argv[3], "off") == 0) {
                    [d setBool:NO forKey:@"titlebar.image.enabled"];
                    BRSetImageRole(d, @"titlebar", nil, nil);
                } else {
                    NSString *path = [[NSString stringWithUTF8String:argv[3]] stringByExpandingTildeInPath];
                    NSString *b64 = BRImageFileToBase64PNG(path, 600);   // downscale + encode
                    if (!b64) { fprintf(stderr, "error: could not read/decode image at %s\n", path.UTF8String); return 1; }
                    BRSetImageRole(d, @"titlebar", b64, path);
                    [d setBool:YES forKey:@"titlebar.image.enabled"];
                    [d setBool:YES forKey:@"titlebar.color.enabled"];    // ensure the bar is inserted
                }
            } else {
                NSMutableArray *list = [[d arrayForKey:@"titlebar.hide"] mutableCopy] ?: [NSMutableArray array];
                if (strcmp(argv[2], "list") == 0) {
                    printf("Titlebar removed for:\n");
                    if (list.count == 0) printf("  (none)\n");
                    for (NSString *b in list) printf("  %s\n", b.UTF8String);
                    return 0;
                }
                if (argc < 4) { fprintf(stderr, "error: titlebar hide|show|list <bundleid>\n"); return 1; }
                NSString *bid = [NSString stringWithUTF8String:argv[3]];
                if (strcmp(argv[2], "hide") == 0)      { if (![list containsObject:bid]) [list addObject:bid]; }
                else if (strcmp(argv[2], "show") == 0) { [list removeObject:bid]; }
                else { fprintf(stderr, "error: titlebar hide|show|list <bundleid> | titlebar color <#RRGGBB|off>\n"); return 1; }
                [d setObject:list forKey:@"titlebar.hide"];
            }
        }

        else if (strcmp(cmd, "border") == 0 && argc >= 3) {
            if (strcmp(argv[2], "size") == 0 && argc >= 4) [d setFloat:(float)atof(argv[3]) forKey:@"border.size"];
            else if (strcmp(argv[2], "color") == 0 && argc >= 4) {
                NSString *val = [NSString stringWithUTF8String:argv[3]];
                uint32_t v;
                if (!BRHexToRGBA(val, &v)) { fprintf(stderr, "error: invalid colour '%s'\n", argv[3]); return 1; }
                [d setObject:val forKey:@"border.color"];
            }
            else if (strcmp(argv[2], "inactive") == 0 && argc >= 4) {
                NSString *val = [NSString stringWithUTF8String:argv[3]];
                if ([val caseInsensitiveCompare:@"auto"] == NSOrderedSame) {
                    [d removeObjectForKey:@"border.colorInactive"]; // fall back to active
                } else {
                    uint32_t v;
                    if (!BRHexToRGBA(val, &v)) { fprintf(stderr, "error: invalid colour '%s'\n", argv[3]); return 1; }
                    [d setObject:val forKey:@"border.colorInactive"];
                }
            }
            else if (strcmp(argv[2], "shadow") == 0 && argc >= 4) [d setBool:(strcmp(argv[3], "on") == 0) forKey:@"border.shadow"];
            else [d setBool:(strcmp(argv[2], "on") == 0) forKey:@"border.enabled"];
        }

        else if (strcmp(cmd, "lights") == 0 && argc >= 3) {
            const char *sub = argv[2];
            if (strcmp(sub, "on") == 0 || strcmp(sub, "off") == 0) {
                [d setBool:(strcmp(sub, "on") == 0) forKey:@"lights.enabled"];
            }
            else if (strcmp(sub, "radius") == 0 && argc >= 4) [d setFloat:(float)atof(argv[3]) forKey:@"lights.radius"];
            else if (strcmp(sub, "image") == 0 && argc >= 4) {
                if (strcmp(argv[3], "off") == 0) {
                    [d setBool:NO forKey:@"lights.image.enabled"];   // keep the images, just stop using them
                } else if (argc >= 5) {
                    NSString *btn = [NSString stringWithUTF8String:argv[3]];
                    NSString *role = [btn isEqualToString:@"close"] ? @"light.close"
                                   : [btn isEqualToString:@"min"]   ? @"light.min"
                                   : [btn isEqualToString:@"zoom"]  ? @"light.zoom" : nil;
                    if (!role) { fprintf(stderr, "error: button must be close, min, or zoom\n"); return 1; }
                    if (strcmp(argv[4], "off") == 0) {
                        BRSetImageRole(d, role, nil, nil);
                    } else {
                        NSString *path = [[NSString stringWithUTF8String:argv[4]] stringByExpandingTildeInPath];
                        NSString *b64 = BRImageFileToBase64PNG(path, 64);   // buttons are tiny; 64px is plenty
                        if (!b64) { fprintf(stderr, "error: could not read/decode image at %s\n", path.UTF8String); return 1; }
                        BRSetImageRole(d, role, b64, path);
                        [d setBool:YES forKey:@"lights.image.enabled"];
                    }
                } else { fprintf(stderr, "usage: lights image <close|min|zoom> <path|off>  |  lights image off\n"); return 1; }
            }
            else if (strcmp(sub, "size")   == 0 && argc >= 4) [d setFloat:(float)atof(argv[3]) forKey:@"lights.size"];
            else if (strcmp(sub, "color")  == 0 && argc >= 5) {
                NSString *key = keyForSlot(argv[3]);
                NSString *val = [NSString stringWithUTF8String:argv[4]];
                if (!key) { fprintf(stderr, "error: slot must be close|min|zoom|inactive|glyph\n"); return 1; }
                if (!validColor(argv[3], val)) { fprintf(stderr, "error: invalid colour '%s'\n", argv[4]); return 1; }
                [d setObject:val forKey:key];
                [d setObject:@"custom" forKey:@"lights.theme"];
            }
            else if (strcmp(sub, "theme") == 0) {
                if (argc >= 4 && strcmp(argv[3], "list") == 0) {
                    printf("Themes:\n");
                    for (int i = 0; i < kBRThemeCount; i++) printf("  %s\n", kBRThemes[i].name);
                    printf("  custom\n");
                    return 0;
                }
                if (argc < 4) { fprintf(stderr, "error: lights theme <name> (try: lights theme list)\n"); return 1; }
                const BRTheme *th = BRThemeNamed(argv[3]);
                if (!th) { fprintf(stderr, "error: unknown theme '%s'\n", argv[3]); return 1; }
                [d setObject:@(th->close)    forKey:@"lights.colorClose"];
                [d setObject:@(th->min)      forKey:@"lights.colorMin"];
                [d setObject:@(th->zoom)     forKey:@"lights.colorZoom"];
                [d setObject:@(th->inactive) forKey:@"lights.colorInactive"];
                [d setObject:@(th->glyph)    forKey:@"lights.colorGlyph"];
                [d setObject:@(th->name)     forKey:@"lights.theme"];
            }
            else { usage(); return 1; }
        }

        else if (strcmp(cmd, "tint") == 0 && argc >= 3) {
            const char *sub = argv[2];
            if (strcmp(sub, "exclude") == 0) {
                NSMutableArray *list = [[d arrayForKey:@"tint.exclude"] mutableCopy] ?: [NSMutableArray array];
                if (argc >= 4 && strcmp(argv[3], "list") == 0) {
                    printf("Tint exclusions:\n");
                    if (list.count == 0) printf("  (none)\n");
                    for (NSString *b in list) printf("  %s\n", b.UTF8String);
                    return 0;
                }
                if (argc < 5) { fprintf(stderr, "error: tint exclude add|remove|list <bundleid>\n"); return 1; }
                NSString *bid = [NSString stringWithUTF8String:argv[4]];
                if (strcmp(argv[3], "add") == 0)         { if (![list containsObject:bid]) [list addObject:bid]; }
                else if (strcmp(argv[3], "remove") == 0) { [list removeObject:bid]; }
                else { fprintf(stderr, "error: tint exclude add|remove|list\n"); return 1; }
                [d setObject:list forKey:@"tint.exclude"];
            }
            else if (strcmp(sub, "on") == 0 || strcmp(sub, "off") == 0) {
                [d setBool:(strcmp(sub, "on") == 0) forKey:@"tint.enabled"];
            }
            else if (strcmp(sub, "color") == 0 && argc >= 4) {
                NSString *val = [NSString stringWithUTF8String:argv[3]];
                uint32_t v;
                if (!BRHexToRGBA(val, &v)) { fprintf(stderr, "error: invalid colour '%s'\n", argv[3]); return 1; }
                [d setObject:val forKey:@"tint.color"];
                [d setObject:@"custom" forKey:@"tint.theme"];
            }
            else if (strcmp(sub, "chrome") == 0 && argc >= 4) {
                NSString *val = [NSString stringWithUTF8String:argv[3]];
                uint32_t v;
                if ([val caseInsensitiveCompare:@"auto"] != NSOrderedSame && !BRHexToRGBA(val, &v)) {
                    fprintf(stderr, "error: chrome must be #RRGGBB or auto\n"); return 1;
                }
                [d setObject:val forKey:@"tint.chrome"];
                [d setObject:@"custom" forKey:@"tint.theme"];
            }
            else if (strcmp(sub, "text") == 0 && argc >= 4) {
                NSString *val = [NSString stringWithUTF8String:argv[3]];
                uint32_t v;
                if ([val caseInsensitiveCompare:@"auto"] != NSOrderedSame && !BRHexToRGBA(val, &v)) {
                    fprintf(stderr, "error: text must be #RRGGBB or auto\n"); return 1;
                }
                [d setObject:val forKey:@"tint.text"];
                [d setObject:@"custom" forKey:@"tint.theme"];
            }
            else if (strcmp(sub, "mode") == 0 && argc >= 4) {
                NSString *m = [NSString stringWithUTF8String:argv[3]];
                if ([m caseInsensitiveCompare:@"auto"]  != NSOrderedSame &&
                    [m caseInsensitiveCompare:@"light"] != NSOrderedSame &&
                    [m caseInsensitiveCompare:@"dark"]  != NSOrderedSame &&
                    [m caseInsensitiveCompare:@"none"]  != NSOrderedSame) {
                    fprintf(stderr, "error: mode must be auto|light|dark|none\n"); return 1;
                }
                [d setObject:m.lowercaseString forKey:@"tint.mode"];
            }
            else if (strcmp(sub, "controls")  == 0 && argc >= 4) [d setBool:(strcmp(argv[3], "on") == 0) forKey:@"tint.controls"];
            else if (strcmp(sub, "icons")     == 0 && argc >= 4) [d setBool:(strcmp(argv[3], "on") == 0) forKey:@"tint.icons"];
            else if (strcmp(sub, "wallpaper") == 0 && argc >= 4) [d setBool:(strcmp(argv[3], "on") == 0) forKey:@"tint.wallpaper"];
            else if (strcmp(sub, "theme") == 0) {
                if (argc >= 4 && strcmp(argv[3], "list") == 0) {
                    printf("Tint themes:\n");
                    for (int i = 0; i < kBRTintThemeCount; i++) printf("  %s\n", kBRTintThemes[i].name);
                    printf("  custom\n");
                    return 0;
                }
                if (argc < 4) { fprintf(stderr, "error: tint theme <name> (try: tint theme list)\n"); return 1; }
                const BRTintTheme *th = BRTintThemeNamed(argv[3]);
                if (!th) { fprintf(stderr, "error: unknown theme '%s'\n", argv[3]); return 1; }
                [d setObject:@(th->color)  forKey:@"tint.color"];
                [d setObject:@(th->chrome) forKey:@"tint.chrome"];
                [d setObject:@(th->mode)   forKey:@"tint.mode"];
                [d setObject:@(th->name)   forKey:@"tint.theme"];
            }
            else { usage(); return 1; }
        }

        else if (strcmp(cmd, "glass") == 0 && argc >= 3) {
            const char *sub = argv[2];
            if (strcmp(sub, "off") == 0)      [d setBool:YES forKey:@"glass.flatten"]; // off = flatten
            else if (strcmp(sub, "on") == 0)  [d setBool:NO  forKey:@"glass.flatten"]; // on  = keep glass
            else if (strcmp(sub, "color") == 0 && argc >= 4) {
                NSString *val = [NSString stringWithUTF8String:argv[3]];
                if ([val caseInsensitiveCompare:@"auto"] == NSOrderedSame) {
                    [d setObject:@"auto" forKey:@"glass.color"];
                } else {
                    uint32_t v;
                    if (!BRHexToRGBA(val, &v)) { fprintf(stderr, "error: glass color must be #RRGGBB or auto\n"); return 1; }
                    [d setObject:val forKey:@"glass.color"];
                }
            }
            else if (strcmp(sub, "image") == 0 && argc >= 4) {
                if (strcmp(argv[3], "off") == 0) {
                    [d setBool:NO forKey:@"glass.image.enabled"];
                    BRSetImageRole(d, @"glass", nil, nil);
                } else {
                    NSString *path = [[NSString stringWithUTF8String:argv[3]] stringByExpandingTildeInPath];
                    NSString *b64 = BRImageFileToBase64PNG(path, 600);
                    if (!b64) { fprintf(stderr, "error: could not read/decode image at %s\n", path.UTF8String); return 1; }
                    BRSetImageRole(d, @"glass", b64, path);
                    [d setBool:YES forKey:@"glass.image.enabled"];
                    [d setBool:YES forKey:@"glass.flatten"];   // painting requires the glass to be flattened
                }
            }
            else if (strcmp(sub, "exclude") == 0) {
                NSMutableArray *list = [[d arrayForKey:@"glass.exclude"] mutableCopy] ?: [NSMutableArray array];
                if (argc >= 4 && strcmp(argv[3], "list") == 0) {
                    printf("Glass exclusions:\n");
                    if (list.count == 0) printf("  (none)\n");
                    for (NSString *b in list) printf("  %s\n", b.UTF8String);
                    return 0;
                }
                if (argc < 5) { fprintf(stderr, "error: glass exclude add|remove|list <bundleid>\n"); return 1; }
                NSString *bid = [NSString stringWithUTF8String:argv[4]];
                if (strcmp(argv[3], "add") == 0)         { if (![list containsObject:bid]) [list addObject:bid]; }
                else if (strcmp(argv[3], "remove") == 0) { [list removeObject:bid]; }
                else { fprintf(stderr, "error: glass exclude add|remove|list\n"); return 1; }
                [d setObject:list forKey:@"glass.exclude"];
            }
            else { usage(); return 1; }
        }

        else if (strcmp(cmd, "status") == 0) {
            changed = NO;
            NSArray *ex = [d arrayForKey:@"toolbar.exclude"];
            printf("Brutalium status:\n");
            printf("  master         : %s\n", [d boolForKey:@"enabled"] ? "on" : "off");
            printf("  corners        : %s  (radius %.1f%s)\n", [d boolForKey:@"corners.enabled"] ? "on" : "off",
                   [d floatForKey:@"corners.radius"], [d floatForKey:@"corners.radius"] == 0 ? " square" : "");
            printf("  corners layers : %s%s",
                   [d boolForKey:@"corners.layers"] ? "on" : "off",
                   [d boolForKey:@"corners.layers"] ? "" : "\n");
            if ([d boolForKey:@"corners.layers"]) {
                float lr = [d floatForKey:@"corners.layers.radius"];
                printf("  (radius %.1f%s)\n", lr, lr == 0 ? " square" : "");
            }
            printf("  corners toolbar: %s\n", [d boolForKey:@"corners.toolbar"] ? "on" : "off");
            printf("  toolbar        : %s\n", [d boolForKey:@"toolbar.enabled"] ? "on" : "off");
            printf("  toolbar excl.  : %s\n", ex.count ? [[ex componentsJoinedByString:@", "] UTF8String] : "(none)");
            printf("  titlebar hidden: %lu app(s)\n",
                   (unsigned long)([d arrayForKey:@"titlebar.hide"] ?: @[]).count);
            printf("  titlebar color : %s\n",
                   [d boolForKey:@"titlebar.color.enabled"]
                     ? [([d stringForKey:@"titlebar.color"] ?: @"#1E1E28") UTF8String] : "off");
            printf("  titlebar image : %s\n",
                   [d boolForKey:@"titlebar.image.enabled"]
                     ? [(([d dictionaryForKey:@"images.paths"][@"titlebar"]) ?: @"(set)") UTF8String] : "off");
            printf("  border         : %s  (size %.1f, color %s, inactive %s, shadow %s)\n",
                   [d boolForKey:@"border.enabled"] ? "on" : "off",
                   [d floatForKey:@"border.size"],
                   [([d stringForKey:@"border.color"] ?: @"-") UTF8String],
                   [([d stringForKey:@"border.colorInactive"] ?: @"(same)") UTF8String],
                   [d boolForKey:@"border.shadow"] ? "on" : "off");
            printf("  lights         : %s  (radius %.1f, size %+.1f, theme %s)\n",
                   [d boolForKey:@"lights.enabled"] ? "on" : "off",
                   [d floatForKey:@"lights.radius"], [d floatForKey:@"lights.size"],
                   [([d stringForKey:@"lights.theme"] ?: @"custom") UTF8String]);
            if ([d boolForKey:@"lights.image.enabled"]) {
                NSDictionary *ip = [d dictionaryForKey:@"images.paths"] ?: @{};
                printf("    images on: close=%s min=%s zoom=%s\n",
                       [((ip[@"light.close"]) ?: @"-") UTF8String],
                       [((ip[@"light.min"])   ?: @"-") UTF8String],
                       [((ip[@"light.zoom"])  ?: @"-") UTF8String]);
            }
            printf("    close=%s min=%s zoom=%s inactive=%s glyph=%s\n",
                   [([d stringForKey:@"lights.colorClose"] ?: @"-") UTF8String],
                   [([d stringForKey:@"lights.colorMin"] ?: @"-") UTF8String],
                   [([d stringForKey:@"lights.colorZoom"] ?: @"-") UTF8String],
                   [([d stringForKey:@"lights.colorInactive"] ?: @"-") UTF8String],
                   [([d stringForKey:@"lights.colorGlyph"] ?: @"-") UTF8String]);
            printf("  tint           : %s  (theme %s, mode %s)\n",
                   [d boolForKey:@"tint.enabled"] ? "on" : "off",
                   [([d stringForKey:@"tint.theme"] ?: @"custom") UTF8String],
                   [([d stringForKey:@"tint.mode"] ?: @"auto") UTF8String]);
            printf("    color=%s chrome=%s text=%s controls=%s icons=%s wallpaper=%s\n",
                   [([d stringForKey:@"tint.color"] ?: @"-") UTF8String],
                   [([d stringForKey:@"tint.chrome"] ?: @"-") UTF8String],
                   [([d stringForKey:@"tint.text"] ?: @"auto") UTF8String],
                   [d boolForKey:@"tint.controls"] ? "on" : "off",
                   [d boolForKey:@"tint.icons"] ? "on" : "off",
                   [d boolForKey:@"tint.wallpaper"] ? "on" : "off");
            printf("    excluded apps: %lu\n",
                   (unsigned long)([d arrayForKey:@"tint.exclude"] ?: @[]).count);
            printf("  glass          : %s  (fill %s, image %s, excl %lu)\n",
                   [d boolForKey:@"glass.flatten"] ? "off — flattened" : "on (default)",
                   [([d stringForKey:@"glass.color"] ?: @"auto") UTF8String],
                   [d boolForKey:@"glass.image.enabled"]
                     ? [(([d dictionaryForKey:@"images.paths"][@"glass"]) ?: @"(set)") UTF8String] : "off",
                   (unsigned long)([d arrayForKey:@"glass.exclude"] ?: @[]).count);
        }
        else if (strcmp(cmd, "publish") == 0) { changed = NO; BRPublishFromDefaults(d); printf("Published.\n"); }
        else { usage(); return 1; }

        if (changed) { [d synchronize]; BRPublishFromDefaults(d); }
    }
    return 0;
}
