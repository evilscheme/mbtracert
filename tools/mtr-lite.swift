/// mtr-lite: lightweight continuous traceroute CLI
/// Compiles against the real ICMPEngine.swift — no code duplication.
///
/// Build:
///   cd tools && swiftc -O -o mtr-lite mtr-lite.swift \
///     ../TraceBar/TraceBar/ICMPEngine.swift
///
/// Run:
///   sudo ./mtr-lite <host> [maxHops] [interval]

import Foundation
import Darwin

// MARK: - Per-Hop Statistics

struct HopStats {
    var address: String = ""
    var sent: Int = 0
    var received: Int = 0
    var totalMs: Double = 0
    var lastMs: Double = -1
    var bestMs: Double = .greatestFiniteMagnitude
    var worstMs: Double = 0

    var loss: Double { sent > 0 ? Double(sent - received) / Double(sent) * 100 : 0 }
    var avg: Double { received > 0 ? totalMs / Double(received) : -1 }

    mutating func record(address: String, latencyMs: Double) {
        sent += 1
        if !address.isEmpty && latencyMs >= 0 {
            if self.address.isEmpty { self.address = address }
            received += 1
            totalMs += latencyMs
            lastMs = latencyMs
            bestMs = min(bestMs, latencyMs)
            worstMs = max(worstMs, latencyMs)
        }
    }

    mutating func recordTimeout() {
        sent += 1
        lastMs = -1
    }
}

// MARK: - Display

func clearScreen() {
    print("\u{1B}[2J\u{1B}[H", terminator: "")
}

func moveCursor(row: Int, col: Int) {
    print("\u{1B}[\(row);\(col)H", terminator: "")
}

func padR(_ s: String, _ w: Int) -> String { s.count >= w ? s : s + String(repeating: " ", count: w - s.count) }
func padL(_ s: String, _ w: Int) -> String { s.count >= w ? s : String(repeating: " ", count: w - s.count) + s }

func renderDisplay(host: String, stats: [HopStats], roundCount: Int, destHop: Int) {
    moveCursor(row: 1, col: 1)

    let header = "mtr-lite: \(host)"
    let probes = "Probes: \(roundCount)"
    let gap = max(1, 72 - header.count - probes.count)
    print("\u{1B}[1m\(header)\(String(repeating: " ", count: gap))\(probes)\u{1B}[0m")
    print()

    print("\(padR("Hop", 4)) \(padR("Host", 38)) \(padL("Avg", 7)) \(padL("Best", 7)) \(padL("Wrst", 7)) \(padL("Last", 7)) \(padL("Loss", 6))")

    for i in 0..<destHop {
        let s = stats[i]
        let hopNum = padR("\(i + 1)", 4)
        let addr = padR(s.address.isEmpty ? "???" : s.address, 38)
        let avg = padL(s.avg >= 0 ? String(format: "%.1fms", s.avg) : "---", 7)
        let best = padL(s.bestMs < .greatestFiniteMagnitude ? String(format: "%.1fms", s.bestMs) : "---", 7)
        let wrst = padL(s.worstMs > 0 ? String(format: "%.1fms", s.worstMs) : "---", 7)
        let last = padL(s.lastMs >= 0 ? String(format: "%.1fms", s.lastMs) : "---", 7)
        let lossPct = padL(s.sent > 0 ? String(format: "%.0f%%", s.loss) : "---", 6)

        // Color loss: green=0%, yellow=1-20%, red=>20%
        let lossColor: String
        if s.loss == 0 { lossColor = "\u{1B}[32m" }
        else if s.loss <= 20 { lossColor = "\u{1B}[33m" }
        else { lossColor = "\u{1B}[31m" }

        print("\(hopNum) \(addr) \(avg) \(best) \(wrst) \(last) \(lossColor)\(lossPct)\u{1B}[0m")
    }

    // Clear any stale lines below
    print("\u{1B}[J", terminator: "")
    fflush(stdout)
}

// MARK: - Signal Handling

nonisolated(unsafe) var keepRunning = true

func handleSignal(_ sig: Int32) {
    keepRunning = false
}

// MARK: - Entry Point

@main struct MtrLite {
    static func main() {
        signal(SIGINT, handleSignal)
        signal(SIGTERM, handleSignal)

        let args = CommandLine.arguments
        guard args.count >= 2 else {
            print("Usage: sudo \(args[0]) <host> [maxHops=30] [intervalSec=1.0]")
            Foundation.exit(1)
        }

        let host = args[1]
        let maxHops = args.count >= 3 ? Int(args[2]) ?? 30 : 30
        let interval = args.count >= 4 ? Double(args[3]) ?? 1.0 : 1.0

        let engine = ICMPEngine()
        var stats = [HopStats](repeating: HopStats(), count: maxHops)
        var roundCount = 0
        var displayHops = 1  // grows as we discover more hops

        clearScreen()
        print("mtr-lite: resolving \(host)...")

        while keepRunning {
            let results = engine.probeRound(host: host, maxHops: maxHops).hops
            roundCount += 1

            // Update per-hop stats
            for result in results {
                let idx = result.hop - 1
                guard idx >= 0 && idx < maxHops else { continue }
                if result.latencyMs >= 0 {
                    stats[idx].record(address: result.address, latencyMs: result.latencyMs)
                } else {
                    stats[idx].recordTimeout()
                }
            }

            // Track the highest hop that ever responded
            let lastResponding = stats.prefix(maxHops).lastIndex(where: { $0.received > 0 }) ?? 0
            displayHops = max(displayHops, min(results.count, lastResponding + 2))

            renderDisplay(host: host, stats: stats, roundCount: roundCount, destHop: displayHops)

            // Sleep in small increments so Ctrl+C is responsive
            let deadline = Date().addingTimeInterval(interval)
            while keepRunning && Date() < deadline {
                usleep(100_000)  // 100ms
            }
        }

        // Restore terminal
        print("\n\u{1B}[0m")
        print("Stopped after \(roundCount) rounds.")
    }
}
