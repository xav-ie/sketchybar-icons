import AppKit

// sketchybar-icons — tiny helper for the sketchybar bar.
//
//   sketchybar-icons symbol --symbol <name> [--value <0..1>]
//                           [--point-size <n>] [--scale <n>]
//                           [--color <0xAARRGGBB>] [--palette <hex,hex,...>]
//                           --out <path>
//   sketchybar-icons wifi        # prints live Wi-Fi state (CoreWLAN)
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
  let level = flags["level"].flatMap { Double($0) } ?? 1.0
  let pointSize = flags["point-size"].flatMap { Double($0) } ?? 16.0
  let scale = flags["scale"].flatMap { Double($0) } ?? 2.0
  let charging = (flags["charging"] ?? "false") == "true"
  let warn = (flags["warn"] ?? "false") == "true"
  let lowPower = (flags["lowpower"] ?? "false") == "true"
  let color = parseColor(flags["color"] ?? "0xffffffff")
  let ok = drawBattery(
    level: level,
    charging: charging,
    warn: warn,
    lowPower: lowPower,
    pointSize: CGFloat(pointSize),
    scale: CGFloat(scale),
    weight: parseWeight(flags["weight"] ?? "regular"),
    colors: [color],
    outPath: outPath
  )
  if !ok { exit(1) }
  print((outPath as NSString).expandingTildeInPath)

case "symbol":
  let flags = parseFlags(args[2...])
  guard let name = flags["symbol"] else { fail("symbol: --symbol is required") }
  guard let outPath = flags["out"] else { fail("symbol: --out is required") }

  let variableValue = flags["value"].flatMap { Double($0) }
  let pointSize = flags["point-size"].flatMap { Double($0) } ?? 16.0
  let scale = flags["scale"].flatMap { Double($0) } ?? 2.0
  let minWidth = flags["min-width"].flatMap { Double($0) } ?? 0.0
  let xShift = flags["x-shift"].flatMap { Double($0) } ?? 0.0

  let colors: [NSColor]
  if let palette = flags["palette"], !palette.isEmpty {
    colors = palette.split(separator: ",").map { parseColor(String($0)) }
  } else {
    colors = [parseColor(flags["color"] ?? "0xffffffff")]
  }

  let ok = renderSymbol(
    name: name,
    variableValue: variableValue,
    pointSize: CGFloat(pointSize),
    scale: CGFloat(scale),
    colors: colors,
    minWidth: CGFloat(minWidth),
    xShift: CGFloat(xShift),
    outPath: outPath
  )
  if !ok { exit(1) }
  // Echo the path so callers can `let p = (sketchybar-icons symbol ...)`.
  print((outPath as NSString).expandingTildeInPath)

default:
  fail("unknown subcommand '\(args[1])' (expected: symbol, wifi)")
}
