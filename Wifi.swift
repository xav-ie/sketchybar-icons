import CoreWLAN
import Foundation
import notify

/// Live Wi-Fi state read via CoreWLAN. Only signal metrics are used — never the
/// SSID/BSSID — so this needs **no** Location Services permission (reading the
/// SSID would trigger a prompt on macOS 14+; RSSI and power state do not).
struct WifiState {
  let powerOn: Bool
  let associated: Bool
  let rssi: Int
  /// RSSI mapped to 0.0…1.0 for a signal-strength fill. ~-50 dBm → full,
  /// ~-85 dBm → empty.
  let fraction: Double

  /// Arcs the `wifi` SF Symbol can actually draw (0…3). Quantizing here — not
  /// in the caller — is what lets the watcher stay quiet while RSSI jitters
  /// within a band.
  var level: Int {
    guard associated else { return 0 }
    if fraction >= 0.66 { return 3 }
    if fraction >= 0.33 { return 2 }
    return 1
  }
}

func readWifiState() -> WifiState {
  guard let iface = CWWiFiClient.shared().interface() else {
    return WifiState(powerOn: false, associated: false, rssi: 0, fraction: 0)
  }
  let powerOn = iface.powerOn()
  let rssi = iface.rssiValue()
  // rssiValue() returns 0 when not associated to a network. Note there is no
  // separate "connecting" flag to read: CoreWLAN's `interfaceState` was
  // deprecated out of the framework, and while the radio is on and unassociated
  // macOS is *always* trying to associate — so powerOn && !associated IS the
  // pending state.
  let associated = powerOn && rssi != 0

  let minRSSI = -85.0
  let maxRSSI = -50.0
  let clamped = max(minRSSI, min(maxRSSI, Double(rssi)))
  let fraction = associated ? (clamped - minRSSI) / (maxRSSI - minRSSI) : 0.0

  return WifiState(powerOn: powerOn, associated: associated, rssi: rssi, fraction: fraction)
}

/// One whitespace-delimited line the Nushell plugin can parse:
/// `power=on associated=yes level=3 rssi=-55 fraction=0.71`
func wifiStateLine(_ s: WifiState) -> String {
  "power=\(s.powerOn ? "on" : "off") "
    + "associated=\(s.associated ? "yes" : "no") "
    + "level=\(s.level) "
    + "rssi=\(s.rssi) "
    + String(format: "fraction=%.2f", s.fraction)
}

func printWifiState() {
  print(wifiStateLine(readWifiState()))
}

/// Streams a state line on every CoreWLAN event, for a daemon to turn into a
/// `sketchybar --trigger`. CoreWLAN events are the same ones Control Center
/// reacts to — instantly. configd's `com.apple.system.config.network_change`
/// is watched too: it lands seconds later, once routes and per-network flags
/// (e.g. `IsExpensive`, which marks a personal hotspot) have settled, and is
/// the only signal for hotspot/tether changes CoreWLAN can't see. It's a
/// darwin notify(3) key, not an NSDistributedNotification, so sketchybar's own
/// `--add event` can't subscribe to it.
final class WifiWatcher: NSObject, CWEventDelegate {
  /// `sketchybar --trigger <event>` on each change, when `--trigger` was given.
  let event: String?
  /// Last emitted line minus the noisy fields, so RSSI jitter inside one arc
  /// band doesn't wake the bar.
  private var last = ""

  init(event: String?) { self.event = event }

  /// Pending network_change trigger; configd posts these in bursts.
  private var settle: DispatchWorkItem?

  /// `force` triggers even when the Wi-Fi state is unchanged, for consumers
  /// whose display depends on network state beyond CoreWLAN's.
  func emit(force: Bool = false) {
    let s = readWifiState()
    let key = "\(s.powerOn)\(s.associated)\(s.level)"
    guard force || key != last else { return }
    last = key
    print(wifiStateLine(s))
    guard let event else { return }
    // Resolved off PATH so the caller (a launchd agent) owns which sketchybar.
    try? Process.run(
      URL(fileURLWithPath: "/usr/bin/env"), arguments: ["sketchybar", "--trigger", event])
  }

  func networkDidChange() {
    settle?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.emit(force: true) }
    settle = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
  }

  func linkDidChangeForWiFiInterface(withName _: String) { emit() }
  func powerStateDidChangeForWiFiInterface(withName _: String) { emit() }
  func linkQualityDidChangeForWiFiInterface(
    withName _: String, rssi _: Int, transmitRate _: Double
  ) { emit() }
}

func watchWifiState(trigger event: String?) -> Never {
  setvbuf(stdout, nil, _IOLBF, 0)  // line-buffered: stdout is usually a log here.
  let client = CWWiFiClient.shared()
  let watcher = WifiWatcher(event: event)
  client.delegate = watcher
  for event in [CWEventType.linkDidChange, .powerDidChange, .linkQualityDidChange] {
    try? client.startMonitoringEvent(with: event)
  }
  var token: Int32 = 0
  notify_register_dispatch("com.apple.system.config.network_change", &token, .main) { _ in
    watcher.networkDidChange()
  }
  watcher.emit()  // prime the bar at startup
  RunLoop.current.run()
  fail("wifi --watch: run loop exited")
}
