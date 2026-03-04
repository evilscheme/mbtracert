import SwiftUI

struct TraceroutePanel: View {
    @ObservedObject var viewModel: TracerouteViewModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.targetHost)
                        .font(.headline)
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Spacer()

                if let lastHop = viewModel.hops.last(where: { $0.lastLatencyMs > 0 }) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(String(format: "%.0fms", lastHop.lastLatencyMs))
                            .font(.system(.title3, design: .monospaced))
                            .foregroundStyle(viewModel.colorScheme.color(for: lastHop.lastLatencyMs))
                        if lastHop.avgLatencyMs > 0 {
                            Text(String(format: "avg %.0fms", lastHop.avgLatencyMs))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Column headers
            HStack(spacing: 6) {
                Text("#")
                    .frame(width: 20, alignment: .trailing)
                Text("Host")
                    .frame(width: 130, alignment: .leading)
                Text("Last")
                    .frame(width: 38, alignment: .trailing)
                Text("Avg")
                    .frame(width: 38, alignment: .trailing)
                Text("Loss")
                    .frame(width: 28, alignment: .trailing)
                Text("History")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            // Hop rows
            if viewModel.hops.isEmpty && !viewModel.isProbing {
                Text(viewModel.helperInstalled ? "Waiting for first probe..." : "Helper not installed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.hops) { hop in
                            HopRowView(hop: hop, historyMinutes: viewModel.historyMinutes, activeInterval: viewModel.activeInterval, colorScheme: viewModel.colorScheme)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }

            Divider()

            // Footer
            HStack {
                Button(action: {
                    NSApp.activate()
                    openSettings()
                }) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")

                Spacer()

                Button(action: {
                    viewModel.clearHistory()
                }) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Reset historical data")

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: 494)
    }
}
