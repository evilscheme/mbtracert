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
            SparklineLabel(dataPoints: viewModel.latencyHistory)
                .task { viewModel.start() }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}
