# Brutalium

*Strip the gloss. Sharpen the edges.*

A macOS [Ammonia](https://github.com/CoreBedtime/ammonia) or playground tweak that makes the whole UI brutally square — and optionally recolours it — for every app:

- **Square window corners** (configurable radius; `0` = fully square).
- **Expanded toolbar style** forced everywhere, with a runtime per-app exclusion list.
- **Remove titlebar** disable by default, per-app include list.
- **Square traffic-light buttons** (close / minimise / zoom) with configurable colours, themes, size, and a hover glyph.
- **Border over windows** (configurable, with colours, size and shadows.

## Architecture

One injected dylib, two feature modules over shared scaffolding:

- `Brutalium.m` — core: process gating, the notify-state config cache, window discovery, and the constructor that arms both modules.
- `BRWindows.m` — corners + toolbar (private `NSWindow` corner plumbing; `setToolbarStyle:` enforcement).
- `BRLights.m` — per-instance isa-swizzling of the three control buttons; square rendering + hover tracking.
- `BRState.h` / `BRConfig.h` — wire format (notify state) and the shared config cache.

Shared robustness: completely inert in Chromium/Electron child processes, and the swizzles are armed only in real app processes. FlatLights squares the traffic lights via a one-time class-level method swizzle of the three private window-button classes — it never reclasses individual buttons, so it coexists with the `NSKVONotifying_` subclasses and Swift titlebar property system AppKit uses under Solarium (squared lights work whether Solarium is on or off). Per-window discovery (for the hover glyph and prompt repaint) targets only genuine top-level main windows, skipping child windows, panels, popovers, and overlays. All configuration is carried over Darwin notify state so it reaches sandboxed apps (Finder, Mail, Notes, Safari…).

## Build & install

```sh
make
sudo make install
```

Relaunch apps to pick up the injection. Settings changes apply live.

## Usage

```sh
Brutalium — square corners, expanded toolbar, square traffic lights, system tint

Usage: brutalium <command>

  on | off | toggle              Master enable

  corners on | off               Square window corners
  corners radius <value>         0 = fully square

  toolbar on | off               Force expanded toolbar
  toolbar exclude add <bundleid> Don't force toolbar for this app
  toolbar exclude remove <bundleid>
  toolbar exclude list

  titlebar hide <bundleid>       Remove the titlebar entirely for this app
  titlebar show <bundleid>       Stop removing it
  titlebar list

  border on | off                Draw a border on every window
  border size <points>           Border width
  border color <#RRGGBB|#RRGGBBAA>          Active-window border colour
  border inactive <#RRGGBB|#RRGGBBAA|auto>  Inactive-window colour (auto = same as active)
  border shadow on | off         Window drop shadow

  lights on | off                Square the traffic-light buttons
  lights radius <value>          Traffic-light corner radius
  lights size <delta>            Adjust square size in points
  lights color <slot> <value>    slot = close|min|zoom|inactive|glyph
                                 value = #RRGGBB / #RRGGBBAA (inactive: auto)
  lights theme <name> | list     Apply a colour preset

  tint on | off                  Recolour the whole UI background
  tint color <#RRGGBB>           Main background colour
  tint chrome <#RRGGBB|auto>     Sidebar/titlebar/toolbar colour
  tint text <#RRGGBB|auto>       Precise text colour (auto = follow appearance)
  tint mode auto|light|dark|none Base appearance for controls/vibrancy
  tint controls on | off         Also tint control backgrounds
  tint icons on | off            Tint toolbar (template) icons with the text colour
  tint wallpaper on | off        Also tint the desktop/wallpaper process
  tint theme <name> | list       Apply a main+chrome preset
  tint exclude add <bundleid>    Don't tint this app at all
  tint exclude remove <bundleid>
  tint exclude list

  status
  publish
```

Find a bundle id with e.g. `osascript -e 'id of app "Finder"'`.


## Tint (system colour)

Folded in from BrutalTint: recolour the whole UI background to any colour, with a
separate chrome colour for vibrancy areas (sidebars/titlebars/toolbars). Off by
default — turn it on explicitly.

```sh
brutalium tint on
brutalium tint theme nord        # or: tint color #1E1E28 ; tint chrome auto
brutalium tint text #E6E6E6      # precise text colour, agnostic of the base (auto = follow appearance)
brutalium tint mode none         # auto|light|dark|none — base appearance for controls/vibrancy
brutalium tint icons on          # tint toolbar template icons with the text colour
brutalium tint controls on       # also tint control backgrounds
brutalium tint wallpaper off     # leave the desktop alone (default)
brutalium tint exclude add com.foo.bar   # never tint this app
brutalium publish
```

Tint stays out of the screenshot UI and (unless `tint wallpaper on`) the desktop
process. `tint theme list` shows the presets.

## Titlebar removal (per app)

Remove the titlebar entirely for chosen apps — content floats up under a hidden,
transparent titlebar and the titlebar container (with its traffic-light buttons) is
hidden. The window stays draggable by its body.

```sh
brutalium titlebar hide com.foo.bar
brutalium titlebar show com.foo.bar
brutalium titlebar list
brutalium publish && killall <app>
```

## Window borders

A configurable border + drop shadow on every titled window.

```sh
brutalium border on
brutalium border size 2
brutalium border color #00000080     # active-window colour (#RRGGBB or #RRGGBBAA)
brutalium border inactive #00000030  # inactive-window colour (auto = same as active)
brutalium border shadow off
brutalium publish
```

The border is drawn on the window frame layer, so it follows the squared (or rounded)
window shape.

## Notes

- A `com.tweak.brutalium.publish` LaunchAgent republishes settings at login so sandboxed apps get them before launch; `brutalium publish` does it on demand.
- Corner squaring uses private `NSWindow` methods (`cornerRadius`, `_setCornerRadius:`, `_cornerMask`, `_updateCornerMask`) — best-effort across macOS versions.
- The toolbar exclusion list is a 128-bit Bloom filter in notify state (rare false positives just mean an app's toolbar isn't forced).

## Thanks

@CoreBedtime (Ammonia/Playground), @aspauldingcode (apple-sharpener), @MTACS (Zephyr)
