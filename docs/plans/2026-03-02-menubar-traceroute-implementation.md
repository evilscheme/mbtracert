# MenubarTracert Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a macOS menubar app that continuously runs ICMP traceroute probes and displays results as a sparkline indicator (idle) and heatmap visualization (active).

**Architecture:** SwiftUI menubar-only app + privileged XPC helper daemon for raw ICMP sockets. The app uses `MenuBarExtra` with `.window` style for the dropdown panel, and `SMAppService.daemon()` for helper installation.

**Tech Stack:** Swift 5.9+, SwiftUI, macOS 14+ (Sonoma), POSIX sockets (ICMP), XPC/NSXPCConnection, ServiceManagement framework

---

### Task 1: Xcode Project Setup (User Task)

**This task is performed by the user in Xcode, not by Claude.**

The user should create the Xcode project with two targets and configure build settings:

**Step 1: Create the main app**

- File > New > Project > macOS > App
- Product Name: `MenubarTracert`
- Bundle Identifier: `com.mbtracert.MenubarTracert`
- Interface: SwiftUI
- Language: Swift
- Deployment Target: macOS 14.0

**Step 2: Create the helper target**

- File > New > Target > macOS > Command Line Tool
- Product Name: `TracertHelper`
- Bundle Identifier: `com.mbtracert.MenubarTracert.TracertHelper`
- Language: Swift

**Step 3: Configure the main app target**

- Target > Info > Custom macOS Application Target Properties:
  - Add `Application is agent (UIElement)` = `YES`
- Target > Signing & Capabilities:
  - Enable Hardened Runtime
  - Add App Sandbox capability
  - Check "Outgoing Connections (Client)" under Network
- Target > Build Phases > Dependencies:
  - Add `TracertHelper`
- Target > Build Phases > + New Copy Files Phase:
  - Destination: "Wrapper"
  - Subpath: `Contents/Library/LaunchDaemons`
  - Add file: `com.mbtracert.MenubarTracert.TracertHelper.plist` (created in Task 2)
- Target > Build Phases > + New Copy Files Phase:
  - Destination: "Executables"
  - Add product: `TracertHelper`
- Target > Frameworks, Libraries: Add `ServiceManagement.framework`

**Step 4: Configure the helper target**

- Target > Signing & Capabilities:
  - Enable Hardened Runtime
  - Same Team as main app
- Target > Build Settings:
  - `SKIP_INSTALL = YES`

**Step 5: Verify the project structure**

After setup, the Xcode project should have:
```
MenubarTracert/
  MenubarTracert/           (main app source)
    MenubarTracertApp.swift
    ContentView.swift       (can delete)
    Assets.xcassets
  TracertHelper/            (helper source)
    main.swift
  Shared/                   (create this group, add to both targets)
  MenubarTracert.xcodeproj
```

**Step 6: Commit the initial Xcode project**

```bash
git add -A
git commit -m "feat: initialize Xcode project with app and helper targets"
```

---

### Task 2: Launchd Plist for Helper Daemon

**Files:**
- Create: `MenubarTracert/com.mbtracert.MenubarTracert.TracertHelper.plist`

**Step 1: Create the launchd plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.mbtracert.MenubarTracert.TracertHelper</string>
    <key>MachServices</key>
    <dict>
        <key>com.mbtracert.MenubarTracert.TracertHelper</key>
        <true/>
    </dict>
    <key>BundleProgram</key>
    <string>MacOS/TracertHelper</string>
    <key>AssociatedBundleIdentifiers</key>
    <array>
        <string>com.mbtracert.MenubarTracert</string>
    </array>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
```

This file must be added to the main app target's "Copy Files" build phase (Destination: Wrapper, Subpath: `Contents/Library/LaunchDaemons`) as described in Task 1.

**Step 2: Commit**

```bash
git add MenubarTracert/com.mbtracert.MenubarTracert.TracertHelper.plist
git commit -m "feat: add launchd plist for privileged helper daemon"
```

---

### Task 3: Shared XPC Protocol

**Files:**
- Create: `Shared/TracertHelperProtocol.swift` (add to BOTH targets)

**Step 1: Write the XPC protocol**

This defines the contract between the main app and the helper. Must use `@objc` and `NSSecureCoding` for XPC serialization.

```swift
import Foundation

// MARK: - XPC Data Transfer Object

