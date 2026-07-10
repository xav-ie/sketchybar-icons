import AppKit

/// Look up a running application's icon by localized name.
///
/// SketchyBar's own `app.<name>` background image does the same lookup
/// internally; mirroring it here lets a caller find out *ahead of time* whether
/// that native path will produce a real icon, so it can substitute its own glyph
/// for the apps SketchyBar would otherwise draw as a giant generic document
/// (e.g. `SecurityAgent`, the Touch ID / sudo prompt).
func runningAppIcon(name: String) -> NSImage? {
  guard !name.isEmpty else { return nil }
  return NSWorkspace.shared.runningApplications
    .first { $0.localizedName == name }?
    .icon
}
