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
                dataPoints: viewModel.latencyHistory,
                colorScheme: viewModel.colorScheme,
                latencyThreshold: viewModel.latencyThreshold,
                showBackground: viewModel.showSparklineBackground,
                latencyMs: viewModel.latencyHistory.last
            )
            .task { viewModel.start() }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}
