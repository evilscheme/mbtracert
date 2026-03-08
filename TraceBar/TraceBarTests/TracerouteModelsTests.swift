import Testing
import Foundation
@testable import TraceBar

@Suite("ProbeResult")
struct ProbeResultTests {

    @Test func timeoutWhenNegativeLatency() {
        let probe = ProbeResult(hop: 1, address: "1.2.3.4", hostname: nil, latencyMs: -1, timestamp: Date())
        #expect(probe.isTimeout)
    }

    @Test func notTimeoutWhenZeroLatency() {
        let probe = ProbeResult(hop: 1, address: "1.2.3.4", hostname: nil, latencyMs: 0, timestamp: Date())
        #expect(!probe.isTimeout)
    }

    @Test func notTimeoutWhenPositiveLatency() {
        let probe = ProbeResult(hop: 1, address: "1.2.3.4", hostname: nil, latencyMs: 15.5, timestamp: Date())
        #expect(!probe.isTimeout)
    }
}

@Suite("HopData")
struct HopDataTests {

    private func makeHop(capacity: Int = 100) -> HopData {
        HopData(id: 1, hop: 1, address: "1.2.3.4", hostname: nil, probes: RingBuffer(capacity: capacity))
    }

    private func probe(latencyMs: Double) -> ProbeResult {
        ProbeResult(hop: 1, address: "1.2.3.4", hostname: nil, latencyMs: latencyMs, timestamp: Date())
    }

    // MARK: - lastLatencyMs

    @Test func lastLatencyEmptyProbes() {
        let hop = makeHop()
        #expect(hop.lastLatencyMs == -1)
    }

    @Test func lastLatencyReturnsNewest() {
        var hop = makeHop()
        hop.probes.append(probe(latencyMs: 10))
        hop.probes.append(probe(latencyMs: 20))
        hop.probes.append(probe(latencyMs: 30))
        #expect(hop.lastLatencyMs == 30)
    }

    @Test func lastLatencyCanBeTimeout() {
        var hop = makeHop()
        hop.probes.append(probe(latencyMs: 10))
        hop.probes.append(probe(latencyMs: -1))
        #expect(hop.lastLatencyMs == -1)
    }

    // MARK: - avgLatencyMs

    @Test func avgLatencyEmptyProbes() {
        let hop = makeHop()
        #expect(hop.avgLatencyMs == -1)
    }

    @Test func avgLatencyAllTimeouts() {
        var hop = makeHop()
        hop.probes.append(probe(latencyMs: -1))
        hop.probes.append(probe(latencyMs: -1))
        #expect(hop.avgLatencyMs == -1)
    }

    @Test func avgLatencyAllValid() {
        var hop = makeHop()
        hop.probes.append(probe(latencyMs: 10))
        hop.probes.append(probe(latencyMs: 20))
        hop.probes.append(probe(latencyMs: 30))
        #expect(hop.avgLatencyMs == 20)
    }

    @Test func avgLatencyIgnoresTimeouts() {
        var hop = makeHop()
        hop.probes.append(probe(latencyMs: 10))
        hop.probes.append(probe(latencyMs: -1))
        hop.probes.append(probe(latencyMs: 30))
        // Average of 10 and 30 only
        #expect(hop.avgLatencyMs == 20)
    }

    @Test func avgLatencySingleProbe() {
        var hop = makeHop()
        hop.probes.append(probe(latencyMs: 42.5))
        #expect(hop.avgLatencyMs == 42.5)
    }

    // MARK: - lossPercent

    @Test func lossPercentEmptyProbes() {
        let hop = makeHop()
        #expect(hop.lossPercent == 0)
    }

    @Test func lossPercentNoLoss() {
        var hop = makeHop()
        hop.probes.append(probe(latencyMs: 10))
        hop.probes.append(probe(latencyMs: 20))
        #expect(hop.lossPercent == 0)
    }

    @Test func lossPercentAllLost() {
        var hop = makeHop()
        hop.probes.append(probe(latencyMs: -1))
        hop.probes.append(probe(latencyMs: -1))
        #expect(hop.lossPercent == 100)
    }

    @Test func lossPercentPartial() {
        var hop = makeHop()
        hop.probes.append(probe(latencyMs: 10))
        hop.probes.append(probe(latencyMs: -1))
        hop.probes.append(probe(latencyMs: 20))
        hop.probes.append(probe(latencyMs: -1))
        #expect(hop.lossPercent == 50)
    }

    @Test func lossPercentOneOfThree() {
        var hop = makeHop()
        hop.probes.append(probe(latencyMs: 10))
        hop.probes.append(probe(latencyMs: -1))
        hop.probes.append(probe(latencyMs: 20))
        let expected = 100.0 / 3.0
        #expect(abs(hop.lossPercent - expected) < 0.01)
    }

    // MARK: - isCurrentlyResponding

    @Test func isCurrentlyRespondingEmptyProbes() {
        let hop = makeHop()
        #expect(!hop.isCurrentlyResponding)
    }

    @Test func isCurrentlyRespondingAllTimeouts() {
        var hop = makeHop()
        hop.probes.append(probe(latencyMs: -1))
        hop.probes.append(probe(latencyMs: -1))
        hop.probes.append(probe(latencyMs: -1))
        #expect(!hop.isCurrentlyResponding)
    }

    @Test func isCurrentlyRespondingOneRecentSuccess() {
        var hop = makeHop()
        hop.probes.append(probe(latencyMs: -1))
        hop.probes.append(probe(latencyMs: -1))
        hop.probes.append(probe(latencyMs: 15))
        #expect(hop.isCurrentlyResponding)
    }

    @Test func isCurrentlyRespondingOldSuccessNewTimeouts() {
        var hop = makeHop()
        hop.probes.append(probe(latencyMs: 15))
        hop.probes.append(probe(latencyMs: -1))
        hop.probes.append(probe(latencyMs: -1))
        hop.probes.append(probe(latencyMs: -1))
        #expect(!hop.isCurrentlyResponding)
    }
}
