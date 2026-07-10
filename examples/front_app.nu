#!/usr/bin/env nu --stdin

# Front-app icon. On every app switch sketchybar's `front_app_switched` event
# hands us the new app's localized name in $env.INFO. sketchybar can draw a real
# app icon itself via the `app.<name>` background image — but for faceless system
# agents (the Touch ID prompt, Gatekeeper, ...) that lookup finds nothing and it
# falls back to a giant generic document. So we ask `sketchybar-icons app-icon`
# whether a real icon exists; if not, we draw our own SF Symbol glyph instead.
#
# Wire it up in your sketchybarrc:
#   sketchybar --add item front_app left \
#              --set front_app script="$CONFIG_DIR/plugins/front_app.nu" \
#              --subscribe front_app front_app_switched

const CACHE_DIR = "~/.cache/sketchybar" | path expand
# On-screen glyph height in px (rendered at 2x, drawn at background.image.scale
# 0.5). Included in the cache filename so bumping it busts stale PNGs.
const POINT_SIZE = 16

# The heart of the mapping: an SF Symbol to draw for apps sketchybar can't
# resolve to a real icon — the faceless system agents that momentarily become the
# front app to show a prompt. Keyed by the localized name sketchybar reports in
# $env.INFO. Add a row to map a new one; anything unlisted falls through to
# `questionmark` — and since its name still shows as the bar label, you'll know
# exactly which key to add.
const FALLBACK_SYMBOLS = {
  SecurityAgent: touchid # Touch ID / sudo prompt
  CoreServicesUIAgent: hand.raised.fill # Gatekeeper / quarantine dialogs
  NetAuthAgent: person.badge.key.fill # network share login
  CoreLocationAgent: location.fill # location permission prompt
  UnmountAssistantAgent: eject.fill # disk not ejected properly
  WiFiAgent: wifi # captive portal / join network
  AirPlayUIAgent: airplayvideo # AirPlay PIN entry
}

# Render (or reuse) a white glyph PNG for an SF Symbol and return its path.
# Rendering once to a stable path (keyed by symbol name) lets sketchybar cache it
# like a real app icon, instead of re-decoding a rewritten file on every switch —
# which would make the icon flicker.
def render-glyph [symbol: string] {
  let out = $"($CACHE_DIR)/front-app-($symbol)-($POINT_SIZE).png"
  if not ($out | path exists) {
    sketchybar-icons symbol --symbol $symbol --point-size $POINT_SIZE --scale 2 --color 0xffffffff --out $out
  }
  $out
}

def draw [name: string] {

  # `sketchybar-icons app-icon` mirrors sketchybar's own app.<name> lookup, so we
  # learn *ahead of time* whether the native path will produce a real icon.
  let image_args = if (sketchybar-icons app-icon --name $name | str trim) == "native" {
    # A real icon exists — let sketchybar draw it.
    [$"icon.background.image=app.($name)" "icon.background.image.scale=0.80"]
  } else {
    # No icon — substitute our own glyph (a mapped one, or a question mark).
    let sym = $FALLBACK_SYMBOLS | get --optional $name | default questionmark
    [
      $"icon.background.image=(render-glyph $sym)"
      "icon.background.image.scale=0.5"
    ]
  }
  sketchybar --set $env.NAME $"label=($name)" ...$image_args
}

def main [] {
  match $env.SENDER {
    "front_app_switched" => { draw $env.INFO }
    "forced" => {
      # Bar (re)load: set static props. The first real icon appears on the next
      # app switch, when `front_app_switched` fires with $env.INFO.
      sketchybar --set $env.NAME "icon.background.drawing=on" "label.padding_left=4" "label.padding_right=4"
    }
    _ => {
      print $"front_app: ignoring event ($env.SENDER)"
    }
  }
}
