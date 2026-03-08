import SwiftUI

struct BandwidthSparklineView: View {
    let samples: [BandwidthSample]
    let now: Date
    let historyMinutes: Double
    let colorScheme: HeatmapColorScheme

    /// The current Y scale (bytes/sec) so the parent can display labels.
    var yScale: Double {
        let totalSeconds = historyMinutes * 60
        let windowStart = Date().addingTimeInterval(-totalSeconds)
        let visible: [BandwidthSample] = samples.filter { $0.timestamp >= windowStart }
        let maxValue = max(
            visible.map(\.downloadBytesPerSec).max() ?? 0,
            visible.map(\.uploadBytesPerSec).max() ?? 0,
            1
        )
        return Self.steppedScale(for: maxValue)
    }

    var body: some View {
        Canvas { context, size in
            let totalSeconds = historyMinutes * 60
            let windowStart = now.addingTimeInterval(-totalSeconds)

            let visible = samples.filter { $0.timestamp >= windowStart }
            guard !visible.isEmpty else { return }

            let midY = size.height / 2

            let maxValue = max(
                visible.map(\.downloadBytesPerSec).max() ?? 0,
                visible.map(\.uploadBytesPerSec).max() ?? 0,
                1
            )
            let scale = Self.steppedScale(for: maxValue)
            let halfHeight = midY

            // Dashed center baseline
            let dashLength: CGFloat = 3
            let gapLength: CGFloat = 3
            var dashX: CGFloat = 0
            while dashX < size.width {
                let segEnd = min(dashX + dashLength, size.width)
                var dash = Path()
                dash.move(to: CGPoint(x: dashX, y: midY))
                dash.addLine(to: CGPoint(x: segEnd, y: midY))
                context.stroke(dash, with: .color(.primary.opacity(0.15)), lineWidth: 0.5)
                dashX = segEnd + gapLength
            }

            func xFor(_ timestamp: Date) -> CGFloat {
                let age = now.timeIntervalSince(timestamp)
                let fraction = 1.0 - age / totalSeconds
                return CGFloat(fraction) * size.width
            }

            for (i, sample) in visible.enumerated() {
                let x = xFor(sample.timestamp)

                let nextX: CGFloat
                if i + 1 < visible.count {
                    nextX = xFor(visible[i + 1].timestamp)
                } else {
                    nextX = size.width
                }

                let barWidth = nextX - x
                guard barWidth > 0 else { continue }

                if sample.uploadBytesPerSec > 0 {
                    let h = CGFloat(sample.uploadBytesPerSec / scale) * halfHeight
                    let rect = CGRect(x: x, y: midY - h, width: barWidth + 0.5, height: h)
                    context.fill(Path(rect), with: .color(colorScheme.uploadColor))
                }

                if sample.downloadBytesPerSec > 0 {
                    let h = CGFloat(sample.downloadBytesPerSec / scale) * halfHeight
                    let rect = CGRect(x: x, y: midY, width: barWidth + 0.5, height: h)
                    context.fill(Path(rect), with: .color(colorScheme.downloadColor))
                }
            }
        }
        .frame(height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }

    /// Stepped Y-axis thresholds. Finer steps at low bandwidth so bars
    /// remain visible even at single-digit KB/s.
    static func steppedScale(for maxValue: Double) -> Double {
        let steps: [Double] = [
            256,                //  256 B/s
            512,                //  512 B/s
            1_024,              //    1 KB/s
            2_048,              //    2 KB/s
            5_120,              //    5 KB/s
            10_240,             //   10 KB/s
            25_600,             //   25 KB/s
            51_200,             //   50 KB/s
            102_400,            //  100 KB/s
            256_000,            //  250 KB/s
            512_000,            //  500 KB/s
            1_048_576,          //    1 MB/s
            2_621_440,          //  2.5 MB/s
            5_242_880,          //    5 MB/s
            10_485_760,         //   10 MB/s
            26_214_400,         //   25 MB/s
            52_428_800,         //   50 MB/s
            104_857_600,        //  100 MB/s
            524_288_000,        //  500 MB/s
            1_073_741_824       //    1 GB/s
        ]
        return steps.first { $0 >= maxValue } ?? maxValue
    }

    /// Format a byte/sec scale value as a short label (e.g. "5 KB/s").
    static func formatScale(_ bytesPerSec: Double) -> String {
        switch bytesPerSec {
        case ..<1_024:
            return String(format: "%.0f B/s", bytesPerSec)
        case ..<1_048_576:
            let kb = bytesPerSec / 1_024
            return kb == kb.rounded() ? String(format: "%.0f KB/s", kb) : String(format: "%.1f KB/s", kb)
        case ..<1_073_741_824:
            let mb = bytesPerSec / 1_048_576
            return mb == mb.rounded() ? String(format: "%.0f MB/s", mb) : String(format: "%.1f MB/s", mb)
        default:
            return String(format: "%.1f GB/s", bytesPerSec / 1_073_741_824)
        }
    }
}
