#!/usr/bin/env bash
# Regenerate the README gallery montages (assets/) from the binary.
# Reproducible so the docs track the real rendering — and rendered at the SAME
# point sizes the example plugins use, so what you see in the README matches
# what the bar actually draws (magnifying the docs is what hid earlier
# rendering regressions).
#
# Usage: render-gallery.sh <path-to-sketchybar-icons> [assets-dir]
# Requires ImageMagick (`magick`).
set -euo pipefail

BIN="${1:?usage: render-gallery.sh <sketchybar-icons> [assets-dir]}"
A="${2:-$(cd "$(dirname "$0")/.." && pwd)/assets}"
mkdir -p "$A"

# Match the example plugins (examples/*.nu).
BATT_PS=22 WIFI_PS=14 WIFI_MINW=26 WIFI_XSHIFT=0.75
WHITE=0xffffffff RED=0xffff453a GREEN=0xff30d158 YELLOW=0xffffd60a
INNER='#23232e' PAGE='#17171f'

lvl() { awk "BEGIN { printf \"%.2f\", $1 / 100 }"; }
# tile: PAGE-bg canvas with a rounded inner rect + the icon centred at its
# native rendered size (no upscaling — keep sizes bar-accurate & relative).
tile() { magick -size 108x60 xc:"$PAGE" -fill "$INNER" -draw "roundrectangle 6,4,101,55,9,9" \
  "$1" -gravity center -composite "$2"; }
# -strip drops PNG metadata (timestamps etc.) so output is byte-deterministic
# for a given OS + ImageMagick — lets CI regenerate and detect real changes.
row() { local out=$1; shift; magick "$@" +append -strip "$out"; }

# Battery rows: discharging / charging / low-power, 100→0 every 10%.
battrow() { # $1=outfile  $2=charging(true|false)  $3=lowpower-fill-colour("" if none)
  local out=$1 chg=$2 lpc=$3 i=0 f wn
  for p in $(seq 100 -10 0); do
    if [ "$chg" = true ]; then f=$GREEN wn=false
    elif [ "$p" -le 5 ]; then f=$RED wn=true
    elif [ "$p" -le 20 ]; then f=$RED wn=false
    elif [ -n "$lpc" ]; then f=$lpc wn=false
    else f=$WHITE wn=false; fi
    "$BIN" battery --level "$(lvl "$p")" --charging "$chg" --warn "$wn" \
      --point-size "$BATT_PS" --scale 2 --weight thin --color "$WHITE" --fill-color "$f" \
      --out /tmp/_g.png >/dev/null
    tile /tmp/_g.png "$A/_t$(printf '%03d' "$i").png"; i=$((i + 1))
  done
  row "$out" "$A"/_t*.png; rm -f "$A"/_t*.png
}
battrow "$A/battery-discharging.png" false ""
battrow "$A/battery-charging.png" true ""
battrow "$A/battery-lowpower.png" false "$YELLOW"

# Wi-Fi row: signal levels, hotspot, disconnected, off.
wifi() { # $1=symbol  $2=value("" for none)  $3=name
  "$BIN" symbol --symbol "$1" ${2:+--value "$2"} --point-size "$WIFI_PS" --scale 2 \
    --min-width "$WIFI_MINW" --x-shift "$WIFI_XSHIFT" --color "$WHITE" --out /tmp/_g.png >/dev/null
  tile /tmp/_g.png "$A/_w$3.png"
}
wifi wifi 1.0 1full
wifi wifi 0.5 2med
wifi wifi 0.2 3low
wifi personalhotspot "" 4hotspot
wifi wifi.exclamationmark "" 5disc
wifi wifi.slash "" 6off
row "$A/wifi.png" "$A"/_w*.png; rm -f "$A"/_w*.png

echo "Rendered gallery to $A"
