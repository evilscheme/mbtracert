import SwiftUI

@main
struct TraceBarApp: App {
    @StateObject private var viewModel = TracerouteViewModel()
    @AppStorage("menubarChartMode") private var menubarChartModeName: String = ChartMode.sparkline.rawValue

    private var menubarChartMode: ChartMode {
        ChartMode(rawValue: menubarChartModeName) ?? .sparkline
    }

    var body: some Scene {
        MenuBarExtra {
            TraceroutePanel(viewModel: viewModel)
                .onAppear {
                    if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
                        menubarChartModeName = menubarChartMode.next.rawValue
                    }
                    viewModel.panelDidOpen()
                }
                .onDisappear { viewModel.panelDidClose() }
        } label: {
            SparklineLabel(
                probes: viewModel.destinationLatencyHop?.probes.elements ?? [],
                now: Date(),
                historyMinutes: viewModel.historyMinutes,
                colorScheme: viewModel.colorScheme,
                latencyThreshold: viewModel.latencyThreshold,
                chartMode: menubarChartMode,
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
