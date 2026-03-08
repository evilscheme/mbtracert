import Foundation

struct BandwidthSample {
    let timestamp: Date
    let downloadBytesPerSec: Double
    let uploadBytesPerSec: Double
    let interfaceName: String

    var downloadFormatted: String { Self.format(downloadBytesPerSec) }
    var uploadFormatted: String { Self.format(uploadBytesPerSec) }

    static func format(_ bytesPerSec: Double) -> String {
        switch bytesPerSec {
        case ..<1_024:
            return String(format: "%.0f B/s", bytesPerSec)
        case ..<1_048_576:
            return String(format: "%.1f KB/s", bytesPerSec / 1_024)
        case ..<1_073_741_824:
            return String(format: "%.1f MB/s", bytesPerSec / 1_048_576)
        default:
            return String(format: "%.2f GB/s", bytesPerSec / 1_073_741_824)
        }
    }
}
