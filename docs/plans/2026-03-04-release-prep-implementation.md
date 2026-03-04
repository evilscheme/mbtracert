# Release Preparation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ship MenubarTracert 1.0.0 as both DMG (direct download) and Mac App Store app, by replacing the privileged XPC daemon with unprivileged ICMP sockets.

**Architecture:** Replace `SOCK_RAW` (requires root, XPC daemon) with `SOCK_DGRAM` + `IPPROTO_ICMP` (unprivileged, in-process). This eliminates the TracertHelper daemon, HelperManager, HelperXPCClient, and the entire XPC layer. The app becomes a single sandboxed process.

**Tech Stack:** Swift, SwiftUI, BSD sockets, macOS App Sandbox, xcodebuild, hdiutil, GitHub Actions

**Decision Gate:** Task 1 is the PoC. If it fails, stop and revisit the design (fall back to DMG-only with current XPC architecture).

---

### Task 1: SOCK_DGRAM Proof of Concept

**Files:**
- Create: `tools/sandbox-probe.swift`
- Create: `tools/sandbox-probe.entitlements`

**Goal:** Validate that `SOCK_DGRAM` + `IPPROTO_ICMP` works with TTL control and receives Time Exceeded responses, both with and without App Sandbox.

**Step 1: Write the PoC tool**

Create `tools/sandbox-probe.swift`:

```swift
import Foundation
import Darwin

func log(_ msg: String) { print("[SandboxProbe] \(msg)") }

// Step 1: Create SOCK_DGRAM ICMP socket
let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
guard sock >= 0 else {
    log("FAIL: socket() failed: \(String(cString: strerror(errno)))")
    exit(1)
}
log("PASS: socket() returned fd \(sock)")

// Step 2: Set TTL
var ttl: Int32 = 3
let ttlResult = setsockopt(sock, IPPROTO_IP, IP_TTL, &ttl, socklen_t(MemoryLayout<Int32>.size))
guard ttlResult == 0 else {
    log("FAIL: setsockopt(IP_TTL) failed: \(String(cString: strerror(errno)))")
    exit(1)
}
log("PASS: setsockopt(IP_TTL=3) succeeded")

// Build ICMP Echo Request packet
var packet = Data(count: 16)
packet[0] = 8  // Echo Request
packet[1] = 0  // Code
let pid = UInt16(getpid() & 0xFFFF)
packet[4] = UInt8(pid >> 8)
packet[5] = UInt8(pid & 0xFF)
packet[6] = 0   // Sequence high byte
packet[7] = 1   // Sequence low byte
// Checksum (kernel may recompute for SOCK_DGRAM, but set it anyway)
var sum: UInt32 = 0
for i in stride(from: 0, to: packet.count - 1, by: 2) {
    sum += UInt32(packet[i]) << 8 | UInt32(packet[i + 1])
}
while sum >> 16 != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
let cksum = ~UInt16(sum & 0xFFFF)
packet[2] = UInt8(cksum >> 8)
packet[3] = UInt8(cksum & 0xFF)

// Resolve 8.8.8.8
var dest = sockaddr_in()
dest.sin_family = sa_family_t(AF_INET)
dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
inet_pton(AF_INET, "8.8.8.8", &dest.sin_addr)

// Step 3: Send ICMP echo with TTL=3
let sent = packet.withUnsafeBytes { buf in
    withUnsafeMutablePointer(to: &dest) { addrPtr in
        addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            sendto(sock, buf.baseAddress, packet.count, 0, sa,
                   socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
}
guard sent >= 0 else {
    log("FAIL: sendto() failed: \(String(cString: strerror(errno)))")
    exit(1)
}
log("PASS: sendto() sent \(sent) bytes with TTL=3")

// Step 4: Receive response (expect Time Exceeded from intermediate router)
var tv = timeval(tv_sec: 3, tv_usec: 0)
setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

var buffer = [UInt8](repeating: 0, count: 4096)
var sender = sockaddr_in()
var senderLen = socklen_t(MemoryLayout<sockaddr_in>.size)

let bytesRead = withUnsafeMutablePointer(to: &sender) { senderPtr in
    senderPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
        recvfrom(sock, &buffer, buffer.count, 0, sa, &senderLen)
    }
}

if bytesRead > 0 {
    let senderIP = String(cString: inet_ntoa(sender.sin_addr))
    let icmpType = buffer[0]  // SOCK_DGRAM: no IP header, ICMP starts at [0]
    let typeName = icmpType == 0 ? "Echo Reply" : icmpType == 11 ? "Time Exceeded" : "Type \(icmpType)"
    log("PASS: recvfrom() got \(bytesRead) bytes from \(senderIP), ICMP type=\(icmpType) (\(typeName))")

    if icmpType == 11 {
        // Parse embedded original packet to verify sequence matching works
        // ICMP Time Exceeded: [type(1)][code(1)][cksum(2)][unused(4)][original IP header...][original ICMP...]
        if bytesRead >= 36 {  // 8 (ICMP hdr) + 20 (min IP hdr) + 8 (ICMP hdr)
            let innerIPHdrLen = Int(buffer[8] & 0x0F) * 4
            let innerICMPOff = 8 + innerIPHdrLen
            if bytesRead >= innerICMPOff + 8 {
                let innerSeq = UInt16(buffer[innerICMPOff + 6]) << 8 | UInt16(buffer[innerICMPOff + 7])
                log("PASS: Inner ICMP sequence=\(innerSeq) (expected 1)")
            }
        }
    }
} else {
    log("FAIL: recvfrom() timed out or failed: \(String(cString: strerror(errno)))")
}

// Step 5: Send with high TTL to get Echo Reply from destination
var highTTL: Int32 = 64
setsockopt(sock, IPPROTO_IP, IP_TTL, &highTTL, socklen_t(MemoryLayout<Int32>.size))

packet[7] = 2  // Sequence = 2
// Recompute checksum
packet[2] = 0; packet[3] = 0
sum = 0
for i in stride(from: 0, to: packet.count - 1, by: 2) {
    sum += UInt32(packet[i]) << 8 | UInt32(packet[i + 1])
}
while sum >> 16 != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
let cksum2 = ~UInt16(sum & 0xFFFF)
packet[2] = UInt8(cksum2 >> 8)
packet[3] = UInt8(cksum2 & 0xFF)

let sent2 = packet.withUnsafeBytes { buf in
    withUnsafeMutablePointer(to: &dest) { addrPtr in
        addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            sendto(sock, buf.baseAddress, packet.count, 0, sa,
                   socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
}

if sent2 >= 0 {
    let bytesRead2 = withUnsafeMutablePointer(to: &sender) { senderPtr in
        senderPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            recvfrom(sock, &buffer, buffer.count, 0, sa, &senderLen)
        }
    }
    if bytesRead2 > 0 {
        let senderIP = String(cString: inet_ntoa(sender.sin_addr))
        let icmpType = buffer[0]
        log("PASS: Echo Reply from \(senderIP), type=\(icmpType)")
    } else {
        log("FAIL: No Echo Reply received")
    }
} else {
    log("FAIL: sendto() with TTL=64 failed")
}

close(sock)
log("All tests complete")
```

