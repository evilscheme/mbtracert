import Foundation
@testable import TraceBar

/// Deterministic test data factories for snapshot and behavior tests.
/// All timestamps use a fixed reference date so snapshots are reproducible.
enum TestData {
    /// Fixed reference time: 2025-01-01 12:00:00 UTC
    static let referenceDate = Date(timeIntervalSinceReferenceDate: 757_382_400)

    /// Standard test capacity matching 3 minutes at 1-second intervals.
    static let standardCapacity = 180

    // MARK: - ProbeResult factories

    /// Creates a single non-timeout probe result.
    static func probe(hop: Int, latencyMs: Double, address: String = "10.0.0.1",
                      secondsAgo: Double = 0) -> ProbeResult {
        ProbeResult(
            hop: hop,
            address: address,
            hostname: nil,
            latencyMs: latencyMs,
            timestamp: referenceDate.addingTimeInterval(-secondsAgo)
        )
    }

    /// Creates a single timeout probe result.
    static func timeout(hop: Int, address: String = "*",
                        secondsAgo: Double = 0) -> ProbeResult {
        ProbeResult(
            hop: hop,
            address: address,
            hostname: nil,
            latencyMs: -1,
            timestamp: referenceDate.addingTimeInterval(-secondsAgo)
        )
    }

    // MARK: - ProbeResult sequence factories

    /// Creates a sequence of probes spread evenly over the history window.
    /// Uses a deterministic pseudo-random pattern with jitter, spikes, and dips
    /// to produce realistic-looking chart data.
    static func probeSequence(hop: Int, count: Int, latencyRange: ClosedRange<Double>,
                              address: String = "10.0.0.1",
                              historySeconds: Double = 180) -> [ProbeResult] {
        let lo = latencyRange.lowerBound
        let hi = latencyRange.upperBound
        let mid = (lo + hi) / 2.0
        let amp = (hi - lo) / 2.0

        return (0..<count).map { i in
            let t = Double(i) / Double(max(count - 1, 1))
            // Layer multiple sine waves for organic-looking variation
            let wave1 = sin(t * .pi * 4.0 + Double(hop))          // slow oscillation
            let wave2 = sin(t * .pi * 11.0 + Double(hop) * 2.3)   // faster jitter
            let wave3 = sin(t * .pi * 23.0 + Double(hop) * 0.7)   // high-freq noise
            // Deterministic spike: every ~17th sample gets a burst
            let spike = (i % 17 == 3) ? 0.8 : 0.0
            let combined = wave1 * 0.5 + wave2 * 0.25 + wave3 * 0.1 + spike
            let latency = max(lo, min(hi, mid + amp * combined))

            let secondsAgo = historySeconds * (1.0 - t)
            return probe(hop: hop, latencyMs: latency, address: address,
                         secondsAgo: secondsAgo)
        }
    }

    /// Creates a probe sequence with a given loss percentage (timeouts interspersed).
    /// Non-timeout probes use jittered latency around `latencyMs` for realistic variation.
    static func probeSequenceWithLoss(hop: Int, count: Int, latencyMs: Double,
                                      lossPercent: Double,
                                      address: String = "10.0.0.1",
                                      historySeconds: Double = 180) -> [ProbeResult] {
        let lossInterval = lossPercent > 0 ? max(Int(100.0 / lossPercent), 2) : Int.max
        return (0..<count).map { i in
            let t = Double(i) / Double(max(count - 1, 1))
            let secondsAgo = historySeconds * (1.0 - t)
            if i % lossInterval == 0 && lossPercent > 0 {
                return timeout(hop: hop, address: "*", secondsAgo: secondsAgo)
            }
            // Jitter around the base latency
            let jitter = sin(t * .pi * 7.0 + Double(hop)) * latencyMs * 0.3
            let lat = max(1.0, latencyMs + jitter)
            return probe(hop: hop, latencyMs: lat, address: address,
                         secondsAgo: secondsAgo)
        }
    }

    // MARK: - HopData factories

    /// Creates a single HopData with probes from a probe sequence.
    static func hopData(hop: Int, probes: [ProbeResult],
                        address: String = "10.0.0.1",
                        hostname: String? = nil) -> HopData {
        var ring = RingBuffer<ProbeResult>(capacity: standardCapacity)
        for p in probes { ring.append(p) }
        return HopData(id: hop, hop: hop, address: address,
                       hostname: hostname, probes: ring)
    }

