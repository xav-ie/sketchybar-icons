#!/usr/bin/env bash
# Regenerate the README gallery montages (assets/) from the binary.
# Reproducible so the docs track the real rendering — and rendered at the SAME
# point sizes the example plugins use, so what you see in the README matches
# what the bar actually draws (magnifying the docs is what hid earlier
# rendering regressions).
#
# Usage: nix run .#render-gallery [assets-dir]   (assets-dir defaults to ./assets)
#
# Runtime deps (sketchybar-icons, ImageMagick, oxipng) are bundled by the Nix
# app. To run this file directly instead, enter `nix develop` first so they're
# on PATH.
set -euo pipefail

# The renderer binary comes from PATH (the Nix app's runtimeInputs, or the
# devShell); the assets dir defaults to ./assets in the current directory.
BIN=sketchybar-icons
A="${1:-$(pwd)/assets}"
mkdir -p "$A"

# Scratch file for each freshly-rendered glyph before it's tiled. Honour $TMPDIR
# (the Nix build sandbox has no writable /tmp) and fall back to /tmp otherwise.
TMP="${TMPDIR:-/tmp}"

# Match the example plugins (examples/*.nu).
BATT_PS=22 WIFI_PS=14 WIFI_MINW=26 WIFI_XSHIFT=0.75 CLOCK_PS=20
WHITE=0xffffffff RED=0xffff453a GREEN=0xff30d158 YELLOW=0xffffd60a
INNER='#23232e' PAGE='none'

lvl() { awk "BEGIN { printf \"%.2f\", $1 / 100 }"; }
# tile: transparent canvas (PAGE=none) with a rounded inner "button" rect + the
# icon centred at its native rendered size (no upscaling — keep sizes
# bar-accurate & relative). Only the button tiles are painted; the surrounding
# page stays transparent so the gallery adapts to the README's light/dark theme.
tile() { magick -size 108x60 xc:"$PAGE" -fill "$INNER" -draw "roundrectangle 6,4,101,55,9,9" \
  "$1" -gravity center -composite "$2"; }
# -strip drops PNG metadata (timestamps etc.) so output is byte-deterministic
# for a given OS + ImageMagick — lets CI regenerate and detect real changes.
# Then losslessly optimise: these flat-colour glyph montages shrink a lot, and
# oxipng is deterministic so the byte-for-byte CI diff still holds.
row() {
  local out=$1
  shift
  magick "$@" +append -strip "$out"
  oxipng --opt max --strip safe --quiet "$out"
}

# Battery rows: discharging / low-power run 100→0; charging runs 0→100 so the
# row reads as filling up. $4 overrides the percent sequence.
battrow() { # $1=outfile  $2=charging(true|false)  $3=lowpower-fill-colour("" if none)  $4=percents
  local out=$1 chg=$2 lpc=$3 percents=${4:-"$(seq 100 -10 0)"} i=0 f wn
  for p in $percents; do
    if [ "$chg" = true ]; then
      f=$GREEN wn=false
    elif [ "$p" -le 5 ]; then
      f=$RED wn=true
    elif [ "$p" -le 20 ]; then
      f=$RED wn=false
    elif [ -n "$lpc" ]; then
      f=$lpc wn=false
    else f=$WHITE wn=false; fi
    "$BIN" battery --level "$(lvl "$p")" --charging "$chg" --warn "$wn" \
      --point-size "$BATT_PS" --scale 2 --weight thin --color "$WHITE" --fill-color "$f" \
      --out "$TMP/_g.png" >/dev/null
    tile "$TMP/_g.png" "$A/_t$(printf '%03d' "$i").png"
    i=$((i + 1))
  done
  row "$out" "$A"/_t*.png
  rm -f "$A"/_t*.png
}
battrow "$A/battery-discharging.png" false ""
battrow "$A/battery-charging.png" true "" "$(seq 0 10 100)"
battrow "$A/battery-lowpower.png" false "$YELLOW"

