# Brutalium

A macOS [Ammonia](https://github.com/CoreBedtime/ammonia) tweak that makes the whole
UI brutally square and optionally recolours and reshapes it for every app:

- **Square window corners** (configurable radius; `0` = fully square) + flatter titlebar.
- **Square *every* layer's corners** (optional, aggressive): buttons, fields, popovers, menus.
- **Expanded toolbar style** forced everywhere, with a per-app exclusion list.
- **Square traffic-light buttons** (close / minimise / zoom) with configurable colours, themes, size, and a hover glyph.
- **System tint**: recolour the whole UI to any colour background, chrome, precise text, toolbar icons with themes and a per-app exclusion list.
- **Titlebar removal** per app (keeps the toolbar where there is one).
- **Window borders** with separate active/inactive colours, width, and a drop-shadow toggle.

It merges three earlier tweaks UIFixer (windows), FlatLights (traffic lights) and
BrutalTint (system tint) into one dylib, one CLI (`brutalium`), and one config.

## Architecture

One injected dylib, three feature modules over shared scaffolding:

- `Brutalium.m` core: process gating, the notify-state config cache, window
  discovery, and the constructor that arms every module.
- `BRWindows.m` corners + expanded toolbar + titlebar removal + window borders, plus
  the optional global `CALayer` corner-squaring (private `NSWindow` corner plumbing and
  a ZKSwizzle group).
- `BRLights.m` class-level method swizzle of the three private window-button classes;
  square rendering + hover tracking.
- `BRTint.m` `NSColor` class-method overrides (backgrounds + text), an
  `NSVisualEffectView` takeover for chrome, an opaque backdrop, appearance forcing, and
  toolbar-icon tinting.
- `BRState.h` / `BRConfig.h` wire format (notify state + global-domain lists) and the shared config cache;
  `BRThemes.h` / `BRTintThemes.h` colour presets.

Shared robustness: completely inert in Chromium/Electron child processes; swizzles are
armed only in real app processes. Traffic lights use a one-time class-level swizzle (no
per-instance reclassing), so they coexist with the `NSKVONotifying_` subclasses and the
Swift titlebar property system under Solarium. Window-affecting features target only
genuine top-level main windows, skipping child windows, panels, popovers, and overlays.
All configuration reaches sandboxed apps (Finder, Mail, Notes, Safari, System
Settings…): live settings travel over Darwin notify state, and the per-app lists ride a
global-domain key. See **Config transport** below.

## Build & install

```sh
make
sudo make install
```

Relaunch apps to pick up the injection. Most settings changes apply live via `publish`;
changes to the per-app exclude/hide lists take effect on the target app's next launch. A
`com.tweak.brutalium.publish` LaunchAgent also republishes at login so sandboxed apps
get everything before launch.

Targeting note: most features apply everywhere and are scoped by per-app exclude/include
lists keyed by **bundle id**. Find one with `osascript -e 'id of app "Finder"'` or
`lsappinfo info -only bundleid $(pgrep -x Finder)`.

## Usage

```sh
brutalium on | off | toggle              # master enable

# Corners ------------------------------------------------------------------
brutalium corners on                     # square window corners
brutalium corners radius 0               # 0 = fully square
brutalium corners layers on              # square EVERY layer's corners (aggressive)
brutalium corners toolbar on             # square only toolbar-item corners (scoped)

# Toolbar ------------------------------------------------------------------
brutalium toolbar on                     # force the expanded toolbar style
brutalium toolbar exclude add com.apple.finder
brutalium toolbar exclude remove com.apple.finder
brutalium toolbar exclude list

# Titlebar removal (per app) -----------------------------------------------
brutalium titlebar hide com.foo.bar      # remove titlebar; keeps the toolbar if present
brutalium titlebar show com.foo.bar
brutalium titlebar list

# Window borders -----------------------------------------------------------
brutalium border on
brutalium border size 2
brutalium border color #FFFFFF           # active window   (#RRGGBB or #RRGGBBAA)
brutalium border inactive #555555        # inactive window (auto = same as active)
brutalium border shadow on | off

# Traffic lights -----------------------------------------------------------
brutalium lights on
brutalium lights radius 0
brutalium lights size +1
brutalium lights color close "#FF3B30"   # close|min|zoom|inactive|glyph
brutalium lights color inactive auto
brutalium lights theme nord              # 20 presets
brutalium lights theme list

# System tint --------------------------------------------------------------
brutalium tint on
brutalium tint theme nord                # 27 presets; or set colours manually:
brutalium tint color #1E1E28             # main background
brutalium tint chrome auto               # sidebars/titlebars/toolbars (auto = derive)
brutalium tint text #E6E6E6              # precise text colour (auto = follow appearance)
brutalium tint mode none                 # auto|light|dark|none base appearance
brutalium tint controls on               # also tint control backgrounds
brutalium tint icons on                  # tint toolbar (template) icons with the text colour
brutalium tint wallpaper off             # leave the desktop alone (default)
brutalium tint exclude add com.foo.bar   # never tint this app
brutalium tint exclude list

brutalium status                         # show all current settings
brutalium publish                        # apply now (also runs at login)
```

## Feature notes

**Corners.** Window squaring uses private `NSWindow` methods (`cornerRadius`,
`_setCornerRadius:`, `_cornerMask`, `_updateCornerMask`) best-effort across macOS
versions. `corners layers` is the aggressive option: a global `CALayer` swizzle that
forces every layer's `cornerRadius` to ~0, flattening *all* rounded rects (including
ones you might want round, like circular buttons). Off by default.

**Titlebar removal.** Applies only to standard `NSThemeFrame` main windows. The title
and traffic lights are hidden; if the window has a toolbar (e.g. Finder) the toolbar is
preserved. Custom-frame apps (Chrome/Electron/Thunderbird) are left untouched they
draw their own titlebar/tab strip and reserve a leading inset for the window controls
that a tweak can't reclaim, so removing it there would only leave an orphan gap.

**Borders.** Drawn on the window frame's own layer (so it never intercepts clicks) and
re-coloured on every focus/app-activation change. Use clearly different active/inactive
colours to see the switch. Follows the squared/rounded shape; `shadow` toggles the
window drop shadow.

**Tint.** Background recolouring works app-wide via the `NSColor` swizzle (no per-window
work). The precise `text` colour is base-agnostic pair it with `mode none` to fully
decouple text from the background. `icons` only affects *template* images (full-colour
icons are unchanged). Menus, popovers, selection and tooltip materials are left native
so hover highlights survive. Tint stays out of the screenshot UI and, unless
`tint wallpaper on`, the desktop process. Excluding a previously-tinted app restores its
original window opacity and background.

**Config transport.** Live settings (toggles, colours, sizes, modes) travel over Darwin
notify state so they reach sandboxed apps and apply instantly. The per-app *lists*
(toolbar exclude, tint exclude, titlebar hide) instead live in a single global-domain
key, `com.tweak.brutalium.lists` the same channel every app reads `AppleInterfaceStyle`
from, so it's readable inside any sandbox. That gives exact string matching (no Bloom
false positives) and an inspectable config (`defaults read -g com.tweak.brutalium.lists`),
at the cost of list changes applying on the target app's next launch rather than live.

## Thanks

@CoreBedtime (Ammonia), @aspauldingcode (apple-sharpener), @MTACS (Zephyr),
@ut0mt8 (uifixer).
