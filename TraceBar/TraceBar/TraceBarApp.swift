import SwiftUI

@main
struct TraceBarApp: App {
    @StateObject private var viewModel = TracerouteViewModel()

    var body: some Scene {
        MenuBarExtra {
            TraceroutePanel(viewModel: viewModel)
                .onAppear { viewModel.panelDidOpen() }
                .onDisappear { viewModel.panelDidClose() }
        } label: {
            SparklineLabel(
                probes: viewModel.destinationLatencyHop?.probes.elements ?? [],
                now: Date(),
                historyMinutes: viewModel.historyMinutes,
                colorScheme: viewModel.colorScheme,
                latencyThreshold: viewModel.latencyThreshold,
                showBackground: viewModel.showSparklineBackground,
                latencyMs: {
                    guard let ms = viewModel.destinationLatencyHop?.lastLatencyMs, ms > 0 else { return nil }
                    return ms
                }()
            )
            .task { viewModel.start() }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}
