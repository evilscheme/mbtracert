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
                            .foregroundStyle(.secondary)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(viewModel.colorScheme.color(for: lastHop.lastLatencyMs))
                                    .frame(height: 2)
                                    .offset(y: 1)
                            }
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

            #if compiler(>=6.2)
            if #available(macOS 26, *) {
                // macOS 26+: use safeAreaInset for scroll edge effects on column
                // headers and footer; dividers are replaced by the edge effect.
                hopList
                    .safeAreaInset(edge: .top, spacing: 0) {
                        columnHeaders
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        footer
                    }
            } else {
                columnHeaders
                Divider()
                hopList
                Divider()
                footer
            }
            #else
            columnHeaders
            Divider()
            hopList
            Divider()
            footer
            #endif
        }
        .frame(width: 600)
    }

    private var columnHeaders: some View {
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
    }

    @ViewBuilder
    private var hopList: some View {
        if viewModel.visibleHops.isEmpty && !viewModel.isProbing {
            Text("Waiting for first probe...")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.visibleHops) { hop in
                        HopRowView(hop: hop, historyMinutes: viewModel.historyMinutes, activeInterval: viewModel.activeInterval, colorScheme: viewModel.colorScheme)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
    }

    private var footer: some View {
        HStack {
            Button(action: {
                NSApp.activate()
                openSettings()
            }) {
                Image(systemName: "gearshape")
            }
            .preferringGlassStyle()
            .help("Settings")

            Spacer()

            Button(action: {
                viewModel.clearHistory()
            }) {
                Image(systemName: "trash")
            }
            .preferringGlassStyle()
            .help("Reset historical data")

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .preferringGlassStyle()
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

private extension View {
    @ViewBuilder
    func preferringGlassStyle() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.borderless)
        }
        #else
        self.buttonStyle(.borderless)
        #endif
    }
}
