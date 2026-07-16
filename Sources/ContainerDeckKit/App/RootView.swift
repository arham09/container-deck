import SwiftUI

/// Main window: NavigationSplitView shell, detail routing, and the
/// window-level dialogs for stop confirmation, kernel install, and errors.
public struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showingOperationsPopover = false

    public init() {}

    public var body: some View {
        @Bindable var power = env.power
        @Bindable var router = env.router
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            detailView
        }
        .frame(minWidth: 900, minHeight: 620)
        .preferredColorScheme(colorScheme)
        .tint(env.settings.accent.color)
        .task {
            await env.power.bootstrap()
            await env.resources.refreshAll()
        }
        .toolbar {
            // On macOS 26 Tahoe every toolbar item gets an automatic Liquid Glass
            // capsule background; the pill draws its own tinted capsule, so hide the
            // system one to avoid two overlapping shapes. macOS 15 has no such glass.
            if #available(macOS 26.0, *) {
                ToolbarItem(placement: .navigation) {
                    DeckToolbarPill()
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .navigation) {
                    DeckToolbarPill()
                }
            }
            ToolbarItem {
                Button {
                    showingOperationsPopover.toggle()
                } label: {
                    Label("Operations", systemImage: "arrow.triangle.2.circlepath")
                }
                .badge(env.operations.active.count)
                .help("Show recent operations")
                .popover(isPresented: $showingOperationsPopover) {
                    OperationsPopoverView()
                }
            }
        }
        .sheet(isPresented: $router.palettePresented) {
            CommandPalette()
        }
        // Turn Off confirmation (spec §12 wording, counts when known).
        .alert(
            "Turn off Apple Container?",
            isPresented: stopConfirmationPresented,
            presenting: power.stopConfirmation
        ) { confirmation in
            Button(
                confirmation.hasKnownRunningResources ? "Turn Off Anyway" : "Turn Off",
                role: .destructive
            ) {
                env.power.confirmTurnOff()
            }
            Button("Cancel", role: .cancel) {
                env.power.cancelTurnOff()
            }
        } message: { confirmation in
            Text(stopConfirmationMessage(confirmation))
        }
        // Kernel installation decision — never silent (spec §8, observed CLI behavior).
        .alert(
            "Linux Kernel Required",
            isPresented: $power.kernelInstallPrompt
        ) {
            Button("Install Kernel and Start") {
                env.power.confirmKernelInstallAndStart()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                """
                Apple Container has no default Linux kernel configured. \
                ContainerDeck can start Apple Container and install the recommended \
                kernel (downloaded from the official kata-containers releases).
                """
            )
        }
        // Error presentation with copyable diagnostics (spec §10).
        .alert(
            power.lastError?.title ?? "Error",
            isPresented: errorPresented,
            presenting: power.lastError
        ) { error in
            Button("Copy Diagnostics") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(error.diagnostics, forType: .string)
            }
            Button("OK", role: .cancel) {}
        } message: { error in
            Text("\(error.explanation)\n\n\(error.recommendedAction)")
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch env.router.selection ?? .dashboard {
        case .dashboard:
            DashboardView()
        case .activity:
            ActivityView()
        case .containers:
            ContainersView()
        case .images:
            ImagesView()
        case .volumes:
            VolumesView()
        case .networks:
            NetworksView()
        case .registries:
            RegistriesView()
        case .machines:
            MachinesView()
        case .builds:
            BuildsView()
        case let item:
            PhasePlaceholderView(item: item)
        }
    }

    private var colorScheme: ColorScheme? {
        switch env.settings.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private var stopConfirmationPresented: Binding<Bool> {
        Binding(
            get: { env.power.stopConfirmation != nil },
            set: { presented in
                if !presented { env.power.cancelTurnOff() }
            }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { env.power.lastError != nil },
            set: { presented in
                if !presented { env.power.lastError = nil }
            }
        )
    }

    private func stopConfirmationMessage(_ confirmation: StopConfirmation) -> String {
        if confirmation.hasKnownRunningResources {
            var lines: [String] = ["The following resources are currently running:", ""]
            if let containers = confirmation.runningContainers, containers > 0 {
                lines.append("• \(containers) container\(containers == 1 ? "" : "s")")
            }
            if let machines = confirmation.runningMachines, machines > 0 {
                lines.append("• \(machines) Linux machine\(machines == 1 ? "" : "s")")
            }
            lines.append("")
            lines.append("Stopping the system may interrupt active development processes.")
            lines.append("No resources will be deleted.")
            return lines.joined(separator: "\n")
        }
        return """
        ContainerDeck will stop the Apple Container system.

        Your containers, images, volumes, networks, and machines will not be deleted.
        """
    }
}

struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView()
            .environment(AppEnvironment.preview(running: true))
            .frame(width: 1180, height: 720)
            .previewDisplayName("Running")

        RootView()
            .environment(AppEnvironment.preview(running: false))
            .frame(width: 1180, height: 720)
            .previewDisplayName("Stopped")
    }
}
