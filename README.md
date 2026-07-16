# sketchybar-icons

Render **native macOS Battery / Wi-Fi icons** (and any SF Symbol) to PNG files
for [SketchyBar](https://github.com/FelixKratz/SketchyBar) — **without** the `alias` feature, so your bar no longer needs
Screen Recording permission.

## Gallery

<!-- Widths are proportional to each strip's tile count so every icon renders
the same size (battery + clock rows have 11 tiles = 100%; the wifi row has
6 = ~54.5%; the system and app-icon rows have 8 = ~72.7%). -->

Battery discharging — continuous fill, red when low, warning triangle when
critical:

<img src="assets/battery-discharging.png" width="100%" alt="battery
  discharging">

Battery charging — real level under a bolt with a knocked-out halo:

<img src="assets/battery-charging.png" width="100%" alt="battery charging">

Low Power Mode — the bar turns yellow (still red when low, warning when
critical):

<img src="assets/battery-lowpower.png" width="100%" alt="battery low power
  mode">

Wi-Fi — Personal Hotspot, then arcs filling by live RSSI, disconnected, and
off:

<img src="assets/wifi.png" width="54.5%" alt="wifi">

Clock — a hand-drawn analog face with real minute-hand precision (red minute
hand):

<img src="assets/clock.png" width="100%" alt="clock">

Control Center + Volume + Mic — the `switch.2` toggles, the macOS `speaker.*`
family (muted, then 0→3 waves), and the `mic.*` mute indicator (live red — you're
being heard — then muted white):

<img src="assets/system.png" width="72.7%" alt="control center, volume and mic">

App-icon fallbacks — a selection of SF Symbols suited to the faceless system
agents that have no real icon (Touch ID, Gatekeeper, share login, location,
eject, Wi-Fi, AirPlay), ending with the `questionmark` catch-all:

<img src="assets/app-icon.png" width="72.7%" alt="app-icon fallbacks">

> [!NOTE]
> Prefer not to build anything? Grab a ready-made PNG set from the [latest
> release](https://github.com/xav-ie/sketchybar-icons/releases/latest).

## Why

SketchyBar's `alias` items draw the real menu-bar icons by **continuously
screen-capturing** them — that's why SketchyBar asks for Screen Recording, and
it wastes power.

`sketchybar-icons` renders Apple's SF Symbols to PNGs instead:
no screen capture, live Wi-Fi signal from CoreWLAN (no Location permission),
and a continuous-fill battery that SF Symbols can't draw on their own. Render
on demand and cache the PNGs by state, so you only re-render when an icon
actually changes.

## Subcommands

Each subcommand writes a PNG to `--out` (except `wifi` and `app-icon`, which
print a line). Common flags: `--point-size N`, `--scale N`, `--color
0xAARRGGBB`.

```
sketchybar-icons symbol  --symbol <name> [--value 0..1] [--min-width pts]
                         [--x-shift pts] [--palette h,h,...] --out <path>

sketchybar-icons battery --level 0..1 [--charging true|false]
                         [--warn true|false] [--weight thin|regular|...]
                         [--fill-color 0xAARRGGBB] --out <path>

sketchybar-icons clock   --hour 0..23 --minute 0..59 [--minute-color 0xAARRGGBB]
                         --out <path>

# prints: power=on associated=yes rssi=-56 fraction=0.83
sketchybar-icons wifi

# prints: native | unknown
sketchybar-icons app-icon --name "<localized app name>"
```

- **`symbol`** — any SF Symbol → PNG. `--value` fills variable symbols (e.g.
  `wifi` arcs by signal); `--palette` colors layers instead of `--color`.
- **`battery`** — macOS-style battery with a proportional fill (SF only has
  0/25/50/75/100). `--charging` adds a bolt, `--warn` a warning triangle.
- **`clock`** — analog face with real minute-hand precision, drawn to match SF's
  optical style. `--color` tints the ring + hour hand.
- **`wifi`** — live Wi-Fi state from CoreWLAN using only RSSI/power (never the
  SSID), so it needs no Location permission.
- **`app-icon`** — see [App-icon fallbacks](#app-icon-fallbacks).

## App-icon fallbacks

For a `front_app_switched` plugin, `app-icon --name "<localized app name>"`
reports whether SketchyBar's own `app.<name>` lookup will find a real icon —
`native` or `unknown`. On `unknown` — a faceless system agent SketchyBar would
otherwise draw as a giant generic document — the plugin substitutes its own
glyph, rendered with the `symbol` subcommand. _Which_ glyph fits _which_ agent
is the plugin's policy, not this tool's; `app-icon` only answers native-or-not.

Some SF Symbols that suit the agents you'll commonly see (render any by its
verbatim SF Symbol name, e.g. `symbol --symbol touchid`):

| SF Symbol               | Suits                                                   |
| ----------------------- | ------------------------------------------------------- |
| `touchid`               | Touch ID / sudo authentication (`SecurityAgent`)        |
| `hand.raised.fill`      | Gatekeeper / quarantine dialogs (`CoreServicesUIAgent`) |
| `person.badge.key.fill` | Network share login (`NetAuthAgent`)                    |
| `location.fill`         | Location permission prompt (`CoreLocationAgent`)        |
| `eject.fill`            | Disk not ejected properly (`UnmountAssistantAgent`)     |
| `wifi`                  | Captive portal / join network (`WiFiAgent`)             |
| `airplayvideo`          | AirPlay PIN entry (`AirPlayUIAgent`)                    |
| `questionmark`          | Catch-all when nothing more specific fits               |

See [`examples/front_app.nu`](./examples/front_app.nu) for a plugin that wires
this up — its `FALLBACK_SYMBOLS` table is where these mappings live.

## Examples

```sh
# Wi-Fi at 66% signal, white, retina, centered in a 29pt-wide button
sketchybar-icons symbol --symbol wifi --value 0.66 --point-size 14 --scale 2 \
  --min-width 29 --x-shift 0.75 --color 0xffffffff \
  --out ~/.cache/sketchybar/wifi.png

# Battery at 90%, discharging, thin outline, white
sketchybar-icons battery --level 0.90 --point-size 18 --scale 2 --weight thin \
  --color 0xffffffff --out ~/.cache/sketchybar/battery.png

# Analog clock at 10:08, white face with a red minute hand
sketchybar-icons clock --hour 10 --minute 8 --point-size 18 --scale 2 \
  --color 0xffffffff --minute-color 0xffff453a \
  --out ~/.cache/sketchybar/clock.png
```

Point the item at the PNG:

```sh
sketchybar --set battery \
  icon.background.image="$HOME/.cache/sketchybar/battery.png" \
  icon.background.image.scale=0.5 icon.background.drawing=on
```

See [`examples/`](./examples) for ready-made Nushell plugins (`battery_icon.nu`,
`wifi.nu`, `front_app.nu`) that wire this into SketchyBar.

## Install (Nix ❄️)

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