**Step 2: Create entitlements file**

Create `tools/sandbox-probe.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
</dict>
</plist>
```

**Step 3: Compile and test WITHOUT sandbox first**

```bash
cd MenubarTracert
swiftc -o /tmp/sandbox-probe ../tools/sandbox-probe.swift
/tmp/sandbox-probe
```

Expected: All 5 steps PASS. This confirms SOCK_DGRAM works at all.

**Step 4: Compile and test WITH sandbox**

```bash
swiftc -o /tmp/sandbox-probe ../tools/sandbox-probe.swift
codesign --force --sign - --entitlements ../tools/sandbox-probe.entitlements /tmp/sandbox-probe
/tmp/sandbox-probe
```

Expected: All 5 steps PASS. This confirms SOCK_DGRAM works inside App Sandbox.

**Step 5: Commit**

```bash
git add tools/sandbox-probe.swift tools/sandbox-probe.entitlements
git commit -m "feat: add SOCK_DGRAM sandbox proof-of-concept tool"
```

**DECISION GATE:** If Step 4 fails, STOP. Fall back to DMG-only with current XPC architecture. Skip Tasks 2-5 and 8. Proceed to Tasks 6-7, 9-10 (app polish and distribution that don't require architecture change).

---

### Task 2: Rewrite ICMPEngine for SOCK_DGRAM

**Files:**
- Create: `MenubarTracert/MenubarTracert/Services/ICMPEngine.swift` (new location, in app target)

**Goal:** Port ICMPEngine from `SOCK_RAW` to `SOCK_DGRAM`, adjusting response parsing for the absence of IP headers.

**Step 1: Create new ICMPEngine in app target**

Create `MenubarTracert/MenubarTracert/Services/ICMPEngine.swift` (the file system synchronized group will auto-include it):

```swift
import Foundation
import Darwin

struct HopResult {
    let hop: Int
    let address: String
    let latencyMs: Double
}

final class ICMPEngine {
    private let identifier: UInt16
    private let sock: Int32
    private var nextSequence: UInt16 = 33434

    init() {
        self.identifier = UInt16(getpid() & 0xFFFF)
        self.sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        if sock < 0 {
            NSLog("[ICMPEngine] socket() failed: %s", String(cString: strerror(errno)))
        }
    }

    deinit {
        if sock >= 0 { close(sock) }
    }

    private func allocateSequence() -> UInt16 {
        let seq = nextSequence
        nextSequence = nextSequence >= 65535 ? 33434 : nextSequence + 1
        return seq
    }

    /// Hybrid probe: send all probes sequentially (reliable TTL) with short
    /// inline collection, then a bulk collection pass for slow responses.
    func probeRound(host: String, maxHops: Int, timeout: TimeInterval = 2.0) -> [HopResult] {
        guard sock >= 0 else { return [] }

        guard var destAddr = resolveHost(host) else {
            return []
        }
        let destIP = ipString(from: destAddr)

        // seq -> (hop, sendTime) mapping for response matching
        var probeMap: [UInt16: (hop: Int, sendTime: UInt64)] = [:]
        var responses: [Int: (address: String, latencyMs: Double)] = [:]
        var destHop = maxHops
        let inlineTimeout: TimeInterval = 0.05  // 50ms per hop

        // Phase 1: Send probes with short inline collection
        for hop in 1...maxHops {
            var ttl = Int32(hop)
            setsockopt(sock, IPPROTO_IP, IP_TTL, &ttl, socklen_t(MemoryLayout<Int32>.size))

            let seq = allocateSequence()
            let packet = buildPacket(sequence: seq)
            probeMap[seq] = (hop: hop, sendTime: mach_absolute_time())

            let sent = packet.withUnsafeBytes { buf in
                withUnsafeMutablePointer(to: &destAddr) { addrPtr in
                    addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        sendto(sock, buf.baseAddress, packet.count, 0, sa,
                               socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            guard sent >= 0 else { continue }

            // Short inline collection -- grab fast responses without blocking
            var tv = timeval(tv_sec: 0, tv_usec: Int32(inlineTimeout * 1_000_000))
            setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            collectResponses(probeMap: probeMap, responses: &responses,
                             destIP: destIP, destHop: &destHop, maxReads: 3)

            if destHop < maxHops && hop >= destHop { break }
        }

        // Phase 2: Bulk collection for slow/rate-limited responses
        let bulkTimeout = max(timeout - Double(min(destHop, maxHops)) * inlineTimeout, 0.5)
        let deadline = Date().addingTimeInterval(bulkTimeout)

        while Date() < deadline {
            let remaining = max(deadline.timeIntervalSinceNow, 0.01)
            var tv = timeval(tv_sec: Int(remaining), tv_usec: Int32((remaining.truncatingRemainder(dividingBy: 1)) * 1_000_000))
            setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

            let before = responses.count
            collectResponses(probeMap: probeMap, responses: &responses,
                             destIP: destIP, destHop: &destHop, maxReads: 1)
            if responses.count == before { break }
            if responses.count >= destHop { break }
        }

        // Build results up to destination (or maxHops if destination didn't reply)
        return (1...destHop).map { hop in
            if let resp = responses[hop] {
                return HopResult(hop: hop, address: resp.address, latencyMs: resp.latencyMs)
            } else {
                return HopResult(hop: hop, address: "", latencyMs: -1)
            }
        }
    }

    // MARK: - Response Collection

    /// SOCK_DGRAM: kernel strips outer IP header. Buffer starts at ICMP header.
    private func collectResponses(
        probeMap: [UInt16: (hop: Int, sendTime: UInt64)],
        responses: inout [Int: (address: String, latencyMs: Double)],
        destIP: String,
        destHop: inout Int,
        maxReads: Int
    ) {
        for _ in 0..<maxReads {
            var buffer = [UInt8](repeating: 0, count: 4096)
            var sender = sockaddr_in()
            var senderLen = socklen_t(MemoryLayout<sockaddr_in>.size)

            let bytesRead = withUnsafeMutablePointer(to: &sender) { senderPtr in
                senderPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(sock, &buffer, buffer.count, 0, sa, &senderLen)
                }
            }
            let recvTime = mach_absolute_time()
            guard bytesRead > 0 else { return }

            let senderIP = ipString(from: sender)

            // SOCK_DGRAM: no IP header. ICMP type is at buffer[0].
            let icmpType = buffer[0]

            if icmpType == 0 { // Echo Reply
                guard bytesRead >= 8 else { continue }
                let seq = UInt16(buffer[6]) << 8 | UInt16(buffer[7])
                // Kernel filters by identifier for SOCK_DGRAM -- no need to check id
                guard let probe = probeMap[seq] else { continue }
                responses[probe.hop] = (senderIP, machDiffMs(probe.sendTime, recvTime))
                if senderIP == destIP { destHop = min(destHop, probe.hop) }
            } else if icmpType == 11 || icmpType == 3 { // Time Exceeded / Dest Unreachable
                // ICMP header (8 bytes) + embedded original IP header + original ICMP
                let innerIPOffset = 8
                guard bytesRead >= innerIPOffset + 20 else { continue }
                let innerIPHdrLen = Int(buffer[innerIPOffset] & 0x0F) * 4
                let innerICMPOff = innerIPOffset + innerIPHdrLen
                guard bytesRead >= innerICMPOff + 8 else { continue }

                let innerSeq = UInt16(buffer[innerICMPOff + 6]) << 8 | UInt16(buffer[innerICMPOff + 7])
                // Kernel filters by identifier -- just match sequence
                guard let probe = probeMap[innerSeq] else { continue }
                responses[probe.hop] = (senderIP, machDiffMs(probe.sendTime, recvTime))
                if icmpType == 3 { destHop = min(destHop, probe.hop) }
            }
        }
    }

    // MARK: - Packet Construction

    private func buildPacket(sequence: UInt16) -> Data {
        var packet = Data(count: 16)

        packet[0] = 8  // Type: Echo Request
        packet[1] = 0  // Code
        packet[4] = UInt8(identifier >> 8)
        packet[5] = UInt8(identifier & 0xFF)
        packet[6] = UInt8(sequence >> 8)
        packet[7] = UInt8(sequence & 0xFF)

        var ts = mach_absolute_time()
        withUnsafeBytes(of: &ts) { tsBytes in
            for i in 0..<8 { packet[8 + i] = tsBytes[i] }
        }

        // Kernel may recompute checksum for SOCK_DGRAM, but compute it anyway
        let checksum = computeChecksum(packet)
        packet[2] = UInt8(checksum >> 8)
        packet[3] = UInt8(checksum & 0xFF)

        return packet
    }

    private func computeChecksum(_ data: Data) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i < data.count - 1 {
            sum += UInt32(data[i]) << 8 | UInt32(data[i + 1])
            i += 2
        }
        if data.count % 2 != 0 {
            sum += UInt32(data[data.count - 1]) << 8
        }
        while sum >> 16 != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        return ~UInt16(sum & 0xFFFF)
    }

    // MARK: - Utilities

    private func resolveHost(_ host: String) -> sockaddr_in? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let info = result else { return nil }
        defer { freeaddrinfo(result) }
        return info.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
    }

    private func ipString(from addr: sockaddr_in) -> String {
        let addr = addr
        return String(cString: inet_ntoa(addr.sin_addr))
    }

    private func machDiffMs(_ start: UInt64, _ end: UInt64) -> Double {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let nanos = Double(end - start) * Double(info.numer) / Double(info.denom)
        return nanos / 1_000_000.0
    }
}
```

**Key differences from the original `TracertHelper/ICMPEngine.swift`:**
1. Line 18: `SOCK_DGRAM` instead of `SOCK_RAW`
2. `collectResponses`: no IP header offset (`ipHdrLen` removed). ICMP type is at `buffer[0]`.
3. Echo Reply matching: no identifier check (kernel filters for SOCK_DGRAM)
4. Time Exceeded parsing: `innerIPOffset = 8` (directly after ICMP header, no outer IP header)

**Step 2: Verify the new file compiles**

```bash
cd MenubarTracert && xcodebuild build -target MenubarTracert -configuration Debug 2>&1 | tail -5
```

Expected: Build may fail due to duplicate `HopResult` type (also defined in `TracertHelper/ICMPEngine.swift`). That's OK -- the TracertHelper target has its own copy. The app target should only see the new file.

**Note:** If there's a naming conflict because `TracertHelper/ICMPEngine.swift` is somehow visible to the app target, rename the new file's `HopResult` temporarily. This will be resolved in Task 4 when we delete the old files.

**Step 3: Commit**

```bash
git add MenubarTracert/MenubarTracert/Services/ICMPEngine.swift
git commit -m "feat: add SOCK_DGRAM ICMPEngine for in-process traceroute"
```

---

### Task 3: Rewire TracerouteViewModel to Use In-Process Engine

**Files:**
- Modify: `MenubarTracert/MenubarTracert/ViewModels/TracerouteViewModel.swift`

**Goal:** Replace XPC calls with direct ICMPEngine calls. Remove helper registration.

**Step 1: Replace XPC client with ICMPEngine**

In `TracerouteViewModel.swift`, replace line 32:

```swift
// OLD
private let xpcClient = HelperXPCClient()
```

with:

```swift
// NEW
private let engine = ICMPEngine()
```

**Step 2: Simplify `start()` method**

Replace lines 40-59 (the entire `start()` method):

```swift
// OLD
func start() {
    // Debug: print the app bundle path and check for the plist
    let bundle = Bundle.main
    print("[Start] Bundle path: \(bundle.bundlePath)")
    let plistPath = bundle.bundlePath + "/Contents/Library/LaunchDaemons/org.evilscheme.MenubarTracert.TracertHelper.plist"
    let helperPath = bundle.bundlePath + "/Contents/MacOS/TracertHelper"
    print("[Start] Plist exists: \(FileManager.default.fileExists(atPath: plistPath))")
    print("[Start] Helper exists: \(FileManager.default.fileExists(atPath: helperPath))")

    do {
        try HelperManager.shared.registerIfNeeded()
        helperInstalled = true
    } catch {
        helperInstalled = false
        errorMessage = "Helper installation failed: \(error.localizedDescription)"
        print("[Start] Registration error: \(error)")
        return
    }
    scheduleProbing()
}
```

with:

```swift
// NEW
func start() {
    scheduleProbing()
}
```

**Step 3: Rewrite `runProbeRound()` to call engine directly**

Replace lines 118-179 (the entire `runProbeRound()` method):

```swift
// OLD (XPC-based, 60+ lines)
private func runProbeRound() async { ... }
```

with:

```swift
// NEW
private func runProbeRound() async {
    isProbing = true
    errorMessage = nil

    let bufferCapacity = Int(historyMinutes * 60 / activeInterval)
    let target = targetHost
    let hops = maxHops

    let results = await Task.detached {
        self.engine.probeRound(host: target, maxHops: hops)
    }.value

    for result in results {
        let probe = ProbeResult(
            hop: result.hop,
            address: result.address,
            hostname: resolveHostnames ? cachedHostname(for: result.address) : nil,
            latencyMs: result.latencyMs,
            timestamp: Date()
        )

        if let idx = self.hops.firstIndex(where: { $0.hop == result.hop }) {
            self.hops[idx].probes.append(probe)
            if !result.address.isEmpty {
                self.hops[idx].address = result.address
                self.hops[idx].hostname = probe.hostname
            }
        } else {
            var hopData = HopData(
                id: result.hop,
                hop: result.hop,
                address: result.address,
                hostname: probe.hostname,
                probes: RingBuffer<ProbeResult>(capacity: bufferCapacity)
            )
            hopData.probes.append(probe)
            self.hops.append(hopData)
            self.hops.sort { $0.hop < $1.hop }
        }
    }

    // Remove hops whose data has fully aged out of the history window.
    let cutoff = Date().addingTimeInterval(-historyMinutes * 60)
    self.hops.removeAll { hop in
        guard let newest = hop.probes.elements.last else { return true }
        return newest.timestamp < cutoff
    }

    if let lastResponding = self.hops.last(where: { $0.lastLatencyMs > 0 }) {
        latencyHistory.append(lastResponding.lastLatencyMs)
        if latencyHistory.count > sparklineCapacity {
            latencyHistory.removeFirst()
        }
    }

    isProbing = false
}
```

**Step 4: Remove `helperInstalled` published property and unused import**

Remove line 13:

```swift
@Published var helperInstalled = false
```

Remove `import Combine` from line 3 if it's no longer needed (check if anything else uses it -- `@Published` comes from `Combine` via `ObservableObject`, so it's implicitly imported. Removing the explicit import should be fine since `SwiftUI` re-exports it).

