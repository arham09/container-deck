import ContainerDeckKit
import SwiftUI

/// Cancels in-flight work on quit so child processes terminate via the
/// runner's SIGTERM→SIGKILL escalation. Quitting never stops Apple Container.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var environment: AppEnvironment?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            environment?.power.cancelLifecycleOperation()
            environment?.metrics.stop()
        }
        return .terminateNow
    }
}

@main
struct ContainerDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment: AppEnvironment
    private let notifier = SystemNotifier()

    init() {
        let environment = AppEnvironment.live()
        environment.power.notify = { [notifier] title, body in
            notifier.postIfInactive(title: title, body: body)
        }
        _environment = State(initialValue: environment)
        notifier.requestAuthorizationIfNeeded()
    }

    var body: some Scene {
        // A single Window (not WindowGroup): openWindow(id: "main") raises
        // the existing window instead of spawning another (spec §14: one
        // primary application window).
        Window("ContainerDeck", id: "main") {
            RootView()
                .environment(environment)
                .onAppear { appDelegate.environment = environment }
        }
        .defaultSize(width: 1180, height: 740)
        .commands {
            AppCommands(environment: environment)
        }

        MenuBarExtra(
            "ContainerDeck",
            systemImage: "shippingbox",
            isInserted: Binding(
                get: { environment.settings.showMenuBarExtra },
                set: { environment.settings.showMenuBarExtra = $0 }
            )
        ) {
            MenuBarView()
                .environment(environment)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(environment)
        }
    }
}
