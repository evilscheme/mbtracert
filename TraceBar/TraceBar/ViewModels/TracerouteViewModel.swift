import Foundation
import SwiftUI
import Combine

@MainActor
final class TracerouteViewModel: ObservableObject {
    // MARK: - Published State

    @Published var hops: [HopData] = []
    // Intentionally not @Published: flipping true→false twice per probe
    // round would otherwise fire two extra SwiftUI invalidations that the
    // UI doesn't actually need. DetailViewPanel reads this only to suppress
    // "Waiting for first probe..." while the first round is in flight, and
    // re-evaluates naturally when hops publishes.
    var isProbing = false
    @Published var isPanelOpen = false
    @Published var errorMessage: String?
    private(set) var destinationHop: Int?
    private var destHopStableSince: Date?

    @Published var bandwidthHistory: [BandwidthSample] = []
    @Published var currentInterface: String = ""
    @Published var lastBandwidthSample: BandwidthSample?

    // MARK: - Settings

    @AppStorage("targetHost") var targetHost = "8.8.8.8"
    @AppStorage("idleProbeInterval") var idleInterval: Double = 10.0
    @AppStorage("activeProbeInterval") var activeInterval: Double = 1.0
    @AppStorage("historyMinutes") var historyMinutes: Double = 3.0
    @AppStorage("resolveHostnames") var resolveHostnames = true
    @AppStorage("maxHops") var maxHops = 30
    @AppStorage("colorScheme") var colorSchemeName: String = ColorTheme.thermal.rawValue
    @AppStorage("latencyThreshold") var latencyThreshold: Double = 100
    @AppStorage("showBandwidth") var showBandwidth = true
    @AppStorage("showMenuBarBackground") var showMenuBarBackground = true

    var colorScheme: ColorTheme {
        ColorTheme(rawValue: colorSchemeName) ?? .lagoon
    }

    /// Hops trimmed to the known destination, or to the last responding entry
    /// for firewalled destinations that never send Echo Reply.
    var visibleHops: [HopData] {
        // If we know the destination hop, cap there
        if let dest = destinationHop {
            let capped = hops.filter { $0.hop <= dest }
            if !capped.isEmpty { return capped }
        }
        // Trim trailing dead hops, keeping one as a "waiting for reply" sentinel
        guard let lastResponding = hops.lastIndex(where: { $0.isCurrentlyResponding }) else {
            return Array(hops.prefix(1))
        }
        let sentinel = min(lastResponding + 1, hops.count - 1)
        return Array(hops.prefix(through: sentinel))
    }

    /// The hop whose probe history drives the menubar chart.
    /// Returns the destination hop even when all probes are timeouts,
    /// so loss markers remain visible.
    var destinationChartHop: HopData? {
        if let dest = destinationHop {
            return hops.first(where: { $0.hop == dest })
        }
        return hops.last(where: { $0.lastLatencyMs > 0 }) ?? hops.last
    }

    /// The hop to use for summary latency display — the destination hop if known,
    /// otherwise the last responding hop.
    var destinationLatencyHop: HopData? {
        if let dest = destinationHop,
           let exact = hops.first(where: { $0.hop == dest && $0.lastLatencyMs > 0 }) {
            return exact
        }
        return hops.last(where: { $0.lastLatencyMs > 0 })
    }

    // MARK: - Private