**Step 5: Build and verify**

```bash
cd MenubarTracert && xcodebuild build -target MenubarTracert -configuration Debug 2>&1 | tail -20
```

Expected: Build succeeds (may have warnings about unused HelperXPCClient/HelperManager, that's fine -- deleted in Task 4).

**Step 6: Commit**

```bash
git add MenubarTracert/MenubarTracert/ViewModels/TracerouteViewModel.swift
git commit -m "feat: replace XPC helper calls with in-process ICMPEngine"
```

---

### Task 4: Remove XPC Infrastructure

**Files:**
- Delete: `MenubarTracert/MenubarTracert/Services/HelperXPCClient.swift`
- Delete: `MenubarTracert/MenubarTracert/Services/HelperManager.swift`
- Delete: `MenubarTracert/Shared/TracertHelperProtocol.swift`
- Delete: `MenubarTracert/TracertHelper/ICMPEngine.swift`
- Delete: `MenubarTracert/TracertHelper/main.swift`
- Delete: `MenubarTracert/MenubarTracert/org.evilscheme.MenubarTracert.TracertHelper.plist`
- Modify: `MenubarTracert/MenubarTracert.xcodeproj/project.pbxproj`
- Modify: `MenubarTracert/MenubarTracert/Views/SettingsView.swift` (remove Helper Status)
- Modify: `MenubarTracert/MenubarTracert/MenubarTracertApp.swift` (if needed)

**Goal:** Remove all XPC/daemon code and clean up the Xcode project.

**Step 1: Remove SettingsView Helper Status and Launch at Login**

In `MenubarTracert/MenubarTracert/Views/SettingsView.swift`, replace the third Section (lines 61-79) with just Launch at Login (no helper status):

```swift
// OLD (lines 61-79)
Section {
    Toggle("Launch at Login", isOn: $launchAtLogin)
        .onChange(of: launchAtLogin) { _, enabled in
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                launchAtLogin = !enabled
            }
        }

    LabeledContent("Helper Status") {
        Text(viewModel.helperInstalled ? "Installed" : "Not Installed")
            .foregroundStyle(viewModel.helperInstalled ? .green : .red)
    }
}
```

with:

```swift
// NEW
Section {
    Toggle("Launch at Login", isOn: $launchAtLogin)
        .onChange(of: launchAtLogin) { _, enabled in
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                launchAtLogin = !enabled
            }
        }
}
```

**Step 2: Delete the old source files**

```bash
rm MenubarTracert/MenubarTracert/Services/HelperXPCClient.swift
rm MenubarTracert/MenubarTracert/Services/HelperManager.swift
rm MenubarTracert/Shared/TracertHelperProtocol.swift
rm MenubarTracert/TracertHelper/ICMPEngine.swift
rm MenubarTracert/TracertHelper/main.swift
rm MenubarTracert/MenubarTracert/org.evilscheme.MenubarTracert.TracertHelper.plist
rmdir MenubarTracert/TracertHelper
rmdir MenubarTracert/Shared
```

**Step 3: Edit project.pbxproj to remove TracertHelper target**

This is the most delicate step. The following sections must be removed or modified in `MenubarTracert/MenubarTracert.xcodeproj/project.pbxproj`:

**Remove these entire blocks:**

1. PBXBuildFile line 10: `TracertHelper in Copy Helper`
2. PBXBuildFile lines 12-13: Both `TracertHelperProtocol.swift in Sources` entries
3. PBXContainerItemProxy lines 17-23: TracertHelper proxy
4. PBXCopyFilesBuildPhase lines 27-35: `CopyFiles` (TracertHelper man page)
5. PBXCopyFilesBuildPhase lines 36-45: `Copy LaunchDaemon Plist`
6. PBXCopyFilesBuildPhase lines 46-56: `Copy Helper`
7. PBXFileReference line 61: `TracertHelper` executable
8. PBXFileReference line 63: `TracertHelperProtocol.swift`
9. PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet lines 67-73
10. PBXFileSystemSynchronizedRootGroup lines 85-89: TracertHelper
11. PBXFrameworksBuildPhase lines 101-107: TracertHelper Frameworks
12. PBXNativeTarget lines 175-196: TracertHelper target
13. PBXSourcesBuildPhase lines 254-261: TracertHelper Sources
14. PBXTargetDependency lines 265-269
15. XCBuildConfiguration lines 459-494: TracertHelper Debug and Release
16. XCConfigurationList lines 516-524: TracertHelper config list

**Modify these blocks:**

17. PBXNativeTarget MenubarTracert (lines 149-174): Remove from `buildPhases`:
    - `9336BE632F56A5EE00913A16 /* Copy LaunchDaemon Plist */,`
    - `9336BE642F56A61B00913A16 /* Copy Helper */,`
    Remove from `dependencies`:
    - `9336BE622F56A5DE00913A16 /* PBXTargetDependency */,`

18. PBXSourcesBuildPhase for app (lines 246-253): Remove:
    - `9336BE8B2F56A9EA00913A16 /* TracertHelperProtocol.swift in Sources */,`

19. PBXGroup Products (lines 122-130): Remove:
    - `9336BE5A2F56A3C000913A16 /* TracertHelper */,`

20. PBXGroup Shared (lines 139-146): Remove entire group

21. PBXGroup root (lines 111-121): Remove:
    - `9336BE692F56A6D800913A16 /* Shared */,`
    - `9336BE5B2F56A3C000913A16 /* TracertHelper */,`

22. PBXProject targets (lines 228-231): Remove:
    - `9336BE592F56A3C000913A16 /* TracertHelper */,`

23. PBXFileSystemSynchronizedRootGroup for MenubarTracert (lines 77-84): Remove the `exceptions` array entirely (or just the membership exception reference)

**Step 4: Build and verify**

```bash
cd MenubarTracert && xcodebuild build -target MenubarTracert -configuration Debug 2>&1 | tail -20
```

Expected: Build succeeds with only the MenubarTracert app target.

**Step 5: Commit**

```bash
git add -A
git commit -m "refactor: remove XPC helper daemon, use in-process ICMP engine"
```

---

### Task 5: Enable App Sandbox and Entitlements

**Files:**
- Create: `MenubarTracert/MenubarTracert/MenubarTracert.entitlements`
- Modify: `MenubarTracert/MenubarTracert.xcodeproj/project.pbxproj`

**Step 1: Create entitlements file**

Create `MenubarTracert/MenubarTracert/MenubarTracert.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
</dict>
</plist>
```

**Step 2: Update pbxproj build settings**

In `project.pbxproj`, for both Debug and Release configs of MenubarTracert target:

Change:
```
ENABLE_APP_SANDBOX = NO;
```
to:
```
CODE_SIGN_ENTITLEMENTS = MenubarTracert/MenubarTracert.entitlements;
ENABLE_APP_SANDBOX = YES;
```

This applies at lines 402 and 435 (Debug and Release respectively).

**Step 3: Build and test**

```bash
cd MenubarTracert && xcodebuild build -target MenubarTracert -configuration Debug 2>&1 | tail -10
```

Expected: Build succeeds. The app should now be sandboxed.

**Step 4: Run and verify ICMP works in sandbox**

Build and run the app (from /Applications per CLAUDE.md instructions). Verify traceroute data appears in the panel.

**Step 5: Commit**

```bash
git add MenubarTracert/MenubarTracert/MenubarTracert.entitlements MenubarTracert/MenubarTracert.xcodeproj/project.pbxproj
git commit -m "feat: enable App Sandbox with network entitlements"
```

---

### Task 6: Fix Build Settings (Deployment Target, Copyright, Category, Version)

**Files:**
- Modify: `MenubarTracert/MenubarTracert.xcodeproj/project.pbxproj`

**Step 1: Fix project-level deployment target**

In `project.pbxproj`, change lines 327 and 385:

```
MACOSX_DEPLOYMENT_TARGET = 26.2;
```
to:
```
MACOSX_DEPLOYMENT_TARGET = 14.6;
```

**Step 2: Set copyright**

Change lines 407 and 440:

```
INFOPLIST_KEY_NSHumanReadableCopyright = "";
```
to:
```
INFOPLIST_KEY_NSHumanReadableCopyright = "Copyright © 2025-2026 Bryan Burns";
```

**Step 3: Add app category**

Add after `INFOPLIST_KEY_NSHumanReadableCopyright` in both Debug (after line 407) and Release (after line 440):

```
INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.utilities";
```

**Step 4: Set marketing version to 1.0.0**

Change lines 413 and 446:

```
MARKETING_VERSION = 1.0;
```
to:
```
MARKETING_VERSION = 1.0.0;
```

**Step 5: Build and verify**

```bash
cd MenubarTracert && xcodebuild build -target MenubarTracert -configuration Release 2>&1 | tail -5
```

**Step 6: Commit**

```bash
git add MenubarTracert/MenubarTracert.xcodeproj/project.pbxproj
git commit -m "chore: fix deployment target, add copyright and app category"
```

---

### Task 7: Add Version Display in Settings

**Files:**
- Modify: `MenubarTracert/MenubarTracert/Views/SettingsView.swift`

**Step 1: Add version info to GeneralTab**

In `SettingsView.swift`, add a new Section after the Launch at Login section (after line 79, before `.formStyle(.grouped)`):

```swift
Section {
    LabeledContent("Version") {
        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")
            .foregroundStyle(.secondary)
    }
}
```

**Step 2: Build and verify**

```bash
cd MenubarTracert && xcodebuild build -target MenubarTracert -configuration Debug 2>&1 | tail -5
```

**Step 3: Commit**

```bash
git add MenubarTracert/MenubarTracert/Views/SettingsView.swift
git commit -m "feat: show app version in settings panel"
```

---

### Task 8: Generate Placeholder App Icon

**Files:**
- Create: `tools/generate-icon.swift`
- Modify: `MenubarTracert/MenubarTracert/Assets.xcassets/AppIcon.appiconset/` (add PNG files)

**Step 1: Write icon generator script**

Create `tools/generate-icon.swift` -- a Swift script that uses CoreGraphics to render a simple network-themed icon (stylized route/path graphic) at all required macOS sizes:

```swift
import AppKit
import CoreGraphics

func generateIcon(size: Int) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(size)
    let pad = s * 0.1

    // Background: rounded rect with gradient
    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    let cornerRadius = s * 0.2
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    // Gradient: dark teal to darker teal
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.1, green: 0.35, blue: 0.45, alpha: 1.0),
        CGColor(red: 0.05, green: 0.2, blue: 0.3, alpha: 1.0)
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
    }

    // Draw stylized route: dots connected by lines
    let nodeRadius = s * 0.05
    let nodes: [(CGFloat, CGFloat)] = [
        (0.2, 0.8), (0.35, 0.55), (0.5, 0.7), (0.65, 0.4), (0.8, 0.25)
    ]

    // Draw connecting lines
    ctx.setStrokeColor(CGColor(red: 0.3, green: 0.8, blue: 0.9, alpha: 0.6))
    ctx.setLineWidth(s * 0.02)
    ctx.setLineCap(.round)
    for i in 0..<nodes.count - 1 {
        let (x1, y1) = nodes[i]
        let (x2, y2) = nodes[i + 1]
        ctx.move(to: CGPoint(x: pad + x1 * (s - 2 * pad), y: pad + y1 * (s - 2 * pad)))
        ctx.addLine(to: CGPoint(x: pad + x2 * (s - 2 * pad), y: pad + y2 * (s - 2 * pad)))
    }
    ctx.strokePath()

    // Draw nodes
    for (i, (x, y)) in nodes.enumerated() {
        let cx = pad + x * (s - 2 * pad)
        let cy = pad + y * (s - 2 * pad)
        let r = nodeRadius * (i == nodes.count - 1 ? 1.5 : 1.0)  // Destination node larger

        // Glow
        ctx.setFillColor(CGColor(red: 0.3, green: 0.8, blue: 0.9, alpha: 0.3))
        ctx.fillEllipse(in: CGRect(x: cx - r * 2, y: cy - r * 2, width: r * 4, height: r * 4))

        // Node
        ctx.setFillColor(CGColor(red: 0.4, green: 0.9, blue: 1.0, alpha: 1.0))
        ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }

    img.unlockFocus()
    return img
}

// macOS icon sizes: 16, 32, 128, 256, 512 at 1x and 2x
let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

for (size, filename) in sizes {
    let img = generateIcon(size: size)
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("Failed to generate \(filename)")
        continue
    }
    let url = URL(fileURLWithPath: outputDir).appendingPathComponent(filename)
    try! png.write(to: url)
    print("Generated \(filename) (\(size)x\(size))")
}
```

**Step 2: Generate icons**

```bash
cd MenubarTracert
swift ../tools/generate-icon.swift MenubarTracert/Assets.xcassets/AppIcon.appiconset/
```

**Step 3: Update Contents.json with filenames**

Replace `MenubarTracert/MenubarTracert/Assets.xcassets/AppIcon.appiconset/Contents.json`:

```json
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

**Step 4: Build and verify**

```bash
cd MenubarTracert && xcodebuild build -target MenubarTracert -configuration Debug 2>&1 | tail -5
```

**Step 5: Commit**

```bash
git add tools/generate-icon.swift MenubarTracert/MenubarTracert/Assets.xcassets/AppIcon.appiconset/
git commit -m "feat: add placeholder app icon"
```

---

### Task 9: Create DMG Build Script

**Files:**
- Create: `scripts/create-dmg.sh`

**Step 1: Write the build script**

Create `scripts/create-dmg.sh`:

```bash
#!/bin/bash
set -euo pipefail

APP_NAME="MenubarTracert"
BUNDLE_ID="org.evilscheme.MenubarTracert"
SCHEME="MenubarTracert"
PROJECT_DIR="$(cd "$(dirname "$0")/../MenubarTracert" && pwd)"
BUILD_DIR="/tmp/${APP_NAME}-build"
DMG_DIR="/tmp/${APP_NAME}-dmg"
VERSION=$(xcodebuild -project "$PROJECT_DIR/${APP_NAME}.xcodeproj" \
    -scheme "$SCHEME" -showBuildSettings 2>/dev/null | \
    grep MARKETING_VERSION | head -1 | awk '{print $3}')
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
OUTPUT_DIR="$(cd "$(dirname "$0")/.." && pwd)/dist"

echo "Building ${APP_NAME} v${VERSION}..."

# Clean build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

# Archive
echo "Archiving..."
xcodebuild archive \
    -project "$PROJECT_DIR/${APP_NAME}.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$BUILD_DIR/${APP_NAME}.xcarchive" \
    CODE_SIGN_STYLE=Manual \
    2>&1 | tail -3

# Export archive
echo "Exporting..."
cat > "$BUILD_DIR/export-options.plist" << 'EXPORTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
</dict>
</plist>
EXPORTEOF

xcodebuild -exportArchive \
    -archivePath "$BUILD_DIR/${APP_NAME}.xcarchive" \
    -exportOptionsPlist "$BUILD_DIR/export-options.plist" \
    -exportPath "$BUILD_DIR/export" \
    2>&1 | tail -3

APP_PATH="$BUILD_DIR/export/${APP_NAME}.app"

# Notarize (requires APPLE_ID and TEAM_ID env vars, or stored keychain profile)
if [ "${SKIP_NOTARIZE:-}" != "1" ]; then
    echo "Notarizing..."
    xcrun notarytool submit "$APP_PATH" \
        --keychain-profile "notarytool-profile" \
        --wait
    echo "Stapling..."
    xcrun stapler staple "$APP_PATH"
fi

# Create DMG
echo "Creating DMG..."
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"
cp -R "$APP_PATH" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "$OUTPUT_DIR/$DMG_NAME"

rm -rf "$DMG_DIR"

echo ""
echo "Done: $OUTPUT_DIR/$DMG_NAME"
echo ""
echo "To set up notarization credentials (one-time):"
echo "  xcrun notarytool store-credentials notarytool-profile"
echo ""
echo "To skip notarization: SKIP_NOTARIZE=1 $0"
```

**Step 2: Make executable**

```bash
chmod +x scripts/create-dmg.sh
```

**Step 3: Add dist/ to .gitignore**

Append to `.gitignore`:

```
dist/
```

**Step 4: Commit**

```bash
git add scripts/create-dmg.sh .gitignore
git commit -m "feat: add DMG build and notarization script"
```

---

### Task 10: Add GitHub Actions CI

**Files:**
- Create: `.github/workflows/build.yml`

**Step 1: Write the CI workflow**

Create `.github/workflows/build.yml`:

```yaml
name: Build

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.app

      - name: Build Debug
        run: |
          xcodebuild build \
            -project MenubarTracert/MenubarTracert.xcodeproj \
            -scheme MenubarTracert \
            -configuration Debug \
            CODE_SIGN_IDENTITY="-" \
            CODE_SIGNING_ALLOWED=NO

      - name: Build Release
        run: |
          xcodebuild build \
            -project MenubarTracert/MenubarTracert.xcodeproj \
            -scheme MenubarTracert \
            -configuration Release \
            CODE_SIGN_IDENTITY="-" \
            CODE_SIGNING_ALLOWED=NO
```

**Step 2: Commit**

```bash
mkdir -p .github/workflows
git add .github/workflows/build.yml
git commit -m "ci: add GitHub Actions build workflow"
```

---

### Task 11: Final Build Verification

**Goal:** End-to-end verification that everything works together.

**Step 1: Clean build from scratch**

```bash
cd MenubarTracert
xcodebuild clean build \
    -project MenubarTracert.xcodeproj \
    -scheme MenubarTracert \
    -configuration Release \
    2>&1 | tail -10
```

Expected: BUILD SUCCEEDED

**Step 2: Verify app sandbox is active**

```bash
codesign -d --entitlements :- /tmp/MenubarTracert-build/Build/Products/Release/MenubarTracert.app 2>&1 | grep sandbox
```

Expected: Shows `com.apple.security.app-sandbox` = true

**Step 3: Run the app and verify traceroute works**

Manual verification:
- Launch from /Applications
- Panel opens showing traceroute hops
- Latency values appear in menubar
- Settings panel shows version 1.0.0

**Step 4: Verify no XPC remnants**

```bash
# Should find no references to TracertHelper, HelperManager, HelperXPCClient, or ProbeResultXPC
grep -r "TracertHelper\|HelperManager\|HelperXPCClient\|ProbeResultXPC\|SOCK_RAW" \
    MenubarTracert/MenubarTracert/ --include="*.swift" || echo "Clean - no XPC remnants"
```

**Step 5: Commit any final fixes**

If any issues found, fix and commit with appropriate message.

---

## Task Dependencies

```
Task 1 (PoC) ──── GATE ────┐
                            ▼
                    Task 2 (Engine rewrite)
                            │
                            ▼
                    Task 3 (Rewire ViewModel)
                            │
                            ▼
                    Task 4 (Remove XPC)
                            │
                    ┌───────┼───────┐
                    ▼       ▼       ▼
            Task 5      Task 6   Task 7
          (Sandbox)   (Settings) (Version)
                    │       │       │
                    └───────┼───────┘
                            ▼
                        Task 8 (Icon)
                    ┌───────┼───────┐
                    ▼               ▼
                Task 9          Task 10
              (DMG script)    (GitHub CI)
                    └───────┬───────┘
                            ▼
                    Task 11 (Final verify)
```

Tasks 5, 6, 7 can run in parallel after Task 4.
Tasks 9 and 10 can run in parallel after Task 8.
