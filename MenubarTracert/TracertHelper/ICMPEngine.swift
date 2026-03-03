import Foundation
import Darwin

struct HopResult {
    let hop: Int
    let address: String
    let latencyMs: Double
}

final class ICMPEngine {
    private let identifier: UInt16

    init() {
        self.identifier = UInt16(getpid() & 0xFFFF)
    }

    func probeRound(host: String, maxHops: Int, timeout: TimeInterval = 2.0) -> [HopResult] {
        let sock = socket(AF_INET, SOCK_RAW, IPPROTO_ICMP)
        guard sock >= 0 else {
            return (1...maxHops).map { HopResult(hop: $0, address: "", latencyMs: -1) }
        }
        defer { close(sock) }

        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        guard var destAddr = resolveHost(host) else {
            return (1...maxHops).map { HopResult(hop: $0, address: "", latencyMs: -1) }
        }
        let destIP = ipString(from: destAddr)

        var results: [HopResult] = []

        for hop in 1...maxHops {
            var ttl = Int32(hop)
            setsockopt(sock, IPPROTO_IP, IP_TTL, &ttl, socklen_t(MemoryLayout<Int32>.size))

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

            let response = receiveResponse(socket: sock, expectedSeq: seq, sendTime: sendTime)
            results.append(HopResult(hop: hop, address: response.address, latencyMs: response.latencyMs))

            if response.address == destIP {
                break
            }
        }

        return results
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

    // MARK: - Response Parsing

    private struct Response {
        let address: String
        let latencyMs: Double
    }

    private func receiveResponse(socket sock: Int32, expectedSeq: UInt16, sendTime: UInt64) -> Response {
        var buffer = [UInt8](repeating: 0, count: 4096)
        var sender = sockaddr_in()
        var senderLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        for _ in 0..<10 {
            let bytesRead = withUnsafeMutablePointer(to: &sender) { senderPtr in
                senderPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(sock, &buffer, buffer.count, 0, sa, &senderLen)
                }
            }
            let recvTime = mach_absolute_time()

            guard bytesRead > 0 else {
                return Response(address: "", latencyMs: -1)
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
