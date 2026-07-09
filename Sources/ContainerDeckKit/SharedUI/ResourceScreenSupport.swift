import SwiftUI

/// Shared state presentation for resource screens: loading, needs-system,
/// unavailable, failed, and empty overlays, plus the stale-data banner.
struct ResourcePhaseOverlay: ViewModifier {
    @Environment(AppEnvironment.self) private var env

    let phase: ResourceLoadPhase
    let isEmpty: Bool
    let isStale: Bool
    let emptyLabel: String
    let emptySymbol: String
    let emptyDescription: String

    func body(content: Content) -> some View {
        content
            .overlay {
                switch phase {
                case .initial:
                    ProgressView()
                case .needsSystem:
                    ContentUnavailableView {
                        Label("Apple Container Is Stopped", systemImage: "poweroff")
                    } description: {
                        Text("Turn on Apple Container to load \(emptyLabel.lowercased()).")
                    } actions: {
                        Button("Turn On Apple Container") {
                            env.power.requestTurnOn()
                        }
                        .disabled(!env.power.state.canTurnOn)
                    }
                case .unavailable(let reason):
                    ContentUnavailableView {
                        Label("Not Available", systemImage: "info.circle")
                    } description: {
                        Text(reason)
                    }
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Could Not Load \(emptyLabel)", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Retry") {
                            Task { await env.resources.refreshAll() }
                        }
                    }
                case .loaded where isEmpty:
                    ContentUnavailableView {
                        Label("No \(emptyLabel)", systemImage: emptySymbol)
                    } description: {
                        Text(emptyDescription)
                    }
                case .loaded:
                    EmptyView()
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if isStale {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.badge.exclamationmark")
                        Text("Showing last known data — Apple Container is stopped.")
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundStyle(Color.deckOrange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.deckOrange.opacity(0.12))
                }
            }
    }
}

extension View {
    func resourcePhase<Item>(
        _ store: ResourceStore<Item>,
        label: String,
        symbol: String,
        emptyDescription: String
    ) -> some View {
        modifier(ResourcePhaseOverlay(
            phase: store.phase,
            isEmpty: store.items.isEmpty,
            isStale: store.isStale,
            emptyLabel: label,
            emptySymbol: symbol,
            emptyDescription: emptyDescription
        ))
    }
}

/// Toolbar refresh button shared by resource screens.
struct RefreshToolbarButton: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Button("Refresh", systemImage: "arrow.clockwise") {
            Task { await env.resources.refreshAll() }
        }
        .help("Refresh all resources (⌘R)")
    }
}

/// Async-loaded raw inspect payload shown inside a detail inspector.
struct InspectSection<Fetch: View>: View {
    let title: String
    @ViewBuilder var content: Fetch

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content
        }
    }
}
