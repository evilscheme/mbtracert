import Foundation
import SwiftUI
import Combine

@MainActor
final class TracerouteViewModel: ObservableObject {
    // MARK: - Published State

    @Published var hops: [HopData] = []
    @Published var latencyHistory: [Double] = []
    @Published var isProbing = false
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
    @AppStorage("activeProbeInterval") var activeInterval: Double = 2.0
    @AppStorage("historyMinutes") var historyMinutes: Double = 3.0
    @AppStorage("resolveHostnames") var resolveHostnames = true
    @AppStorage("maxHops") var maxHops = 30
    @AppStorage("heatmapColorScheme") var colorSchemeName: String = HeatmapColorScheme.lagoon.rawValue
    @AppStorage("latencyThreshold") var latencyThreshold: Double = 100
    @AppStorage("showBandwidth") var showBandwidth = true
    @AppStorage("showSparklineBackground") var showSparklineBackground = true

    var colorScheme: HeatmapColorScheme {
        HeatmapColorScheme(rawValue: colorSchemeName) ?? .lagoon
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
    private let probeQueue = DispatchQueue(label: "org.evilscheme.TraceBar.probe")
    private var probeTimer: Timer?
    private var rescheduleDebounce: DispatchWorkItem?
    private let sparklineCapacity = 60
    private var hostnameCache: [String: String] = [:]  // ip -> hostname
    private var probeRoundsSinceInterfaceCheck = 0

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
        latencyHistory.removeAll()
        hostnameCache.removeAll()
        destinationHop = nil
        destHopStableSince = nil
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

        let addresses = hops.map { $0.address }
        let queue = probeQueue
        Task {
            let resolved = await withCheckedContinuation { continuation in
                queue.async {
                    var results: [String: String] = [:]
                    for addr in addresses {
                        if let name = TracerouteViewModel.resolveHostname(addr) {
                            results[addr] = name
                        }
                    }
                    continuation.resume(returning: results)
                }
            }
            hostnameCache = resolved
            for i in hops.indices {
                hops[i].hostname = resolved[hops[i].address]
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
        errorMessage = nil

        let bufferCapacity = Int(historyMinutes * 60 / activeInterval)
        let target = targetHost
        let hops = maxHops
        let eng = engine
        let resolve = resolveHostnames
        let queue = probeQueue
        let cachedNames = hostnameCache
        let bwMonitor = bandwidthMonitor
        let trackBandwidth = showBandwidth
        let shouldResolveInterface = probeRoundsSinceInterfaceCheck >= 10
        if shouldResolveInterface { probeRoundsSinceInterfaceCheck = 0 }
        probeRoundsSinceInterfaceCheck += 1

        let (probeResults, bwSample, destHop) = await withCheckedContinuation { (continuation: CheckedContinuation<([(HopResult, String?)], BandwidthSample?, Int), Never>) in
            queue.async {
                let roundResult = eng.probeRound(host: target, maxHops: hops)

                if shouldResolveInterface {
                    bwMonitor.invalidateInterface()
                }
                var bwSample: BandwidthSample?
                if trackBandwidth, let destAddr = eng.cachedAddr,
                   let iface = bwMonitor.activeInterface(for: destAddr) {
                    bwSample = bwMonitor.sample(interfaceName: iface)
                }

                let mapped = roundResult.hops.map { r in
                    let hostname: String? = resolve
                        ? (cachedNames[r.address] ?? TracerouteViewModel.resolveHostname(r.address))
                        : nil
                    return (r, hostname)
                }
                continuation.resume(returning: (mapped, bwSample, roundResult.destinationHop))
            }
        }

        // Discard results if the target changed while we were probing.
        guard targetHost == target else {
            isProbing = false
            return
        }

        // Update bandwidth state
        if let bwSample {
            lastBandwidthSample = bwSample
            currentInterface = bwSample.interfaceName
            bandwidthHistory.append(bwSample)
            if bandwidthHistory.count > bufferCapacity {
                bandwidthHistory.removeFirst()
            }
        }

        // Track destination hop with dampening (ignore error returns where destHop == 0)
        if destHop > 0 {
            if destinationHop != destHop {
                destinationHop = destHop
                destHopStableSince = Date()
            } else if destHopStableSince == nil {
                destHopStableSince = Date()
            }
        }

        for (result, hostname) in probeResults {
            if let hostname { hostnameCache[result.address] = hostname }
            let probe = ProbeResult(
                hop: result.hop,
                address: result.address,
                hostname: hostname,
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
            guard let newest = hop.probes.last else { return true }
            return newest.timestamp < cutoff
        }

        // Prune hops beyond destination after grace period (dampens route flapping)
        if let dest = destinationHop, let stableSince = destHopStableSince,
           Date().timeIntervalSince(stableSince) > 10 {
            self.hops.removeAll { $0.hop > dest }
        }

        if let destHopData = self.destinationLatencyHop {
            latencyHistory.append(destHopData.lastLatencyMs)
            if latencyHistory.count > sparklineCapacity {
                latencyHistory.removeFirst()
            }
        }

        isProbing = false
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
