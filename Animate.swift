import Foundation

/// Cycles a sketchybar item's icon image through `frames`, one every
/// `interval` seconds, then settles on the first frame and exits once
/// `duration` has passed. Meant for short-lived states such as joining a
/// network: a plugin starts it on entering the state and stops it (SIGTERM)
/// on leaving, and the time limit means a state that sticks can't keep waking
/// the Mac. SIGTERM is handled between frames, so a stopped animation never
/// sets an image after its plugin has drawn the next state.
func animateItem(_ item: String, frames: [String], interval: TimeInterval, duration: TimeInterval)
  -> Never
{
  // Resolved off PATH, like the plugin's own `sketchybar` calls.
  func show(_ frame: String) {
    let process = try? Process.run(
      URL(fileURLWithPath: "/usr/bin/env"),
      arguments: ["sketchybar", "--set", item, "icon.background.image=\(frame)"])
    process?.waitUntilExit()
  }

  signal(SIGTERM, SIG_IGN)
  let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
  term.setEventHandler { exit(0) }
  term.resume()

  let start = Date()
  var index = 0
  show(frames[index])
  let timer = Timer(timeInterval: interval, repeats: true) { _ in
    if Date().timeIntervalSince(start) >= duration {
      show(frames[0])
      exit(0)
    }
    index = (index + 1) % frames.count
    show(frames[index])
  }
  RunLoop.main.add(timer, forMode: .default)
  withExtendedLifetime((term, timer)) { RunLoop.main.run() }
  exit(0)
}
