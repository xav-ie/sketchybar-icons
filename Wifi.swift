import CoreWLAN
import Foundation
import Network
import SystemConfiguration
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
  /// Holds a non-link-local IPv4 address. Associated without one means DHCP is
  /// still running (or failed and macOS self-assigned 169.254.x).
  let ip: Bool
  var internet: Internet = .none

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

/// Whether traffic gets past the access point, per macOS's own verdict (see
/// `readInternet`). `none` = no connection to judge (unassociated or no IP);
/// `captive` = a portal is waiting for login.
enum Internet: String {
  case none, online, captive, offline
}

func readWifiState() -> WifiState {
  guard let iface = CWWiFiClient.shared().interface() else {
    return WifiState(powerOn: false, associated: false, rssi: 0, fraction: 0, ip: false)
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

  let name = iface.interfaceName ?? "en0"
  let ip = associated && hasRoutableIPv4(name)
  return WifiState(
    powerOn: powerOn, associated: associated, rssi: rssi, fraction: fraction,
    ip: ip, internet: ip ? readInternet(name) : .none)
}

/// Reads configd's per-interface IPv4 state — the same store `scutil` shows.
func hasRoutableIPv4(_ interface: String) -> Bool {
  guard
    let addresses = configdValue("State:/Network/Interface/\(interface)/IPv4")?["Addresses"]
      as? [String]
  else { return false }
  return addresses.contains { !$0.hasPrefix("169.254.") }
}

/// macOS's verdict, read rather than re-derived, so the bar sends no traffic
/// of its own. Three of its signals, each catching what the others miss — the
/// menu-bar icon misses most of them, as its captive check "assumes online"
/// whenever its probe times out or DNS fails:
/// - symptomsd's broken-backhaul state: connections stop making progress and
///   its probe confirms it (dead uplink, dropped or refused traffic). CoreWiFi
///   mirrors it; `4` is broken. CoreWiFi is private, so it's resolved at
///   runtime and a macOS without it skips this check.
/// - configd's captive stage: `UIRequired`/`Websheet` while a portal waits for
///   login.
/// - the system path: `unsatisfied` is what apps see as offline (Firefox's
///   NS_ERROR_OFFLINE). It needs history (`PathWatch`), so only `--watch`
///   applies it, on top of this.
func readInternet(_ interface: String) -> Internet {
  if coreWiFi?.value(forKey: "brokenBackhaulState") as? Int == 4 { return .offline }
  let stage =
    configdValue("State:/Network/Interface/\(interface)/CaptiveNetwork")?["Stage"] as? String
  if stage == "UIRequired" || stage == "Websheet" { return .captive }
  return .online
}

/// Tracks how long the system's default path has been unsatisfied, calling
/// back on every update and once more when an outage outlasts `grace`. The
/// grace restarts whenever the network itself changes (`restartGrace`): the
/// path is unsatisfied while a join or a captive login is in progress, and
/// that shouldn't count once it ends.
final class PathWatch {
  /// Longer than the unsatisfied blip every join produces.
  static let grace: TimeInterval = 3

  private let monitor = NWPathMonitor()
  /// Uptime, the clock `asyncAfter` schedules on.
  private var unsatisfiedSince: TimeInterval?

  var down: Bool {
    unsatisfiedSince.map { ProcessInfo.processInfo.systemUptime - $0 >= Self.grace } ?? false
  }

  private let onChange: () -> Void

  init(onChange: @escaping () -> Void) {
    self.onChange = onChange
    monitor.pathUpdateHandler = { [weak self] path in
      guard let self else { return }
      if path.status == .satisfied {
        unsatisfiedSince = nil
      } else if unsatisfiedSince == nil {
        startGrace()
      }
      onChange()
    }
    monitor.start(queue: .main)
  }

  func restartGrace() {
    if unsatisfiedSince != nil { startGrace() }
  }

  private func startGrace() {
    unsatisfiedSince = ProcessInfo.processInfo.systemUptime
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.grace, execute: onChange)
  }
}

/// Posted by symptomsd whenever it re-evaluates the backhaul.
let brokenBackhaulNotification = "com.apple.symptoms.managed_events.broken-backhaul"

private let coreWiFi: NSObject? = {
  guard dlopen("/System/Library/PrivateFrameworks/CoreWiFi.framework/CoreWiFi", RTLD_NOW) != nil,
    let cls = NSClassFromString("CWFInterface") as? NSObject.Type,
    cls.instancesRespond(to: NSSelectorFromString("brokenBackhaulState")),
    cls.instancesRespond(to: NSSelectorFromString("activate"))
  else { return nil }
  let iface = cls.init()
  _ = iface.perform(NSSelectorFromString("activate"))
  return iface
}()

