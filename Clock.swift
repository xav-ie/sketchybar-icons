import AppKit

/// Draw an analog clock face at a given time. Unlike Battery/Wi-Fi this isn't an
/// SF Symbol — SF Symbols has no time-aware clock (its `clock`/`deskclock` glyphs
/// are frozen poses, and there's no hour-specific family) — so the face is drawn
/// directly with CoreGraphics, matching SF Symbols' optical style (bare ring,
/// rounded line caps). It gives real minute-hand precision, which the discrete
/// Nerd-Font `clock_time_*` glyphs can't.
///
/// - `colors[0]` tints the ring and the (shorter, thicker) hour hand.
/// - `colors[1]` tints the (longer, thinner) minute hand; defaults to
///   `colors[0]` when a single colour is given.
/// - The glyph is drawn into a square of side `pointSize` points, rendered at
///   `pointSize * scale` pixels so it's crisp on Retina and sits at the same
///   scale as the other icons (18pt @2× = 36px).
@discardableResult
func drawClock(
  hour: Int,
  minute: Int,
  pointSize: CGFloat,
  scale: CGFloat,
  colors: [NSColor],
  outPath: String
) -> Bool {
  let primary = colors.first ?? .white
  let accent = colors.count > 1 ? colors[1] : primary

  let side = pointSize
  let px = max(1, Int((side * scale).rounded()))
  guard
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )
  else { return false }
  rep.size = NSSize(width: side, height: side)

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  guard let ctx = NSGraphicsContext.current?.cgContext else {
    NSGraphicsContext.restoreGraphicsState()
    return false
  }

  let s = side
  let cx = s / 2, cy = s / 2
  let ring = s * 0.055
  let radius = s * 0.5 - ring
  ctx.setLineCap(.round)

  // Face ring.
  primary.setStroke()
  ctx.setLineWidth(ring)
  ctx.strokeEllipse(in: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))

  // Hand angles, measured clockwise from 12 o'clock (up).
  let m = CGFloat(minute % 60)
  let h = CGFloat(hour % 12)
  let hourAngle = (h / 12 + m / 720) * 2 * .pi
  let minuteAngle = m / 60 * 2 * .pi
  func hand(_ angle: CGFloat, length: CGFloat, width: CGFloat, color: NSColor) {
    color.setStroke()
    ctx.setLineWidth(width)
    ctx.move(to: CGPoint(x: cx, y: cy))
    ctx.addLine(to: CGPoint(x: cx + sin(angle) * length, y: cy + cos(angle) * length))
    ctx.strokePath()
  }

  // Minute hand first (longer), then the hour hand (shorter) on top: the minute
  // hand extends past the hour hand so its tip always shows, and layering the
  // hour hand above keeps it readable where they cross. Both hands share a
  // thickness — only length distinguishes them.
  hand(minuteAngle, length: radius * 0.76, width: s * 0.055, color: accent)
  hand(hourAngle, length: radius * 0.5, width: s * 0.055, color: primary)

  NSGraphicsContext.restoreGraphicsState()

  guard let png = rep.representation(using: .png, properties: [:]) else { return false }
  do {
    let url = URL(fileURLWithPath: (outPath as NSString).expandingTildeInPath)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try png.write(to: url)
    return true
  } catch {
    FileHandle.standardError.write(Data("sketchybar-icons: clock write failed: \(error)\n".utf8))
    return false
  }
}
