import AppKit

/// Typed accessors over the parsed `--flag value` dictionary, so each subcommand
/// reads its options declaratively instead of respelling the parse-with-default
/// idiom (and re-typing the defaults) at every call site.
extension [String: String] {
  func double(_ key: String, _ fallback: Double) -> Double {
    self[key].flatMap { Double($0) } ?? fallback
  }
  func cgFloat(_ key: String, _ fallback: Double) -> CGFloat {
    CGFloat(double(key, fallback))
  }
  func int(_ key: String, _ fallback: Int) -> Int {
    self[key].flatMap { Int($0) } ?? fallback
  }
  func bool(_ key: String) -> Bool {
    self[key] == "true"
  }
  func color(_ key: String, _ fallback: String = "0xffffffff") -> NSColor {
    parseColor(self[key] ?? fallback)
  }
}

/// Shared tail of every file-writing subcommand: exit(1) on failure, else echo
/// the tilde-expanded output path so callers can capture it.
func emit(_ ok: Bool, _ outPath: String) -> Never {
  if !ok { exit(1) }
  print((outPath as NSString).expandingTildeInPath)
  exit(0)
}
