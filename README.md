# Brutalium

A macOS [Ammonia/Playground](https://github.com/CoreBedtime/) tweak that makes the whole
UI brutally square and optionally recolours / reshapes / themes it for every app:

- **Square window corners** (configurable radius; `0` = fully square) + flatter titlebar.
- **Square *every* layer's corners** (optional, aggressive): buttons, fields, popovers, menus.
- **Expanded toolbar style** forced everywhere, with a per-app exclusion list.
- **Square traffic-light buttons** (close / minimise / zoom) with configurable colours, themes, size, and a hover glyph. Each button can also be replaced with its own image (auto-dimmed when the window is unfocused; clicks unaffected).
- **System tint**: recolour the whole UI to any colour background, chrome, precise text, toolbar icons with themes and a per-app exclusion list.
- **De-glass**: flatten Tahoe's Liquid Glass (`NSGlassEffectView`) to an opaque panel window-background or a fixed colour with a per-app exclusion list. Glass surfaces can also be painted with a tiled image, so a seamless texture repeats cleanly at any panel size.
- **Custom titlebar**: give the titlebar strip a plain colour *or* a background image (traffic lights + title kept, toolbar left alone) a draggable custom window frame alongside the border.
- **Titlebar removal** per app (keeps the toolbar where there is one).
- **Window borders** with separate active/inactive colours, width, and a drop-shadow toggle. The border reserves its own space content and the titlebar are inset by the border width so even thick borders never cover the window contents.

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
brutalium titlebar color #1E1E28         # colour the titlebar strip
brutalium titlebar color off             # stop colouring
brutalium titlebar image ~/pic.png       # image background for the strip
brutalium titlebar image off             # back to the flat colour

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
brutalium lights image close ~/x.png     # per-button image (close|min|zoom); 'off' disables
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

brutalium glass off                      # flatten glass to an opaque panel
brutalium glass on                       # restore glass (default)
brutalium glass color #1E1E28            # fixed fill colour...
brutalium glass image ~/tex.png          # paint glass surfaces with an image
brutalium glass color auto               # ...or the window background (default)
brutalium glass exclude add com.foo.bar  # leave this app's glass alone
brutalium glass exclude list

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

**Borders.** Drawn on the window frame's own layer (so it never intercepts clicks) and re-coloured on every focus/app-activation change. A CALayer border draws *inward*, which would overlap content, so the border reserves its space: the titlebar container and content view are inset inward by the border width and the border sits in the exposed margin a real ring around everything, with content and traffic lights inside it. Recomputed on every window event so it tracks live resizes; natural layout is restored when the border is off. Standard `NSThemeFrame` windows only; apps that pin their content view with Auto Layout can override the inset, and there a thick border may still overlap. `shadow` toggles the window drop shadow.

**Tint.** Background recolouring works app-wide via the `NSColor` swizzle (no per-window
work). The precise `text` colour is base-agnostic pair it with `mode none` to fully
decouple text from the background. `icons` only affects *template* images (full-colour
icons are unchanged). Menus, popovers, selection and tooltip materials are left native
so hover highlights survive. Tint stays out of the screenshot UI and, unless
`tint wallpaper on`, the desktop process. Excluding a previously-tinted app restores its
original window opacity and background.

**De-glass.** `NSGlassEffectView` isn't layer-backed and renders its content *through* the glass, so there's no filter to strip or backing layer to recolour. Brutalium instead paints the view's `ContentHolderView` layer opaque at the view's own corner radius a solid rounded panel, content intact. It targets the public glass class only; system chrome drawn by private glass views is unaffected. Changes apply live to open windows.

**Custom titlebar.** The titlebar background is glass, so we don't recolour it we insert an opaque, draggable bar into `NSTitlebarView` below the title (in front of the backdrops, behind the controls), sized to just the strip above any toolbar/format-bar accessory. Traffic lights and title stay live on top; the toolbar keeps its own look. Standard `NSThemeFrame` windows only. A background image works the same way, with one wrinkle: sandboxed apps can't read an arbitrary file path, so the CLI (which runs unsandboxed as you) downscales the image, re-encodes it as PNG, and stores it base64 in a global-domain key the same launch-readable channel the exclusion lists use. The dylib decodes it once and aspect-fills it into the strip. Because it's cached in prefs, image changes apply on the target app's next launch, and very large images bloat the global domain, so keep them modest (the CLI caps the longest side at 600px).

**Images (shared).** Titlebar, glass, and traffic lights all draw images through one registry: the CLI downscales + base64-encodes each image and writes a single `{ role : image }` dictionary to a global-domain key; the dylib decodes each role once (re-decoding only when it changes) and every feature asks for its role by name (`titlebar`, `glass`, `light.close`/`light.min`/`light.zoom`). Each feature renders to suit its surface: the titlebar strip aspect-fills a single image; glass fills its panels with a repeating tile (via a `CGPattern` colour) so a seamless texture never stretches; the traffic lights draw one image per button, clipped to the button shape and dimmed when the window is unfocused. Per-feature enable flags ride the notify words; the image bytes ride the global domain. Same relaxed timing as the exclusion lists changes apply on the target app's next launch so keep textures modest (the CLI caps the longest side at 600px, 64px for the tiny buttons).

**Config transport.** Live settings (toggles, colours, sizes, modes) travel over Darwin
notify state so they reach sandboxed apps and apply instantly. The per-app *lists*
(toolbar exclude, tint exclude, titlebar hide, glass exclude) instead live in a single global-domain
key, `com.tweak.brutalium.lists` the same channel every app reads `AppleInterfaceStyle`
from, so it's readable inside any sandbox. That gives exact string matching (no Bloom
false positives) and an inspectable config (`defaults read -g com.tweak.brutalium.lists`),
at the cost of list changes applying on the target app's next launch rather than live.

## Thanks

@CoreBedtime (Ammonia), @aspauldingcode (apple-sharpener), @MTACS (Zephyr)
