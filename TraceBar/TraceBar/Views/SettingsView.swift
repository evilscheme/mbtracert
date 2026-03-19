import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var viewModel: TracerouteViewModel

    var body: some View {
        TabView {
            GeneralTab(viewModel: viewModel)
                .tabItem { Label("General", systemImage: "gear") }

            AppearanceTab(viewModel: viewModel)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            NetworkTab(viewModel: viewModel)
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .background(WindowConfigurator())
    }
}

/// Window identifier used to locate the settings window from other views.
let settingsWindowID = NSUserInterfaceItemIdentifier("TraceBarSettings")

/// Invisible NSViewRepresentable that configures the hosting window to follow the user
/// across Spaces and tags it so the settings-open action can find it reliably.
private struct WindowConfigurator: NSViewRepresentable {

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.identifier = settingsWindowID
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct GeneralTab: View {
    @ObservedObject var viewModel: TracerouteViewModel
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @State private var editingHost: String = ""

    var body: some View {
        Form {
            Section {
                TextField("Target Host:", text: $editingHost)
                    .onAppear { editingHost = viewModel.targetHost }
                    .onSubmit { commitHost() }
                    .onChange(of: viewModel.targetHost) {
                        editingHost = viewModel.targetHost
                    }
                    .help("IP address or hostname to trace the route to")

                Toggle("Resolve DNS Names", isOn: $viewModel.resolveHostnames)
                    .onChange(of: viewModel.resolveHostnames) {
                        viewModel.refreshHostnames()
                    }
                    .help("Look up hostnames for each hop's IP address")
            }

            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .help("Automatically start when you log in")
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !enabled
                        }
                    }

                LabeledContent("Version") {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .onDisappear { commitHost() }
    }

    private func commitHost() {
        let trimmed = editingHost.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != viewModel.targetHost else { return }
        viewModel.targetHost = trimmed
        viewModel.clearHistory()
        viewModel.rescheduleProbing()
    }
}

private struct AppearanceTab: View {
    @ObservedObject var viewModel: TracerouteViewModel
    @AppStorage("compactMenubar") private var compactMenubar = false
    @AppStorage("menubarChartMode") private var menubarChartModeName: String = ChartMode.sparkline.rawValue
    @AppStorage("chartMode") private var detailChartModeName: String = ChartMode.heatmap.rawValue

    private var menubarChartMode: Binding<ChartMode> {
        Binding(
            get: { ChartMode(rawValue: menubarChartModeName) ?? .sparkline },
            set: { menubarChartModeName = $0.rawValue }
        )
    }

    private var detailChartMode: Binding<ChartMode> {
        Binding(
            get: { ChartMode(rawValue: detailChartModeName) ?? .sparkline },
            set: { detailChartModeName = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Color Scheme", selection: $viewModel.colorSchemeName) {
                    ForEach(ColorTheme.allCases) { scheme in
                        Text(scheme.displayName).tag(scheme.rawValue)
                    }
                }
                .help("Color gradient used to visualize latency")

                Canvas { context, size in
                    let scheme = viewModel.colorScheme
                    let maxMs = viewModel.latencyThreshold
                    let steps = Int(size.width)
                    for x in 0..<steps {
                        let ms = Double(x) / Double(steps) * maxMs
                        let rect = CGRect(x: CGFloat(x), y: 0, width: 1.5, height: size.height)
                        context.fill(Path(rect), with: .color(scheme.color(for: ms, maxMs: maxMs)))
                    }
                }
                .frame(height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            Section {
                Picker("Menubar Chart", selection: menubarChartMode) {
                    ForEach(ChartMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .help("Chart style shown in the menubar")

                Picker("Detail Chart", selection: detailChartMode) {
                    ForEach(ChartMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .help("Chart style shown in the detail panel for each hop")

                Toggle("Compact menubar", isOn: $compactMenubar)
                    .help("Stack chart and latency vertically to save menubar space")

                Toggle("Menubar background", isOn: $viewModel.showMenuBarBackground)
                    .help("Show a solid color behind the menubar chart for better visibility")

                Toggle("Show interface bandwidth", isOn: $viewModel.showBandwidth)
                    .help("Display upload/download rates for the active network interface")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

private struct NetworkTab: View {
    @ObservedObject var viewModel: TracerouteViewModel

    var body: some View {
        Form {
            Section("Probe Intervals") {
                LabeledContent("Idle") {
                    HStack {
                        Slider(value: snapping($viewModel.idleInterval, step: 1), in: 2...30)
                        Text("\(Int(viewModel.idleInterval))s")
                            .monospacedDigit()
                            .frame(width: 30)
                    }
                }
                .help("Seconds between probes when the panel is closed")
                .onChange(of: viewModel.idleInterval) {
                    viewModel.rescheduleProbing()
                }

                LabeledContent("Active") {
                    HStack {
                        Slider(value: snapping($viewModel.activeInterval, step: 0.5), in: 1...5)
                        Text(String(format: "%.1fs", viewModel.activeInterval))
                            .monospacedDigit()
                            .frame(width: 30)
                    }
                }
                .help("Seconds between probes when the panel is open")
                .onChange(of: viewModel.activeInterval) {
                    viewModel.rescheduleProbing()
                }
            }

            Section("Thresholds") {
                LabeledContent("Latency Scale") {
                    HStack {
                        Slider(value: snapping($viewModel.latencyThreshold, step: 10), in: 20...500)
                        Text("\(Int(viewModel.latencyThreshold)) ms")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                .help("Latency at the \"worst\" end of the color scale — lower values make the colors more sensitive")
            }

            Section("Limits") {
                LabeledContent("History Window") {
                    HStack {
                        Slider(value: snapping($viewModel.historyMinutes, step: 1), in: 2...15)
                        Text("\(Int(viewModel.historyMinutes))m")
                            .monospacedDigit()
                            .frame(width: 30)
                    }
                }
                .help("How far back to keep probe data in the heatmap")

                LabeledContent("Max Hops") {
                    HStack {
                        Slider(value: snapping(Binding(
                            get: { Double(viewModel.maxHops) },
                            set: { viewModel.maxHops = Int($0) }
                        ), step: 1), in: 10...64)
                        Text("\(viewModel.maxHops)")
                            .monospacedDigit()
                            .frame(width: 30)
                    }
                }
                .help("Maximum number of network hops to trace")
            }
        }
        .formStyle(.grouped)
    }
}

/// Returns a binding that rounds to the nearest step, eliminating slider tick marks
/// while preserving discrete value snapping.
private func snapping(_ binding: Binding<Double>, step: Double) -> Binding<Double> {
    Binding(
        get: { binding.wrappedValue },
        set: { binding.wrappedValue = (($0 / step).rounded() * step) }
    )
}
