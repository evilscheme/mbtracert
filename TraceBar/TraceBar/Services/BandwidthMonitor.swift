import Foundation
import Darwin

/// Polls per-interface byte counters via sysctl NET_RT_IFLIST2.
/// Must be called from a single serial queue (same constraint as ICMPEngine).
final class BandwidthMonitor: @unchecked Sendable {
    private var previousBytes: (download: UInt64, upload: UInt64)?
    private var previousTime: UInt64?  // mach_absolute_time
    private var cachedInterface: String?
    private var cachedDestination: String?

    private let machNumer: Double
    private let machDenom: Double

    init() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        machNumer = Double(info.numer)
        machDenom = Double(info.denom)
    }

    /// Determine which network interface carries traffic to the given destination.
    /// Uses a UDP connect() trick to trigger a routing table lookup without sending data.
    func activeInterface(for destination: String) -> String? {
        if destination == cachedDestination, let cached = cachedInterface {
            return cached
        }

        // Resolve destination to sockaddr_in
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(destination, "80", &hints, &result) == 0, let info = result else {
            return nil
        }
        defer { freeaddrinfo(result) }

        // Create a temporary UDP socket, connect to trigger routing lookup
        let udpSock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard udpSock >= 0 else { return nil }
        defer { close(udpSock) }

        guard connect(udpSock, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 else {
            return nil
        }

        // Get local address chosen by the kernel
        var localAddr = sockaddr_in()
        var localLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        guard withUnsafeMutablePointer(to: &localAddr, { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                getsockname(udpSock, sa, &localLen)
            }
        }) == 0 else { return nil }

        // Match local address against getifaddrs() to find interface name
        var ifaddrsPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrsPtr) == 0, let firstAddr = ifaddrsPtr else { return nil }
        defer { freeifaddrs(ifaddrsPtr) }

        var current: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let ifa = current {
            defer { current = ifa.pointee.ifa_next }
            guard let addr = ifa.pointee.ifa_addr,
                  addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }

            let ifAddr = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            if ifAddr.sin_addr.s_addr == localAddr.sin_addr.s_addr {
                let name = String(cString: ifa.pointee.ifa_name)
                cachedInterface = name
                cachedDestination = destination
                return name
            }
        }

        return nil
    }

    /// Invalidate cached interface so it gets re-resolved on next call.
    func invalidateInterface() {
        cachedInterface = nil
        cachedDestination = nil
    }

    /// Sample byte counters for the given interface.
    /// Returns nil on first call (need two samples to compute a rate) or on error.
    func sample(interfaceName: String) -> BandwidthSample? {
        let now = mach_absolute_time()
        guard let (download, upload) = readInterfaceBytes(interfaceName) else { return nil }

        defer {
            previousBytes = (download, upload)
            previousTime = now
        }

        guard let prev = previousBytes, let prevTime = previousTime else { return nil }

        let elapsedNs = Double(now - prevTime) * machNumer / machDenom
        let elapsedSec = elapsedNs / 1_000_000_000
        guard elapsedSec > 0 else { return nil }

        // Handle counter wrap (extremely unlikely with 64-bit, but safe)
        let dlDelta = download >= prev.download ? download - prev.download : download
        let ulDelta = upload >= prev.upload ? upload - prev.upload : upload

        return BandwidthSample(
            timestamp: Date(),
            downloadBytesPerSec: Double(dlDelta) / elapsedSec,
            uploadBytesPerSec: Double(ulDelta) / elapsedSec,
            interfaceName: interfaceName
        )
    }

    /// Reset stored counters (e.g. when clearing history).
    func reset() {
        previousBytes = nil
        previousTime = nil
        cachedInterface = nil
        cachedDestination = nil
    }

    // MARK: - sysctl NET_RT_IFLIST2

    /// Read 64-bit byte counters for a named interface using sysctl NET_RT_IFLIST2.
    private func readInterfaceBytes(_ interfaceName: String) -> (download: UInt64, upload: UInt64)? {
        let ifIndex = if_nametoindex(interfaceName)
        guard ifIndex > 0 else { return nil }

        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len: Int = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &len, nil, 0) == 0, len > 0 else { return nil }

        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, UInt32(mib.count), &buf, &len, nil, 0) == 0 else { return nil }

        var offset = 0
        while offset < len {
            let msgPtr = buf.withUnsafeMutableBufferPointer { bufPtr -> UnsafeMutableRawPointer in
                UnsafeMutableRawPointer(bufPtr.baseAddress! + offset)
            }
            let header = msgPtr.assumingMemoryBound(to: if_msghdr2.self).pointee

            if header.ifm_type == RTM_IFINFO2 && header.ifm_index == UInt16(ifIndex) {
                let data = header.ifm_data
                return (download: data.ifi_ibytes, upload: data.ifi_obytes)
            }

            offset += Int(header.ifm_msglen)
            if header.ifm_msglen == 0 { break }  // safety: avoid infinite loop
        }

        return nil
    }
}