# Wi-Fi row: signal levels, hotspot, disconnected, off.
wifi() { # $1=symbol  $2=value("" for none)  $3=name
  "$BIN" symbol --symbol "$1" ${2:+--value "$2"} --point-size "$WIFI_PS" --scale 2 \
    --min-width "$WIFI_MINW" --x-shift "$WIFI_XSHIFT" --color "$WHITE" --out "$TMP/_g.png" >/dev/null
  tile "$TMP/_g.png" "$A/_w$3.png"
}
wifi personalhotspot "" 1hotspot
wifi wifi 1.0 2full
wifi wifi 0.5 3med
wifi wifi 0.2 4low
wifi wifi.exclamationmark "" 5disc
wifi wifi.slash "" 6off
row "$A/wifi.png" "$A"/_w*.png
rm -f "$A"/_w*.png

# Clock row: analog faces through the day, white face + red minute hand. Varied
# minutes (not just :00) so the minute-hand precision the Nerd Font can't do reads.
clockrow() { # $1=outfile
  local out=$1 i=0
  local times=("0 0" "2 10" "4 20" "6 35" "8 45" "10 5" "13 15" "15 25" "17 40" "19 50" "22 55")
  for t in "${times[@]}"; do
    # shellcheck disable=SC2086
    set -- $t
    "$BIN" clock --hour "$1" --minute "$2" --point-size "$CLOCK_PS" --scale 2 \
      --color "$WHITE" --minute-color "$RED" --out "$TMP/_g.png" >/dev/null
    tile "$TMP/_g.png" "$A/_c$(printf '%03d' "$i").png"
    i=$((i + 1))
  done
  row "$out" "$A"/_c*.png
  rm -f "$A"/_c*.png
}
clockrow "$A/clock.png"

# System row: static SF Symbols that replace common Nerd-Font bar glyphs — the
# Control Center toggles (switch.2) and the macOS volume family (speaker.*).
# Rendered all-white via `--palette` (multi-layer symbols, so a single
# hierarchical colour would dim the toggles/waves) using the generic `symbol`
# subcommand. Matches wifi's point size so they line up in a bar.
sysicon() { # $1=symbol  $2=name
  "$BIN" symbol --symbol "$1" --point-size "$WIFI_PS" --scale 2 \
    --palette "$WHITE,$WHITE,$WHITE,$WHITE" --out "$TMP/_g.png" >/dev/null
  tile "$TMP/_g.png" "$A/_s$2.png"
}
sysicon switch.2 1cc
sysicon speaker.slash.fill 2mute
sysicon speaker.fill 3vol0
sysicon speaker.wave.1.fill 4vol1
sysicon speaker.wave.2.fill 5vol2
sysicon speaker.wave.3.fill 6vol3
row "$A/system.png" "$A"/_s*.png
rm -f "$A"/_s*.png

# App-icon fallback row: the glyphs `app-icon` substitutes for faceless system
# agents SketchyBar can't resolve to a real icon (SecurityAgent → touchid, …),
# ending with the `questionmark` catch-all. Rendered exactly as the front_app
# plugin draws them (single white --color), so the row matches the bar.
appicon() { # $1=symbol  $2=name
  "$BIN" symbol --symbol "$1" --point-size "$WIFI_PS" --scale 2 \
    --color "$WHITE" --out "$TMP/_g.png" >/dev/null
  tile "$TMP/_g.png" "$A/_a$2.png"
}
appicon touchid 1touchid
appicon hand.raised.fill 2gatekeeper
appicon person.badge.key.fill 3netauth
appicon location.fill 4location
appicon eject.fill 5eject
appicon wifi 6wifiagent
appicon airplayvideo 7airplay
appicon questionmark 8unknown
row "$A/app-icon.png" "$A"/_a*.png
rm -f "$A"/_a*.png

echo "Rendered gallery to $A"
