# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TraceBar is a macOS menubar app providing continuous graphical traceroute monitoring (like `mtr`). Built with Swift + SwiftUI, targeting macOS 14.6+. Bundle ID: `org.evilscheme.TraceBar`, Dev Team: `4PX677GC4R`.

## Development Guidlines
- whenever thinking about color, make sure colors are selected that work with the color theme system (HeatmapColorScheme.swift)
- use the xcode MCP server if configured when interacting with xcode
- use the xcode MCP and/or the context7 MCP to look up swift/MacOS API details

## Architecture

Single-process sandboxed app using unprivileged ICMP sockets (`SOCK_DGRAM`).

```
TraceBar/TraceBar/
  TraceBarApp.swift              — @main, MenuBarExtra + Settings scene
  ViewModels/
    TracerouteViewModel.swift    — @MainActor ObservableObject, all app state + probe scheduling
  Views/
    SparklineView.swift          — SparklineLabel: renders NSImage for menubar
    SparklineBar.swift           — Canvas line chart
    HeatmapBar.swift             — Canvas heatmap grid
    BandwidthSparklineView.swift — Dual-axis bandwidth bars
    TraceroutePanel.swift        — Main dropdown panel
    HopRowView.swift             — Single hop row with stats + history chart
    SettingsView.swift           — General + Advanced tabs
  Models/
    TracerouteModels.swift       — ProbeResult, HopData (stats computed from RingBuffer)
    HeatmapColorScheme.swift     — 15 color schemes with gradient interpolation
    BandwidthModels.swift        — BandwidthSample
    RingBuffer.swift             — Generic circular buffer
  Services/
    ICMPEngine.swift             — SOCK_DGRAM ICMP sockets, probeRound() (serial queue only)
    BandwidthMonitor.swift       — Interface detection via routing socket, sysctl byte counters
tools/
  mtr-lite.swift                 — CLI traceroute tool (compiles with ICMPEngine.swift)
```

### Concurrency Model
- **@MainActor:** TracerouteViewModel — all UI state, @Published properties
- **Serial probe queue (GCD):** ICMPEngine + BandwidthMonitor must be called from single serial DispatchQueue
- **Receiver thread:** Global concurrent queue with blocking recvfrom() in probeRound()
- **Timing:** mach_absolute_time() for sub-ms latency measurement
- **Debouncing:** DispatchWorkItem for settings-triggered reschedule

### Key Types
- `ProbeResult` — single probe: hop, address, latency, timestamp
- `HopData` — accumulated hop: address, hostname, RingBuffer of probes, computed last/avg/loss
- `RingBuffer<T>` — generic circular buffer, chronological iteration
- `HeatmapColorScheme` — enum with 15 schemes, 2-3 stop RGB gradient interpolation
- `BandwidthSample` — timestamp, download/upload bytes per sec, interface name

### Settings (@AppStorage keys)
`targetHost` (8.8.8.8), `resolveHostnames` (true), `heatmapColorScheme` (lagoon), `showBandwidth` (true), `showSparklineBackground` (true), `idleProbeInterval` (10s), `activeProbeInterval` (2s), `historyMinutes` (3), `maxHops` (30), `latencyThreshold` (100ms). Launch at login via SMAppService.

### Dependencies
None external. Uses Foundation, SwiftUI, Darwin (sockets, mach timing), AppKit (NSImage/NSColor for menubar), ServiceManagement.

**Entitlements:** `com.apple.security.app-sandbox`, `com.apple.security.network.client`, `com.apple.security.network.server`. The `SOCK_DGRAM` + `IPPROTO_ICMP` approach requires no root privileges and works inside App Sandbox.

## Build & Run

Open `TraceBar/TraceBar.xcodeproj` in Xcode. Single target: TraceBar.

## Tests

Uses Swift Testing framework (`@Test`, `@Suite`). Run via Xcode (Cmd+U) or:
```bash
xcodebuild test -project TraceBar/TraceBar.xcodeproj -scheme TraceBar -destination 'platform=macOS'
```

| File | Coverage |
|------|----------|
| RingBufferTests.swift | empty, append, wraparound, capacity |
| TracerouteModelsTests.swift | ProbeResult timeouts, HopData stats |
| ICMPParsingTests.swift | Echo Reply, Time Exceeded, Dest Unreachable, identifier validation |
| HeatmapColorSchemeTests.swift | boundary colors, interpolation, clamping |

## CLI Tools

```bash
cd tools && swiftc -O -o mtr-lite mtr-lite.swift ../TraceBar/TraceBar/Services/ICMPEngine.swift
sudo ./mtr-lite <host> [maxHops] [intervalSec]
```

### ICMP Validation

After making substantive changes to packet construction, parsing, or probe logic in `ICMPEngine.swift`, run the validation tool to verify correctness against mtr:
```bash
tools/validate-icmp.sh
```
This auto-builds `tools/icmp-probe` from source, probes real-world targets, and compares results against `mtr`. All checks should pass before merging.

## Checking Logs

```bash
# App logs
log show --predicate 'process == "TraceBar"' --last 2m --style compact

# Verify code signing
codesign --verify --deep --strict --verbose=2 /Applications/TraceBar.app
```

## Commit Conventions

Do not include `Co-Authored-By: Claude` lines in commit messages.

## PR Workflow

Before opening a PR, consider whether the change warrants a version number bump. Suggest to the user rather than doing it automatically.