@objc public class ProbeResultXPC: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    @objc public let hop: Int
    @objc public let address: String   // "" if timeout
    @objc public let latencyMs: Double // -1 if timeout
    @objc public let timestamp: Double // CFAbsoluteTimeGetCurrent()

    public init(hop: Int, address: String, latencyMs: Double, timestamp: Double) {
        self.hop = hop
        self.address = address
        self.latencyMs = latencyMs
        self.timestamp = timestamp
    }

    public func encode(with coder: NSCoder) {
        coder.encode(hop, forKey: "hop")
        coder.encode(address, forKey: "address")
        coder.encode(latencyMs, forKey: "latencyMs")
        coder.encode(timestamp, forKey: "timestamp")
    }

    public required init?(coder: NSCoder) {
        self.hop = coder.decodeInteger(forKey: "hop")
        self.address = (coder.decodeObject(of: NSString.self, forKey: "address") as? String) ?? ""
        self.latencyMs = coder.decodeDouble(forKey: "latencyMs")
        self.timestamp = coder.decodeDouble(forKey: "timestamp")
        super.init()
    }
}

// MARK: - XPC Protocol

@objc public protocol TracertHelperProtocol {
    /// Run a single probe round: sends ICMP echo requests with TTL 1..maxHops.
    /// Calls reply once per hop, then once with hop=-1 to signal completion.
    func probeRound(
        host: String,
        maxHops: Int,
        withReply reply: @escaping (ProbeResultXPC) -> Void
    )

    /// Health check
    func ping(withReply reply: @escaping (String) -> Void)
}
```

**Step 2: Verify target membership**

In Xcode, select `TracertHelperProtocol.swift` > File Inspector > Target Membership: check both `MenubarTracert` AND `TracertHelper`.

**Step 3: Commit**

```bash
git add Shared/TracertHelperProtocol.swift
git commit -m "feat: add shared XPC protocol between app and helper"
```

---

### Task 4: ICMP Traceroute Engine

**Files:**
- Create: `TracertHelper/ICMPEngine.swift` (helper target only)

**Step 1: Write the ICMP engine**

This is the core networking code that creates raw ICMP sockets, sends echo requests with incrementing TTL, and parses responses. It runs inside the privileged helper (as root).

```swift
import Foundation
import Darwin

struct HopResult {
    let hop: Int
    let address: String   // "" if timeout
    let latencyMs: Double // -1 if timeout
}

final class ICMPEngine {
    private let identifier: UInt16

    init() {
        self.identifier = UInt16(getpid() & 0xFFFF)
    }

