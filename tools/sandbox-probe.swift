/// sandbox-probe: SOCK_DGRAM ICMP proof-of-concept
///
/// Validates that unprivileged ICMP sockets work with TTL control
/// and can receive both Time Exceeded and Echo Reply responses.
/// Tests with and without App Sandbox.
///
/// Build & run (no sandbox):
///   cd tools
///   swiftc -o /tmp/sandbox-probe sandbox-probe.swift
///   /tmp/sandbox-probe
///
/// Build & run (with sandbox):
///   cd tools
///   swiftc -o /tmp/sandbox-probe sandbox-probe.swift \
///     -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist \
///     -Xlinker /dev/stdin <<< \
///     '<?xml version="1.0" encoding="UTF-8"?>
///     <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
///       "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
///     <plist version="1.0"><dict>
///       <key>CFBundleIdentifier</key>
///       <string>org.evilscheme.sandbox-probe</string>
///     </dict></plist>'
///   codesign --force --sign - --entitlements sandbox-probe.entitlements /tmp/sandbox-probe
///   /tmp/sandbox-probe
///
/// Note: App Sandbox requires an embedded Info.plist with CFBundleIdentifier
/// in the binary.  Without it, libsecinit crashes at startup (SIGTRAP).

import Foundation
import Darwin

// MARK: - Constants

/// macOS setsockopt option to strip IP header from received packets on ICMP
/// DGRAM sockets.  Without this, received packets include the IP header
/// (ICMP type is at buffer[ipHdrLen], not buffer[0]).  With this enabled,
/// the kernel strips the IP header so ICMP type is at buffer[0].
/// Value 23 is IP_STRIPHDR from <netinet/in.h> (not exposed to Swift).
let IP_STRIPHDR: Int32 = 23

// MARK: - Helpers

func pass(_ step: Int, _ msg: String) {
    print("  Step \(step): PASS - \(msg)")
}

func fail(_ step: Int, _ msg: String) {
    print("  Step \(step): FAIL - \(msg)")
}

func ipString(from addr: sockaddr_in) -> String {
    var mutable = addr
    return withUnsafePointer(to: &mutable.sin_addr) { ptr in
        String(cString: inet_ntoa(ptr.pointee))
    }
}

func machDiffMs(_ start: UInt64, _ end: UInt64) -> Double {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    let nanos = Double(end - start) * Double(info.numer) / Double(info.denom)
    return nanos / 1_000_000.0
}

/// Build an ICMP Echo Request packet (8-byte header + 8-byte timestamp payload).
func buildEchoRequest(identifier: UInt16, sequence: UInt16) -> Data {
    var packet = Data(count: 16)

    packet[0] = 8  // Type: Echo Request
    packet[1] = 0  // Code
    // Checksum at [2..3] — filled below
    packet[4] = UInt8(identifier >> 8)
    packet[5] = UInt8(identifier & 0xFF)
    packet[6] = UInt8(sequence >> 8)
    packet[7] = UInt8(sequence & 0xFF)

    // Payload: mach_absolute_time timestamp
    var ts = mach_absolute_time()
    withUnsafeBytes(of: &ts) { tsBytes in
        for i in 0..<8 { packet[8 + i] = tsBytes[i] }
    }

    // Checksum (kernel may recompute for SOCK_DGRAM, but we set it for correctness)
    var sum: UInt32 = 0
    var i = 0
    while i < packet.count - 1 {
        sum += UInt32(packet[i]) << 8 | UInt32(packet[i + 1])
        i += 2
    }
    if packet.count % 2 != 0 {
        sum += UInt32(packet[packet.count - 1]) << 8
    }
    while sum >> 16 != 0 {
        sum = (sum & 0xFFFF) + (sum >> 16)
    }
    let cksum = ~UInt16(sum & 0xFFFF)
    packet[2] = UInt8(cksum >> 8)
    packet[3] = UInt8(cksum & 0xFF)

    return packet
}

// MARK: - Detect Sandbox

func isSandboxed() -> Bool {
    let env = ProcessInfo.processInfo.environment
    if env["APP_SANDBOX_CONTAINER_ID"] != nil { return true }
    return false
}

// MARK: - Main

let target = "8.8.8.8"
let identifier = UInt16(getpid() & 0xFFFF)

print("=== SOCK_DGRAM ICMP Proof-of-Concept ===")
print("Target: \(target)")
print("PID: \(getpid()), Identifier: \(identifier)")
print("Sandboxed: \(isSandboxed() ? "YES" : "NO (or unable to detect)")")
print()

