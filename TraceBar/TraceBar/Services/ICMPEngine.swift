import Foundation
import Darwin

struct HopResult: Sendable {
    let hop: Int
    let address: String
    let latencyMs: Double
    let icmpType: UInt8?
    let icmpCode: UInt8?
}

struct ParsedICMPResponse: Sendable {
    let seq: UInt16
    let icmpType: UInt8
    let icmpCode: UInt8
}

struct ProbeRoundResult: Sendable {
    let hops: [HopResult]
    let destinationHop: Int
}

final class ICMPEngine: @unchecked Sendable {
    private let identifier: UInt16
    private let sock: Int32
    private var nextSequence: UInt16 = 33434
    private let machNumer: Double
    private let machDenom: Double
    private var cachedHost: String = ""
    private(set) var cachedAddr: sockaddr_in?

    init() {
        self.identifier = UInt16(getpid() & 0xFFFF)
        self.sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        if sock < 0 {
            NSLog("[ICMPEngine] socket() failed: %s", String(cString: strerror(errno)))
        }
        // IP_STRIPHDR (value 23) is not exposed in Swift headers.
        // It tells the kernel to strip the IP header from received packets,
        // so ICMP data starts at buffer[0].
        var strip: Int32 = 1
        setsockopt(sock, IPPROTO_IP, 23, &strip, socklen_t(MemoryLayout<Int32>.size))

        // Cache mach timebase (constant for process lifetime)
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        self.machNumer = Double(info.numer)
        self.machDenom = Double(info.denom)
    }

    deinit {
        if sock >= 0 { close(sock) }
    }

    private func allocateSequence() -> UInt16 {
        let seq = nextSequence
        nextSequence = nextSequence >= 65535 ? 33434 : nextSequence + 1
        return seq
    }

    private final class ProbeState: @unchecked Sendable {
        let lock = NSLock()
        var sendTimes: [UInt16: UInt64] = [:]
        var responses: [Int: (address: String, latencyMs: Double, icmpType: UInt8, icmpCode: UInt8)] = [:]
        var sendErrors: Set<Int> = []
        var destHop: Int
        var destHopConfirmed = false
        var sendingDone = false
        init(maxHops: Int) { self.destHop = maxHops }
    }

