import SwiftUI

@main
struct TraceBarApp: App {
    @StateObject private var viewModel = TracerouteViewModel()
    @AppStorage("menubarChartMode") private var menubarChartModeName: String = ChartMode.sparkline.rawValue
    @AppStorage("compactMenubar") private var compactMenubar = false

    private var menubarChartMode: ChartMode {
        ChartMode(rawValue: menubarChartModeName) ?? .sparkline
    }

    var body: some Scene {
        MenuBarExtra {
            DetailViewPanel(viewModel: viewModel)
                .onAppear {
                    if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
                        menubarChartModeName = menubarChartMode.next.rawValue
                    }
                    viewModel.panelDidOpen()
                }
                .onDisappear { viewModel.panelDidClose() }
        } label: {
            // Anchor `now` to the latest probe's timestamp rather than
            // Date.now so MenuBarView's inputs are stable between probe
            // rounds. Combined with Equatable + `.equatable()` this lets
            // SwiftUI skip the expensive ImageRenderer rasterization when
            // nothing relevant has actually changed — otherwise every
            // @Published emit from the view model (many per round) caused
            // the menubar bitmap to be regenerated.
            let chartHop = viewModel.destinationChartHop
            MenuBarView(
                probes: chartHop?.probes.elements ?? [],
                now: chartHop?.probes.last?.timestamp ?? .distantPast,
                historyMinutes: viewModel.historyMinutes,
                colorScheme: viewModel.colorScheme,
                latencyThreshold: viewModel.latencyThreshold,
                chartMode: menubarChartMode,
                showBackground: viewModel.showMenuBarBackground,
                compactMenubar: compactMenubar,
                latencyMs: {
                    guard let ms = viewModel.destinationLatencyHop?.lastLatencyMs, ms > 0 else { return nil }
                    return ms
                }()
            )
            .equatable()
            .task { viewModel.start() }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}