// Resolve target
var destAddr = sockaddr_in()
destAddr.sin_family = sa_family_t(AF_INET)
inet_pton(AF_INET, target, &destAddr.sin_addr)

// ── Step 1: Create SOCK_DGRAM ICMP socket ──────────────────────────

let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
if fd >= 0 {
    pass(1, "socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP) returned fd=\(fd)")
} else {
    fail(1, "socket() failed: \(String(cString: strerror(errno))) (errno=\(errno))")
    print("\nCannot continue without a socket. Exiting.")
    exit(1)
}

// Enable IP_STRIPHDR so the kernel strips the IP header from received
// packets.  With this option, ICMP type is at buffer[0] (not behind an
// IP header), and Time Exceeded messages are reliably delivered.
var stripHdr: Int32 = 1
let stripResult = setsockopt(fd, IPPROTO_IP, IP_STRIPHDR, &stripHdr,
                              socklen_t(MemoryLayout<Int32>.size))
if stripResult == 0 {
    print("  (IP_STRIPHDR enabled)")
} else {
    print("  (IP_STRIPHDR failed, errno=\(errno) — will parse with IP header)")
}
print()

// ── Step 2: Set TTL via setsockopt ─────────────────────────────────

var ttl: Int32 = 3
let optResult = setsockopt(fd, IPPROTO_IP, IP_TTL, &ttl, socklen_t(MemoryLayout<Int32>.size))
if optResult == 0 {
    // Verify by reading it back
    var readTTL: Int32 = 0
    var readLen = socklen_t(MemoryLayout<Int32>.size)
    getsockopt(fd, IPPROTO_IP, IP_TTL, &readTTL, &readLen)
    pass(2, "setsockopt(IP_TTL, 3) succeeded, readback=\(readTTL)")
} else {
    fail(2, "setsockopt(IP_TTL) failed: \(String(cString: strerror(errno))) (errno=\(errno))")
}

// ── Step 3: Send ICMP Echo Request with TTL=3 ──────────────────────

