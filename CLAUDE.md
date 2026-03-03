# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MenubarTracert is a macOS menubar app providing continuous graphical traceroute monitoring (like `mtr`). Built with Swift + SwiftUI, targeting macOS 14.6+. Bundle ID: `org.evilscheme.MenubarTracert`, Dev Team: `4PX677GC4R`.

## Architecture

Two-process architecture: unprivileged SwiftUI app + privileged XPC helper daemon.

```
MenubarTracert.app (SwiftUI, menubar-only)
  ├── TracerouteViewModel — state management, adaptive probe scheduling
  ├── HelperManager — daemon registration via SMAppService.daemon()
  ├── HelperXPCClient — NSXPCConnection to helper
  └── Views: SparklineView (menubar), TraceroutePanel (dropdown), HeatmapBar, HopRowView, SettingsView
        │
        │ XPC (Mach service: org.evilscheme.MenubarTracert.TracertHelper)
        ▼
TracertHelper (privileged daemon, runs as root)
  ├── NSXPCListener + TracertHelperService
  └── ICMPEngine — raw ICMP sockets (SOCK_RAW), TTL manipulation for traceroute
```

**Shared code:** `Shared/TracertHelperProtocol.swift` defines the XPC protocol and `ProbeResultXPC` (NSSecureCoding). This file has manual target membership in both targets.

## Build & Run

Open `MenubarTracert/MenubarTracert.xcodeproj` in Xcode. Two targets: MenubarTracert (app) and TracertHelper (command-line tool).

**Critical:** The app must run from `/Applications` for `SMAppService.daemon()` registration to work. Set up a scheme post-action (Build → Post-actions) to copy:
```bash
rm -rf /Applications/MenubarTracert.app
cp -R "${BUILT_PRODUCTS_DIR}/MenubarTracert.app" /Applications/MenubarTracert.app
```
Set the scheme's Run executable to `/Applications/MenubarTracert.app`.

**After changing helper code**, restart the daemon:
```bash
sudo launchctl kickstart -k system/org.evilscheme.MenubarTracert.TracertHelper
```

## XPC Daemon Pitfalls

These are hard-won lessons — do not revert these without understanding why:

- **Helper signing:** TracertHelper needs `PRODUCT_BUNDLE_IDENTIFIER`, `GENERATE_INFOPLIST_FILE = YES`, and `CREATE_INFOPLIST_SECTION_IN_BINARY = YES`. Without embedded Info.plist, command-line tools get signed with just the product name instead of the bundle identifier.
- **BundleProgram path:** Must be `Contents/MacOS/TracertHelper` in the launchd plist (relative to `.app` root, NOT relative to `Contents/`).
- **ObjC class names:** `@objc(ProbeResultXPC)` is required on the shared class. Without it, Swift modules produce different ObjC names (`_TtC14MenubarTracert14ProbeResultXPC` vs `_TtC13TracertHelper14ProbeResultXPC`), breaking XPC deserialization.
- **XPC reply blocks:** Can only be called once. Protocol returns `[ProbeResultXPC]` array, not individual callbacks per hop.
- **NSArray in whitelist:** Both client and server must include `NSArray.self` in the XPC `setClasses` call.
- **NSSet cast:** Swift metatypes don't work directly with `setClasses()`. Use `NSSet(array: [...]) as! Set<AnyHashable>`.
- **Never unregister when `.enabled`:** Calling `service.unregister()` when status is `.enabled` changes BTM disposition to `disabled`, and subsequent `register()` will be rejected as "not allowed to bootstrap".
- **App Sandbox:** Must be disabled (`ENABLE_APP_SANDBOX = NO`) for XPC to privileged daemon.

## Checking Daemon Logs

```bash
# Helper daemon logs (NSLog output)
log show --predicate 'process == "TracertHelper"' --last 2m --style compact

# App registration logs
log show --predicate 'eventMessage CONTAINS "HelperManager"' --last 1m --style compact

# BTM (Background Task Management) decisions
log show --predicate 'process == "backgroundtaskmanagementd" AND eventMessage CONTAINS "evilscheme"' --last 1m --style compact

# Verify code signing
codesign --verify --deep --strict --verbose=2 /Applications/MenubarTracert.app
```

## Commit Conventions

Do not include `Co-Authored-By: Claude` lines in commit messages.