    private let engine = ICMPEngine()
    private let bandwidthMonitor = BandwidthMonitor()
    // `.utility` keeps the probe off the userInteractive band so Activity
    // Monitor doesn't score background traceroute as urgent foreground work.
    // The minor scheduling-latency tradeoff (~1-5ms) is invisible for the
    // network-scale latencies we measure.
    private let probeQueue = DispatchQueue(label: "org.evilscheme.TraceBar.probe", qos: .utility)
    private var probeTimer: Timer?
    private var rescheduleDebounce: DispatchWorkItem?
    // ip -> hostname lookup result with expiry. A nil hostname represents
    // a negative cache entry — we tried to resolve and got no PTR record.
    // Negative entries get a shorter TTL so newly-assigned reverse DNS
    // records are picked up within a reasonable window. Caching negatives
    // avoids a blocking getnameinfo syscall every round for hops without
    // reverse DNS (common for home routers, carrier-grade NAT, transit
    // backbones), which matters especially on slow networks where the
    // OS-level resolver cache is less effective.
    private struct HostnameCacheEntry {
        let hostname: String?
        let expiresAt: Date
    }
    private var hostnameCache: [String: HostnameCacheEntry] = [:]
    private var probeRoundsSinceInterfaceCheck = 0
    private var roundsWithoutDestConfirmation = 0
    private static let probeHopMargin = 3
    private static let roundsBeforeFullRescan = 3
    // `nonisolated` so the probeQueue closure (which is not MainActor-isolated)
    // can read these constants while performing hostname lookups.
    nonisolated private static let hostnamePositiveTTL: TimeInterval = 24 * 60 * 60  // 24h
    nonisolated private static let hostnameNegativeTTL: TimeInterval = 15 * 60       // 15min

    // MARK: - Lifecycle

    func start() {
        rescheduleProbing()
    }

    func panelDidOpen() {
        isPanelOpen = true
        rescheduleProbing()
    }

    func panelDidClose() {
        isPanelOpen = false
        rescheduleProbing()
    }

    func clearHistory() {
        hops.removeAll()
        hostnameCache.removeAll()
        destinationHop = nil
        destHopStableSince = nil
        roundsWithoutDestConfirmation = 0
        bandwidthHistory.removeAll()
        lastBandwidthSample = nil
        let bwMonitor = bandwidthMonitor
        probeQueue.async { bwMonitor.reset() }
    }

    func refreshHostnames() {
        if !resolveHostnames {
            hostnameCache.removeAll()
            for i in hops.indices { hops[i].hostname = nil }
            return
        }

        let addresses = hops.map { $0.address }.filter { !$0.isEmpty }
        let queue = probeQueue
        Task {
            let resolved: [String: String?] = await withCheckedContinuation { continuation in
                queue.async {
                    var results: [String: String?] = [:]
                    for addr in addresses {
                        results[addr] = TracerouteViewModel.resolveHostname(addr)
                    }
                    continuation.resume(returning: results)
                }
            }
            let now = Date()
            for (ip, hostname) in resolved {
                let ttl = hostname != nil ? Self.hostnamePositiveTTL : Self.hostnameNegativeTTL
                hostnameCache[ip] = HostnameCacheEntry(
                    hostname: hostname,
                    expiresAt: now.addingTimeInterval(ttl)
                )
            }
            for i in hops.indices {
                hops[i].hostname = resolved[hops[i].address] ?? nil
            }
        }
    }

    // MARK: - Probing

