# sketchybar-icons

Render **native macOS Battery / Wi-Fi icons** (and any SF Symbol) to PNG files for
[SketchyBar](https://github.com/FelixKratz/SketchyBar) — **without** the
`alias` feature, so your bar no longer needs Screen Recording permission.

## Gallery

Battery discharging — continuous fill, red when low, warning triangle when critical:

![battery discharging](assets/battery-discharging.png)

Battery charging — real level underneath a bolt with a knocked-out halo:

![battery charging](assets/battery-charging.png)

Wi-Fi — arcs fill by live RSSI, plus disconnected and off:

![wifi](assets/wifi.png)

> Prefer not to build anything? Grab a ready-made PNG set from the
> [latest release](https://github.com/xav-ie/sketchybar-icons/releases/latest).

## Why

SketchyBar's `alias` items (`"Control Center,Battery"`, `"Control Center,WiFi"`)
work by **continuously screen-capturing** the real macOS menu-bar items. That's
the reason SketchyBar shows up as "recording your screen" — and it burns more
power than drawing a glyph.

`sketchybar-icons` renders Apple's own SF Symbols to PNGs instead, so you get
pixel-native Battery/Wi-Fi icons with zero screen capture. It also reads live
Wi-Fi signal via CoreWLAN (no Location permission needed) and draws a
continuous-fill battery that SF Symbols can't produce on its own.

## Subcommands

```
sketchybar-icons symbol  --symbol <name> [--value 0..1] [--point-size N] [--scale N]
                         [--min-width pts] [--x-shift pts]
                         [--color 0xAARRGGBB] [--palette h,h,...] --out <path>

sketchybar-icons wifi    # prints: power=on associated=yes rssi=-56 fraction=0.83

sketchybar-icons battery --level 0..1 [--charging true|false] [--warn true|false]
                         [--point-size N] [--scale N] [--weight thin|regular|...]
                         [--color 0xAARRGGBB] --out <path>
```

- **`symbol`** — any SF Symbol → PNG. `--value` drives `variableValue` (e.g. the
  `wifi` symbol fills its arcs by signal). `--min-width`/`--x-shift` pad/center
  the glyph in the canvas (SketchyBar left-aligns background images).
- **`wifi`** — live Wi-Fi state from CoreWLAN. Uses only RSSI/power (never the
  SSID), so it needs **no** Location permission. `fraction` is RSSI mapped to
  0…1 (~-50 dBm → 1.0, ~-85 dBm → 0.0).
- **`battery`** — a macOS-style battery: Apple's `battery.0` outline with a
  **continuous proportional fill** (SF only has 0/25/50/75/100, and its battery
  `variableValue` is inert). `--charging` overlays a bolt with a uniform halo
  gap; `--warn` overlays a low-battery warning triangle. The fillable interior
  is measured from the rendered outline so it stays symmetric at any size/weight.

All rendering happens on demand — cache the PNGs by state and you re-render only
when the icon changes (vs. the alias's constant capture).

## Examples

```sh
# Wi-Fi at 66% signal, white, retina, centered in a 29pt-wide button
sketchybar-icons symbol --symbol wifi --value 0.66 --point-size 14 --scale 2 \
  --min-width 29 --x-shift 0.75 --color 0xffffffff --out ~/.cache/sketchybar/wifi.png

# Battery at 90%, discharging, thin outline, white
sketchybar-icons battery --level 0.90 --point-size 18 --scale 2 --weight thin \
  --color 0xffffffff --out ~/.cache/sketchybar/battery.png

# Charging at 45%, green with bolt
sketchybar-icons battery --level 0.45 --charging true --point-size 18 --scale 2 \
  --weight thin --color 0xff30d158 --out ~/.cache/sketchybar/battery.png
```

Point the item at the PNG:

```sh
sketchybar --set battery icon.background.image="$HOME/.cache/sketchybar/battery.png" \
                         icon.background.image.scale=0.5 icon.background.drawing=on
```

### Example plugins

See [`examples/`](./examples) for Nushell plugins (`battery_icon.nu`, `wifi.nu`)
that wire this into SketchyBar — including driving Wi-Fi off the
`com.apple.system.config.network_change` distributed notification and battery off
`pmset -g pslog`.

## Install (Nix)

```nix
# flake.nix
inputs.sketchybar-icons.url = "github:xav-ie/sketchybar-icons";

# then, on darwin:
inputs.sketchybar-icons.packages.${system}.default
```

Or build/run directly:

```sh
nix run github:xav-ie/sketchybar-icons -- battery --level 0.5 --out /tmp/b.png
```

### Without Nix

```sh
swiftc -O *.swift -o sketchybar-icons   # macOS, Swift toolchain
```

## License

MIT
