import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var viewModel: TracerouteViewModel

    var body: some View {
        TabView {
            GeneralTab(viewModel: viewModel)
                .tabItem { Label("General", systemImage: "gear") }

            NetworkTab(viewModel: viewModel)
                .tabItem { Label("Network", systemImage: "network") }
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
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

                Toggle("Resolve DNS Names", isOn: $viewModel.resolveHostnames)
                    .onChange(of: viewModel.resolveHostnames) {
                        viewModel.refreshHostnames()
                    }
            }

            Section {
                Picker("Color Scheme", selection: $viewModel.colorSchemeName) {
                    ForEach(HeatmapColorScheme.allCases) { scheme in
                        Text(scheme.displayName).tag(scheme.rawValue)
                    }
                }

                Canvas { context, size in
                    let scheme = viewModel.colorScheme
                    let steps = Int(size.width)
                    for x in 0..<steps {
                        let ms = Double(x) / Double(steps) * 100.0
                        let rect = CGRect(x: CGFloat(x), y: 0, width: 1.5, height: size.height)
                        context.fill(Path(rect), with: .color(scheme.color(for: ms)))
                    }
                }
                .frame(height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
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
    }
}

private struct NetworkTab: View {
    @ObservedObject var viewModel: TracerouteViewModel

    var body: some View {
        Form {
            Section("Probe Intervals") {
                LabeledContent("Idle") {
                    HStack {
                        Slider(value: $viewModel.idleInterval, in: 2...30, step: 1)
                        Text("\(Int(viewModel.idleInterval))s")
                            .monospacedDigit()
                            .frame(width: 30)
                    }
                }
                .onChange(of: viewModel.idleInterval) {
                    viewModel.rescheduleProbing()
                }

                LabeledContent("Active") {
                    HStack {
                        Slider(value: $viewModel.activeInterval, in: 0.5...5, step: 0.5)
                        Text(String(format: "%.1fs", viewModel.activeInterval))
                            .monospacedDigit()
                            .frame(width: 30)
                    }
                }
                .onChange(of: viewModel.activeInterval) {
                    viewModel.rescheduleProbing()
                }
            }

            Section("Limits") {
                LabeledContent("History Window") {
                    HStack {
                        Slider(value: $viewModel.historyMinutes, in: 2...15, step: 1)
                        Text("\(Int(viewModel.historyMinutes))m")
                            .monospacedDigit()
                            .frame(width: 30)
                    }
                }

                LabeledContent("Max Hops") {
                    HStack {
                        Slider(value: Binding(
                            get: { Double(viewModel.maxHops) },
                            set: { viewModel.maxHops = Int($0) }
                        ), in: 10...64, step: 1)
                        Text("\(viewModel.maxHops)")
                            .monospacedDigit()
                            .frame(width: 30)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}
