# MenubarTracert Design

A macOS menubar app providing continuous, graphical traceroute monitoring — like `mtr`, but with a persistent sparkline indicator and heatmap visualization.

## Decisions

- **Stack:** Swift + SwiftUI, macOS 14+ (Sonoma)
- **Architecture:** Menubar-only agent app + privileged XPC helper for ICMP
- **Probe method:** ICMP (like mtr default), via raw sockets in helper
- **Target:** Single configurable host (default `8.8.8.8`)
- **History:** Rolling in-memory window (configurable, default 5 min)
- **Probe rate:** Adaptive — slow when idle, fast when panel open, user-configurable
- **Settings:** Standard macOS Preferences window (Cmd+,)

## Architecture

Two build targets in one Xcode project:

### MenubarTracert.app (main, unprivileged)

| Component | Role |
|-----------|------|
| `MenubarApp` | App entry point, `MenuBarExtra` with sparkline |
| `TracerouteViewModel` | ObservableObject driving all UI state |
| `ProbeScheduler` | Manages adaptive probe timing |
| `HopStore` | In-memory ring buffer of probe results per hop |
| `SparklineView` | Tiny menubar graph (~30px wide) showing overall latency trend |
| `TraceroutePanel` | Dropdown popover with heatmap visualization |
| `HopRowView` | Single hop row: number, hostname, avg, loss%, heatmap bar |
| `HeatmapBar` | Canvas drawing of colored cells for latency history |
| `SettingsView` | Preferences window |

### TracertHelper (privileged XPC helper)

- Lightweight process opening raw ICMP sockets
- Sends probes with incremented TTL values
- Reports `(hop, latency, address, loss)` tuples back over XPC
- Installed via `SMAppService.register()` (macOS 13+ API)

### Data Flow

```
ProbeScheduler --> (XPC) --> TracertHelper --> ICMP probe --> response
                                                |
TracerouteViewModel <-- (XPC callback) <-- TracertHelper
        |
    HopStore (ring buffer per hop)
        |
    SparklineView + TraceroutePanel
```

## Visualization

### Menubar Sparkline

- ~30px wide, rendered with SwiftUI Canvas
- Plots latency to the final hop (overall RTT) over the last ~2 minutes
- Color-coded: green baseline, yellow/red on spikes
- Click opens TraceroutePanel popover

### Dropdown Panel

~450px wide, dynamic height. Shows:
- Header: target host, status, overall RTT
- Hop rows with heatmap bars

```
 Hop  Host            Avg   Loss  [---- History (color = latency) ----]
  1   192.168.1.1     2ms   0%   |████████████████████████████████████|
  2   10.0.0.1        8ms   0%   |████████████████████████████████████|
  3   72.14.215.65   12ms   0%   |██████████████████████▓▓▓▓▓▓▓▓█████|
  4   108.170.232.1  18ms   1%   |████████▓▓▓▓▓▓▓▓▓▓▓▓░░░░▓▓▓▓██████|
  5   8.8.8.8        14ms   0%   |████████████████████████████████████|
```

- Each cell = one probe result
- Color scale: green (low) -> yellow (medium) -> red (high) -> black gap (packet loss)
- Newest probes on the right, scroll left over time
- Hover tooltip: `12ms at 3:42:15 PM`
- Rows animate in/out as route changes

### Adaptive Probe Rate

- Panel closed (idle): every N seconds (default 5s, range 2-30s)
- Panel open (active): every M seconds (default 1s, range 0.5-5s)
- Transitions immediately on panel open/close

## Data Model

```swift
struct ProbeResult {
    let hop: Int
    let address: String?       // nil if timeout
    let hostname: String?      // resolved DNS name
    let latency: TimeInterval? // nil if timeout/loss
    let timestamp: Date
}

struct HopData: Identifiable {
    let hop: Int
    var address: String
    var hostname: String?
    var probes: RingBuffer<ProbeResult>  // fixed-size rolling window
    var avgLatency: TimeInterval
    var lossPercent: Double
}
```

Ring buffer capacity = `historyDuration / probeInterval` (e.g., 300 entries for 5 min at 1s).

## Settings (Cmd+,)

- Target host (text field, default `8.8.8.8`)
- Idle probe interval (slider, 2-30s, default 5s)
- Active probe interval (slider, 0.5-5s, default 1s)
- History window duration (slider, 2-15 min, default 5 min)
- Launch at login toggle
- DNS resolution toggle (resolve hostnames vs IPs only)

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Helper not installed/crashed | "Setup required" in panel, button to re-authorize |
| Target unreachable | Last known route grayed out, sparkline goes flat/red |
| Individual hop timeout | Black cell in heatmap, increment loss% |
| Route changes | Animate rows in/out, reset new hop's history |
| Network interface down | Pause probing, "No network" indicator, auto-resume |
| DNS resolution fails | Fall back to IP address display |

## Platform Requirements

- macOS 14+ (Sonoma)
- Xcode 15+, Swift 5.9+
- One-time admin authorization for helper installation