    /// Run one probe round: send echo requests with TTL 1..maxHops, collect responses.
    func probeRound(host: String, maxHops: Int, timeout: TimeInterval = 2.0) -> [HopResult] {
        // Create raw ICMP socket
        let sock = socket(AF_INET, SOCK_RAW, IPPROTO_ICMP)
        guard sock >= 0 else {
            return (1...maxHops).map { HopResult(hop: $0, address: "", latencyMs: -1) }
        }
        defer { close(sock) }

        // Set receive timeout
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // Resolve target
        guard var destAddr = resolveHost(host) else {
            return (1...maxHops).map { HopResult(hop: $0, address: "", latencyMs: -1) }
        }
        let destIP = ipString(from: destAddr)

        var results: [HopResult] = []

        for hop in 1...maxHops {
            // Set TTL
            var ttl = Int32(hop)
            setsockopt(sock, IPPROTO_IP, IP_TTL, &ttl, socklen_t(MemoryLayout<Int32>.size))

            // Build and send probe
            let seq = UInt16(hop)
            let packet = buildPacket(sequence: seq)
            let sendTime = mach_absolute_time()

            let sent = packet.withUnsafeBytes { buf in
                withUnsafeMutablePointer(to: &destAddr) { addrPtr in
                    addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        sendto(sock, buf.baseAddress, packet.count, 0, sa,
                               socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }

            guard sent >= 0 else {
                results.append(HopResult(hop: hop, address: "", latencyMs: -1))
                continue
            }

            // Receive response
            let response = receiveResponse(socket: sock, expectedSeq: seq, sendTime: sendTime)
            results.append(HopResult(hop: hop, address: response.address, latencyMs: response.latencyMs))

            // Stop if we reached the destination
            if response.address == destIP {
                break
            }
        }

        return results
    }

    // MARK: - Packet Construction

    private func buildPacket(sequence: UInt16) -> Data {
        var packet = Data(count: 16) // 8 header + 8 payload

        packet[0] = 8  // Type: Echo Request
        packet[1] = 0  // Code
        // [2..3] checksum (fill later)
        packet[4] = UInt8(identifier >> 8)
        packet[5] = UInt8(identifier & 0xFF)
        packet[6] = UInt8(sequence >> 8)
        packet[7] = UInt8(sequence & 0xFF)

        // Payload: mach_absolute_time for RTT
        var ts = mach_absolute_time()
        withUnsafeBytes(of: &ts) { tsBytes in
            for i in 0..<8 { packet[8 + i] = tsBytes[i] }
        }

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

    // MARK: - Response Parsing

    private struct Response {
        let address: String
        let latencyMs: Double
    }

    private func receiveResponse(socket sock: Int32, expectedSeq: UInt16, sendTime: UInt64) -> Response {
        var buffer = [UInt8](repeating: 0, count: 4096)
        var sender = sockaddr_in()
        var senderLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        // Retry loop to skip unrelated ICMP packets
        for _ in 0..<10 {
            let bytesRead = withUnsafeMutablePointer(to: &sender) { senderPtr in
                senderPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(sock, &buffer, buffer.count, 0, sa, &senderLen)
                }
            }
            let recvTime = mach_absolute_time()

            guard bytesRead > 0 else {
                return Response(address: "", latencyMs: -1) // Timeout
            }

            let data = Data(bytes: buffer, count: bytesRead)
            let senderIP = ipString(from: sender)
            let ipHdrLen = Int(data[0] & 0x0F) * 4
            guard data.count >= ipHdrLen + 8 else { continue }

            let icmpType = data[ipHdrLen]

            if icmpType == 0 { // Echo Reply
                let id = UInt16(data[ipHdrLen + 4]) << 8 | UInt16(data[ipHdrLen + 5])
                let seq = UInt16(data[ipHdrLen + 6]) << 8 | UInt16(data[ipHdrLen + 7])
                if id == identifier && seq == expectedSeq {
                    return Response(address: senderIP, latencyMs: machDiffMs(sendTime, recvTime))
                }
            } else if icmpType == 11 { // Time Exceeded
                let innerIPOffset = ipHdrLen + 8
                guard data.count >= innerIPOffset + 20 else { continue }
                let innerIPHdrLen = Int(data[innerIPOffset] & 0x0F) * 4
                let innerICMPOff = innerIPOffset + innerIPHdrLen
                guard data.count >= innerICMPOff + 8 else { continue }

                let innerID = UInt16(data[innerICMPOff + 4]) << 8 | UInt16(data[innerICMPOff + 5])
                let innerSeq = UInt16(data[innerICMPOff + 6]) << 8 | UInt16(data[innerICMPOff + 7])
                if innerID == identifier && innerSeq == expectedSeq {
                    return Response(address: senderIP, latencyMs: machDiffMs(sendTime, recvTime))
                }
            }
        }
        return Response(address: "", latencyMs: -1)
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
        var addr = addr
        return String(cString: inet_ntoa(addr.sin_addr))
    }

    private func machDiffMs(_ start: UInt64, _ end: UInt64) -> Double {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let nanos = Double(end - start) * Double(info.numer) / Double(info.denom)
        return nanos / 1_000_000.0 // nanoseconds to milliseconds
    }
}
```

**Step 2: Commit**

```bash
git add TracertHelper/ICMPEngine.swift
git commit -m "feat: add ICMP traceroute engine with raw socket probing"
```

---

### Task 5: Helper XPC Service and Main Entry Point

**Files:**
- Create: `TracertHelper/TracertHelperService.swift` (helper target only)
- Modify: `TracertHelper/main.swift`

**Step 1: Write the XPC service implementation**

```swift
import Foundation

final class TracertHelperService: NSObject, TracertHelperProtocol {
    private let engine = ICMPEngine()

    func probeRound(host: String, maxHops: Int, withReply reply: @escaping (ProbeResultXPC) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [engine] in
            let results = engine.probeRound(host: host, maxHops: maxHops)
            for result in results {
                reply(ProbeResultXPC(
                    hop: result.hop,
                    address: result.address,
                    latencyMs: result.latencyMs,
                    timestamp: CFAbsoluteTimeGetCurrent()
                ))
            }
            // Signal completion
            reply(ProbeResultXPC(hop: -1, address: "", latencyMs: -1, timestamp: CFAbsoluteTimeGetCurrent()))
        }
    }

    func ping(withReply reply: @escaping (String) -> Void) {
        reply("pong")
    }
}
```

**Step 2: Write the helper main.swift**

```swift
import Foundation

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        conn.exportedInterface = NSXPCInterface(with: TracertHelperProtocol.self)

