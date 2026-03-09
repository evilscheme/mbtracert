/// icmp-probe: machine-readable ICMP probe tool
/// Compiles against the real ICMPEngine.swift — no code duplication.
///
/// Build:
///   cd tools && swiftc -O -o icmp-probe icmp-probe.swift \
///     ../TraceBar/TraceBar/Services/ICMPEngine.swift
///
/// Run:
///   ./icmp-probe <host> [--rounds 3] [--max-hops 30] [--interval 1.0]

import Foundation
import Darwin

// MARK: - Argument Parsing

struct Config {
    var host: String = ""
    var rounds: Int = 3
    var maxHops: Int = 30
    var interval: Double = 1.0
}

func parseArgs() -> Config? {
    let args = CommandLine.arguments
    guard args.count >= 2 else { return nil }

    var config = Config()
    config.host = args[1]

    var i = 2
    while i < args.count {
        switch args[i] {
        case "--rounds":
            i += 1
            guard i < args.count, let v = Int(args[i]) else { return nil }
            config.rounds = v
        case "--max-hops":
            i += 1
            guard i < args.count, let v = Int(args[i]) else { return nil }
            config.maxHops = v
        case "--interval":
            i += 1
            guard i < args.count, let v = Double(args[i]) else { return nil }
            config.interval = v
        default:
            return nil
        }
        i += 1
    }
    return config
}

// MARK: - JSON Output

func jsonString(_ s: String) -> String {
    "\"\(s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
}

func hopToJSON(_ hop: HopResult) -> String {
    let typeStr = hop.icmpType.map { "\($0)" } ?? "null"
    let codeStr = hop.icmpCode.map { "\($0)" } ?? "null"
    return "{\"hop\":\(hop.hop),\"address\":\(jsonString(hop.address)),\"latency_ms\":\(String(format: "%.3f", hop.latencyMs)),\"icmp_type\":\(typeStr),\"icmp_code\":\(codeStr)}"
}

func roundToJSON(host: String, round: Int, result: ProbeRoundResult) -> String {
    let ts = ISO8601DateFormatter().string(from: Date())
    let hopsJSON = result.hops.map { hopToJSON($0) }.joined(separator: ",")
    let destReached = result.destinationHop > 0
    return "{\"host\":\(jsonString(host)),\"round\":\(round),\"timestamp\":\(jsonString(ts)),\"destination_hop\":\(result.destinationHop),\"destination_reached\":\(destReached),\"hops\":[\(hopsJSON)]}"
}

// MARK: - Entry Point

@main struct ICMPProbe {
    static func main() {
        guard let config = parseArgs() else {
            let name = CommandLine.arguments[0]
            fputs("Usage: \(name) <host> [--rounds 3] [--max-hops 30] [--interval 1.0]\n", stderr)
            Foundation.exit(1)
        }

        let engine = ICMPEngine()

        for round in 1...config.rounds {
            let result = engine.probeRound(host: config.host, maxHops: config.maxHops)
            print(roundToJSON(host: config.host, round: round, result: result))
            fflush(stdout)
            if round < config.rounds {
                usleep(UInt32(config.interval * 1_000_000))
            }
        }
    }
}