    /// Creates a simple HopData with uniform latency.
    static func simpleHop(hop: Int, latencyMs: Double, probeCount: Int = 30,
                          address: String? = nil) -> HopData {
        let addr = address ?? "10.0.0.\(hop)"
        let probes = probeSequence(hop: hop, count: probeCount,
                                   latencyRange: latencyMs...latencyMs,
                                   address: addr)
        return hopData(hop: hop, probes: probes, address: addr,
                       hostname: "hop\(hop).example.com")
    }

    // MARK: - Multi-hop trace factories

    /// Creates a realistic trace: latency increases with hop count.
    static func normalTrace(hopCount: Int = 8, probeCount: Int = 30) -> [HopData] {
        (1...hopCount).map { hop in
            let baseLat = Double(hop) * 5.0  // 5ms, 10ms, 15ms...
            let probes = probeSequence(hop: hop, count: probeCount,
                                       latencyRange: baseLat...(baseLat + 3.0),
                                       address: "10.0.0.\(hop)")
            return hopData(hop: hop, probes: probes, address: "10.0.0.\(hop)",
                           hostname: "hop\(hop).example.com")
        }
    }

    /// Creates a trace with one high-latency hop and one lossy hop.
    static func problematicTrace() -> [HopData] {
        var hops = normalTrace(hopCount: 6)
        // Hop 3: high latency
        let highLatProbes = probeSequence(hop: 3, count: 30,
                                          latencyRange: 80...120,
                                          address: "10.0.0.3")
        hops[2] = hopData(hop: 3, probes: highLatProbes, address: "10.0.0.3",
                          hostname: "slow.example.com")
        // Hop 5: packet loss
        let lossyProbes = probeSequenceWithLoss(hop: 5, count: 30, latencyMs: 25,
                                                 lossPercent: 30, address: "10.0.0.5")
        hops[4] = hopData(hop: 5, probes: lossyProbes, address: "10.0.0.5",
                          hostname: "lossy.example.com")
        return hops
    }

    // MARK: - BandwidthSample factories

    static func bandwidthSamples(count: Int, downloadRange: ClosedRange<Double>,
                                  uploadRange: ClosedRange<Double>,
                                  historySeconds: Double = 180) -> [BandwidthSample] {
        let dlMid = (downloadRange.lowerBound + downloadRange.upperBound) / 2.0
        let dlAmp = (downloadRange.upperBound - downloadRange.lowerBound) / 2.0
        let ulMid = (uploadRange.lowerBound + uploadRange.upperBound) / 2.0
        let ulAmp = (uploadRange.upperBound - uploadRange.lowerBound) / 2.0

        return (0..<count).map { i in
            let t = Double(i) / Double(max(count - 1, 1))
            // Varied bandwidth with bursty pattern
            let dlWave = sin(t * .pi * 3.0) * 0.6 + sin(t * .pi * 8.0) * 0.3
            let ulWave = sin(t * .pi * 5.0 + 1.0) * 0.5 + sin(t * .pi * 13.0) * 0.2
            let dl = max(downloadRange.lowerBound, min(downloadRange.upperBound, dlMid + dlAmp * dlWave))
            let ul = max(uploadRange.lowerBound, min(uploadRange.upperBound, ulMid + ulAmp * ulWave))
            let secondsAgo = historySeconds * (1.0 - t)
            return BandwidthSample(
                timestamp: referenceDate.addingTimeInterval(-secondsAgo),
                downloadBytesPerSec: dl,
                uploadBytesPerSec: ul,
                interfaceName: "en0"
            )
        }
    }

    static func idleBandwidth(count: Int = 30) -> [BandwidthSample] {
        bandwidthSamples(count: count, downloadRange: 0...0, uploadRange: 0...0)
    }

    static func asymmetricBandwidth(count: Int = 30) -> [BandwidthSample] {
        bandwidthSamples(count: count,
                          downloadRange: 5_000_000...10_000_000,
                          uploadRange: 100_000...500_000)
    }
}
