import SwiftUI

/// Menu commands and keyboard shortcuts (spec §33 foundation: ⌘R refresh,
/// system lifecycle in a dedicated menu; ⌘, Settings comes free with the
/// Settings scene). The full command palette arrives in Phase 7.
public struct AppCommands: Commands {
    private let environment: AppEnvironment
    @Environment(\.openWindow) private var openWindow

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Run Container…") {
                openWindow(id: "main")
                environment.router.selection = .containers
                environment.containerActions.runFormPresented = true
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(environment.power.state != .running)
        }

        CommandGroup(after: .toolbar) {
            Button("Command Palette…") {
                openWindow(id: "main")
                environment.router.palettePresented = true
            }
            .keyboardShortcut("k", modifiers: .command)

            Button("Refresh") {
                Task {
                    await environment.power.refreshStatus()
                    await environment.resources.refreshAll()
                }
            }
            .keyboardShortcut("r", modifiers: .command)
        }

        CommandMenu("System") {
            Button("Turn On Apple Container") {
                environment.power.requestTurnOn()
            }
            .disabled(!environment.power.state.canTurnOn || environment.power.isPerformingLifecycleAction)

            Button("Turn Off Apple Container…") {
                // The confirmation dialog lives on the main window.
                openWindow(id: "main")
                environment.power.requestTurnOff()
            }
            .disabled(!environment.power.state.canTurnOff || environment.power.isPerformingLifecycleAction)
        }
    }
}
