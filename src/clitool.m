//
//  clitool.m — `brutalium` unified CLI (windows + lights + tint).
//

#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#import "BRState.h"
#import "BRThemes.h"
#import "BRTintThemes.h"

// Validate an on/off argument. Returns 0 (off) or 1 (on), or -1 on error.
static int parseOnOff(const char *val) {
    if (strcmp(val, "on") == 0 || strcmp(val, "ON") == 0 || strcmp(val, "1") == 0 || strcmp(val, "yes") == 0) return 1;
    if (strcmp(val, "off") == 0 || strcmp(val, "OFF") == 0 || strcmp(val, "0") == 0 || strcmp(val, "no") == 0) return 0;
    fprintf(stderr, "error: expected 'on' or 'off', got '%s'\n", val);
    return -1;
}
// Macro: parse on/off and return 1 on error (so mistyped values don't silently disable features).
#define PARSE_ONOFF(val, out) do { int _r = parseOnOff(val); if (_r < 0) return 1; out = _r; } while(0)

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
        "Brutalium — window styling tweak for macOS Tahoe/Golden Gate\n"
        "\n"
        "Usage: brutalium <group> <command> [args]\n"
        "\n"
        "general:\n"
        "  on | off | toggle\n"
        "  status\n"
        "  publish\n"
        "  reset                         restore every setting to its default\n"
        "\n"
        "window:\n"
        "  window corners on | off\n"
        "  window corners radius <value>\n"
        "  window border on | off\n"
        "  window border size <points>\n"
        "  window border color <#RRGGBB>\n"
        "  window border inactive <#RRGGBB|auto>\n"
        "  window border shadow on | off\n"
        "  window border edge <top|right|bottom|left> color <#RRGGBB|off>\n"
        "  window border edge <top|right|bottom|left> image <path|off>\n"
        "  window border corner <tl|tr|br|bl> color <#RRGGBB|off>\n"
        "  window border corner <tl|tr|br|bl> image <path|off>\n"
        "\n"
        "elements:\n"
        "  elements on | off\n"
        "  elements radius <value>\n"
        "\n"
        "menus:\n"
        "  menus on | off\n"
        "  menus radius <value>\n"
        "  menus shadow on | off\n"
        "  menus selectcolor <#RRGGBB|off>\n"
        "\n"
        "toolbar:\n"
        "  toolbar on | off               force expanded toolbar\n"
        "  toolbar slim on | off          reduce toolbar + button sizes\n"
        "  toolbar slim height <value>    target toolbar strip height (default 36, was 52)\n"
        "  toolbar slim radius <value>    glass capsule corner radius (default 5)\n"
        "  toolbar exclude add | remove | list <bundleid>\n"
        "\n"
        "titlebar:\n"
        "  titlebar hide | show <bundleid>\n"
        "  titlebar list\n"
        "  titlebar color <#RRGGBB|off>   colour the titlebar strip\n"
        "  titlebar image <path|off>\n"
        "\n"
        "sidebar:\n"
        "  sidebar tint on | off         override the sidebar's own colour (else follows tint chrome)\n"
        "  sidebar tint color <#RRGGBB|auto>\n"
        "  sidebar corners on | off      square the sidebar independently of corners elements\n"
        "  sidebar corners radius <value>\n"
        "\n"
        "lights:\n"
        "  lights on | off\n"
        "  lights radius <value>\n"
        "  lights size <delta>\n"
        "  lights color <close|min|zoom|inactive|glyph> <#RRGGBB>\n"
        "  lights image <close|min|zoom> <path|off>\n"
        "  lights theme <name> | list\n"
        "\n"
        "tint:\n"
        "  tint on | off\n"
        "  tint color <#RRGGBB>\n"
        "  tint chrome | text | accent <#RRGGBB|auto>\n"
        "  tint mode auto | light | dark | none\n"
        "  tint controls | icons | wallpaper on | off\n"
        "  tint theme <name> | list\n"
        "  tint exclude add | remove | list <bundleid>\n"
        "\n"
        "glass:\n"
        "  glass on | off\n"
        "  glass color <#RRGGBB|auto>\n"
        "  glass image <path|off>\n"
        "  glass exclude add | remove | list <bundleid>\n"
        "\n"
        "dock:\n"
        "  dock on | off                 flat background behind Dock icons (only in com.apple.dock)\n"
        "  dock color <#RRGGBB>          background colour (default #1C1C1E)\n"
        "  dock radius <value>           corner radius, 0 = square (default 0)\n"
        "  dock border on | off          border around the flat background\n"
        "  dock border color <#RRGGBB>   border colour (default #FFFFFF)\n"
        "  dock border size <value>      border width in points (default 1)\n"
        "\n"
        "debug:\n"
        "  debug tree on | off\n"
        "\n"
        "config:\n"
        "  config export [path]           export settings to plist\n"
        "  config import <path>           import settings from plist\n"
        "\n");
}

