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
/// - `badge` names a symbol drawn in the bottom-right corner the way SF Symbols'
///   own `*.badge.*` variants look (see `composeBadge`), from glyphs every
///   supported macOS has.
///
/// Returns true on success.
@discardableResult
func renderSymbol(
  name: String,
  variableValue: Double?,
  badge: String? = nil,
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

  var badgeImage: NSImage?
  if let badge {
    guard let symbol = NSImage(systemSymbolName: badge, accessibilityDescription: nil) else {
      FileHandle.standardError.write(Data("sketchybar-icons: unknown symbol '\(badge)'\n".utf8))
      return false
    }
    let badgeCfg = NSImage.SymbolConfiguration(pointSize: pointSize * 0.5, weight: .semibold)
    badgeImage = symbol.withSymbolConfiguration(badgeCfg.applying(colorCfg))
    if badgeImage == nil { return false }
  }
  // A badge overhangs the base's bottom edge; Apple's badged canvases leave room below.
  let footer = badgeImage == nil ? 0 : pointSize / 14
  let size = NSSize(width: configured.size.width, height: configured.size.height + footer)

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

  // Centre the glyph in the canvas, then apply the caller's optical shift
  // (positive = right). sketchybar can't nudge a background image, so any
  // horizontal fine-tuning has to be baked into the PNG here.
  let origin = NSPoint(x: (canvasW - size.width) / 2.0 + xShift, y: footer)
  if let badgeImage {
    guard
      drawBadged(
        configured, badge: badgeImage, at: origin, into: rep, pointSize: pointSize, scale: scale)
    else { return false }
  } else {
    drawInto(rep) { configured.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1) }
  }
  return writePNG(rep, to: outPath, label: "write")
}

/// Draw `base` at `baseOrigin` with `badge` the way SF Symbols' own `*.badge.*`
/// variants look: the base at half opacity, the badge at full in its bottom-right
/// corner, cut out of the base with a gap (wide enough to cover a lock's shackle
/// hole, so no arc shows through it). Proportions
/// are tuned against `wifi.badge.lock` at 14 pt, the bar's size; the badge is
/// snapped to the pixel grid so its edges stay crisp and the gap stays clear.
private func drawBadged(
  _ base: NSImage, badge: NSImage, at baseOrigin: NSPoint, into out: NSBitmapImageRep,
  pointSize: CGFloat, scale: CGFloat
) -> Bool {
  let overhangRight = pointSize * 0.75 / 14
  let overhangBottom = pointSize * 0.5 / 14
  let gapPx = Double(pointSize * 0.75 / 14 * scale)
  guard let baseInk = inkRect(base), let badgeInk = inkRect(badge),
    let layer = makeRGBARep(pxW: out.pixelsWide, pxH: out.pixelsHigh, pointSize: out.size)
  else { return false }

  let x = baseOrigin.x + baseInk.maxX + overhangRight - badgeInk.maxX
  let y = baseOrigin.y + baseInk.minY - overhangBottom - badgeInk.minY
  let badgeOrigin = NSPoint(x: (x * scale).rounded() / scale, y: (y * scale).rounded() / scale)
  drawInto(out) { base.draw(at: baseOrigin, from: .zero, operation: .sourceOver, fraction: 0.5) }
  drawInto(layer) { badge.draw(at: badgeOrigin, from: .zero, operation: .sourceOver, fraction: 1) }
  guard let basePx = out.bitmapData, let badgePx = layer.bitmapData else { return false }

  // Scale each base pixel by its distance to the badge: fully clear within the
  // gap, then a one-pixel ramp back to the base's own antialiasing. Faint rim
  // pixels count as badge, so the gap starts at its soft edge.
  let (w, h, rowBytes) = (out.pixelsWide, out.pixelsHigh, out.bytesPerRow)
  let reach = Int(gapPx.rounded(.up)) + 1
  for py in 0..<h {
    for px in 0..<w {
      var d2 = Int.max
      for ny in max(0, py - reach)...min(h - 1, py + reach) {
        for nx in max(0, px - reach)...min(w - 1, px + reach)
        where badgePx[ny * rowBytes + nx * 4 + 3] > 12 {
          d2 = min(d2, (nx - px) * (nx - px) + (ny - py) * (ny - py))
        }
      }
      guard d2 != .max else { continue }
      let keep = min(1, max(0, Double(d2).squareRoot() - gapPx))
      let o = py * rowBytes + px * 4
      for c in 0..<4 { basePx[o + c] = UInt8(Double(basePx[o + c]) * keep) }
    }
  }

  drawInto(out) { badge.draw(at: badgeOrigin, from: .zero, operation: .sourceOver, fraction: 1) }
  return true
}

/// Tight bounds of an image's ink, in points from its bottom-left. Ink is any
/// pixel at least half the image's peak opacity, so a dim colour measures the
/// same as white.
private func inkRect(_ image: NSImage) -> NSRect? {
  guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
    return nil
  }
  let w = rep.pixelsWide
  let h = rep.pixelsHigh
  var peak: CGFloat = 0
  for y in 0..<h {
    for x in 0..<w { peak = max(peak, rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) }
  }
  var minX = w
  var minY = h
  var maxX = -1
  var maxY = -1
  for y in 0..<h {
    for x in 0..<w where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > peak / 2 {
      minX = min(minX, x)
      maxX = max(maxX, x)
      minY = min(minY, y)
      maxY = max(maxY, y)
    }
  }
  guard maxX >= 0 else { return nil }
  let sx = image.size.width / CGFloat(w)
  let sy = image.size.height / CGFloat(h)
  return NSRect(
    x: CGFloat(minX) * sx, y: image.size.height - CGFloat(maxY + 1) * sy,
    width: CGFloat(maxX - minX + 1) * sx, height: CGFloat(maxY - minY + 1) * sy)
}

private func drawInto(_ rep: NSBitmapImageRep, _ body: () -> Void) {
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  body()
  NSGraphicsContext.restoreGraphicsState()
}
