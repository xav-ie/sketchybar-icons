import AppKit

/// Allocate an RGBA8 device-RGB bitmap `pxW`×`pxH` pixels, sized in points to
/// `pointSize` so callers draw at point scale onto the larger (Retina) buffer.
func makeRGBARep(pxW: Int, pxH: Int, pointSize: NSSize) -> NSBitmapImageRep? {
  guard
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )
  else { return nil }
  rep.size = pointSize
  return rep
}

/// PNG-encode `rep` and write it to `outPath`, creating parent dirs. Atomic so a
/// consumer reading the stable cache path never sees a half-written file.
/// `label` tags the error message. Returns true on success.
func writePNG(_ rep: NSBitmapImageRep, to outPath: String, label: String) -> Bool {
  guard let png = rep.representation(using: .png, properties: [:]) else { return false }
  do {
    let url = URL(fileURLWithPath: (outPath as NSString).expandingTildeInPath)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try png.write(to: url, options: .atomic)
    return true
  } catch {
    FileHandle.standardError.write(Data("sketchybar-icons: \(label) failed: \(error)\n".utf8))
    return false
  }
}
