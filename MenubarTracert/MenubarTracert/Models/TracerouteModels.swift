import Foundation

struct ProbeResult: Identifiable {
    let id = UUID()
    let hop: Int
    let address: String
    let hostname: String?
    let latencyMs: Double
    let timestamp: Date

    var isTimeout: Bool { latencyMs < 0 }
}

struct HopData: Identifiable {
    let id: Int
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