/// A nil store uses SystemConfiguration's shared session.
func configdValue(_ key: String) -> [String: Any]? {
  SCDynamicStoreCopyValue(nil, key as CFString) as? [String: Any]
}

/// Posted (e.g. by `wifi --refresh`) to make `--watch` re-send its line even
/// if unchanged — for a consumer that just restarted and lost it.
let refreshNotification = "sketchybar-icons.wifi.refresh"

/// One whitespace-delimited line the Nushell plugin can parse:
/// `power=on associated=yes ip=yes internet=online level=3 rssi=-55 fraction=0.71`
func wifiStateLine(_ s: WifiState) -> String {
  "power=\(s.powerOn ? "on" : "off") "
    + "associated=\(s.associated ? "yes" : "no") "
    + "ip=\(s.ip ? "yes" : "no") "
    + "internet=\(s.internet.rawValue) "
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
///
/// The internet verdict's sources push too — symptomsd's broken-backhaul
/// notification, configd's captive key, and the system path — so it flips the
/// moment macOS's does.
final class WifiWatcher: NSObject, CWEventDelegate {
  /// `sketchybar --trigger <event>` on each change, when `--trigger` was given.
  let event: String?
  /// Last emitted line minus the noisy fields, so RSSI jitter inside one arc
  /// band doesn't wake the bar.
  private var last = ""

  init(event: String?) { self.event = event }

  /// Set once the watcher's path monitor is running.
  var path: PathWatch?

  /// Pending network_change trigger; configd posts these in bursts.
  private var settle: DispatchWorkItem?

  /// Association, address and the other internet signals, as of the last
  /// refresh; a change restarts the path's grace.
  private var network = ""

  /// Re-read Wi-Fi state and emit it if the displayed state changed. `force`
  /// triggers even when the state is unchanged, for consumers whose display
  /// depends on network state beyond CoreWLAN's.
  func refresh(force: Bool = false) {
    var s = readWifiState()
    let network = "\(s.associated)\(s.ip)\(s.internet)"
    if network != self.network {
      self.network = network
      path?.restartGrace()
    }
    if s.internet == .online, path?.down == true { s.internet = .offline }
    emit(s, force: force)
  }

  private func emit(_ s: WifiState, force: Bool) {
    let key = "\(s.powerOn)\(s.associated)\(s.level)\(s.ip)\(s.internet)"
    guard force || key != last else { return }
    last = key
    let line = wifiStateLine(s)
    print(line)
    guard let event else { return }
    // Resolved off PATH so the caller (a launchd agent) owns which sketchybar.
    // The line rides along as $WIFI_STATE so the plugin needn't re-read it.
    try? Process.run(
      URL(fileURLWithPath: "/usr/bin/env"),
      arguments: ["sketchybar", "--trigger", event, "WIFI_STATE=\(line)"])
  }

  func networkDidChange() {
    settle?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.refresh(force: true) }
    settle = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
  }

  // CoreWLAN may call these off the main queue, where everything else runs.
  func linkDidChangeForWiFiInterface(withName _: String) {
    DispatchQueue.main.async { self.refresh() }
  }
  func powerStateDidChangeForWiFiInterface(withName _: String) {
    DispatchQueue.main.async { self.refresh() }
  }
  func linkQualityDidChangeForWiFiInterface(
    withName _: String, rssi _: Int, transmitRate _: Double
  ) {
    DispatchQueue.main.async { self.refresh() }
  }
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

  var backhaulToken: Int32 = 0
  notify_register_dispatch(brokenBackhaulNotification, &backhaulToken, .main) { _ in
    watcher.refresh()
  }
  var refreshToken: Int32 = 0
  notify_register_dispatch(refreshNotification, &refreshToken, .main) { _ in
    watcher.refresh(force: true)
  }

  watcher.path = PathWatch { watcher.refresh() }

  var context = SCDynamicStoreContext(
    version: 0, info: Unmanaged.passUnretained(watcher).toOpaque(),
    retain: nil, release: nil, copyDescription: nil)
  let store = SCDynamicStoreCreate(
    nil, "sketchybar-icons" as CFString,
    { _, _, info in
      guard let info else { return }
      Unmanaged<WifiWatcher>.fromOpaque(info).takeUnretainedValue().refresh()
    }, &context)
  if let store {
    SCDynamicStoreSetNotificationKeys(
      store, nil, ["State:/Network/Interface/[^/]+/CaptiveNetwork"] as CFArray)
    CFRunLoopAddSource(
      CFRunLoopGetMain(), SCDynamicStoreCreateRunLoopSource(nil, store, 0), .defaultMode)
  }

  watcher.refresh()  // prime the bar at startup
  withExtendedLifetime((watcher, store)) { RunLoop.current.run() }
  fail("wifi --watch: run loop exited")
}