// Seed / reset every setting to its default. Shared by first-use seeding and `brutalium reset`.
static void BRSeedDefaults(NSUserDefaults *d) {
    [d setBool:NO forKey:@"enabled"];
    [d setBool:NO forKey:@"corners.enabled"];
    [d setFloat:0.0f forKey:@"corners.radius"];
    [d setBool:NO forKey:@"corners.menus"];
    [d setFloat:0.0f forKey:@"corners.menus.radius"];
    [d setBool:NO forKey:@"corners.elements"];
    for (NSString *edge in @[@"top", @"right", @"bottom", @"left"]) {
        [d setObject:@0 forKey:[NSString stringWithFormat:@"border.edge.%@", edge]];
        [d setBool:NO forKey:[NSString stringWithFormat:@"border.edge.%@.image", edge]];
    }
    for (NSString *corner in @[@"tl", @"tr", @"br", @"bl"]) {
        [d setObject:@0 forKey:[NSString stringWithFormat:@"border.corner.%@", corner]];
        [d setBool:NO forKey:[NSString stringWithFormat:@"border.corner.%@.image", corner]];
    }
    [d setFloat:0.0f forKey:@"corners.elements.radius"];
    [d setBool:NO forKey:@"corners.menus.shadow"];
    [d setObject:@"" forKey:@"corners.menus.selectcolor"];
    [d setBool:NO forKey:@"toolbar.enabled"];
    [d setBool:NO forKey:@"toolbar.slim"];
    [d setFloat:36.0f forKey:@"toolbar.slim.height"];
    [d setFloat:5.0f forKey:@"toolbar.slim.radius"];
    [d setBool:NO forKey:@"dock.flat"];
    [d setObject:@"#1C1C1E" forKey:@"dock.color"];
    [d setFloat:0.0f forKey:@"dock.radius"];
    [d setBool:NO forKey:@"dock.border"];
    [d setObject:@"#FFFFFF" forKey:@"dock.border.color"];
    [d setFloat:1.0f forKey:@"dock.border.size"];
    [d setObject:@[] forKey:@"toolbar.exclude"];
    [d setBool:NO forKey:@"lights.enabled"];
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
    [d setObject:@"auto"    forKey:@"tint.accent"];
    [d setObject:@"auto"    forKey:@"tint.mode"];
    [d setBool:NO     forKey:@"tint.controls"];
    [d setBool:NO     forKey:@"tint.icons"];
    [d setBool:NO     forKey:@"tint.wallpaper"];
    [d setObject:@"derive"  forKey:@"tint.theme"];
    [d setObject:@[]        forKey:@"tint.exclude"];
    [d setObject:@[]        forKey:@"titlebar.hide"];
    [d setBool:NO     forKey:@"border.enabled"];
    [d setFloat:1.0f  forKey:@"border.size"];
    [d setObject:@"#000000" forKey:@"border.color"];
    [d setBool:NO     forKey:@"border.shadow"];
    [d setBool:NO       forKey:@"glass.flatten"];
    [d setObject:@"auto" forKey:@"glass.color"];
    [d setObject:@[]     forKey:@"glass.exclude"];
    [d setBool:NO       forKey:@"titlebar.color.enabled"];
    [d setObject:@"#1E1E28" forKey:@"titlebar.color"];
    [d setBool:NO       forKey:@"titlebar.image.enabled"];
    [d setBool:NO     forKey:@"sidebar.tint.enabled"];
    [d setObject:@"auto" forKey:@"sidebar.tint.color"];
    [d setBool:NO     forKey:@"sidebar.corners"];
    [d setFloat:0.0f  forKey:@"sidebar.corners.radius"];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) { usage(); return 1; }
        const char *cmd = argv[1];
        NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:BR_SUITE];

        // Seed defaults on first use.
        if (![d objectForKey:@"enabled"]) {
            BRSeedDefaults(d);
        }

        BOOL changed = YES;

        if (strcmp(cmd, "on") == 0)        [d setBool:YES forKey:@"enabled"];
        else if (strcmp(cmd, "off") == 0)  [d setBool:NO  forKey:@"enabled"];
        else if (strcmp(cmd, "toggle") == 0) [d setBool:![d boolForKey:@"enabled"] forKey:@"enabled"];

        // --- window group ---
        else if (strcmp(cmd, "window") == 0 && argc >= 3) {
            const char *sub = argv[2];
            if (strcmp(sub, "corners") == 0 && argc >= 4) {
                if (strcmp(argv[3], "radius") == 0 && argc >= 5)
                    [d setFloat:(float)atof(argv[4]) forKey:@"corners.radius"];
                else { BOOL _v; PARSE_ONOFF(argv[3], _v); [d setBool:_v forKey:@"corners.enabled"]; }
            }
            else if (strcmp(sub, "border") == 0 && argc >= 4) {
                const char *bsub = argv[3];
                if (strcmp(bsub, "size") == 0 && argc >= 5) [d setFloat:(float)atof(argv[4]) forKey:@"border.size"];
                else if (strcmp(bsub, "color") == 0 && argc >= 5) {
                    NSString *val = [NSString stringWithUTF8String:argv[4]]; uint32_t v;
                    if (BRHexToRGBA(val, &v)) [d setObject:val forKey:@"border.color"];
                }
                else if (strcmp(bsub, "inactive") == 0 && argc >= 5) {
                    NSString *val = [NSString stringWithUTF8String:argv[4]]; uint32_t v;
                    if ([val caseInsensitiveCompare:@"auto"] == NSOrderedSame || BRHexToRGBA(val, &v))
                        [d setObject:val forKey:@"border.colorInactive"];
                }
                else if (strcmp(bsub, "shadow") == 0 && argc >= 5) { BOOL _v; PARSE_ONOFF(argv[4], _v); [d setBool:_v forKey:@"border.shadow"]; }
                else if (strcmp(bsub, "edge") == 0 && argc >= 6) {
                    NSString *edge = [NSString stringWithUTF8String:argv[4]];
                    NSArray *validEdges = @[@"top", @"right", @"bottom", @"left"];
                    if (![validEdges containsObject:edge]) {
                        fprintf(stderr, "error: window border edge <top|right|bottom|left> color|image <value>\n"); return 1;
                    }
                    if (strcmp(argv[5], "color") == 0 && argc >= 7) {
                        NSString *val = [NSString stringWithUTF8String:argv[6]];
                        if (strcmp(argv[6], "off") == 0) {
                            [d setObject:@0 forKey:[NSString stringWithFormat:@"border.edge.%@", edge]];
                        } else {
                            uint32_t v;
                            if (!BRHexToRGBA(val, &v)) { fprintf(stderr, "error: color must be #RRGGBB or off\n"); return 1; }
                            [d setObject:@(v) forKey:[NSString stringWithFormat:@"border.edge.%@", edge]];
                        }
                    } else if (strcmp(argv[5], "image") == 0 && argc >= 7) {
                        NSString *role = [NSString stringWithFormat:@"border.edge.%@", edge];
                        if (strcmp(argv[6], "off") == 0) {
                            [d setBool:NO forKey:[NSString stringWithFormat:@"border.edge.%@.image", edge]];
                            BRSetImageRole(d, role, nil, nil);
                        } else {
                            NSString *path = [[NSString stringWithUTF8String:argv[6]] stringByExpandingTildeInPath];
                            NSString *b64 = BRImageFileToBase64PNG(path, 200);
                            if (!b64) { fprintf(stderr, "error: could not read/decode image\n"); return 1; }
                            BRSetImageRole(d, role, b64, path);
                            [d setBool:YES forKey:[NSString stringWithFormat:@"border.edge.%@.image", edge]];
                        }
                    } else { fprintf(stderr, "error: window border edge <top|right|bottom|left> color|image <value>\n"); return 1; }
                }
                else if (strcmp(bsub, "corner") == 0 && argc >= 6) {
                    NSString *corner = [NSString stringWithUTF8String:argv[4]];
                    NSArray *validCorners = @[@"tl", @"tr", @"br", @"bl"];
                    if (![validCorners containsObject:corner]) {
                        fprintf(stderr, "error: window border corner <tl|tr|br|bl> color|image <value>\n"); return 1;
                    }
                    if (strcmp(argv[5], "color") == 0 && argc >= 7) {
                        NSString *val = [NSString stringWithUTF8String:argv[6]];
                        if (strcmp(argv[6], "off") == 0) {
                            [d setObject:@0 forKey:[NSString stringWithFormat:@"border.corner.%@", corner]];
                        } else {
                            uint32_t v;
                            if (!BRHexToRGBA(val, &v)) { fprintf(stderr, "error: color must be #RRGGBB or off\n"); return 1; }
                            [d setObject:@(v) forKey:[NSString stringWithFormat:@"border.corner.%@", corner]];
                        }
                    } else if (strcmp(argv[5], "image") == 0 && argc >= 7) {
                        NSString *role = [NSString stringWithFormat:@"border.corner.%@", corner];
                        if (strcmp(argv[6], "off") == 0) {
                            [d setBool:NO forKey:[NSString stringWithFormat:@"border.corner.%@.image", corner]];
                            BRSetImageRole(d, role, nil, nil);
                        } else {
                            NSString *path = [[NSString stringWithUTF8String:argv[6]] stringByExpandingTildeInPath];
                            NSString *b64 = BRImageFileToBase64PNG(path, 100);
                            if (!b64) { fprintf(stderr, "error: could not read/decode image\n"); return 1; }
                            BRSetImageRole(d, role, b64, path);
                            [d setBool:YES forKey:[NSString stringWithFormat:@"border.corner.%@.image", corner]];
                        }
                    } else { fprintf(stderr, "error: window border corner <tl|tr|br|bl> color|image <value>\n"); return 1; }
                }
                else { BOOL _v; PARSE_ONOFF(bsub, _v); [d setBool:_v forKey:@"border.enabled"]; }
            }
            else { usage(); return 1; }
        }

        // --- elements group ---
        else if (strcmp(cmd, "elements") == 0 && argc >= 3) {
            if (strcmp(argv[2], "radius") == 0 && argc >= 4)
                [d setFloat:(float)atof(argv[3]) forKey:@"corners.elements.radius"];
            else { BOOL _v; PARSE_ONOFF(argv[2], _v); [d setBool:_v forKey:@"corners.elements"]; }
        }

        // --- menus group ---
        else if (strcmp(cmd, "menus") == 0 && argc >= 3) {
            if (strcmp(argv[2], "radius") == 0 && argc >= 4) [d setFloat:(float)atof(argv[3]) forKey:@"corners.menus.radius"];
            else if (strcmp(argv[2], "shadow") == 0 && argc >= 4) { BOOL _v; PARSE_ONOFF(argv[3], _v); [d setBool:_v forKey:@"corners.menus.shadow"]; }
            else if (strcmp(argv[2], "selectcolor") == 0 && argc >= 4)
                [d setObject:[NSString stringWithUTF8String:argv[3]] forKey:@"corners.menus.selectcolor"];
            else { BOOL _v; PARSE_ONOFF(argv[2], _v); [d setBool:_v forKey:@"corners.menus"]; }
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
            } else if (strcmp(argv[2], "slim") == 0 && argc >= 4) {
                if (strcmp(argv[3], "height") == 0 && argc >= 5)
                    [d setFloat:(float)atof(argv[4]) forKey:@"toolbar.slim.height"];
                else if (strcmp(argv[3], "radius") == 0 && argc >= 5)
                    [d setFloat:(float)atof(argv[4]) forKey:@"toolbar.slim.radius"];
                else { BOOL _v; PARSE_ONOFF(argv[3], _v); [d setBool:_v forKey:@"toolbar.slim"]; }
            } else {
                { BOOL _v; PARSE_ONOFF(argv[2], _v); [d setBool:_v forKey:@"toolbar.enabled"]; }
            }
        }

        // --- dock (flat background + corner radius; only active inside com.apple.dock) ---
        else if (strcmp(cmd, "dock") == 0 && argc >= 3) {
            if (strcmp(argv[2], "color") == 0 && argc >= 4) {
                NSString *val = [NSString stringWithUTF8String:argv[3]]; uint32_t v;
                if (!BRHexToRGBA(val, &v)) { fprintf(stderr, "error: dock color must be #RRGGBB or #RRGGBBAA\n"); return 1; }
                [d setObject:val forKey:@"dock.color"];
            }
            else if (strcmp(argv[2], "radius") == 0 && argc >= 4) {
                [d setFloat:(float)atof(argv[3]) forKey:@"dock.radius"];
            }
            else if (strcmp(argv[2], "border") == 0 && argc >= 4) {
                if (strcmp(argv[3], "color") == 0 && argc >= 5) {
                    NSString *val = [NSString stringWithUTF8String:argv[4]]; uint32_t v;
                    if (!BRHexToRGBA(val, &v)) { fprintf(stderr, "error: dock border color must be #RRGGBB or #RRGGBBAA\n"); return 1; }
                    [d setObject:val forKey:@"dock.border.color"];
                }
                else if (strcmp(argv[3], "size") == 0 && argc >= 5) {
                    [d setFloat:(float)atof(argv[4]) forKey:@"dock.border.size"];
                }
                else { BOOL _v; PARSE_ONOFF(argv[3], _v); [d setBool:_v forKey:@"dock.border"]; }
            }
            else { BOOL _v; PARSE_ONOFF(argv[2], _v); [d setBool:_v forKey:@"dock.flat"]; }
        }

        // --- sidebar (tint + corner-radius overrides, independent of the general settings) ---
        else if (strcmp(cmd, "sidebar") == 0 && argc >= 3) {
            const char *sub = argv[2];
            if (strcmp(sub, "tint") == 0 && argc >= 4) {
                if (strcmp(argv[3], "color") == 0 && argc >= 5) {
                    NSString *val = [NSString stringWithUTF8String:argv[4]];
                    if (strcmp(argv[4], "auto") == 0) {
                        [d setObject:@"auto" forKey:@"sidebar.tint.color"];
                    } else {
                        uint32_t v;
                        if (!BRHexToRGBA(val, &v)) { fprintf(stderr, "error: sidebar tint color must be #RRGGBB or auto\n"); return 1; }
                        [d setObject:val forKey:@"sidebar.tint.color"];
                    }
                }
                else { BOOL _v; PARSE_ONOFF(argv[3], _v); [d setBool:_v forKey:@"sidebar.tint.enabled"]; }
            }
            else if (strcmp(sub, "corners") == 0 && argc >= 4) {
                if (strcmp(argv[3], "radius") == 0 && argc >= 5) {
                    [d setFloat:(float)atof(argv[4]) forKey:@"sidebar.corners.radius"];
                }
                else { BOOL _v; PARSE_ONOFF(argv[3], _v); [d setBool:_v forKey:@"sidebar.corners"]; }
            }
            else { fprintf(stderr, "error: sidebar tint <on|off|color> | sidebar corners <on|off|radius>\n"); return 1; }
        }

        // --- lights ---
        else if (strcmp(cmd, "lights") == 0 && argc >= 3) {
            const char *sub = argv[2];
            if (strcmp(sub, "on") == 0 || strcmp(sub, "off") == 0) {
                BOOL _v; PARSE_ONOFF(sub, _v); [d setBool:_v forKey:@"lights.enabled"];
            }
            else if (strcmp(sub, "radius") == 0 && argc >= 4) [d setFloat:(float)atof(argv[3]) forKey:@"lights.radius"];
            else if (strcmp(sub, "size") == 0 && argc >= 4) [d setFloat:(float)atof(argv[3]) forKey:@"lights.size"];
            else if (strcmp(sub, "color") == 0 && argc >= 5) {
                NSString *slot = [NSString stringWithUTF8String:argv[3]];
                NSString *val = [NSString stringWithUTF8String:argv[4]];
                NSString *key = nil;
                if ([slot isEqualToString:@"close"])    key = @"lights.colorClose";
                else if ([slot isEqualToString:@"min"])  key = @"lights.colorMin";
                else if ([slot isEqualToString:@"zoom"]) key = @"lights.colorZoom";
                else if ([slot isEqualToString:@"inactive"]) key = @"lights.colorInactive";
                else if ([slot isEqualToString:@"glyph"]) key = @"lights.colorGlyph";
                if (key) [d setObject:val forKey:key];
                else { fprintf(stderr, "error: lights color <close|min|zoom|inactive|glyph> <#RRGGBB>\n"); return 1; }
            }
            else if (strcmp(sub, "image") == 0 && argc >= 4) {
                if (strcmp(argv[3], "off") == 0) {
                    [d setBool:NO forKey:@"lights.image.enabled"];
                } else if (argc >= 5) {
                    NSString *btn = [NSString stringWithUTF8String:argv[3]];
                    NSString *role = [btn isEqualToString:@"close"] ? @"light.close"
                                   : [btn isEqualToString:@"min"]   ? @"light.min"
                                   : [btn isEqualToString:@"zoom"]  ? @"light.zoom" : nil;
                    if (!role) { fprintf(stderr, "error: lights image <close|min|zoom> <path|off>\n"); return 1; }
                    if (strcmp(argv[4], "off") == 0) {
                        BRSetImageRole(d, role, nil, nil);
                    } else {
                        NSString *path = [[NSString stringWithUTF8String:argv[4]] stringByExpandingTildeInPath];
                        NSString *b64 = BRImageFileToBase64PNG(path, 64);
                        if (!b64) { fprintf(stderr, "error: could not read/decode image\n"); return 1; }
                        BRSetImageRole(d, role, b64, path);
                        [d setBool:YES forKey:@"lights.image.enabled"];
                    }
                }
            }
            else if (strcmp(sub, "theme") == 0) {
                if (argc >= 4 && strcmp(argv[3], "list") == 0) {
                    printf("Light themes:\n");
                    for (int i = 0; i < kBRThemeCount; i++) printf("  %s\n", kBRThemes[i].name);
                    printf("  custom\n");
                    return 0;
                }
                if (argc >= 4) {
                    NSString *name = [NSString stringWithUTF8String:argv[3]];
                    for (int i = 0; i < kBRThemeCount; i++) {
                        if ([name caseInsensitiveCompare:[NSString stringWithUTF8String:kBRThemes[i].name]] == NSOrderedSame) {
                            [d setObject:[NSString stringWithUTF8String:kBRThemes[i].close] forKey:@"lights.colorClose"];
                            [d setObject:[NSString stringWithUTF8String:kBRThemes[i].min]   forKey:@"lights.colorMin"];
                            [d setObject:[NSString stringWithUTF8String:kBRThemes[i].zoom]  forKey:@"lights.colorZoom"];
                            [d setObject:name forKey:@"lights.theme"];
                            break;
                        }
                    }
                }
            }
        }

        // --- tint ---
        else if (strcmp(cmd, "tint") == 0 && argc >= 3) {
            const char *sub = argv[2];
            if (strcmp(sub, "on") == 0 || strcmp(sub, "off") == 0) {
                BOOL _v; PARSE_ONOFF(sub, _v); [d setBool:_v forKey:@"tint.enabled"];
            }
            else if (strcmp(sub, "color") == 0 && argc >= 4) {
                NSString *val = [NSString stringWithUTF8String:argv[3]]; uint32_t v;
                if (BRHexToRGBA(val, &v)) { [d setObject:val forKey:@"tint.color"]; [d setObject:@"custom" forKey:@"tint.theme"]; }
            }
            else if (strcmp(sub, "chrome") == 0 && argc >= 4) [d setObject:[NSString stringWithUTF8String:argv[3]] forKey:@"tint.chrome"];
            else if (strcmp(sub, "text") == 0 && argc >= 4) [d setObject:[NSString stringWithUTF8String:argv[3]] forKey:@"tint.text"];
            else if (strcmp(sub, "accent") == 0 && argc >= 4) [d setObject:[NSString stringWithUTF8String:argv[3]] forKey:@"tint.accent"];
            else if (strcmp(sub, "mode") == 0 && argc >= 4) {
                NSString *m = [NSString stringWithUTF8String:argv[3]];
                [d setObject:m.lowercaseString forKey:@"tint.mode"];
            }
            else if (strcmp(sub, "controls") == 0 && argc >= 4) { BOOL _v; PARSE_ONOFF(argv[3], _v); [d setBool:_v forKey:@"tint.controls"]; }
            else if (strcmp(sub, "icons") == 0 && argc >= 4) { BOOL _v; PARSE_ONOFF(argv[3], _v); [d setBool:_v forKey:@"tint.icons"]; }
            else if (strcmp(sub, "wallpaper") == 0 && argc >= 4) { BOOL _v; PARSE_ONOFF(argv[3], _v); [d setBool:_v forKey:@"tint.wallpaper"]; }
            else if (strcmp(sub, "theme") == 0) {
                if (argc >= 4 && strcmp(argv[3], "list") == 0) {
                    printf("Tint themes:\n");
                    for (int i = 0; i < kBRTintThemeCount; i++) printf("  %s\n", kBRTintThemes[i].name);
                    printf("  custom\n");
                    return 0;
                }
                if (argc >= 4) {
                    NSString *name = [NSString stringWithUTF8String:argv[3]];
                    for (int i = 0; i < kBRTintThemeCount; i++) {
                        if ([name caseInsensitiveCompare:[NSString stringWithUTF8String:kBRTintThemes[i].name]] == NSOrderedSame) {
                            [d setObject:[NSString stringWithUTF8String:kBRTintThemes[i].color]  forKey:@"tint.color"];
                            [d setObject:[NSString stringWithUTF8String:kBRTintThemes[i].chrome] forKey:@"tint.chrome"];
                            [d setObject:[NSString stringWithUTF8String:kBRTintThemes[i].mode]   forKey:@"tint.mode"];
                            [d setObject:@"auto" forKey:@"tint.text"];
                            [d setObject:@"auto" forKey:@"tint.accent"];
                            [d setObject:name forKey:@"tint.theme"];
                            break;
                        }
                    }
                }
            }
            else if (strcmp(sub, "exclude") == 0 && argc >= 4) {
                NSMutableArray *list = [[d arrayForKey:@"tint.exclude"] mutableCopy] ?: [NSMutableArray array];
                if (strcmp(argv[3], "list") == 0) {
                    printf("Tint excluded apps:\n");
                    for (NSString *b in list) printf("  %s\n", b.UTF8String);
                    if (list.count == 0) printf("  (none)\n");
                    return 0;
                }
                if (argc >= 5) {
                    NSString *bid = [NSString stringWithUTF8String:argv[4]];
                    if (strcmp(argv[3], "add") == 0) { if (![list containsObject:bid]) [list addObject:bid]; }
                    else if (strcmp(argv[3], "remove") == 0) [list removeObject:bid];
                }
                [d setObject:list forKey:@"tint.exclude"];
            }
        }

        // --- glass ---
        else if (strcmp(cmd, "glass") == 0 && argc >= 3) {
            const char *sub = argv[2];
            if (strcmp(sub, "on") == 0)  [d setBool:YES forKey:@"glass.flatten"];
            else if (strcmp(sub, "off") == 0) [d setBool:NO forKey:@"glass.flatten"];
            else if (strcmp(sub, "color") == 0 && argc >= 4) [d setObject:[NSString stringWithUTF8String:argv[3]] forKey:@"glass.color"];
            else if (strcmp(sub, "image") == 0 && argc >= 4) {
                if (strcmp(argv[3], "off") == 0) {
                    [d setBool:NO forKey:@"glass.image.enabled"];
                    BRSetImageRole(d, @"glass", nil, nil);
                } else {
                    NSString *path = [[NSString stringWithUTF8String:argv[3]] stringByExpandingTildeInPath];
                    NSString *b64 = BRImageFileToBase64PNG(path, 600);
                    if (!b64) { fprintf(stderr, "error: could not read/decode image\n"); return 1; }
                    BRSetImageRole(d, @"glass", b64, path);
                    [d setBool:YES forKey:@"glass.image.enabled"];
                }
            }
            else if (strcmp(sub, "exclude") == 0 && argc >= 4) {
                NSMutableArray *list = [[d arrayForKey:@"glass.exclude"] mutableCopy] ?: [NSMutableArray array];
                if (strcmp(argv[3], "list") == 0) {
                    printf("Glass excluded apps:\n");
                    for (NSString *b in list) printf("  %s\n", b.UTF8String);
                    if (list.count == 0) printf("  (none)\n");
                    return 0;
                }
                if (argc >= 5) {
                    NSString *bid = [NSString stringWithUTF8String:argv[4]];
                    if (strcmp(argv[3], "add") == 0) { if (![list containsObject:bid]) [list addObject:bid]; }
                    else if (strcmp(argv[3], "remove") == 0) [list removeObject:bid];
                }
                [d setObject:list forKey:@"glass.exclude"];
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
                    NSString *b64 = BRImageFileToBase64PNG(path, 600);
                    if (!b64) { fprintf(stderr, "error: could not read/decode image at %s\n", path.UTF8String); return 1; }
                    BRSetImageRole(d, @"titlebar", b64, path);
                    [d setBool:YES forKey:@"titlebar.image.enabled"];
                    [d setBool:YES forKey:@"titlebar.color.enabled"];
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

        // --- status ---
        else if (strcmp(cmd, "status") == 0) {
            changed = NO;
            printf("brutalium status:\n");
            printf("\n");
            printf("  window:\n");
            printf("    master       : %s\n", [d boolForKey:@"enabled"] ? "on" : "off");
            printf("    corners      : %s  (radius %.1f)\n",
                   [d boolForKey:@"corners.enabled"] ? "on" : "off", [d floatForKey:@"corners.radius"]);
            printf("    border       : %s", [d boolForKey:@"border.enabled"] ? "on" : "off");
            if ([d boolForKey:@"border.enabled"])
                printf("  (size %.1f, color %s, inactive %s, shadow %s)",
                       [d floatForKey:@"border.size"],
                       [([d stringForKey:@"border.color"] ?: @"-") UTF8String],
                       [([d stringForKey:@"border.colorInactive"] ?: @"auto") UTF8String],
                       [d boolForKey:@"border.shadow"] ? "on" : "off");
            printf("\n");
            {
                static NSString * const edgeKeys[4]   = { @"top", @"right", @"bottom", @"left" };
                static NSString * const cornerKeys[4] = { @"tl", @"tr", @"br", @"bl" };
                NSMutableArray *parts = [NSMutableArray array];
                for (int i = 0; i < 4; i++) {
                    id ev = [d objectForKey:[NSString stringWithFormat:@"border.edge.%@", edgeKeys[i]]];
                    BOOL eimg = [d boolForKey:[NSString stringWithFormat:@"border.edge.%@.image", edgeKeys[i]]];
                    BOOL hasColor = [ev isKindOfClass:[NSNumber class]] && [ev unsignedLongLongValue] != 0;
                    if (hasColor || eimg) {
                        NSString *colorPart = hasColor ? [NSString stringWithFormat:@"#%06X", (unsigned int)([ev unsignedLongLongValue] >> 8)] : @"-";
                        NSString *imgPart = eimg ? @"+img" : @"";
                        [parts addObject:[NSString stringWithFormat:@"%@=%@%@", edgeKeys[i], colorPart, imgPart]];
                    }
                }
                for (int i = 0; i < 4; i++) {
                    id cv = [d objectForKey:[NSString stringWithFormat:@"border.corner.%@", cornerKeys[i]]];
                    BOOL cimg = [d boolForKey:[NSString stringWithFormat:@"border.corner.%@.image", cornerKeys[i]]];
                    BOOL hasColor = [cv isKindOfClass:[NSNumber class]] && [cv unsignedLongLongValue] != 0;
                    if (hasColor || cimg) {
                        NSString *colorPart = hasColor ? [NSString stringWithFormat:@"#%06X", (unsigned int)([cv unsignedLongLongValue] >> 8)] : @"-";
                        NSString *imgPart = cimg ? @"+img" : @"";
                        [parts addObject:[NSString stringWithFormat:@"%@=%@%@", cornerKeys[i], colorPart, imgPart]];
                    }
                }
                if (parts.count) printf("    border edges : %s\n", [[parts componentsJoinedByString:@", "] UTF8String]);
            }
            printf("\n");
            printf("  elements:\n");
            printf("    corners      : %s  (radius %.1f)\n",
                   [d boolForKey:@"corners.elements"] ? "on" : "off", [d floatForKey:@"corners.elements.radius"]);
            printf("\n");
            printf("  menus:\n");
            printf("    corners      : %s  (radius %.1f)\n",
                   [d boolForKey:@"corners.menus"] ? "on" : "off", [d floatForKey:@"corners.menus.radius"]);
            if ([d boolForKey:@"corners.menus"])
                printf("    shadow=%s selectcolor=%s\n",
                       [d boolForKey:@"corners.menus.shadow"] ? "on" : "off",
                       [([d stringForKey:@"corners.menus.selectcolor"] ?: @"off") UTF8String]);
            printf("\n");
            printf("  toolbar:\n");
            NSArray *ex = [d arrayForKey:@"toolbar.exclude"];
            printf("    expanded     : %s\n", [d boolForKey:@"toolbar.enabled"] ? "on" : "off");
            printf("    slim         : %s", [d boolForKey:@"toolbar.slim"] ? "on" : "off");
            if ([d boolForKey:@"toolbar.slim"]) {
                float h = [d floatForKey:@"toolbar.slim.height"];
                float r = [d floatForKey:@"toolbar.slim.radius"];
                printf("  (height %.0f, radius %.0f)", h > 0 ? h : 36.0f, r > 0 ? r : 5.0f);
            }
            printf("\n");
            printf("    exclude      : %s\n", ex.count ? [[ex componentsJoinedByString:@", "] UTF8String] : "(none)");
            printf("\n");
            printf("  titlebar:\n");
            printf("    hidden       : %lu app(s)\n", (unsigned long)([d arrayForKey:@"titlebar.hide"] ?: @[]).count);
            printf("    color        : %s\n",
                   [d boolForKey:@"titlebar.color.enabled"]
                     ? [([d stringForKey:@"titlebar.color"] ?: @"#1E1E28") UTF8String] : "off");
            printf("    image        : %s\n",
                   [d boolForKey:@"titlebar.image.enabled"]
                     ? [(([d dictionaryForKey:@"images.paths"][@"titlebar"]) ?: @"(set)") UTF8String] : "off");
            printf("\n");
            printf("  sidebar:\n");
            printf("    tint         : %s", [d boolForKey:@"sidebar.tint.enabled"] ? "on" : "off");
            if ([d boolForKey:@"sidebar.tint.enabled"])
                printf("  (color %s)", [([d stringForKey:@"sidebar.tint.color"] ?: @"auto") UTF8String]);
            printf("\n");
            printf("    corners      : %s", [d boolForKey:@"sidebar.corners"] ? "on" : "off");
            if ([d boolForKey:@"sidebar.corners"])
                printf("  (radius %.0f)", [d floatForKey:@"sidebar.corners.radius"]);
            printf("\n");
            printf("\n");
            printf("  traffic lights:\n");
            printf("    enabled      : %s  (radius %.1f, size %+.1f, theme %s)\n",
                   [d boolForKey:@"lights.enabled"] ? "on" : "off",
                   [d floatForKey:@"lights.radius"], [d floatForKey:@"lights.size"],
                   [([d stringForKey:@"lights.theme"] ?: @"custom") UTF8String]);
            printf("    close=%s min=%s zoom=%s inactive=%s glyph=%s\n",
                   [([d stringForKey:@"lights.colorClose"] ?: @"-") UTF8String],
                   [([d stringForKey:@"lights.colorMin"] ?: @"-") UTF8String],
                   [([d stringForKey:@"lights.colorZoom"] ?: @"-") UTF8String],
                   [([d stringForKey:@"lights.colorInactive"] ?: @"-") UTF8String],
                   [([d stringForKey:@"lights.colorGlyph"] ?: @"-") UTF8String]);
            printf("\n");
            printf("  tint:\n");
            printf("    enabled      : %s  (theme %s, mode %s)\n",
                   [d boolForKey:@"tint.enabled"] ? "on" : "off",
                   [([d stringForKey:@"tint.theme"] ?: @"custom") UTF8String],
                   [([d stringForKey:@"tint.mode"] ?: @"auto") UTF8String]);
            printf("    color=%s chrome=%s text=%s accent=%s\n",
                   [([d stringForKey:@"tint.color"] ?: @"-") UTF8String],
                   [([d stringForKey:@"tint.chrome"] ?: @"auto") UTF8String],
                   [([d stringForKey:@"tint.text"] ?: @"auto") UTF8String],
                   [([d stringForKey:@"tint.accent"] ?: @"auto") UTF8String]);
            printf("    controls=%s icons=%s wallpaper=%s\n",
                   [d boolForKey:@"tint.controls"] ? "on" : "off",
                   [d boolForKey:@"tint.icons"] ? "on" : "off",
                   [d boolForKey:@"tint.wallpaper"] ? "on" : "off");
            printf("    excluded     : %lu app(s)\n",
                   (unsigned long)([d arrayForKey:@"tint.exclude"] ?: @[]).count);
            printf("\n");
            printf("  glass:\n");
            printf("    flatten      : %s  (fill %s, image %s, excl %lu)\n",
                   [d boolForKey:@"glass.flatten"] ? "on — flattened" : "off (native glass)",
                   [([d stringForKey:@"glass.color"] ?: @"auto") UTF8String],
                   [d boolForKey:@"glass.image.enabled"]
                     ? [(([d dictionaryForKey:@"images.paths"][@"glass"]) ?: @"(set)") UTF8String] : "off",
                   (unsigned long)([d arrayForKey:@"glass.exclude"] ?: @[]).count);
            printf("\n");
            printf("  dock:\n");
            printf("    flat         : %s", [d boolForKey:@"dock.flat"] ? "on" : "off");
            if ([d boolForKey:@"dock.flat"]) {
                float r = [d floatForKey:@"dock.radius"];
                printf("  (color %s, radius %.0f)",
                       [([d stringForKey:@"dock.color"] ?: @"#1C1C1E") UTF8String], r);
            }
            printf("\n");
            printf("    border       : %s", [d boolForKey:@"dock.border"] ? "on" : "off");
            if ([d boolForKey:@"dock.border"]) {
                float bs = [d floatForKey:@"dock.border.size"];
                printf("  (color %s, size %.1f)",
                       [([d stringForKey:@"dock.border.color"] ?: @"#FFFFFF") UTF8String], bs);
            }
            printf("\n");
        }

        // --- config export/import ---
        else if (strcmp(cmd, "config") == 0 && argc >= 3) {
            changed = NO;
            if (strcmp(argv[2], "export") == 0) {
                NSString *path = (argc >= 4) ? [NSString stringWithUTF8String:argv[3]] : @"brutalium-config.plist";
                NSDictionary *dict = [d dictionaryRepresentation];
                NSMutableDictionary *filtered = [NSMutableDictionary dictionary];
                for (NSString *key in dict) {
                    if ([key hasPrefix:@"corners."] || [key hasPrefix:@"border."] ||
                        [key hasPrefix:@"toolbar."] || [key hasPrefix:@"titlebar."] ||
                        [key hasPrefix:@"lights."] || [key hasPrefix:@"tint."] ||
                        [key hasPrefix:@"glass."] || [key hasPrefix:@"images."] ||
                        [key hasPrefix:@"dock."] || [key hasPrefix:@"sidebar."] ||
                        [key isEqualToString:@"enabled"])
                        filtered[key] = dict[key];
                }
                NSError *err = nil;
                NSData *data = [NSPropertyListSerialization dataWithPropertyList:filtered
                    format:NSPropertyListXMLFormat_v1_0 options:0 error:&err];
                if (!data) { fprintf(stderr, "error: %s\n", err.localizedDescription.UTF8String); return 1; }
                if (![data writeToFile:path options:NSDataWritingAtomic error:&err]) {
                    fprintf(stderr, "error: %s\n", err.localizedDescription.UTF8String); return 1;
                }
                printf("config exported to %s (%lu keys)\n", path.UTF8String, (unsigned long)filtered.count);
                return 0;
            }
            else if (strcmp(argv[2], "import") == 0 && argc >= 4) {
                NSString *path = [NSString stringWithUTF8String:argv[3]];
                NSData *data = [NSData dataWithContentsOfFile:path];
                if (!data) { fprintf(stderr, "error: cannot read '%s'\n", path.UTF8String); return 1; }
                NSError *err = nil;
                NSDictionary *imported = [NSPropertyListSerialization propertyListWithData:data
                    options:NSPropertyListImmutable format:NULL error:&err];
                if (!imported || ![imported isKindOfClass:[NSDictionary class]]) {
                    fprintf(stderr, "error: invalid plist: %s\n", err.localizedDescription.UTF8String); return 1;
                }
                for (NSString *key in imported) [d setObject:imported[key] forKey:key];
                printf("config imported from %s (%lu keys)\n", path.UTF8String, (unsigned long)imported.count);
                changed = YES;
            }
            else { usage(); return 1; }
        }

        // --- debug ---
        else if (strcmp(cmd, "debug") == 0 && argc >= 4) {
            if (strcmp(argv[2], "tree") == 0) {
                BOOL on; PARSE_ONOFF(argv[3], on);
                CFPreferencesSetValue(CFSTR("com.tweak.brutalium.debug.tree"),
                                      on ? kCFBooleanTrue : kCFBooleanFalse,
                                      kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
                CFPreferencesAppSynchronize(kCFPreferencesAnyApplication);
                printf("debug tree: %s (writes to /tmp/brutalium-tree.log for 30s)\n", on ? "on" : "off");
            }
        }

        else if (strcmp(cmd, "reset") == 0) {
            changed = NO;
            NSString *suiteName = BR_SUITE;
            [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:suiteName];
            BRSeedDefaults(d);
            [d synchronize];
            BRPublishFromDefaults(d);
            printf("All settings reset to defaults and published.\n");
        }
        else if (strcmp(cmd, "publish") == 0) { changed = NO; BRPublishFromDefaults(d); printf("Published.\n"); }
        else { usage(); return 1; }

        if (changed) { [d synchronize]; BRPublishFromDefaults(d); }
    }
    return 0;
}