        // Allow ProbeResultXPC in reply blocks
        let classes: Set<AnyHashable> = [ProbeResultXPC.self, NSString.self, NSNumber.self]
        conn.exportedInterface?.setClasses(
            classes,
            for: #selector(TracertHelperProtocol.probeRound(host:maxHops:withReply:)),
            argumentIndex: 0,
            ofReply: true
        )

        conn.exportedObject = TracertHelperService()
        conn.resume()
        return true
    }
}

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: "com.mbtracert.MenubarTracert.TracertHelper")
listener.delegate = delegate
listener.resume()

RunLoop.current.run()
```

**Step 3: Commit**

```bash
git add TracertHelper/TracertHelperService.swift TracertHelper/main.swift
git commit -m "feat: add helper XPC listener and service implementation"
```

---

### Task 6: Data Model (Ring Buffer, HopData)

**Files:**
- Create: `MenubarTracert/Models/RingBuffer.swift` (main app target)
- Create: `MenubarTracert/Models/TracerouteModels.swift` (main app target)

**Step 1: Write the ring buffer**

```swift
struct RingBuffer<T> {
    private var storage: [T?]
    private var writeIndex = 0
    private(set) var count = 0

    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }

    mutating func append(_ element: T) {
        storage[writeIndex] = element
        writeIndex = (writeIndex + 1) % capacity
        count = min(count + 1, capacity)
    }

    /// Returns elements in chronological order (oldest first).
    var elements: [T] {
        if count < capacity {
            return storage[0..<count].compactMap { $0 }
        }
        let tail = storage[writeIndex..<capacity].compactMap { $0 }
        let head = storage[0..<writeIndex].compactMap { $0 }
        return tail + head
    }

    mutating func clear() {
        storage = Array(repeating: nil, count: capacity)
        writeIndex = 0
        count = 0
    }
}
```

**Step 2: Write the traceroute models**

```swift
import Foundation

struct ProbeResult: Identifiable {
    let id = UUID()
    let hop: Int
    let address: String       // "" if timeout
    let hostname: String?     // resolved DNS name
    let latencyMs: Double     // -1 if timeout
    let timestamp: Date

    var isTimeout: Bool { latencyMs < 0 }
}

struct HopData: Identifiable {
    let id: Int // hop number
    let hop: Int
    var address: String
    var hostname: String?
    var probes: RingBuffer<ProbeResult>

    var avgLatencyMs: Double {
        let valid = probes.elements.filter { !$0.isTimeout }
        guard !valid.isEmpty else { return -1 }
        return valid.reduce(0) { $0 + $1.latencyMs } / Double(valid.count)
    }

    var lossPercent: Double {
        guard probes.count > 0 else { return 0 }
        let timeouts = probes.elements.filter { $0.isTimeout }.count
        return Double(timeouts) / Double(probes.count) * 100
    }
}
```

**Step 3: Commit**

```bash
git add MenubarTracert/Models/
git commit -m "feat: add RingBuffer and traceroute data models"
```

---

### Task 7: XPC Client and Helper Manager

**Files:**
- Create: `MenubarTracert/Services/HelperXPCClient.swift` (main app target)
- Create: `MenubarTracert/Services/HelperManager.swift` (main app target)

**Step 1: Write the XPC client**

```swift
import Foundation

final class HelperXPCClient {
    static let machServiceName = "com.mbtracert.MenubarTracert.TracertHelper"

    private var connection: NSXPCConnection?

    func connect() -> TracertHelperProtocol? {
        if let conn = connection {
            return conn.remoteObjectProxyWithErrorHandler { error in
                print("XPC proxy error: \(error)")
            } as? TracertHelperProtocol
        }

        let conn = NSXPCConnection(machServiceName: Self.machServiceName, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: TracertHelperProtocol.self)

        let classes: Set<AnyHashable> = [ProbeResultXPC.self, NSString.self, NSNumber.self]
        conn.remoteObjectInterface?.setClasses(
            classes,
            for: #selector(TracertHelperProtocol.probeRound(host:maxHops:withReply:)),
            argumentIndex: 0,
            ofReply: true
        )

        conn.invalidationHandler = { [weak self] in
            self?.connection = nil
        }
        conn.interruptionHandler = { [weak self] in
            self?.connection = nil
        }

        conn.resume()
        self.connection = conn

        return conn.remoteObjectProxyWithErrorHandler { error in
            print("XPC proxy error: \(error)")
        } as? TracertHelperProtocol
    }

