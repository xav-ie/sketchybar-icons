#!/usr/bin/env nu --stdin

# Native battery icon. Hands sketchybar a PNG rendered by `sketchybar-icons`.
# Replaces the old `Control Center,Battery` alias, which mirrored the menu-bar
# item by continuously screen-recording it. The `battery_change` event
# (percent + AC) is emitted by the `sketchybar-battery` daemon (pmset -g pslog).
#
# Both states use our custom battery: Apple's `battery.0` outline with a
# *continuous* proportional fill (SF Symbols only has 0/25/50/75/100 and its
# variable fill is inert, so 90% would otherwise look full). When charging, a
# bolt is knocked out of the fill — so charging also shows the true level.

const CACHE_DIR = ("~/.cache/sketchybar" | path expand)
# Point size (= battery body height) for the rendered icon.
const POINT_SIZE = 18
# SF Symbol weight for the battery.0 outline (stroke thickness): ultralight,
# thin, light, regular, medium, semibold, bold.
const WEIGHT = "thin"

def battery-color [percent: int, plugged: bool] {
  if $plugged {
    "0xff30d158" # green
  } else if $percent <= 20 {
    "0xffff453a" # red
  } else {
    "0xffffffff" # white
  }
}

# Low Power Mode on? (`pmset -g` reports `lowpowermode 0|1`.)
def is-lowpower [] {
  let m = (pmset -g | parse -r 'lowpowermode\s+(?<v>\d+)')
  ($m | length) > 0 and (($m | first | get v) == "1")
}

# Render (or reuse) the PNG for this state and return its path. The filename is
# derived from the icon's appearance so (a) sketchybar reloads whenever the look
# changes, since the path changes, and (b) unchanged states skip re-rendering.
def render [percent: int, plugged: bool] {
  let color = (battery-color $percent $plugged)
  let lvl = (($percent | into float) / 100)
  # Critically low (and not charging) shows a warning triangle overlay.
  let warn = ((not $plugged) and $percent <= 5)
  # Low Power Mode shows a yellow leaf badge. The renderer's priority is
  # charging > warning > low-power, so it only appears while discharging above 5%.
  let low = (is-lowpower)
  let key = $"fill-($percent)-($plugged)-($warn)-($low)-($color)-($POINT_SIZE)-($WEIGHT)" | str replace --all "0x" ""
  let out = $"($CACHE_DIR)/battery-($key).png"
  if not ($out | path exists) {
    sketchybar-icons battery --level $lvl --charging ($plugged | into string) --warn ($warn | into string) --lowpower ($low | into string) --point-size $POINT_SIZE --scale 2 --weight $WEIGHT --color $color --out $out
  }
  $out
}

def main [] {
  let item_props = [
    "click_script=$HOME/.config/sketchybar/select_control_center.nu \"Battery\""
    "icon.background.drawing=on"
    "icon.background.image.scale=0.5"
    "icon.padding_left=0"
    "icon.padding_right=0"
    "label.padding_left=0"
    "label.padding_right=0"
    "padding_left=0"
    "padding_right=0"
  ]

  match $env.SENDER {
    "forced" => {
      let batt = (pmset -g batt)
      let percent = ($batt | parse -r '(?<p>\d?\d?\d)%' | get p | first | into int)
      # "Now drawing from 'AC Power'" when plugged, "'Battery Power'" otherwise.
      let plugged = ($batt | str contains "AC Power")
      let out = (render $percent $plugged)
      sketchybar --set $"($env.NAME)" ...$item_props $"icon.background.image=($out)"
    }
    "battery_change" => {
      let percent = ($env.BATTERY | into int)
      let plugged = (($env.AC? | default "false") == "true")
      let out = (render $percent $plugged)
      sketchybar --set $"($env.NAME)" $"icon.background.image=($out)"
    }
    _ => {
      print $"battery_icon: ignoring event ($env.SENDER)"
    }
  }
}
