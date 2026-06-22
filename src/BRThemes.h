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
    // name           close       min         zoom        inactive    glyph
    { "classic",     "#FF5F57", "#FEBC2E", "#28C840", "auto",      "#0000008C" },
    { "mono",        "#8E8E93", "#8E8E93", "#8E8E93", "auto",      "#000000A6" },
    { "graphite",    "#7D7D7D", "#9B9B9B", "#B9B9B9", "auto",      "#000000A6" },
    { "neon",        "#FF3B30", "#FFCC00", "#34C759", "auto",      "#000000A6" },
    { "nord",        "#BF616A", "#EBCB8B", "#A3BE8C", "#4C566A",   "#2E3440C0" },
    { "solarized",   "#DC322F", "#B58900", "#859900", "#586E75",   "#002B36C0" },
    { "dracula",     "#FF5555", "#F1FA8C", "#50FA7B", "#44475A",   "#282A36C0" },
    { "gruvbox",     "#CC241D", "#D79921", "#98971A", "#504945",   "#282828C0" },
    { "tokyo-night", "#F7768E", "#E0AF68", "#9ECE6A", "#414868",   "#1A1B26C0" },
    { "catppuccin",  "#F38BA8", "#F9E2AF", "#A6E3A1", "#45475A",   "#1E1E2EC0" },
    { "one-dark",    "#E06C75", "#E5C07B", "#98C379", "#4B5263",   "#282C34C0" },
    { "monokai",     "#F92672", "#E6DB74", "#A6E22E", "#49483E",   "#272822C0" },
    { "rose-pine",   "#EB6F92", "#F6C177", "#9CCFD8", "#26233A",   "#191724C0" },
    { "everforest",  "#E67E80", "#DBBC7F", "#A7C080", "#4F585E",   "#2D353BC0" },
    { "ayu",         "#F07178", "#FFB454", "#AAD94C", "#475266",   "#0B0E14C0" },
    { "gotham",      "#D26937", "#EDB443", "#2AA889", "#2A3C44",   "#0A0F14C0" },
    { "matrix",      "#00CC33", "#00CC33", "#00CC33", "#0A2A12",   "#001A08D0" },
    { "amber",       "#FFB000", "#FFB000", "#FFB000", "#3A2A00",   "#1A1200D0" },
    { "pastel",      "#FFB3BA", "#FFE4A1", "#B5EAD7", "auto",      "#00000080" },
    { "synthwave",   "#FF6AD5", "#FFD319", "#05FFA1", "#2A2139",   "#1A1433C0" },
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
