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
    @Published var helperInstalled = false
    @Published var errorMessage: String?

    // MARK: - Settings

    @AppStorage("targetHost") var targetHost = "8.8.8.8"
    @AppStorage("idleProbeInterval") var idleInterval: Double = 5.0
    @AppStorage("activeProbeInterval") var activeInterval: Double = 1.0
    @AppStorage("historyMinutes") var historyMinutes: Double = 5.0
    @AppStorage("resolveHostnames") var resolveHostnames = true
    @AppStorage("maxHops") var maxHops = 30

    // MARK: - Private

    private let xpcClient = HelperXPCClient()
    private var probeTimer: Timer?
    private let sparklineCapacity = 60

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

                if let lastHop = self.hops.last, lastHop.avgLatencyMs > 0 {
                    self.latencyHistory.append(lastHop.avgLatencyMs)
                    if self.latencyHistory.count > self.sparklineCapacity {
                        self.latencyHistory.removeFirst()
                    }
                }
            }
        }
    }

    private nonisolated func resolveHostname(_ ip: String) -> String? {
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
