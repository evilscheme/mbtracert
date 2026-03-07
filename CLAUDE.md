# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TraceBar is a macOS menubar app providing continuous graphical traceroute monitoring (like `mtr`). Built with Swift + SwiftUI, targeting macOS 14.6+. Bundle ID: `org.evilscheme.TraceBar`, Dev Team: `4PX677GC4R`.

## Architecture

Single-process sandboxed app using unprivileged ICMP sockets (`SOCK_DGRAM`).

```
TraceBar.app (SwiftUI, menubar-only, App Sandbox enabled)
  ├── TracerouteViewModel — state management, adaptive probe scheduling
  ├── ICMPEngine — SOCK_DGRAM ICMP sockets, concurrent send/receive probing (must be called from a single serial queue)
  └── Views: SparklineBar (menubar), TraceroutePanel (dropdown), HeatmapBar, HopRowView, SettingsView
```

**Entitlements:** `com.apple.security.app-sandbox`, `com.apple.security.network.client`, `com.apple.security.network.server`. The `SOCK_DGRAM` + `IPPROTO_ICMP` approach requires no root privileges and works inside App Sandbox.

## Build & Run

Open `TraceBar/TraceBar.xcodeproj` in Xcode. Single target: TraceBar.

## Checking Logs

```bash
# App logs
log show --predicate 'process == "TraceBar"' --last 2m --style compact

# Verify code signing
codesign --verify --deep --strict --verbose=2 /Applications/TraceBar.app
```

## Commit Conventions

Do not include `Co-Authored-By: Claude` lines in commit messages.
