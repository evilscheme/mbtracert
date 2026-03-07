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

    var lastLatencyMs: Double {
        probes.last?.latencyMs ?? -1
    }

    var avgLatencyMs: Double {
        var sum = 0.0
        var n = 0
        probes.forEach { probe in
            if !probe.isTimeout {
                sum += probe.latencyMs
                n += 1
            }
        }
        return n > 0 ? sum / Double(n) : -1
    }

    var lossPercent: Double {
        guard probes.count > 0 else { return 0 }
        var timeouts = 0
        probes.forEach { if $0.isTimeout { timeouts += 1 } }
        return Double(timeouts) / Double(probes.count) * 100
    }
}
