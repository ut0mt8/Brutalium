//
//  clitool.m — `brutalium` unified CLI (windows + lights).
//

#import <Foundation/Foundation.h>
#import "BRState.h"
#import "BRThemes.h"

static void usage(void) {
    fprintf(stderr,
        "Brutalium — square corners, expanded toolbar, square traffic lights\n"
        "\n"
        "Usage: brutalium <command>\n"
        "\n"
        "  on | off | toggle              Master enable\n"
        "\n"
        "  corners on | off               Square window corners\n"
        "  corners radius <value>         0 = fully square\n"
        "\n"
        "  toolbar on | off               Force expanded toolbar\n"
        "  toolbar exclude add <bundleid> Don't force toolbar for this app\n"
        "  toolbar exclude remove <bundleid>\n"
        "  toolbar exclude list\n"
        "\n"
        "  lights on | off                Square the traffic-light buttons\n"
        "  lights radius <value>          Traffic-light corner radius\n"
        "  lights size <delta>            Adjust square size in points\n"
        "  lights color <slot> <value>    slot = close|min|zoom|inactive|glyph\n"
        "                                 value = #RRGGBB / #RRGGBBAA (inactive: auto)\n"
        "  lights theme <name> | list     Apply a colour preset\n"
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
        }

        BOOL changed = YES;

        if (strcmp(cmd, "on") == 0)        [d setBool:YES forKey:@"enabled"];
        else if (strcmp(cmd, "off") == 0)  [d setBool:NO  forKey:@"enabled"];
        else if (strcmp(cmd, "toggle") == 0) [d setBool:![d boolForKey:@"enabled"] forKey:@"enabled"];

        else if (strcmp(cmd, "corners") == 0 && argc >= 3) {
            if (strcmp(argv[2], "radius") == 0 && argc >= 4) [d setFloat:(float)atof(argv[3]) forKey:@"corners.radius"];
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

        else if (strcmp(cmd, "lights") == 0 && argc >= 3) {
            const char *sub = argv[2];
            if (strcmp(sub, "on") == 0 || strcmp(sub, "off") == 0) {
                [d setBool:(strcmp(sub, "on") == 0) forKey:@"lights.enabled"];
            }
            else if (strcmp(sub, "radius") == 0 && argc >= 4) [d setFloat:(float)atof(argv[3]) forKey:@"lights.radius"];
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

        else if (strcmp(cmd, "status") == 0) {
            changed = NO;
            NSArray *ex = [d arrayForKey:@"toolbar.exclude"];
            printf("Brutalium status:\n");
            printf("  master         : %s\n", [d boolForKey:@"enabled"] ? "on" : "off");
            printf("  corners        : %s  (radius %.1f%s)\n", [d boolForKey:@"corners.enabled"] ? "on" : "off",
                   [d floatForKey:@"corners.radius"], [d floatForKey:@"corners.radius"] == 0 ? " square" : "");
            printf("  toolbar        : %s\n", [d boolForKey:@"toolbar.enabled"] ? "on" : "off");
            printf("  toolbar excl.  : %s\n", ex.count ? [[ex componentsJoinedByString:@", "] UTF8String] : "(none)");
            printf("  lights         : %s  (radius %.1f, size %+.1f, theme %s)\n",
                   [d boolForKey:@"lights.enabled"] ? "on" : "off",
                   [d floatForKey:@"lights.radius"], [d floatForKey:@"lights.size"],
                   [([d stringForKey:@"lights.theme"] ?: @"custom") UTF8String]);
            printf("    close=%s min=%s zoom=%s inactive=%s glyph=%s\n",
                   [([d stringForKey:@"lights.colorClose"] ?: @"-") UTF8String],
                   [([d stringForKey:@"lights.colorMin"] ?: @"-") UTF8String],
                   [([d stringForKey:@"lights.colorZoom"] ?: @"-") UTF8String],
                   [([d stringForKey:@"lights.colorInactive"] ?: @"-") UTF8String],
                   [([d stringForKey:@"lights.colorGlyph"] ?: @"-") UTF8String]);
        }
        else if (strcmp(cmd, "publish") == 0) { changed = NO; BRPublishFromDefaults(d); printf("Published.\n"); }
        else { usage(); return 1; }

        if (changed) { [d synchronize]; BRPublishFromDefaults(d); }
    }
    return 0;
}