    func rescheduleProbing() {
        // Debounce rapid calls (e.g. slider dragging) — only the last
        // invocation within the window actually restarts probing.
        rescheduleDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.applyReschedule()
            }
        }
        rescheduleDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func applyReschedule() {
        probeTimer?.invalidate()
        let interval = isPanelOpen ? activeInterval : idleInterval
        probeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.runProbeRound()
            }
        }
        Task { await runProbeRound() }
    }

    private func runProbeRound() async {
        guard !isProbing else { return }
        isProbing = true
        // Avoid a redundant @Published emit when there's no error to clear.
        if errorMessage != nil { errorMessage = nil }

        let bufferCapacity = Int(historyMinutes * 60 / activeInterval)
        let target = targetHost
        // Cap the probe range at `knownDest + margin` once the destination
        // has been confirmed recently. This avoids probing the full maxHops
        // every round when we already know the route length — particularly
        // important on high-latency links (e.g. inflight wifi ~600ms RTT)
        // where ICMPEngine's in-round early-exit can't trigger: all 30
        // sends complete in 300ms, long before the first reply arrives.
        //
        // After `roundsBeforeFullRescan` consecutive rounds without dest
        // confirmation (route grew past our cap, or destination stopped
        // replying), we fall back to a full scan to rediscover.
        let probeHopLimit: Int
        if let knownDest = destinationHop,
           roundsWithoutDestConfirmation < Self.roundsBeforeFullRescan {
            probeHopLimit = min(maxHops, knownDest + Self.probeHopMargin)
        } else {
            probeHopLimit = maxHops
        }
        let eng = engine
        let resolve = resolveHostnames
        let queue = probeQueue
        let cachedNames = hostnameCache
        let bwMonitor = bandwidthMonitor
        let trackBandwidth = showBandwidth
        let shouldResolveInterface = probeRoundsSinceInterfaceCheck >= 10
        if shouldResolveInterface { probeRoundsSinceInterfaceCheck = 0 }
        probeRoundsSinceInterfaceCheck += 1

        // Snapshot `isPanelOpen` for the whole round so the same behavior
        // applies to every hop — toggling mid-round would risk double-insert
        // or gaps. When the panel is open, we stream each reply live (mtr
        // feel); when it's closed, we keep the amortized batch behavior so
        // background work stays cheap.
        let streaming = isPanelOpen
        let streamCallback: (@Sendable (HopResult) -> Void)?
        if streaming {
            streamCallback = { [weak self] result in
                let arrival = Date()
                Task { @MainActor [weak self] in
                    self?.applyStreamingHopResult(
                        result,
                        timestamp: arrival,
                        expectedTarget: target,
                        bufferCapacity: bufferCapacity
                    )
                }
            }
        } else {
            streamCallback = nil
        }

        let (probeResults, freshLookups, bwSample, destHop) = await withCheckedContinuation { (continuation: CheckedContinuation<([(HopResult, String?)], [String: HostnameCacheEntry], BandwidthSample?, Int), Never>) in
            queue.async {
                let roundResult = eng.probeRound(host: target, maxHops: probeHopLimit, onHopResult: streamCallback)

                if shouldResolveInterface {
                    bwMonitor.invalidateInterface()
                }
                var bwSample: BandwidthSample?
                if trackBandwidth, let destAddr = eng.cachedAddr,
                   let iface = bwMonitor.activeInterface(for: destAddr) {
                    bwSample = bwMonitor.sample(interfaceName: iface)
                }

                let lookupNow = Date()
                var freshLookups: [String: HostnameCacheEntry] = [:]
                let mapped = roundResult.hops.map { r -> (HopResult, String?) in
                    guard resolve, !r.address.isEmpty else { return (r, nil) }

                    if let cached = cachedNames[r.address], cached.expiresAt > lookupNow {
                        return (r, cached.hostname)
                    }
                    // Re-use an in-round resolution if two hops share an IP
                    // (can happen with load-balanced paths).
                    if let fresh = freshLookups[r.address] {
                        return (r, fresh.hostname)
                    }

                    let hostname = TracerouteViewModel.resolveHostname(r.address)
                    let ttl = hostname != nil
                        ? TracerouteViewModel.hostnamePositiveTTL
                        : TracerouteViewModel.hostnameNegativeTTL
                    freshLookups[r.address] = HostnameCacheEntry(
                        hostname: hostname,
                        expiresAt: lookupNow.addingTimeInterval(ttl)
                    )
                    return (r, hostname)
                }
                continuation.resume(returning: (mapped, freshLookups, bwSample, roundResult.destinationHop))
            }
        }

        // Discard results if the target changed while we were probing.
        guard targetHost == target else {
            isProbing = false
            return
        }

        // Track destination hop with dampening (ignore error returns where destHop == 0)
        if destHop > 0 {
            roundsWithoutDestConfirmation = 0
            if destinationHop != destHop {
                destinationHop = destHop
                destHopStableSince = Date()
            } else if destHopStableSince == nil {
                destHopStableSince = Date()
            }
        } else {
            roundsWithoutDestConfirmation += 1
        }

        // Merge newly-resolved hostname entries (both positive and negative)
        // into the persistent cache.
        for (ip, entry) in freshLookups {
            hostnameCache[ip] = entry
        }

        // Build a local copy of hops and mutate in place. Swift arrays are
        // copy-on-write, so the shared storage isn't duplicated until we
        // actually mutate — this is cheap. Assigning to self.hops once at
        // the end collapses ~30 @Published emits per round into a single
        // SwiftUI invalidation.
        var newHops = self.hops
        let now = Date()

        // In streaming mode, successful replies were already appended live
        // by applyStreamingHopResult. We still need to add timeout entries
        // (no arrival event = no streaming callback) and backfill hostnames
        // that resolved after the probe streamed in.
        for (result, hostname) in probeResults {
            if streaming && result.latencyMs >= 0 {
                continue
            }
            let probe = ProbeResult(
                hop: result.hop,
                address: result.address,
                hostname: hostname,
                latencyMs: result.latencyMs,
                timestamp: now
            )
            Self.insertProbe(into: &newHops, probe: probe, bufferCapacity: bufferCapacity)
        }

        if streaming {
            // Backfill hostnames on hops that streamed in before DNS resolved.
            for i in newHops.indices where newHops[i].hostname == nil && !newHops[i].address.isEmpty {
                if let cached = hostnameCache[newHops[i].address]?.hostname {
                    newHops[i].hostname = cached
                }
            }
        }

        // Remove hops whose data has fully aged out of the history window.
        let cutoff = now.addingTimeInterval(-historyMinutes * 60)
        newHops.removeAll { hop in
            guard let newest = hop.probes.last else { return true }
            return newest.timestamp < cutoff
        }

        // Prune hops beyond destination after grace period (dampens route flapping)
        if let dest = destinationHop, let stableSince = destHopStableSince,
           now.timeIntervalSince(stableSince) > 10 {
            newHops.removeAll { $0.hop > dest }
        }

        self.hops = newHops

        if let bwSample {
            lastBandwidthSample = bwSample
            if currentInterface != bwSample.interfaceName {
                currentInterface = bwSample.interfaceName
            }
            if bandwidthHistory.count >= bufferCapacity {
                bandwidthHistory.removeFirst(bandwidthHistory.count - bufferCapacity + 1)
            }
            bandwidthHistory.append(bwSample)
        }

        isProbing = false
    }

    /// Apply a single hop reply live, in the order it arrived from the
    /// receiver thread. Only called while the panel is open — the batched
    /// post-round handler takes over when it's closed. Each call emits one
    /// @Published mutation on `hops`, which is the point: SwiftUI invalidates
    /// per-hop so the row redraws as the reply comes in.
    private func applyStreamingHopResult(
        _ result: HopResult,
        timestamp: Date,
        expectedTarget: String,
        bufferCapacity: Int
    ) {
        // Target may have changed while the reply was in flight; discard.
        guard targetHost == expectedTarget else { return }

        let hostname = hostnameCache[result.address]?.hostname
        let probe = ProbeResult(
            hop: result.hop,
            address: result.address,
            hostname: hostname,
            latencyMs: result.latencyMs,
            timestamp: timestamp
        )
        Self.insertProbe(into: &hops, probe: probe, bufferCapacity: bufferCapacity)
    }

    /// Append a probe to the matching hop, or create the hop if it doesn't
    /// exist yet (keeping the array sorted by hop number). Shared by the
    /// streaming and batched paths so both produce identical hop state.
    private static func insertProbe(
        into hops: inout [HopData],
        probe: ProbeResult,
        bufferCapacity: Int
    ) {
        if let idx = hops.firstIndex(where: { $0.hop == probe.hop }) {
            hops[idx].probes.append(probe)
            if !probe.address.isEmpty {
                hops[idx].address = probe.address
                hops[idx].hostname = probe.hostname
            }
        } else {
            var hopData = HopData(
                id: probe.hop,
                hop: probe.hop,
                address: probe.address,
                hostname: probe.hostname,
                probes: RingBuffer<ProbeResult>(capacity: bufferCapacity)
            )
            hopData.probes.append(probe)
            hops.append(hopData)
            hops.sort { $0.hop < $1.hop }
        }
    }

    fileprivate static nonisolated func resolveHostname(_ ip: String) -> String? {
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
