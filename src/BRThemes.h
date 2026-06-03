//
//  BRThemes.h — named colour presets, shared by the CLI and the settings app.
//
//  Each entry supplies hex strings for the three controls plus the inactive
//  (background-window) and glyph colours. "auto" means "follow the system".
//

#ifndef BRTHEMES_H
#define BRTHEMES_H

#import <Foundation/Foundation.h>
#include <strings.h>

typedef struct {
    const char *name;
    const char *close;
    const char *min;
    const char *zoom;
    const char *inactive;
    const char *glyph;
} BRTheme;

static const BRTheme kBRThemes[] = {
    // name          close       min         zoom        inactive    glyph
    { "classic",   "#FF5F57", "#FEBC2E", "#28C840", "auto",      "#0000008C" },
    { "mono",      "#8E8E93", "#8E8E93", "#8E8E93", "auto",      "#000000A6" },
    { "graphite",  "#7D7D7D", "#9B9B9B", "#B9B9B9", "auto",      "#000000A6" },
    { "neon",      "#FF3B30", "#FFCC00", "#34C759", "auto",      "#000000A6" },
    { "nord",      "#BF616A", "#EBCB8B", "#A3BE8C", "#4C566A",   "#2E3440C0" },
    { "solarized", "#DC322F", "#B58900", "#859900", "#586E75",   "#002B36C0" },
    { "dracula",   "#FF5555", "#F1FA8C", "#50FA7B", "#44475A",   "#282A36C0" },
};

static const int kBRThemeCount = (int)(sizeof(kBRThemes) / sizeof(kBRThemes[0]));

// Returns the preset with the given name, or NULL.
static inline const BRTheme *BRThemeNamed(const char *name) {
    if (!name) return NULL;
    for (int i = 0; i < kBRThemeCount; i++) {
        if (strcasecmp(name, kBRThemes[i].name) == 0) return &kBRThemes[i];
    }
    return NULL;
}

#endif /* BRTHEMES_H */