    func disconnect() {
        connection?.invalidate()
        connection = nil
    }
}
```

**Step 2: Write the helper manager**

```swift
import Foundation
import ServiceManagement

final class HelperManager {
    static let shared = HelperManager()

    private let service = SMAppService.daemon(
        plistName: "com.mbtracert.MenubarTracert.TracertHelper.plist"
    )

    var status: SMAppService.Status { service.status }

    var isInstalled: Bool {
        service.status == .enabled
    }

    func registerIfNeeded() throws {
        switch service.status {
        case .notRegistered, .notFound:
            try service.register()
        case .enabled:
            break
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
        @unknown default:
            break
        }
    }

    func unregister() throws {
        try service.unregister()
    }
}
```

**Step 3: Commit**

```bash
git add MenubarTracert/Services/
git commit -m "feat: add XPC client and helper manager with SMAppService"
```

---

### Task 8: TracerouteViewModel

**Files:**
- Create: `MenubarTracert/ViewModels/TracerouteViewModel.swift` (main app target)

**Step 1: Write the view model**

This is the central coordinator — manages probe scheduling, XPC communication, and all UI state.

```swift
import Foundation
import SwiftUI
import Combine

@MainActor
final class TracerouteViewModel: ObservableObject {
    // MARK: - Published State

    @Published var hops: [HopData] = []
    @Published var latencyHistory: [Double] = [] // for sparkline
    @Published var isProbing = false
    @Published var isPanelOpen = false
    @Published var helperInstalled = false
    @Published var errorMessage: String?

    // MARK: - Settings (backed by UserDefaults)

    @AppStorage("targetHost") var targetHost = "8.8.8.8"
    @AppStorage("idleProbeInterval") var idleInterval: Double = 5.0
    @AppStorage("activeProbeInterval") var activeInterval: Double = 1.0
    @AppStorage("historyMinutes") var historyMinutes: Double = 5.0
    @AppStorage("resolveHostnames") var resolveHostnames = true
    @AppStorage("maxHops") var maxHops = 30

    // MARK: - Private

    private let xpcClient = HelperXPCClient()
    private var probeTimer: Timer?
    private let sparklineCapacity = 60 // last ~60 data points for sparkline

    // MARK: - Lifecycle

    func start() {
        do {
            try HelperManager.shared.registerIfNeeded()
            helperInstalled = true
        } catch {
            helperInstalled = false
            errorMessage = "Helper installation failed: \(error.localizedDescription)"
            return
        }
        scheduleProbing()
    }

    func panelDidOpen() {
        isPanelOpen = true
        rescheduleProbing()
    }

    func panelDidClose() {
        isPanelOpen = false
        rescheduleProbing()
    }

    // MARK: - Probing

    private func scheduleProbing() {
        rescheduleProbing()
    }

    private func rescheduleProbing() {
        probeTimer?.invalidate()
        let interval = isPanelOpen ? activeInterval : idleInterval
        probeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.runProbeRound()
            }
        }
        // Fire immediately
        Task { await runProbeRound() }
    }

    private func runProbeRound() async {
        guard let proxy = xpcClient.connect() else {
            errorMessage = "Cannot connect to helper"
            return
        }

        isProbing = true
        errorMessage = nil

        let bufferCapacity = Int(historyMinutes * 60 / activeInterval)

        proxy.probeRound(host: targetHost, maxHops: maxHops) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if result.hop == -1 {
                    // Round complete
                    self.isProbing = false
                    return
                }

                let probe = ProbeResult(
                    hop: result.hop,
                    address: result.address,
                    hostname: self.resolveHostnames ? self.resolveHostname(result.address) : nil,
                    latencyMs: result.latencyMs,
                    timestamp: Date(timeIntervalSinceReferenceDate: result.timestamp)
                )

                // Update or create hop data
                if let idx = self.hops.firstIndex(where: { $0.hop == result.hop }) {
                    self.hops[idx].probes.append(probe)
                    if !result.address.isEmpty {
                        self.hops[idx].address = result.address
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

                // Update sparkline with overall RTT (last hop latency)
                if let lastHop = self.hops.last, lastHop.avgLatencyMs > 0 {
                    self.latencyHistory.append(lastHop.avgLatencyMs)
                    if self.latencyHistory.count > self.sparklineCapacity {
                        self.latencyHistory.removeFirst()
                    }
                }
            }
        }
    }

    private func resolveHostname(_ ip: String) -> String? {
        guard !ip.isEmpty else { return nil }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        inet_pton(AF_INET, ip, &addr.sin_addr)

        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                getnameinfo(sa, socklen_t(MemoryLayout<sockaddr_in>.size),
                           &hostname, socklen_t(hostname.count),
                           nil, 0, NI_NAMEREQD)
            }
        }
        return result == 0 ? String(cString: hostname) : nil
    }
}
```

**Step 2: Commit**

```bash
git add MenubarTracert/ViewModels/
git commit -m "feat: add TracerouteViewModel with adaptive probe scheduling"
```

---

### Task 9: Sparkline View (Menubar Icon)

**Files:**
- Create: `MenubarTracert/Views/SparklineView.swift` (main app target)

**Step 1: Write the sparkline renderer**

The sparkline renders as an NSImage so it works reliably in the menubar label area. It uses color (green/yellow/red) rather than `isTemplate` to convey latency status.

```swift
import SwiftUI
import AppKit

