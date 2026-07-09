import SwiftUI

/// ⌘K command palette (spec §33): searchable actions, filtered to what is
/// valid for the current system state.
struct CommandPalette: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private struct PaletteAction: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let perform: @MainActor () -> Void
    }

    private var actions: [PaletteAction] {
        var available: [PaletteAction] = []
        let power = env.power
        if power.state.canTurnOn {
            available.append(PaletteAction(id: "on", title: "Turn On Apple Container", symbol: "power") {
                power.requestTurnOn()
            })
        }
        if power.state.canTurnOff {
            available.append(PaletteAction(id: "off", title: "Turn Off Apple Container", symbol: "poweroff") {
                power.requestTurnOff()
            })
            available.append(PaletteAction(id: "restart", title: "Restart Apple Container", symbol: "arrow.clockwise.circle") {
                env.restartSystem()
            })
            available.append(PaletteAction(id: "run", title: "Run Container", symbol: "plus.square") {
                env.router.selection = .containers
                env.containerActions.runFormPresented = true
            })
            available.append(PaletteAction(id: "pull", title: "Pull Image", symbol: "square.and.arrow.down") {
                env.router.selection = .images
                env.imageActions.pullSheetPresented = true
            })
            available.append(PaletteAction(id: "build", title: "Build Image", symbol: "hammer") {
                env.router.selection = .builds
                env.imageActions.buildSheetPresented = true
            })
            available.append(PaletteAction(id: "machine", title: "Create Machine", symbol: "desktopcomputer") {
                env.router.selection = .machines
                env.machineActions.createSheetPresented = true
            })
        }
        available.append(PaletteAction(id: "activity", title: "Open Activity", symbol: "waveform.path.ecg") {
            env.router.selection = .activity
        })
        available.append(PaletteAction(id: "refresh", title: "Refresh Current View", symbol: "arrow.clockwise") {
            Task {
                await env.power.refreshStatus()
                await env.resources.refreshAll()
            }
        })
        available.append(PaletteAction(id: "status", title: "View Apple Container Status", symbol: "info.circle") {
            env.router.selection = .dashboard
        })
        guard !query.isEmpty else { return available }
        return available.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Type a command…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(12)
            Divider()
            if actions.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(height: 160)
            } else {
                List(actions) { action in
                    Button {
                        dismiss()
                        action.perform()
                    } label: {
                        Label(action.title, systemImage: action.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .frame(height: min(300, CGFloat(actions.count) * 36 + 16))
            }
        }
        .frame(width: 440)
    }
}

extension AppEnvironment {
    /// System restart (spec §33): stop → verify stopped → start → verify
    /// running. The power controller's verified stop path chains into start;
    /// if the stop fails, start never runs.
    public func restartSystem() {
        guard power.state.canTurnOff else { return }
        power.onSystemStopped = { [weak self] in
            guard let self else { return }
            self.resources.markAllStale()
            self.power.onSystemStopped = { [weak self] in
                self?.resources.markAllStale()
            }
            self.power.requestTurnOn()
        }
        // Bypass the confirmation: restart was an explicit palette action.
        power.confirmTurnOff()
    }
}
