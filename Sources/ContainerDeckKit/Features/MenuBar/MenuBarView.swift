import SwiftUI

/// Menu-bar extra content (spec §31): compact, shares the single
/// SystemPowerController and resource stores — no independent state, no
/// dedicated polling (data refreshes when the menu opens).
public struct MenuBarView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Apple Container")
                    .font(.headline)
                Spacer()
                SystemStateBadge(state: env.power.state)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if env.power.state == .running, env.resources.hasLoadedResources {
                Divider()
                resourceList
            }

            Divider()
            actions
        }
        .frame(width: 280)
        .task {
            await env.power.refreshStatus()
            if env.power.state == .running {
                await env.resources.refreshAll()
            }
        }
    }

    @ViewBuilder
    private var resourceList: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !env.resources.containers.items.isEmpty {
                Text("Containers")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(env.resources.containers.items.prefix(6)) { container in
                    row(name: container.name, running: container.isRunning)
                }
            }
            if !env.resources.machines.items.isEmpty {
                Text("Machines")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                ForEach(env.resources.machines.items.prefix(4)) { machine in
                    row(name: machine.name, running: machine.isRunning)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func row(name: String, running: Bool) -> some View {
        HStack(spacing: 7) {
            StatusDot(color: running ? .deckGreen : .deckTextFaint, size: 7, ring: 2)
            Text(name)
                .font(.callout)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(alignment: .leading, spacing: 2) {
            MenuBarButton("Run Container…") {
                openMainWindow()
                env.router.selection = .containers
                env.containerActions.runFormPresented = true
            }
            .disabled(env.power.state != .running)
            MenuBarButton("Create Machine…") {
                openMainWindow()
                env.router.selection = .machines
                env.machineActions.createSheetPresented = true
            }
            .disabled(env.power.state != .running)
            Divider()
            // Contradictory actions disabled during transitions (spec §31).
            if env.power.state.canTurnOff {
                MenuBarButton("Turn Off Apple Container…") {
                    // The confirmation dialog lives on the main window.
                    openMainWindow()
                    env.power.requestTurnOff()
                }
                .disabled(env.power.isPerformingLifecycleAction)
            } else {
                MenuBarButton("Turn On Apple Container") {
                    env.power.requestTurnOn()
                }
                .disabled(!env.power.state.canTurnOn || env.power.isPerformingLifecycleAction)
            }
            Divider()
            MenuBarButton("Open ContainerDeck") {
                openMainWindow()
            }
            MenuBarButton("Quit ContainerDeck") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }

    private func openMainWindow() {
        NSApplication.shared.activate()
        openWindow(id: "main")
    }
}

/// Full-width plain button row for the menu-bar popover.
private struct MenuBarButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .foregroundStyle(isEnabled ? .primary : .tertiary)
    }
}
