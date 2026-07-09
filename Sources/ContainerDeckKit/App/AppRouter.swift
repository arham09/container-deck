import Foundation
import Observation

/// Sidebar destinations (spec §15).
public enum SidebarItem: String, CaseIterable, Identifiable, Sendable {
    // SYSTEM
    case dashboard
    case activity
    // CONTAINERS
    case containers
    case images
    case builds
    // RESOURCES
    case volumes
    case networks
    case registries
    // LINUX
    case machines

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .activity: "Activity"
        case .containers: "Containers"
        case .images: "Images"
        case .builds: "Builds"
        case .volumes: "Volumes"
        case .networks: "Networks"
        case .registries: "Registries"
        case .machines: "Machines"
        }
    }

    public var symbolName: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.50percent"
        case .activity: "waveform.path.ecg"
        case .containers: "shippingbox"
        case .images: "opticaldisc"
        case .builds: "hammer"
        case .volumes: "externaldrive"
        case .networks: "network"
        case .registries: "building.columns"
        case .machines: "desktopcomputer"
        }
    }

    /// The phase in which this destination gains real functionality;
    /// nil means it is functional in Phase 0.
    public var plannedPhase: Int? {
        switch self {
        case .dashboard: nil
        case .containers, .images, .volumes, .networks, .registries: 1
        case .builds: 3
        case .machines: 1
        case .activity: 6
        }
    }
}

/// Window-level navigation state.
@MainActor
@Observable
public final class AppRouter {
    public var selection: SidebarItem? = .dashboard
    /// ⌘K command palette visibility.
    public var palettePresented = false

    public init() {}
}
