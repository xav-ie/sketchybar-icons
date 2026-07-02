#!/usr/bin/env bash
# Render a ready-to-use PNG icon set with sketchybar-icons.
# Usage: render-icon-pack.sh <path-to-sketchybar-icons> <out-dir>
set -euo pipefail

BIN="${1:?usage: render-icon-pack.sh <sketchybar-icons> <out-dir>}"
OUT="${2:?usage: render-icon-pack.sh <sketchybar-icons> <out-dir>}"
PS=24 # point size (retina, drawn at background.image.scale 0.5)

mkdir -p "$OUT/battery" "$OUT/wifi"

lvl() { awk "BEGIN { printf \"%.2f\", $1 / 100 }"; }

# Battery, discharging: white, red at <=20%, warning triangle at <=5%.
for p in $(seq 0 5 100); do
  if [ "$p" -le 5 ]; then
    color=0xffff453a warn=true
  elif [ "$p" -le 20 ]; then
    color=0xffff453a warn=false
  else
    color=0xffffffff warn=false
  fi
  "$BIN" battery --level "$(lvl "$p")" --charging false --warn "$warn" \
    --point-size "$PS" --scale 2 --weight thin --color "$color" \
    --out "$OUT/battery/discharge-$(printf '%03d' "$p").png"
done

# Battery, charging: green with bolt.
for p in $(seq 0 5 100); do
  "$BIN" battery --level "$(lvl "$p")" --charging true --warn false \
    --point-size "$PS" --scale 2 --weight thin --color 0xff30d158 \
    --out "$OUT/battery/charge-$(printf '%03d' "$p").png"
done

# Wi-Fi: signal levels, disconnected, off.
wifi() { "$BIN" symbol --symbol "$1" ${2:+--value "$2"} --point-size 18 --scale 2 \
  --min-width 26 --x-shift 0.75 --color 0xffffffff --out "$OUT/wifi/$3.png"; }
wifi wifi 1.0 full
wifi wifi 0.66 high
wifi wifi 0.34 low
wifi wifi.exclamationmark "" disconnected
wifi wifi.slash "" off

echo "Rendered icon pack to $OUT"