struct SparklineLabel: View {
    let dataPoints: [Double]

    var body: some View {
        Image(nsImage: renderSparkline())
    }

    private func renderSparkline() -> NSImage {
        let width: CGFloat = 32
        let height: CGFloat = 18
        let image = NSImage(size: NSSize(width: width, height: height))

        guard !dataPoints.isEmpty else {
            // Draw a flat gray line when no data
            image.lockFocus()
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.setStrokeColor(NSColor.secondaryLabelColor.cgColor)
                ctx.setLineWidth(1)
                ctx.move(to: CGPoint(x: 0, y: height / 2))
                ctx.addLine(to: CGPoint(x: width, y: height / 2))
                ctx.strokePath()
            }
            image.unlockFocus()
            return image
        }

        image.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }

        let maxVal = max(dataPoints.max() ?? 1, 10) // minimum 10ms scale
        let padding: CGFloat = 1

        // Draw sparkline segments with color based on latency
        for i in 0..<dataPoints.count {
            let x = padding + CGFloat(i) / CGFloat(max(dataPoints.count - 1, 1)) * (width - padding * 2)
            let y = padding + (1 - CGFloat(dataPoints[i]) / CGFloat(maxVal)) * (height - padding * 2)

            let color = colorForLatency(dataPoints[i])
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(1.5)

            if i == 0 {
                ctx.move(to: CGPoint(x: x, y: y))
            } else {
                ctx.addLine(to: CGPoint(x: x, y: y))
                ctx.strokePath()
                ctx.move(to: CGPoint(x: x, y: y))
            }
        }

        image.unlockFocus()
        return image
    }

    private func colorForLatency(_ ms: Double) -> NSColor {
        switch ms {
        case ..<20:  return .systemGreen
        case ..<50:  return .systemYellow
        case ..<100: return .systemOrange
        default:     return .systemRed
        }
    }
}
```

**Step 2: Commit**

```bash
git add MenubarTracert/Views/SparklineView.swift
git commit -m "feat: add menubar sparkline view with color-coded latency"
```

---

### Task 10: Heatmap Bar View

**Files:**
- Create: `MenubarTracert/Views/HeatmapBar.swift` (main app target)

**Step 1: Write the heatmap bar**

Each hop row has a horizontal bar of colored cells showing latency history.

```swift
import SwiftUI

struct HeatmapBar: View {
    let probes: [ProbeResult]

    var body: some View {
        Canvas { context, size in
            guard !probes.isEmpty else { return }
            let cellWidth = size.width / CGFloat(probes.count)

            for (i, probe) in probes.enumerated() {
                let rect = CGRect(
                    x: CGFloat(i) * cellWidth,
                    y: 0,
                    width: cellWidth + 0.5, // overlap to prevent gaps
                    height: size.height
                )
                let color = probe.isTimeout ? Color.black : colorForLatency(probe.latencyMs)
                context.fill(Path(rect), with: .color(color))
            }
        }
        .frame(height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }

    private func colorForLatency(_ ms: Double) -> Color {
        let normalized = min(ms / 100.0, 1.0) // 100ms = full red
        if normalized < 0.5 {
            return Color(red: normalized * 2, green: 1.0, blue: 0)
        } else {
            return Color(red: 1.0, green: 1.0 - (normalized - 0.5) * 2, blue: 0)
        }
    }
}
```

**Step 2: Commit**

```bash
git add MenubarTracert/Views/HeatmapBar.swift
git commit -m "feat: add heatmap bar view with green-yellow-red latency scale"
```

---

### Task 11: Hop Row View

**Files:**
- Create: `MenubarTracert/Views/HopRowView.swift` (main app target)

**Step 1: Write the hop row**

```swift
import SwiftUI

struct HopRowView: View {
    let hop: HopData

