# Brutalium

*Strip the gloss. Sharpen the edges.*

A macOS [Ammonia](https://github.com/CoreBedtime/ammonia) tweak that makes the whole UI brutally square

- **Square window corners** (configurable radius; `0` = fully square) + flatter titlebar.
- **Expanded toolbar style** forced everywhere, with a runtime per-app exclusion list.
- **Square traffic-light buttons** (close / minimise / zoom) with configurable colours, themes, size, and a hover glyph.

It merges two earlier tweaks — UIFixer (windows) and FlatLights (traffic lights) — into one dylib, one CLI, and one config.

## Architecture

One injected dylib, two feature modules over shared scaffolding:

- `Brutalium.m` — core: process gating, the notify-state config cache, window discovery, and the constructor that arms both modules.
- `BRWindows.m` — corners + toolbar (private `NSWindow` corner plumbing; `setToolbarStyle:` enforcement).
- `BRLights.m` — per-instance isa-swizzling of the three control buttons; square rendering + hover tracking.
- `BRState.h` / `BRConfig.h` — wire format (notify state) and the shared config cache.

Shared robustness: completely inert in Chromium/Electron child processes, swizzles armed only in real app processes, and all configuration carried over Darwin notify state so it reaches sandboxed apps (Finder, Mail, Notes, Safari…).

## Build & install

```sh
make
sudo make install
```

Relaunch apps to pick up the injection. Settings changes apply live.

## Usage

```sh
brutalium on                         # master enable

brutalium corners on                 # square window corners
brutalium corners radius 0           # 0 = fully square

brutalium toolbar on                 # force expanded toolbar
brutalium toolbar exclude add com.apple.finder
brutalium toolbar exclude list

brutalium lights on                  # square the traffic lights
brutalium lights radius 0
brutalium lights size +1
brutalium lights color close "#FF3B30"
brutalium lights color inactive auto
brutalium lights theme nord          # classic|mono|graphite|neon|nord|solarized|dracula
brutalium lights theme list

brutalium status
```

Find a bundle id with e.g. `osascript -e 'id of app "Finder"'`.

## Notes

- A `com.tweak.brutalium.publish` LaunchAgent republishes settings at login so sandboxed apps get them before launch; `brutalium publish` does it on demand.
- Corner squaring uses private `NSWindow` methods (`cornerRadius`, `_setCornerRadius:`, `_cornerMask`, `_updateCornerMask`) — best-effort across macOS versions.
- The toolbar exclusion list is a 128-bit Bloom filter in notify state (rare false positives just mean an app's toolbar isn't forced).

## Thanks

@CoreBedtime (Ammonia), @aspauldingcode (apple-sharpener), @MTACS (Zephyr)
