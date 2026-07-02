import AppKit

/// Draw a macOS battery: Apple's exact `battery.0` outline with a continuous
/// proportional fill. The fillable interior is *measured* from the rendered
/// outline (so it stays correct across weights/sizes) and filled with equal
/// margins. When `charging`, a bolt is drawn with a knocked-out halo around it
/// (the fill is cleared in a slightly-larger bolt shape), matching macOS.
///
/// `level` is 0…1; `colors.first` tints outline and fill; `weight` sets the
/// outline stroke thickness.
@discardableResult
func drawBattery(
  level: Double,
  charging: Bool,
  warn: Bool,
  pointSize: CGFloat,
  scale: CGFloat,
  weight: NSFont.Weight,
  colors: [NSColor],
  outPath: String
) -> Bool {
  let lvl = max(0.0, min(1.0, level))
  // colors[0] = outline (and overlay) colour; colors[1] = fill colour (defaults
  // to the outline colour). Lets Low Power Mode tint just the bar yellow while
  // the outline stays white.
  let color = colors.first ?? .white
  let fillColor = colors.count > 1 ? colors[1] : color

  guard let base = NSImage(systemSymbolName: "battery.0", accessibilityDescription: nil) else {
    FileHandle.standardError.write(Data("sketchybar-icons: battery.0 unavailable\n".utf8))
    return false
  }
  let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    .applying(NSImage.SymbolConfiguration(hierarchicalColor: color))
  guard let outline = base.withSymbolConfiguration(cfg) else { return false }

  let size = outline.size
  let pxW = max(1, Int((size.width * scale).rounded()))
  let pxH = max(1, Int((size.height * scale).rounded()))
  guard
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )
  else { return false }
  rep.size = size

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  outline.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1.0)

  // Measure the interior (empty space between the outline walls) from the drawn
  // outline. rep pixels are top-left origin; the drawing context is bottom-up.
  func opaque(_ x: Int, _ y: Int) -> Bool {
    guard x >= 0, x < pxW, y >= 0, y < pxH else { return false }
    return (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.3
  }
  func runs(_ flags: [Bool]) -> [(Int, Int)] {
    var out: [(Int, Int)] = []
    var start: Int? = nil
    for (i, f) in flags.enumerated() {
      if f, start == nil { start = i }
      if !f, let s = start { out.append((s, i - 1)); start = nil }
    }
    if let s = start { out.append((s, flags.count - 1)) }
    return out
  }
  let rowRuns = runs((0..<pxW).map { opaque($0, pxH / 2) })
  // Left wall = first run, right wall = second run (third, if any, is the nub).
  let inLpx = rowRuns.count >= 2 ? rowRuns[0].1 + 1 : Int(0.12 * Double(pxW))
  let inRpx = rowRuns.count >= 2 ? rowRuns[1].0 - 1 : Int(0.76 * Double(pxW))
  let colRuns = runs((0..<pxH).map { opaque((inLpx + inRpx) / 2, $0) })
  let inTpx = colRuns.count >= 2 ? colRuns[0].1 + 1 : Int(0.25 * Double(pxH))
  let inBpx = colRuns.count >= 2 ? colRuns[1].0 - 1 : Int(0.75 * Double(pxH))

  // Interior in drawing points (bottom-up).
  let interiorLeft = CGFloat(inLpx) / scale
  let interiorW = CGFloat(inRpx - inLpx) / scale
  let interiorH = CGFloat(inBpx - inTpx) / scale
  let interiorBottom = CGFloat(pxH - inBpx) / scale
  let interiorCenterX = interiorLeft + interiorW / 2
  let interiorCenterY = interiorBottom + interiorH / 2

  // Fill with equal margins.
  let m = interiorH * 0.16
  let fx = interiorLeft + m
  let fullW = interiorW - 2 * m
  let fw = fullW * CGFloat(lvl)
  let fy = interiorBottom + m
  let fh = interiorH - 2 * m
  if fw > 0.5 {
    fillColor.setFill()
    NSBezierPath(roundedRect: NSRect(x: fx, y: fy, width: fw, height: fh),
      xRadius: fh * 0.3, yRadius: fh * 0.3).fill()
  }

  // Overlay a glyph (charging bolt, or a low-battery warning triangle) centred
  // on the body, with a UNIFORM halo gap knocked out of the fill around it.
  func overlay(_ name: String, heightFrac: CGFloat, tint: NSColor) {
    guard let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
    let cfgS = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
    let h = interiorH * heightFrac
    let gap = interiorH * 0.16
    func rect(_ img: NSImage, _ dx: CGFloat = 0, _ dy: CGFloat = 0) -> NSRect {
      let w = h * (img.size.width / max(1, img.size.height))
      return NSRect(x: interiorCenterX - w / 2 + dx, y: interiorCenterY - h / 2 + dy, width: w, height: h)
    }
    // Uniform halo: knock out the glyph *dilated* by `gap`. Scaling the glyph
    // grows it non-uniformly (thin strokes gain less), so instead stamp it around
    // a ring of radius `gap` (Minkowski sum with a disk = uniform outset).
    if let hb = sym.withSymbolConfiguration(cfgS) {
      hb.draw(in: rect(hb), from: .zero, operation: .destinationOut, fraction: 1.0)
      let steps = 32
      for i in 0..<steps {
        let a = 2.0 * Double.pi * Double(i) / Double(steps)
        hb.draw(in: rect(hb, gap * CGFloat(cos(a)), gap * CGFloat(sin(a))),
          from: .zero, operation: .destinationOut, fraction: 1.0)
      }
    }
    if let cb = sym.withSymbolConfiguration(
      cfgS.applying(NSImage.SymbolConfiguration(hierarchicalColor: tint)))
    {
      cb.draw(in: rect(cb), from: .zero, operation: .sourceOver, fraction: 1.0)
    }
  }

  if charging {
    // Bolt big enough to cross the top/bottom battery lines.
    overlay("bolt.fill", heightFrac: 1.22, tint: fillColor)
  } else if warn {
    overlay("exclamationmark.triangle.fill", heightFrac: 1.35, tint: fillColor)
  }

  // Redraw the outline on top so it always keeps its colour (white) even where
  // an overlay glyph crosses it — the outline stays clean, the glyph reads as
  // tucked behind it.
  outline.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1.0)

  NSGraphicsContext.restoreGraphicsState()

  guard let png = rep.representation(using: .png, properties: [:]) else { return false }
  do {
    let url = URL(fileURLWithPath: (outPath as NSString).expandingTildeInPath)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try png.write(to: url)
    return true
  } catch {
    FileHandle.standardError.write(Data("sketchybar-icons: battery write failed: \(error)\n".utf8))
    return false
  }
}
