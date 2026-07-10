import AppKit

// sketchybar-icons — tiny helper for the sketchybar bar.
//
//   sketchybar-icons symbol --symbol <name> [--value <0..1>]
//                           [--point-size <n>] [--scale <n>]
//                           [--color <0xAARRGGBB>] [--palette <hex,hex,...>]
//                           --out <path>
//   sketchybar-icons wifi        # prints live Wi-Fi state (CoreWLAN)
//   sketchybar-icons clock  --hour <0..23> --minute <0..59>
//                           [--point-size <n>] [--scale <n>]
//                           [--color <0xAARRGGBB>] [--minute-color <0xAARRGGBB>]
//                           --out <path>
//
// Renders Apple's own SF Symbols to PNGs so the bar can draw native Battery/Wi-Fi
// icons without screen-recording the real Control Center items.

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("sketchybar-icons: \(message)\n".utf8))
  exit(1)
}

/// Turn `["--symbol", "wifi", "--out", "/x"]` into `["--symbol": "wifi", ...]`.
func parseFlags(_ args: ArraySlice<String>) -> [String: String] {
  var out: [String: String] = [:]
  var it = args.makeIterator()
  while let token = it.next() {
    guard token.hasPrefix("--") else { continue }
    let key = String(token.dropFirst(2))
    out[key] = it.next() ?? ""
  }
  return out
}

let args = CommandLine.arguments
guard args.count >= 2 else {
  fail("usage: sketchybar-icons <symbol|wifi> [flags]")
}

switch args[1] {
case "wifi":
  printWifiState()

case "battery":
  // Continuous-fill battery for the discharging case.
  let flags = parseFlags(args[2...])
  guard let outPath = flags["out"] else { fail("battery: --out is required") }
  // --color = outline (and overlay); --fill-color = the bar (defaults to --color).
  let color = flags.color("color")
  let colors = flags["fill-color"].map { [color, parseColor($0)] } ?? [color]
  let ok = drawBattery(
    level: flags.double("level", 1),
    charging: flags.bool("charging"),
    warn: flags.bool("warn"),
    pointSize: flags.cgFloat("point-size", 16),
    scale: flags.cgFloat("scale", 2),
    weight: parseWeight(flags["weight"] ?? "regular"),
    colors: colors,
    outPath: outPath
  )
  emit(ok, outPath)

case "clock":
  // Analog clock face at a given time (drawn directly, not an SF Symbol).
  let flags = parseFlags(args[2...])
  guard let outPath = flags["out"] else { fail("clock: --out is required") }
  // --color = ring + hour hand; --minute-color = minute hand (defaults to --color).
  let color = flags.color("color")
  let colors = flags["minute-color"].map { [color, parseColor($0)] } ?? [color]
  let ok = drawClock(
    hour: flags.int("hour", 0),
    minute: flags.int("minute", 0),
    pointSize: flags.cgFloat("point-size", 18),
    scale: flags.cgFloat("scale", 2),
    colors: colors,
    outPath: outPath
  )
  emit(ok, outPath)

case "app-icon":
  // Report whether SketchyBar's `app.<name>` lookup will find a real icon for
  // the front app — "native" if so, else "unknown". A front_app plugin uses this
  // to decide when to substitute its own glyph (SketchyBar draws a giant generic
  // document for faceless agents like SecurityAgent). *Which* glyph to draw is
  // the caller's policy, not ours — this only answers native-or-not.
  let flags = parseFlags(args[2...])
  print(runningAppIcon(name: flags["name"] ?? "") != nil ? "native" : "unknown")

case "symbol":
  let flags = parseFlags(args[2...])
  guard let name = flags["symbol"] else { fail("symbol: --symbol is required") }
  guard let outPath = flags["out"] else { fail("symbol: --out is required") }

  let variableValue = flags["value"].flatMap { Double($0) }
  let colors: [NSColor]
  if let palette = flags["palette"], !palette.isEmpty {
    colors = palette.split(separator: ",").map { parseColor(String($0)) }
  } else {
    colors = [flags.color("color")]
  }

  let ok = renderSymbol(
    name: name,
    variableValue: variableValue,
    pointSize: flags.cgFloat("point-size", 16),
    scale: flags.cgFloat("scale", 2),
    colors: colors,
    minWidth: flags.cgFloat("min-width", 0),
    xShift: flags.cgFloat("x-shift", 0),
    outPath: outPath
  )
  // Echo the path so callers can `let p = (sketchybar-icons symbol ...)`.
  emit(ok, outPath)

default:
  fail("unknown subcommand '\(args[1])' (expected: symbol, wifi, battery, clock)")
}
