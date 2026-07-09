import SwiftUI
import UniformTypeIdentifiers

/// Native Settings window (spec §32). Power controls appear here too but the
/// sidebar/dashboard remain the primary surfaces.
public struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env

    public init() {}

    public var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppleContainerSettingsTab()
                .tabItem { Label("Apple Container", systemImage: "shippingbox") }
            TerminalSettingsTab()
                .tabItem { Label("Terminal", systemImage: "terminal") }
            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            ResourcesSettingsTab()
                .tabItem { Label("Resources", systemImage: "chart.xyaxis.line") }
            AdvancedSettingsTab()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 560)
        .scenePadding()
    }
}

private struct GeneralSettingsTab: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var settings = env.settings
        Form {
            Toggle("Turn on Apple Container when ContainerDeck launches", isOn: $settings.autoStartOnLaunch)
            Toggle("Confirm before turning off Apple Container", isOn: $settings.confirmBeforeStopping)
            Toggle("Show menu-bar item", isOn: $settings.showMenuBarExtra)
            LabeledContent("Refresh interval") {
                Stepper(
                    "\(Int(settings.refreshIntervalSeconds)) seconds",
                    value: $settings.refreshIntervalSeconds,
                    in: 5...300,
                    step: 5
                )
            }
            Text("Launch-at-login arrives in Phase 7.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct AppleContainerSettingsTab: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showingFilePicker = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Binary") {
                    Text(env.power.binaryLocation?.url.path ?? "Not found")
                        .textSelection(.enabled)
                        .foregroundStyle(env.power.binaryLocation == nil ? .secondary : .primary)
                }
                if let location = env.power.binaryLocation {
                    LabeledContent("Found via") {
                        Text(sourceDescription(location.source))
                    }
                }
                LabeledContent("CLI version") {
                    Text(env.power.version?.shortDescription ?? "Unknown")
                }
                HStack {
                    Button("Re-detect") {
                        Task { await env.power.redetectBinary() }
                    }
                    Button("Choose Binary…") {
                        showingFilePicker = true
                    }
                }
            }
            Section {
                LabeledContent("Service state") {
                    SystemStateBadge(state: env.power.state)
                }
                HStack {
                    Button("Turn On") {
                        env.power.requestTurnOn()
                    }
                    .disabled(!env.power.state.canTurnOn)
                    Button("Turn Off") {
                        env.power.requestTurnOff()
                    }
                    .disabled(!env.power.state.canTurnOff)
                }
            }
            if env.power.state == .unavailable {
                Section {
                    Text("Install Apple Container with `brew install --cask container` or from the [releases page](https://github.com/apple/container/releases).")
                        .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.unixExecutable, .executable, .item]
        ) { result in
            if case .success(let url) = result {
                env.settings.binaryPathOverride = url.path
                Task { await env.power.adoptBinary(at: url) }
            }
        }
    }

    private func sourceDescription(_ source: ContainerBinaryLocation.Source) -> String {
        switch source {
        case .userConfigured: "Configured path"
        case .persistedPreference: "Previous detection"
        case .environmentPath: "PATH environment"
        case .knownLocation: "Known install location"
        case .manualSelection: "Manual selection"
        }
    }
}

