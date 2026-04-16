import Foundation

struct ProbeResult: Identifiable, Equatable {
    let id = UUID()
    let hop: Int
    let address: String
    let hostname: String?
    let latencyMs: Double
    let timestamp: Date

    var isTimeout: Bool { latencyMs < 0 }

    // Each ProbeResult is created once and stored by value in a RingBuffer,
    // so UUID identity is a sufficient (and cheap) equality check. This lets
    // `[ProbeResult]` compare as equal when chart views ask SwiftUI whether
    // their inputs changed, short-circuiting redundant Canvas redraws.
    static func == (lhs: ProbeResult, rhs: ProbeResult) -> Bool {
        lhs.id == rhs.id
    }
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

    /// Whether any of the last 3 probes got a response.
    var isCurrentlyResponding: Bool {
        let recent = probes.elements.suffix(3)
        return recent.contains(where: { !$0.isTimeout })
    }
}
