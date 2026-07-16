#!/usr/bin/env bash
# Render a ready-to-use PNG icon set with sketchybar-icons.
# Usage: render-icon-pack.sh <path-to-sketchybar-icons> <out-dir>
set -euo pipefail

BIN="${1:?usage: render-icon-pack.sh <sketchybar-icons> <out-dir>}"
OUT="${2:?usage: render-icon-pack.sh <sketchybar-icons> <out-dir>}"
PS=24 # point size (retina, drawn at background.image.scale 0.5)

mkdir -p "$OUT/battery" "$OUT/wifi" "$OUT/zoom"

lvl() { awk "BEGIN { printf \"%.2f\", $1 / 100 }"; }

WHITE=0xffffffff RED=0xffff453a GREEN=0xff30d158 YELLOW=0xffffd60a
# Outline is always white; only the bar (--fill-color) is coloured.
batt() { "$BIN" battery --point-size "$PS" --scale 2 --weight thin --color "$WHITE" "$@"; }

# Discharging: white bar, red at <=20%, warning triangle at <=5%.
for p in $(seq 0 5 100); do
  if [ "$p" -le 5 ]; then
    f=$RED warn=true
  elif [ "$p" -le 20 ]; then
    f=$RED warn=false
  else
    f=$WHITE warn=false
  fi
  batt --level "$(lvl "$p")" --charging false --warn "$warn" --fill-color "$f" \
    --out "$OUT/battery/discharge-$(printf '%03d' "$p").png"
done

# Charging: green bar with bolt.
for p in $(seq 0 5 100); do
  batt --level "$(lvl "$p")" --charging true --fill-color "$GREEN" \
    --out "$OUT/battery/charge-$(printf '%03d' "$p").png"
done

# Low Power Mode: yellow bar (red at <=20%, warning at <=5%).
for p in $(seq 0 5 100); do
  if [ "$p" -le 5 ]; then
    f=$RED warn=true
  elif [ "$p" -le 20 ]; then
    f=$RED warn=false
  else
    f=$YELLOW warn=false
  fi
  batt --level "$(lvl "$p")" --charging false --warn "$warn" --fill-color "$f" \
    --out "$OUT/battery/lowpower-$(printf '%03d' "$p").png"
done

# Wi-Fi: signal levels, disconnected, off.
wifi() { "$BIN" symbol --symbol "$1" ${2:+--value "$2"} --point-size 18 --scale 2 \
  --min-width 26 --x-shift 0.75 --color 0xffffffff --out "$OUT/wifi/$3.png"; }
# The wifi glyph has 3 arc levels; values must land in distinct variableValue
# bands (0.2 / 0.5 / 1.0) or adjacent levels render identically.
wifi wifi 1.0 full
wifi wifi 0.5 medium
wifi wifi 0.2 low
wifi personalhotspot "" hotspot
wifi wifi.exclamationmark "" disconnected
wifi wifi.slash "" off

# Zoom mute indicator: mic.fill live = red (you're being heard), mic.slash.fill
# muted = white (safe/quiet). Colour passed as a two-entry palette (both the
# same) so multi-layer glyphs render FLAT, not SF's two-tone hierarchical gray.
# Matches ../dots sketchybar zoom_mute.nu.
"$BIN" symbol --symbol mic.fill --point-size 16 --scale 2 --palette "$RED,$RED" \
  --out "$OUT/zoom/unmuted.png"
"$BIN" symbol --symbol mic.slash.fill --point-size 16 --scale 2 --palette "$WHITE,$WHITE" \
  --out "$OUT/zoom/muted.png"

echo "Rendered icon pack to $OUT"