    var body: some View {
        HStack(spacing: 6) {
            Text("\(hop.hop)")
                .font(.system(.caption, design: .monospaced))
                .frame(width: 20, alignment: .trailing)
                .foregroundStyle(.secondary)

            Text(hop.hostname ?? hop.address)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 130, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(hop.address) // tooltip shows full IP

            Text(hop.avgLatencyMs > 0 ? String(format: "%.0fms", hop.avgLatencyMs) : "---")
                .font(.system(.caption, design: .monospaced))
                .frame(width: 38, alignment: .trailing)

            Text(String(format: "%.0f%%", hop.lossPercent))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(hop.lossPercent > 0 ? .red : .secondary)
                .frame(width: 28, alignment: .trailing)

            HeatmapBar(probes: hop.probes.elements)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
    }
}
```

**Step 2: Commit**

```bash
git add MenubarTracert/Views/HopRowView.swift
git commit -m "feat: add hop row view with stats and heatmap"
```

---

### Task 12: Traceroute Panel (Dropdown)

**Files:**
- Create: `MenubarTracert/Views/TraceroutePanel.swift` (main app target)

**Step 1: Write the panel view**

```swift
import SwiftUI

struct TraceroutePanel: View {
    @ObservedObject var viewModel: TracerouteViewModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.targetHost)
                        .font(.headline)
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Spacer()

                if viewModel.isProbing {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                }

                if let lastHop = viewModel.hops.last, lastHop.avgLatencyMs > 0 {
                    Text(String(format: "%.0fms", lastHop.avgLatencyMs))
                        .font(.system(.title3, design: .monospaced))
                        .foregroundStyle(lastHop.avgLatencyMs < 50 ? .green : .orange)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Column headers
            HStack(spacing: 6) {
                Text("#")
                    .frame(width: 20, alignment: .trailing)
                Text("Host")
                    .frame(width: 130, alignment: .leading)
                Text("Avg")
                    .frame(width: 38, alignment: .trailing)
                Text("Loss")
                    .frame(width: 28, alignment: .trailing)
                Text("History")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            // Hop rows
            if viewModel.hops.isEmpty && !viewModel.isProbing {
                Text(viewModel.helperInstalled ? "Waiting for first probe..." : "Helper not installed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.hops) { hop in
                            HopRowView(hop: hop)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }

            Divider()

            // Footer
            HStack {
                Button("Settings...") {
                    NSApp.activate()
                    openSettings()
                }
                .buttonStyle(.borderless)
                .font(.caption)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: 450)
    }
}
```

**Step 2: Commit**

```bash
git add MenubarTracert/Views/TraceroutePanel.swift
git commit -m "feat: add traceroute panel dropdown with hop list and header"
```

---

### Task 13: Settings View

**Files:**
- Create: `MenubarTracert/Views/SettingsView.swift` (main app target)

**Step 1: Write the settings view**

```swift
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var viewModel: TracerouteViewModel

    var body: some View {
        TabView {
            GeneralTab(viewModel: viewModel)
                .tabItem { Label("General", systemImage: "gear") }

            NetworkTab(viewModel: viewModel)
                .tabItem { Label("Network", systemImage: "network") }
        }
        .frame(width: 420, height: 260)
    }
}

private struct GeneralTab: View {
    @ObservedObject var viewModel: TracerouteViewModel
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Form {
            TextField("Target Host:", text: $viewModel.targetHost)

            Toggle("Resolve DNS Names", isOn: $viewModel.resolveHostnames)

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
        .formStyle(.grouped)
        .padding()
    }
}

private struct NetworkTab: View {
    @ObservedObject var viewModel: TracerouteViewModel

