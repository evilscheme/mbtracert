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
        .frame(width: 420, height: 260)
    }
}

private struct GeneralTab: View {
    @ObservedObject var viewModel: TracerouteViewModel
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Form {
            TextField("Target Host:", text: $viewModel.targetHost)

            Toggle("Resolve DNS Names", isOn: $viewModel.resolveHostnames)

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

            LabeledContent("Helper Status") {
                Text(viewModel.helperInstalled ? "Installed" : "Not Installed")
                    .foregroundStyle(viewModel.helperInstalled ? .green : .red)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct NetworkTab: View {
    @ObservedObject var viewModel: TracerouteViewModel

    var body: some View {
        Form {
            LabeledContent("Idle Probe Interval") {
                HStack {
                    Slider(value: $viewModel.idleInterval, in: 2...30, step: 1)
                    Text("\(Int(viewModel.idleInterval))s")
                        .monospacedDigit()
                        .frame(width: 30)
                }
            }

            LabeledContent("Active Probe Interval") {
                HStack {
                    Slider(value: $viewModel.activeInterval, in: 0.5...5, step: 0.5)
                    Text(String(format: "%.1fs", viewModel.activeInterval))
                        .monospacedDigit()
                        .frame(width: 30)
                }
            }

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
        .formStyle(.grouped)
        .padding()
    }
}
