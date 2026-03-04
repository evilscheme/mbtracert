import SwiftUI

@main
struct MenubarTracertApp: App {
    @StateObject private var viewModel = TracerouteViewModel()

    var body: some Scene {
        MenuBarExtra {
            TraceroutePanel(viewModel: viewModel)
                .onAppear { viewModel.panelDidOpen() }
                .onDisappear { viewModel.panelDidClose() }
        } label: {
            HStack(spacing: 2) {
                if let last = viewModel.latencyHistory.last {
                    Text(String(format: "%3.0fms", last))
                        .font(.init(NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)))
                        .foregroundStyle(viewModel.colorScheme.color(for: last))
                } else {
                    Text(" --ms")
                        .font(.init(NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)))
                        .foregroundStyle(.secondary)
                }
                if viewModel.latencyHistory.count >= 2 {
                    SparklineLabel(dataPoints: viewModel.latencyHistory, colorScheme: viewModel.colorScheme)
                }
            }
            .task { viewModel.start() }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}
