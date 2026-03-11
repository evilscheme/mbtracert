import SwiftUI

enum ChartMode: String, CaseIterable, Identifiable {
    var id: String { rawValue }

    case sparkline
    case heatmap
    case bars

    var displayName: String {
        switch self {
        case .sparkline: return "Sparkline"
        case .heatmap:   return "Heatmap"
        case .bars:      return "Bars"
        }
    }

    var systemImage: String {
        switch self {
        case .sparkline: return "chart.line.uptrend.xyaxis"
        case .heatmap:   return "chart.bar.fill"
        case .bars:      return "chart.bar.xaxis"
        }
    }

    var next: ChartMode {
        let all = ChartMode.allCases
        let idx = all.firstIndex(of: self)!
        return all[(idx + 1) % all.count]
    }

    @ViewBuilder
    func chartView(probes: [ProbeResult], now: Date, historyMinutes: Double, colorScheme: HeatmapColorScheme, latencyThreshold: Double) -> some View {
        switch self {
        case .sparkline:
            SparklineChart(probes: probes, now: now, historyMinutes: historyMinutes, colorScheme: colorScheme, latencyThreshold: latencyThreshold)
        case .heatmap:
            HeatmapChart(probes: probes, now: now, historyMinutes: historyMinutes, colorScheme: colorScheme, latencyThreshold: latencyThreshold)
        case .bars:
            VerticalBarsChart(probes: probes, now: now, historyMinutes: historyMinutes, colorScheme: colorScheme, latencyThreshold: latencyThreshold)
        }
    }
}

// MARK: - Shared latency chart protocol

protocol LatencyChart: View {
    var probes: [ProbeResult] { get }
    var now: Date { get }
    var historyMinutes: Double { get }
    var colorScheme: HeatmapColorScheme { get }
    var latencyThreshold: Double { get }
}

extension LatencyChart {
    var totalSeconds: Double { historyMinutes * 60 }
    var windowStart: Date { now.addingTimeInterval(-totalSeconds) }
    var visibleProbes: [ProbeResult] { probes.filter { $0.timestamp >= windowStart } }

    func latencyYScale(for visible: [ProbeResult]) -> Double {
        let maxLatency = visible.filter { !$0.isTimeout }.map(\.latencyMs).max() ?? 10
        let steps: [Double] = [50, 100, 200, 500, 1000]
        return steps.first { $0 >= maxLatency } ?? maxLatency
    }

    func xPosition(for timestamp: Date, in width: CGFloat, inset: CGFloat = 0) -> CGFloat {
        let age = now.timeIntervalSince(timestamp)
        let fraction = 1.0 - age / totalSeconds
        return inset + CGFloat(fraction) * (width - inset * 2)
    }

    func nextX(after index: Int, in visible: [ProbeResult], width: CGFloat) -> CGFloat {
        if index + 1 < visible.count {
            return xPosition(for: visible[index + 1].timestamp, in: width)
        }
        return width
    }
}
