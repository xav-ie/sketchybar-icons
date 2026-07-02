import CoreWLAN
import Foundation

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
}

func readWifiState() -> WifiState {
  guard let iface = CWWiFiClient.shared().interface() else {
    return WifiState(powerOn: false, associated: false, rssi: 0, fraction: 0)
  }
  let powerOn = iface.powerOn()
  let rssi = iface.rssiValue()
  // rssiValue() returns 0 when not associated to a network.
  let associated = powerOn && rssi != 0

  let minRSSI = -85.0
  let maxRSSI = -50.0
  let clamped = max(minRSSI, min(maxRSSI, Double(rssi)))
  let fraction = associated ? (clamped - minRSSI) / (maxRSSI - minRSSI) : 0.0

  return WifiState(powerOn: powerOn, associated: associated, rssi: rssi, fraction: fraction)
}

/// Print one whitespace-delimited line the Nushell plugin can parse:
/// `power=on associated=yes rssi=-55 fraction=0.71`
func printWifiState() {
  let s = readWifiState()
  let line =
    "power=\(s.powerOn ? "on" : "off") "
    + "associated=\(s.associated ? "yes" : "no") "
    + "rssi=\(s.rssi) "
    + String(format: "fraction=%.2f", s.fraction)
  print(line)
}