    /// Concurrent send/receive probe: a dedicated receiver thread captures
    /// recvTime immediately on packet arrival while the sender paces probes
    /// with a short inter-packet delay on the calling thread.
    /// - Important: Must be called from a single serial queue (not concurrently).
    func probeRound(host: String, maxHops: Int, timeout: TimeInterval = 2.0) -> ProbeRoundResult {
        guard sock >= 0 else { return ProbeRoundResult(hops: [], destinationHop: 0) }

        // Cache resolved address — only re-resolve when target changes
        if host != cachedHost || cachedAddr == nil {
            guard let addr = resolveHost(host) else { return ProbeRoundResult(hops: [], destinationHop: 0) }
            cachedHost = host
            cachedAddr = addr
        }
        guard var destAddr = cachedAddr else { return ProbeRoundResult(hops: [], destinationHop: 0) }

        // Pre-allocate sequences so the receiver can map seq→hop without
        // waiting for the sender to populate the map.
        var hopSeqs: [(hop: Int, seq: UInt16)] = []
        for hop in 1...maxHops {
            hopSeqs.append((hop, allocateSequence()))
        }
        let seqToHop = Dictionary(uniqueKeysWithValues: hopSeqs.map { ($0.seq, $0.hop) })

        let state = ProbeState(maxHops: maxHops)

        // Capture immutable values for the receiver closure
        let sockFd = self.sock
        let engineID = self.identifier
        let numer = self.machNumer
        let denom = self.machDenom
        let destIPAddr = destAddr.sin_addr.s_addr
        let totalHops = maxHops
        let deadline = Date().addingTimeInterval(timeout)

        // --- Receiver thread: always blocking on recvfrom so recvTime is accurate ---
        // Runs until the full deadline, until every expected hop has responded,
        // or until sending is done and every hop is accounted for via responses
        // or send errors. The empty-recv path also re-checks completion so a
        // round where every send failed doesn't burn the full timeout.
        let recvGroup = DispatchGroup()
        recvGroup.enter()
        DispatchQueue.global(qos: .userInteractive).async {
            defer { recvGroup.leave() }
            var buf = [UInt8](repeating: 0, count: 4096)

            // A hop is "accounted for" if it responded or if its send failed.
            let isComplete: () -> Bool = {
                let accountedFor: (Int) -> Bool = { state.responses[$0] != nil || state.sendErrors.contains($0) }
                return (1...totalHops).allSatisfy(accountedFor)
                    || (state.destHop < totalHops && (1...state.destHop).allSatisfy(accountedFor))
            }

            while Date() < deadline {
                let remaining = min(max(deadline.timeIntervalSinceNow, 0.01), 0.15)
                var tv = timeval(tv_sec: 0, tv_usec: Int32(remaining * 1_000_000))
                setsockopt(sockFd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

                var sender = sockaddr_in()
                var senderLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                let n = withUnsafeMutablePointer(to: &sender) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        recvfrom(sockFd, &buf, buf.count, 0, sa, &senderLen)
                    }
                }
                let recvTime = mach_absolute_time()

                guard n > 0 else {
                    // No packet this slice — if sending is done and every hop
                    // is accounted for (responded or sendError), exit early
                    // instead of waiting out the full deadline.
                    state.lock.lock()
                    let canExit = state.sendingDone && isComplete()
                    state.lock.unlock()
                    if canExit { break }
                    continue
                }

                // Parse ICMP response (IP_STRIPHDR: ICMP starts at byte 0)
                guard let parsed = ICMPEngine.parseResponse(buf, count: n, identifier: engineID) else { continue }
                guard let hop = seqToHop[parsed.seq] else { continue }

                var addrBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &sender.sin_addr, &addrBuf, socklen_t(INET_ADDRSTRLEN))
                let senderIP = String(cString: addrBuf)

                // Echo Reply always indicates destination. Dest Unreachable only
                // counts as destination when it comes from the target IP itself;
                // an intermediate sending Unreachable does not truncate the trace.
                let isDestReply = parsed.icmpType == 0 ||
                    (parsed.icmpType == 3 && sender.sin_addr.s_addr == destIPAddr)

                state.lock.lock()
                if let sendTime = state.sendTimes[parsed.seq] {
                    // First valid response wins for stored latency/address — a
                    // later duplicate or multipath reply would otherwise inflate
                    // latency. The destination check still runs on every reply
                    // so a late Echo Reply can confirm the dest even if a Time
                    // Exceeded for the same seq won the race.
                    if state.responses[hop] == nil {
                        let latencyMs = Double(recvTime - sendTime) * numer / denom / 1_000_000.0
                        state.responses[hop] = (senderIP, latencyMs, parsed.icmpType, parsed.icmpCode)
                    }
                    if isDestReply {
                        state.destHop = min(state.destHop, hop)
                        state.destHopConfirmed = true
                    }
                }
                let complete = isComplete()
                state.lock.unlock()

                if complete { break }
            }
        }

        // --- Sender: current thread, paced 10ms apart ---
        for (hop, seq) in hopSeqs {
            // Stop sending past the destination once the receiver identifies it
            state.lock.lock()
            let currentDest = state.destHop
            state.lock.unlock()
            if currentDest < maxHops && hop > currentDest { break }

            var ttl = Int32(hop)
            let ttlRc = setsockopt(sockFd, IPPROTO_IP, IP_TTL, &ttl, socklen_t(MemoryLayout<Int32>.size))
            if ttlRc != 0 {
                // Without a fresh TTL, a reply could be misattributed to the
                // previous hop. Mark as a send error and skip.
                state.lock.lock()
                state.sendErrors.insert(hop)
                state.lock.unlock()
                continue
            }

            let packet = buildPacket(sequence: seq)
            let sendTime = mach_absolute_time()

            // Record sendTime before sendto so the receiver can match a fast
            // reply even if the send syscall hasn't returned yet.
            state.lock.lock()
            state.sendTimes[seq] = sendTime
            state.lock.unlock()

            let sent = packet.withUnsafeBytes { rawBuf -> Int in
                withUnsafeMutablePointer(to: &destAddr) { addrPtr in
                    addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        sendto(sockFd, rawBuf.baseAddress, packet.count, 0, sa,
                               socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }

            if sent < 0 {
                // sendto failed — roll back the pending sendTime so a stray
                // matching reply isn't attributed to a send that never went
                // out, and mark the hop as a send error so it doesn't pollute
                // loss statistics.
                state.lock.lock()
                state.sendTimes.removeValue(forKey: seq)
                state.sendErrors.insert(hop)
                state.lock.unlock()
            }

            if hop < maxHops { usleep(10_000) } // 10ms between sends
        }

        state.lock.lock()
        state.sendingDone = true
        state.lock.unlock()

        // Wait for receiver to finish (bounded by timeout deadline)
        recvGroup.wait()

        // Build results
        state.lock.lock()
        let confirmedDest = state.destHopConfirmed
        let hopRange = state.destHop
        let finalResponses = state.responses
        let sendErrorHops = state.sendErrors
        state.lock.unlock()

        // Hops whose send syscall failed are omitted from results rather than
        // reported as timeouts — otherwise transient EHOSTUNREACH/ENOBUFS would
        // masquerade as packet loss in the UI.
        let hops = (1...hopRange).compactMap { hop -> HopResult? in
            if sendErrorHops.contains(hop) { return nil }
            if let resp = finalResponses[hop] {
                return HopResult(hop: hop, address: resp.address, latencyMs: resp.latencyMs,
                                 icmpType: resp.icmpType, icmpCode: resp.icmpCode)
            }
            return HopResult(hop: hop, address: "", latencyMs: -1,
                             icmpType: nil, icmpCode: nil)
        }
        return ProbeRoundResult(hops: hops, destinationHop: confirmedDest ? hopRange : 0)
    }

    // MARK: - Packet Construction

    private func buildPacket(sequence: UInt16) -> Data {
        var packet = Data(count: 16)

        packet[0] = 8  // Type: Echo Request
        packet[1] = 0  // Code
        // Checksum at [2..3] — filled below
        packet[4] = UInt8(identifier >> 8)
        packet[5] = UInt8(identifier & 0xFF)
        packet[6] = UInt8(sequence >> 8)
        packet[7] = UInt8(sequence & 0xFF)

        var ts = mach_absolute_time()
        withUnsafeBytes(of: &ts) { tsBytes in
            for i in 0..<8 { packet[8 + i] = tsBytes[i] }
        }

        // Compute checksum — required because some routers/firewalls validate
        // ICMP checksums on forwarded packets and drop malformed ones.
        var sum: UInt32 = 0
        for i in stride(from: 0, to: packet.count - 1, by: 2) {
            sum += UInt32(packet[i]) << 8 | UInt32(packet[i + 1])
        }
        while sum >> 16 != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        let cksum = ~UInt16(sum & 0xFFFF)
        packet[2] = UInt8(cksum >> 8)
        packet[3] = UInt8(cksum & 0xFF)

        return packet
    }

    // MARK: - Packet Parsing

    /// Parse an ICMP response buffer (with IP header already stripped).
    /// Returns nil for unrecognised types, too-short buffers, or identifier mismatch.
    static func parseResponse(_ buf: [UInt8], count: Int, identifier: UInt16) -> ParsedICMPResponse? {
        guard count >= 8 else { return nil }
        let icmpType = buf[0]
        let icmpCode = buf[1]

        if icmpType == 0 { // Echo Reply
            let seq = UInt16(buf[6]) << 8 | UInt16(buf[7])
            return ParsedICMPResponse(seq: seq, icmpType: icmpType, icmpCode: icmpCode)
        } else if icmpType == 11 || icmpType == 3 { // Time Exceeded / Dest Unreachable
            let innerIPOffset = 8
            guard count >= innerIPOffset + 20 else { return nil }
            let ihl = Int(buf[innerIPOffset] & 0x0F) * 4
            let innerICMPOff = innerIPOffset + ihl
            guard count >= innerICMPOff + 8 else { return nil }
            // Validate identifier in inner ICMP header to reject unrelated traffic
            let innerID = UInt16(buf[innerICMPOff + 4]) << 8 | UInt16(buf[innerICMPOff + 5])
            guard innerID == identifier else { return nil }
            let seq = UInt16(buf[innerICMPOff + 6]) << 8 | UInt16(buf[innerICMPOff + 7])
            return ParsedICMPResponse(seq: seq, icmpType: icmpType, icmpCode: icmpCode)
        }

        return nil
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

}