    var body: some View {
        Form {
            LabeledContent("Idle Probe Interval") {
                HStack {
                    Slider(value: $viewModel.idleInterval, in: 2...30, step: 1)
                    Text("\(Int(viewModel.idleInterval))s")
                        .monospacedDigit()
                        .frame(width: 30)
                }
            }

            LabeledContent("Active Probe Interval") {
                HStack {
                    Slider(value: $viewModel.activeInterval, in: 0.5...5, step: 0.5)
                    Text(String(format: "%.1fs", viewModel.activeInterval))
                        .monospacedDigit()
                        .frame(width: 30)
                }
            }

            LabeledContent("History Window") {
                HStack {
                    Slider(value: $viewModel.historyMinutes, in: 2...15, step: 1)
                    Text("\(Int(viewModel.historyMinutes))m")
                        .monospacedDigit()
                        .frame(width: 30)
                }
            }

            LabeledContent("Max Hops") {
                HStack {
                    Slider(value: Binding(
                        get: { Double(viewModel.maxHops) },
                        set: { viewModel.maxHops = Int($0) }
                    ), in: 10...64, step: 1)
                    Text("\(viewModel.maxHops)")
                        .monospacedDigit()
                        .frame(width: 30)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
```

**Step 2: Commit**

```bash
git add MenubarTracert/Views/SettingsView.swift
git commit -m "feat: add settings view with general and network tabs"
```

---

### Task 14: App Entry Point

**Files:**
- Modify: `MenubarTracert/MenubarTracertApp.swift`

**Step 1: Write the app entry point**

```swift
import SwiftUI

@main
struct MenubarTracertApp: App {
    @StateObject private var viewModel = TracerouteViewModel()

    var body: some Scene {
        MenuBarExtra {
            TraceroutePanel(viewModel: viewModel)
                .onAppear { viewModel.panelDidOpen() }
                .onDisappear { viewModel.panelDidClose() }
        } label: {
            SparklineLabel(dataPoints: viewModel.latencyHistory)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(viewModel: viewModel)
        }
    }

    init() {
        // Kick off helper registration and probing when app launches
        // (deferred to onAppear of first view since @StateObject isn't ready in init)
    }
}
```

Note: The viewModel's `start()` method should be called on first appearance. Add `.task { viewModel.start() }` to the TraceroutePanel or use an `.onAppear` on the `MenuBarExtra` label.

Update the SparklineLabel to trigger start:

```swift
SparklineLabel(dataPoints: viewModel.latencyHistory)
    .task { viewModel.start() }
```

**Step 2: Delete the default ContentView.swift** if it exists — it's not needed.

**Step 3: Commit**

```bash
git add MenubarTracert/MenubarTracertApp.swift
git rm MenubarTracert/ContentView.swift 2>/dev/null || true
git commit -m "feat: add app entry point with MenuBarExtra and Settings"
```

---

### Task 15: Build and Test

**Step 1: Build in Xcode**

- Select the `MenubarTracert` scheme
- Build (Cmd+B) and fix any compilation errors
- Common issues to watch for:
  - Target membership: ensure `TracertHelperProtocol.swift` is in both targets
  - Missing imports
  - The helper target links correctly

**Step 2: Test helper in isolation**

```bash
# Build the helper
xcodebuild -target TracertHelper -configuration Debug

# Test ICMP directly (needs root)
sudo ./build/Debug/TracertHelper
# In another terminal, check it responds to XPC
```

**Step 3: Test the full app**

- Run MenubarTracert from Xcode
- It should prompt for admin credentials to install the helper
- The sparkline should appear in the menubar
- Click to open the dropdown panel
- Verify hops populate with latency data and heatmap

**Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: resolve build issues and verify end-to-end functionality"
```

---

## File Tree Summary

```
MenubarTracert/
├── MenubarTracert/
│   ├── MenubarTracertApp.swift          (Task 14)
│   ├── Models/
│   │   ├── RingBuffer.swift             (Task 6)
│   │   └── TracerouteModels.swift       (Task 6)
│   ├── Services/
│   │   ├── HelperXPCClient.swift        (Task 7)
│   │   └── HelperManager.swift          (Task 7)
│   ├── ViewModels/
│   │   └── TracerouteViewModel.swift    (Task 8)
│   ├── Views/
│   │   ├── SparklineView.swift          (Task 9)
│   │   ├── HeatmapBar.swift             (Task 10)
│   │   ├── HopRowView.swift             (Task 11)
│   │   ├── TraceroutePanel.swift        (Task 12)
│   │   └── SettingsView.swift           (Task 13)
│   └── Assets.xcassets
├── TracertHelper/
│   ├── main.swift                       (Task 5)
│   ├── TracertHelperService.swift       (Task 5)
│   └── ICMPEngine.swift                 (Task 4)
├── Shared/
│   └── TracertHelperProtocol.swift      (Task 3)
├── com.mbtracert.MenubarTracert.TracertHelper.plist  (Task 2)
├── docs/plans/
│   ├── 2026-03-02-menubar-traceroute-design.md
│   └── 2026-03-02-menubar-traceroute-implementation.md
└── MenubarTracert.xcodeproj             (Task 1, user creates)
```
