# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MenubarTracert is a macOS menubar app providing continuous graphical traceroute monitoring (like `mtr`). Built with Swift + SwiftUI, targeting macOS 14.6+. Bundle ID: `org.evilscheme.MenubarTracert`, Dev Team: `4PX677GC4R`.

## Architecture

Single-process sandboxed app using unprivileged ICMP sockets (`SOCK_DGRAM`).

```
MenubarTracert.app (SwiftUI, menubar-only, App Sandbox enabled)
  ├── TracerouteViewModel — state management, adaptive probe scheduling
  ├── ICMPEngine — SOCK_DGRAM ICMP sockets, TTL manipulation for traceroute
  └── Views: SparklineView (menubar), TraceroutePanel (dropdown), HeatmapBar, HopRowView, SettingsView
```

**Entitlements:** `com.apple.security.app-sandbox`, `com.apple.security.network.client`, `com.apple.security.network.server`. The `SOCK_DGRAM` + `IPPROTO_ICMP` approach requires no root privileges and works inside App Sandbox.

## Build & Run

Open `MenubarTracert/MenubarTracert.xcodeproj` in Xcode. Single target: MenubarTracert.

## Checking Logs

```bash
# App logs
log show --predicate 'process == "MenubarTracert"' --last 2m --style compact

# Verify code signing
codesign --verify --deep --strict --verbose=2 /Applications/MenubarTracert.app
```

## Commit Conventions

Do not include `Co-Authored-By: Claude` lines in commit messages.
