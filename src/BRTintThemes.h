//
//  BRTintThemes.h — matched main+chrome colour presets for the tint module
//  (shared by the CLI). chrome == "auto" means derive it from the main colour.
//

#ifndef BRTINTTHEMES_H
#define BRTINTTHEMES_H

#import <Foundation/Foundation.h>
#include <strings.h>

typedef struct {
    const char *name;
    const char *color;   // main background
    const char *chrome;  // sidebar/titlebar/toolbar ("auto" to derive)
    const char *mode;    // auto|light|dark|none
} BRTintTheme;

static const BRTintTheme kBRTintThemes[] = {
    // name               main         chrome       mode
    { "slate",          "#1E1E28",   "#2C2C3C",   "dark"  },
    { "graphite",       "#1C1C1C",   "#2A2A2A",   "dark"  },
    { "nord",           "#2E3440",   "#3B4252",   "dark"  },
    { "dracula",        "#282A36",   "#343746",   "dark"  },
    { "solarized",      "#002B36",   "#073642",   "dark"  },
    { "midnight",       "#0D1B2A",   "#1B263B",   "dark"  },
    { "forest",         "#14201A",   "#1E2E26",   "dark"  },
    { "mocha",          "#241B18",   "#332622",   "dark"  },
    { "gruvbox",        "#282828",   "#3C3836",   "dark"  },
    { "tokyo-night",    "#1A1B26",   "#24283B",   "dark"  },
    { "catppuccin",     "#1E1E2E",   "#313244",   "dark"  },
    { "one-dark",       "#282C34",   "#21252B",   "dark"  },
    { "monokai",        "#272822",   "#33342B",   "dark"  },
    { "rose-pine",      "#191724",   "#1F1D2E",   "dark"  },
    { "everforest",     "#2D353B",   "#343F44",   "dark"  },
    { "ayu",            "#0B0E14",   "#11151C",   "dark"  },
    { "ayu-mirage",     "#1F2430",   "#232834",   "dark"  },
    { "carbon",         "#161616",   "#262626",   "dark"  },
    { "oled",           "#000000",   "#0E0E0E",   "dark"  },
    { "paper",          "#F5F0E6",   "#E8E0D0",   "light" },
    { "solarized-lt",   "#FDF6E3",   "#EEE8D5",   "light" },
    { "fog",            "#E6E8EC",   "#D6D9DE",   "light" },
    { "gruvbox-lt",     "#FBF1C7",   "#EBDBB2",   "light" },
    { "catppuccin-lt",  "#EFF1F5",   "#E6E9EF",   "light" },
    { "rose-pine-dawn", "#FAF4ED",   "#FFFAF3",   "light" },
    { "nord-lt",        "#ECEFF4",   "#E5E9F0",   "light" },
    { "derive",         "#1E1E28",   "auto",      "auto"  }, // main + auto-derived chrome
};

static const int kBRTintThemeCount = (int)(sizeof(kBRTintThemes) / sizeof(kBRTintThemes[0]));

static inline const BRTintTheme *BRTintThemeNamed(const char *name) {
    if (!name) return NULL;
    for (int i = 0; i < kBRTintThemeCount; i++)
        if (strcasecmp(name, kBRTintThemes[i].name) == 0) return &kBRTintThemes[i];
    return NULL;
}

#endif /* BRTINTTHEMES_H */
