import AppKit

/// Parse a color literal in the form `0xAARRGGBB` (or `0xRRGGBB`, assumed fully
/// opaque) into an `NSColor`. Falls back to opaque white on a parse failure so a
/// bad argument still renders something visible rather than crashing.
func parseColor(_ raw: String) -> NSColor {
  var s = raw.lowercased()
  if s.hasPrefix("0x") { s.removeFirst(2) }
  if s.hasPrefix("#") { s.removeFirst() }
  guard let value = UInt32(s, radix: 16) else {
    return .white
  }
  let (a, r, g, b): (UInt32, UInt32, UInt32, UInt32)
  if s.count <= 6 {
    a = 0xff
    r = (value >> 16) & 0xff
    g = (value >> 8) & 0xff
    b = value & 0xff
  } else {
    a = (value >> 24) & 0xff
    r = (value >> 16) & 0xff
    g = (value >> 8) & 0xff
    b = value & 0xff
  }
  return NSColor(
    srgbRed: CGFloat(r) / 255.0,
    green: CGFloat(g) / 255.0,
    blue: CGFloat(b) / 255.0,
    alpha: CGFloat(a) / 255.0
  )
}

private let symbolWeights: [String: NSFont.Weight] = [
  "ultralight": .ultraLight,
  "thin": .thin,
  "light": .light,
  "regular": .regular,
  "medium": .medium,
  "semibold": .semibold,
  "bold": .bold,
]

/// Parse an SF Symbol weight name (defaults to regular).
func parseWeight(_ s: String) -> NSFont.Weight {
  symbolWeights[s.lowercased()] ?? .regular
}

/// Render an SF Symbol to a PNG file.
///
/// - Colors: pass one color for a hierarchical (single-tint) render, or several
///   for a palette render (e.g. battery outline vs. fill). SF Symbols like
///   `battery.*` are multi-layer, so a palette gives the Control-Center look.
/// - `variableValue` drives proportional fill (works well on `wifi`; battery is
///   handled with discrete symbol names by the caller).
/// - The bitmap is rendered at `pointSize * scale` pixels so the PNG is crisp on
///   Retina; the caller sizes it down in sketchybar via `background.image.scale`.
///
/// Returns true on success.
@discardableResult
func renderSymbol(
  name: String,
  variableValue: Double?,
  pointSize: CGFloat,
  scale: CGFloat,
  colors: [NSColor],
  minWidth: CGFloat,
  xShift: CGFloat,
  outPath: String
) -> Bool {
  let base: NSImage?
  if let v = variableValue {
    base = NSImage(systemSymbolName: name, variableValue: v, accessibilityDescription: nil)
  } else {
    base = NSImage(systemSymbolName: name, accessibilityDescription: nil)
  }
  guard let symbol = base else {
    FileHandle.standardError.write(Data("sketchybar-icons: unknown symbol '\(name)'\n".utf8))
    return false
  }

  let sizeCfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
  let colorCfg: NSImage.SymbolConfiguration
  if colors.count > 1 {
    colorCfg = NSImage.SymbolConfiguration(paletteColors: colors)
  } else {
    colorCfg = NSImage.SymbolConfiguration(hierarchicalColor: colors.first ?? .white)
  }
  guard let configured = symbol.withSymbolConfiguration(sizeCfg.applying(colorCfg)) else {
    return false
  }

  let size = configured.size
  // Optionally pad the canvas to a minimum width and centre the glyph in it.
  // sketchybar left-aligns a background image within `icon.width`, so widening
  // the button there leaves dead space on the right; baking symmetric padding
  // into the PNG instead keeps the glyph centred in a wider (e.g. control-center
  // matching) button. Height is left at the glyph's natural size.
  let canvasW = max(size.width, minWidth)
  let pxW = max(1, Int((canvasW * scale).rounded()))
  let pxH = max(1, Int((size.height * scale).rounded()))
  // Map the point-sized drawing onto the larger pixel buffer.
  guard
    let rep = makeRGBARep(
      pxW: pxW, pxH: pxH, pointSize: NSSize(width: canvasW, height: size.height))
  else { return false }

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  // Centre the glyph in the canvas, then apply the caller's optical shift
  // (positive = right). sketchybar can't nudge a background image, so any
  // horizontal fine-tuning has to be baked into the PNG here.
  let xOffset = (canvasW - size.width) / 2.0 + xShift
  configured.draw(
    in: NSRect(x: xOffset, y: 0, width: size.width, height: size.height),
    from: .zero,
    operation: .sourceOver,
    fraction: 1.0
  )
  NSGraphicsContext.restoreGraphicsState()

  return writePNG(rep, to: outPath, label: "write")
}