private struct TerminalSettingsTab: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var settings = env.settings
        Form {
            Picker("Preferred terminal", selection: $settings.preferredTerminal) {
                ForEach(TerminalApp.allCases, id: \.self) { terminal in
                    Text(terminal.displayName).tag(terminal)
                }
            }
            Text(
                """
                Terminal.app and iTerm2 open a window running the command (macOS will \
                ask once for Automation permission). Ghostty and Warp have no scripting \
                interface, so the command is copied and the app is opened.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceSettingsTab: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var settings = env.settings
        Form {
            Picker("Appearance", selection: $settings.appearance) {
                ForEach(AppearancePreference.allCases, id: \.self) { preference in
                    Text(preference.displayName).tag(preference)
                }
            }
            .pickerStyle(.segmented)
            Picker("Accent color", selection: $settings.accent) {
                ForEach(AccentPreference.allCases, id: \.self) { preference in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(preference.color)
                            .frame(width: 12, height: 12)
                        Text(preference.displayName)
                    }
                    .tag(preference)
                }
            }
            Text("The accent color tints controls, selected navigation, charts, and status highlights throughout ContainerDeck.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct ResourcesSettingsTab: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var settings = env.settings
        Form {
            LabeledContent("Statistics polling") {
                Stepper(
                    String(format: "%.0f seconds", settings.statisticsIntervalSeconds),
                    value: $settings.statisticsIntervalSeconds,
                    in: 1...60,
                    step: 1
                )
            }
            LabeledContent("Log buffer") {
                Stepper(
                    "\(settings.logBufferLines) lines",
                    value: $settings.logBufferLines,
                    in: 1000...50000,
                    step: 1000
                )
            }
            Text("Statistics polling is used by Activity (Phase 6); the log buffer is used by the log viewer (Phase 2).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct AdvancedSettingsTab: View {
    @Environment(AppEnvironment.self) private var env
    @State private var confirmingReset = false
    @State private var diagnosticsPreview: String?

    var body: some View {
        @Bindable var settings = env.settings
        Form {
            Toggle("Show generated commands", isOn: $settings.showGeneratedCommands)
            Section {
                Button("Export Diagnostics…") {
                    diagnosticsPreview = buildDiagnostics()
                }
                Text("You preview exactly what the export contains before saving; no secrets are included.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Reset Application Data…", role: .destructive) {
                    confirmingReset = true
                }
                Text("Resets preferences, build history, and saved configurations. Apple Container resources are never touched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Reset all ContainerDeck application data?",
            isPresented: $confirmingReset
        ) {
            Button("Reset Application Data", role: .destructive) {
                resetSettings()
                env.imageActions.buildHistory.clear()
                env.savedConfigurations.clear()
            }
        } message: {
            Text("Preferences, build history, and saved run configurations return to their defaults. Your containers, images, and other Apple Container resources are not affected.")
        }
        .sheet(isPresented: Binding(
            get: { diagnosticsPreview != nil },
            set: { if !$0 { diagnosticsPreview = nil } }
        )) {
            DiagnosticsPreviewSheet(text: diagnosticsPreview ?? "")
        }
    }

    /// Diagnostics bundle: app/CLI versions, state, and capabilities.
    /// No environment values, no passwords (spec §8).
    private func buildDiagnostics() -> String {
        var lines: [String] = []
        lines.append("ContainerDeck diagnostics — \(Date().formatted(.iso8601))")
        lines.append("App version: 1.0.1 (Phase 7)")
        lines.append("CLI: \(env.power.version?.shortDescription ?? "unknown") at \(env.power.binaryLocation?.url.path ?? "not found")")
        lines.append("System state: \(env.power.state.displayName)")
        if let caps = env.resources.capabilities {
            lines.append("Capabilities: statistics=\(caps.statistics), networks=\(caps.networks)")
        }
        return lines.joined(separator: "\n")
    }

    private func resetSettings() {
        let settings = env.settings
        settings.binaryPathOverride = nil
        settings.autoStartOnLaunch = false
        settings.confirmBeforeStopping = true
        settings.appearance = .system
        settings.accent = .blue
        settings.refreshIntervalSeconds = 30
        settings.statisticsIntervalSeconds = 2
        settings.logBufferLines = 5000
        settings.showGeneratedCommands = true
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environment(AppEnvironment.preview(running: true))
    }
}


/// Preview-before-export so users see exactly what leaves the machine.
private struct DiagnosticsPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Diagnostics Preview")
                .font(.headline)
            ScrollView {
                Text(text)
                    .font(.caption.monospaced())
                    .foregroundStyle(Color.deckTermText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(minHeight: 260)
            .background(Color.deckTermBg, in: RoundedRectangle(cornerRadius: DeckMetrics.controlRadius))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save…") {
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = "containerdeck-diagnostics.txt"
                    if panel.runModal() == .OK, let url = panel.url {
                        try? Data(text.utf8).write(to: url)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 560)
    }
}
