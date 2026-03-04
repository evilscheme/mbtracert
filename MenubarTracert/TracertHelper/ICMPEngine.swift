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
        self.sock = socket(AF_INET, SOCK_RAW, IPPROTO_ICMP)
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

            // Short inline collection — grab fast responses without blocking
            var tv = timeval(tv_sec: 0, tv_usec: Int32(inlineTimeout * 1_000_000))
            setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            collectResponses(probeMap: probeMap, responses: &responses,
                             destIP: destIP, destHop: &destHop, maxReads: 3)

            if destHop < maxHops && hop >= destHop { break }
        }

        // Phase 2: Bulk collection for slow/rate-limited responses
        let bulkTimeout = max(timeout - Double(min(destHop, maxHops)) * inlineTimeout, 0.5)
        let deadline = Date().addingTimeInterval(bulkTimeout)

        var consecutiveMisses = 0
        let maxConsecutiveMisses = 3

        let bulkReadTimeout: TimeInterval = 0.15  // 150ms per read, short enough to keep rounds fast

        while Date() < deadline {
            let remaining = min(max(deadline.timeIntervalSinceNow, 0.01), bulkReadTimeout)
            var tv = timeval(tv_sec: 0, tv_usec: Int32(remaining * 1_000_000))
            setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

            let before = responses.count
            collectResponses(probeMap: probeMap, responses: &responses,
                             destIP: destIP, destHop: &destHop, maxReads: 1)
            if responses.count == before {
                consecutiveMisses += 1
                if consecutiveMisses >= maxConsecutiveMisses { break }
            } else {
                consecutiveMisses = 0
            }
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

            let data = Data(bytes: buffer, count: bytesRead)
            let senderIP = ipString(from: sender)
            let ipHdrLen = Int(data[0] & 0x0F) * 4
            guard data.count >= ipHdrLen + 8 else { continue }

            let icmpType = data[ipHdrLen]

            if icmpType == 0 { // Echo Reply
                let id = UInt16(data[ipHdrLen + 4]) << 8 | UInt16(data[ipHdrLen + 5])
                let seq = UInt16(data[ipHdrLen + 6]) << 8 | UInt16(data[ipHdrLen + 7])
                guard id == identifier, let probe = probeMap[seq] else { continue }
                responses[probe.hop] = (senderIP, machDiffMs(probe.sendTime, recvTime))
                if senderIP == destIP { destHop = min(destHop, probe.hop) }
            } else if icmpType == 11 || icmpType == 3 { // Time Exceeded / Dest Unreachable
                let innerIPOffset = ipHdrLen + 8
                guard data.count >= innerIPOffset + 20 else { continue }
                let innerIPHdrLen = Int(data[innerIPOffset] & 0x0F) * 4
                let innerICMPOff = innerIPOffset + innerIPHdrLen
                guard data.count >= innerICMPOff + 8 else { continue }

                let innerID = UInt16(data[innerICMPOff + 4]) << 8 | UInt16(data[innerICMPOff + 5])
                let innerSeq = UInt16(data[innerICMPOff + 6]) << 8 | UInt16(data[innerICMPOff + 7])
                guard innerID == identifier, let probe = probeMap[innerSeq] else { continue }
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
