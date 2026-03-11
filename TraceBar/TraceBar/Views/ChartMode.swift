import SwiftUI

enum ChartMode: String, CaseIterable {
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
}