let packet3 = buildEchoRequest(identifier: identifier, sequence: 1)
let sendTime3 = mach_absolute_time()
let sendResult3 = packet3.withUnsafeBytes { buf in
    withUnsafeMutablePointer(to: &destAddr) { addrPtr in
        addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            sendto(fd, buf.baseAddress, packet3.count, 0, sa,
                   socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
}

if sendResult3 == packet3.count {
    pass(3, "sendto() sent \(sendResult3) bytes with TTL=3")
} else if sendResult3 >= 0 {
    fail(3, "sendto() partial: sent \(sendResult3) of \(packet3.count) bytes")
} else {
    fail(3, "sendto() failed: \(String(cString: strerror(errno))) (errno=\(errno))")
}

// ── Step 4: Receive ICMP Time Exceeded ─────────────────────────────

// Set receive timeout
var tv = timeval(tv_sec: 3, tv_usec: 0)
setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

var step4Passed = false
var step4RouterIP = ""

// May need multiple reads — kernel might deliver other ICMP messages
for _ in 0..<10 {
    var buffer = [UInt8](repeating: 0, count: 4096)
    var sender = sockaddr_in()
    var senderLen = socklen_t(MemoryLayout<sockaddr_in>.size)

    let bytesRead = withUnsafeMutablePointer(to: &sender) { senderPtr in
        senderPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            recvfrom(fd, &buffer, buffer.count, 0, sa, &senderLen)
        }
    }
    let recvTime = mach_absolute_time()

    guard bytesRead > 0 else {
        fail(4, "recvfrom() timed out or failed: \(String(cString: strerror(errno)))")
        break
    }

    // With IP_STRIPHDR the kernel strips the outer IP header.
    // ICMP type is at buffer[0].
    let icmpType = buffer[0]
    let icmpCode = buffer[1]
    let senderIP = ipString(from: sender)
    let latency = machDiffMs(sendTime3, recvTime)

    if icmpType == 11 { // Time Exceeded
        // Layout: ICMP header (8 bytes) | embedded orig IP header | embedded orig ICMP
        if bytesRead >= 36 { // 8 + 20 + 8 minimum
            let innerIPHdrLen = Int(buffer[8] & 0x0F) * 4
            let innerICMPOff = 8 + innerIPHdrLen
            if bytesRead >= innerICMPOff + 8 {
                let innerType = buffer[innerICMPOff]
                let innerID = UInt16(buffer[innerICMPOff + 4]) << 8
                             | UInt16(buffer[innerICMPOff + 5])
                let innerSeq = UInt16(buffer[innerICMPOff + 6]) << 8
                              | UInt16(buffer[innerICMPOff + 7])
                pass(4, "Time Exceeded from \(senderIP) (type=\(icmpType), code=\(icmpCode)), "
                     + "latency=\(String(format: "%.1f", latency))ms, "
                     + "inner: type=\(innerType) id=\(innerID) seq=\(innerSeq)")
            } else {
                pass(4, "Time Exceeded from \(senderIP) (type=\(icmpType), code=\(icmpCode)), "
                     + "latency=\(String(format: "%.1f", latency))ms")
            }
        } else {
            pass(4, "Time Exceeded from \(senderIP) (type=\(icmpType)), "
                 + "latency=\(String(format: "%.1f", latency))ms "
                 + "(\(bytesRead) bytes)")
        }
        step4Passed = true
        step4RouterIP = senderIP
        break
    } else if icmpType == 0 {
        // Echo Reply — unexpected with TTL=3 unless target is very close
        print("  Step 4: INFO - Got Echo Reply from \(senderIP) instead of Time Exceeded")
        print("           (target may be <= 3 hops away; this is still a valid response)")
        step4Passed = true
        step4RouterIP = senderIP
        break
    } else if icmpType == 3 {
        print("  Step 4: INFO - Got Dest Unreachable (code=\(icmpCode)) from \(senderIP)")
        step4Passed = true
        step4RouterIP = senderIP
        break
    } else {
        print("  Step 4: INFO - Ignoring ICMP type=\(icmpType) from \(senderIP), retrying...")
        continue
    }
}

if !step4Passed {
    fail(4, "No Time Exceeded response received within timeout")
}

// ── Step 5: Send with TTL=64 and receive Echo Reply ────────────────

var ttl64: Int32 = 64
setsockopt(fd, IPPROTO_IP, IP_TTL, &ttl64, socklen_t(MemoryLayout<Int32>.size))

let packet5 = buildEchoRequest(identifier: identifier, sequence: 2)
let sendTime5 = mach_absolute_time()
let sendResult5 = packet5.withUnsafeBytes { buf in
    withUnsafeMutablePointer(to: &destAddr) { addrPtr in
        addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            sendto(fd, buf.baseAddress, packet5.count, 0, sa,
                   socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
}

guard sendResult5 >= 0 else {
    fail(5, "sendto() with TTL=64 failed: \(String(cString: strerror(errno)))")
    close(fd)
    exit(1)
}

var step5Passed = false

for _ in 0..<10 {
    var buffer = [UInt8](repeating: 0, count: 4096)
    var sender = sockaddr_in()
    var senderLen = socklen_t(MemoryLayout<sockaddr_in>.size)

    let bytesRead = withUnsafeMutablePointer(to: &sender) { senderPtr in
        senderPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            recvfrom(fd, &buffer, buffer.count, 0, sa, &senderLen)
        }
    }
    let recvTime = mach_absolute_time()

    guard bytesRead > 0 else {
        fail(5, "recvfrom() timed out or failed: \(String(cString: strerror(errno)))")
        break
    }

    let icmpType = buffer[0]
    let senderIP = ipString(from: sender)
    let latency = machDiffMs(sendTime5, recvTime)

    if icmpType == 0 { // Echo Reply
        let replyID = UInt16(buffer[4]) << 8 | UInt16(buffer[5])
        let replySeq = UInt16(buffer[6]) << 8 | UInt16(buffer[7])
        pass(5, "Echo Reply from \(senderIP), latency=\(String(format: "%.1f", latency))ms, "
             + "id=\(replyID) seq=\(replySeq), \(bytesRead) bytes")
        step5Passed = true
        break
    } else {
        print("  Step 5: INFO - Ignoring ICMP type=\(icmpType) from \(senderIP), "
              + "waiting for Echo Reply...")
        continue
    }
}

if !step5Passed {
    fail(5, "No Echo Reply received within timeout")
}

close(fd)

// ── Summary ────────────────────────────────────────────────────────

print()
let allPassed = step4Passed && step5Passed
if allPassed {
    print("=== ALL STEPS PASSED ===")
    print("SOCK_DGRAM + IPPROTO_ICMP works for traceroute.")
    if !step4RouterIP.isEmpty {
        print("Intermediate router at TTL=3: \(step4RouterIP)")
    }
} else {
    print("=== SOME STEPS FAILED ===")
    print("Review output above for details.")
}
