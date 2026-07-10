import AppKit

/// Draw an analog clock face at a given time. Unlike Battery/Wi-Fi this isn't an
/// SF Symbol — SF Symbols has no time-aware clock (its `clock`/`deskclock` glyphs
/// are frozen poses, and there's no hour-specific family) — so the face is drawn
/// directly with CoreGraphics, matching SF Symbols' optical style (bare ring,
/// rounded line caps). It gives real minute-hand precision, which the discrete
/// Nerd-Font `clock_time_*` glyphs can't.
///
/// Both hands are skinny kite/lozenge shapes — widest at the centre, tapering to
/// a sharp point at the tip and a shorter sharp counterweight tail past the
/// centre (the classic analog-hand silhouette). The hour is short; the minute is
/// long. Filling the hands (vs. a hairline stroke) also keeps the accent-coloured
/// minute hand legible against a dark bar, where a thin coloured line washes out.
///
/// - `colors[0]` tints the ring and the hour hand.
/// - `colors[1]` tints the minute hand; defaults to `colors[0]` when a single
///   colour is given.
/// - The ring stroke is sized to sit at the same optical weight as the battery's
///   `thin` SF Symbol outline, so the two icons match side by side in a bar.
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
  guard let rep = makeRGBARep(pxW: px, pxH: px, pointSize: NSSize(width: side, height: side))
  else { return false }

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  guard let ctx = NSGraphicsContext.current?.cgContext else {
    NSGraphicsContext.restoreGraphicsState()
    return false
  }

  let s = side
  let cx = s / 2
  let cy = s / 2
  // Ring stroke ≈ the battery's `thin` SF Symbol outline (~0.048·pointSize) so the
  // two read at the same weight side by side.
  let ring = s * 0.048
  let radius = s * 0.5 - ring

  // Face ring.
  primary.setStroke()
  ctx.setLineWidth(ring)
  ctx.strokeEllipse(
    in: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))

  // Hand angles, measured clockwise from 12 o'clock (up).
  let m = CGFloat(minute % 60)
  let h = CGFloat(hour % 12)
  let hourAngle = (h / 12 + m / 720) * 2 * .pi
  let minuteAngle = m / 60 * 2 * .pi

  // Kite/lozenge hand: widest at the centre (2·halfWidth), tapering to a sharp
  // point at `front` and a shorter sharp counterweight tail at `tail` behind the
  // centre.
  func hand(_ angle: CGFloat, front: CGFloat, tail: CGFloat, halfWidth: CGFloat, color: NSColor) {
    let dx = sin(angle)
    let dy = cos(angle)  // along the hand
    let px = cos(angle)
    let py = -sin(angle)  // perpendicular
    let tip = CGPoint(x: cx + dx * front, y: cy + dy * front)
    let back = CGPoint(x: cx - dx * tail, y: cy - dy * tail)
    let left = CGPoint(x: cx + px * halfWidth, y: cy + py * halfWidth)
    let right = CGPoint(x: cx - px * halfWidth, y: cy - py * halfWidth)
    color.setFill()
    ctx.move(to: tip)
    ctx.addLine(to: right)
    ctx.addLine(to: back)
    ctx.addLine(to: left)
    ctx.closePath()
    ctx.fillPath()
  }

  // Minute hand first (under), hour hand on top: the hour hand reads clearly where
  // they cross, and the longer minute hand still shows past it.
  hand(minuteAngle, front: radius * 0.86, tail: radius * 0.18, halfWidth: s * 0.045, color: accent)
  hand(hourAngle, front: radius * 0.48, tail: radius * 0.18, halfWidth: s * 0.042, color: primary)

  NSGraphicsContext.restoreGraphicsState()

  return writePNG(rep, to: outPath, label: "clock write")
}
