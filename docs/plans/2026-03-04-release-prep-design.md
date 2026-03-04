# Release Preparation Design

**Date:** 2026-03-04
**Status:** Approved
**Version:** 1.0.0

## Goal

Ship MenubarTracert as both a direct-download DMG and a Mac App Store app, using a single unified codebase.

## Key Constraint

The current architecture uses a privileged XPC helper daemon (`TracertHelper`) with `SOCK_RAW` ICMP sockets, which requires root and `ENABLE_APP_SANDBOX = NO`. The Mac App Store requires App Sandbox. Multiple existing App Store traceroute apps (Network Analyzer Pro, PingDoctor, Best Trace) demonstrate that unprivileged ICMP is feasible.

## Approach: Validate-Then-Unify

Prove that `SOCK_DGRAM` + `IPPROTO_ICMP` works inside App Sandbox, then simplify to a single architecture with no privileged daemon.

**Decision gate:** If Phase 1 validation fails, pivot to DMG-only with the current XPC architecture.

## Phase 1: SOCK_DGRAM Proof of Concept

Build a minimal sandboxed test target (`SandboxProbe`) in the existing Xcode project.

**Configuration:**
- App Sandbox enabled
- `com.apple.security.network.client` + `com.apple.security.network.server` entitlements

**Validation steps (all must succeed):**
1. `socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)` returns a valid fd
2. `setsockopt(fd, IPPROTO_IP, IP_TTL, 3)` succeeds
3. `sendto()` ICMP echo request to `8.8.8.8` with TTL=3 succeeds
4. `recvfrom()` receives ICMP Time Exceeded with intermediate router IP
5. Send with TTL=64 and receive Echo Reply from destination

**Known gotcha:** `setsockopt(IP_TTL)` is synchronous but `sendto` is async. Probes must be sent one at a time with confirmation before changing TTL (Apple Developer Forums thread 726398).

## Phase 2: ICMPEngine Rewrite

Replace the privileged daemon architecture with in-process unprivileged ICMP.

**Changes to ICMPEngine:**
- `SOCK_RAW` -> `SOCK_DGRAM` on socket creation
- Replace synchronous `recvfrom` with `DispatchSource.makeReadSource()` for async I/O
- Serialize probes: send one, wait for send buffer drain, change TTL, send next
- Move from TracertHelper target into MenubarTracert app target

**Delete:**
- `TracertHelper/` target and all sources (`main.swift`, `TracertHelperService.swift`)
- `HelperManager.swift` (SMAppService daemon registration)
- `HelperXPCClient.swift` (NSXPCConnection to helper)
- `TracertHelperProtocol.swift` (shared XPC protocol)
- `ProbeResultXPC.swift` (NSSecureCoding wrapper — replace with plain Swift struct)
- `org.evilscheme.MenubarTracert.TracertHelper.plist` (launchd plist)

**New data flow:**
```
TracerouteViewModel
  -> ICMPEngine.runTrace(target:maxHops:) async
    -> socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
    -> for hop in 1...maxHops:
        setsockopt(IP_TTL, hop)
        sendto(ICMP echo)
        await response via DispatchSource
        yield ProbeResult
  -> ViewModel updates @Published state
```

**Unchanged:** All UI code, SparklineView, TraceroutePanel, SettingsView, HopRowView, HeatmapBar.

## Phase 3: App Polish

**Placeholder app icon:**
- Generate a simple network/route motif rendered to all 10 required macOS sizes (16-512 @1x and @2x)
- Slot into existing `AppIcon.appiconset` (Contents.json already correct)

**Version display:**
- Add version label in settings panel from `Bundle.main.infoDictionary`

**Copyright:**
- `INFOPLIST_KEY_NSHumanReadableCopyright = "Copyright © 2025-2026 Bryan Burns"`

**App category:**
- `LSApplicationCategoryType = public.app-category.utilities`

**Deployment target fix:**
- Project-level deployment target is incorrectly set to `26.2` — fix to `14.6`

**Privacy manifest:**
- Add `PrivacyInfo.xcprivacy` for App Store (declare required reason API usage)

## Phase 4: Distribution Infrastructure

**DMG creation (`scripts/create-dmg.sh`):**
1. `xcodebuild archive` (Release)
2. Export archive
3. Notarize with `notarytool` (requires Developer ID cert)
4. Create DMG with drag-to-Applications layout via `hdiutil`
5. Staple notarization ticket

**GitHub Actions (`.github/workflows/build.yml`):**
- Trigger on push/PR to main
- `xcodebuild build` for Debug and Release
- macOS runner (`macos-14` or `macos-15`)
- No signing, no artifacts — build validation only

**Release flow:**
1. Tag version (`git tag v1.0.0`)
2. Run `scripts/create-dmg.sh` locally (sign + notarize)
3. Create GitHub Release, attach DMG
4. For App Store: `xcodebuild archive` -> upload via Transporter

## Phase 5: App Store Submission

- Enable `ENABLE_APP_SANDBOX = YES`
- Add entitlements: `network.client`, `network.server`
- Add App Store metadata (description, screenshots, privacy policy URL)
- Submit via Transporter or Xcode Organizer

## Out of Scope for 1.0

- Auto-update framework (Sparkle) — users download new versions from GitHub Releases
- Professional app icon — placeholder for now, commission later
- IPv6 support
- Signed CI artifacts

## References

- Apple DTS: BSD sockets recommended for ICMP (Developer Forums thread 672109)
- `SOCK_DGRAM` + `IPPROTO_ICMP` works without root (macOS icmp(4) man page)
- `setsockopt`/`sendto` TTL race condition (Developer Forums thread 726398)
- Apple recommends DispatchSource over CFSocket for socket integration (Developer Forums thread 724595)
- Existing App Store traceroute apps: Network Analyzer Pro, PingDoctor, Best Trace, Nice Trace
