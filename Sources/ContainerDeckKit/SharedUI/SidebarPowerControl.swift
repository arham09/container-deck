import SwiftUI

/// Persistent power control pinned near the bottom of the sidebar (spec §12).
/// Renders all seven system states with symbol + text and state-appropriate
/// actions; observes the single `SystemPowerController`.
struct SidebarPowerControl: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 9) {
                stateSymbol
                VStack(alignment: .leading, spacing: 1) {
                    Text("Apple Container")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.deckText)
                    Text(env.power.state.displayName)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.deckTextDim)
                }
                Spacer(minLength: 0)
            }
            actions
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.deckSidebar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.deckBorder)
                .frame(height: DeckMetrics.hairline)
        }
    }

    @ViewBuilder
    private var stateSymbol: some View {
        switch env.power.state {
        case .starting, .stopping, .unknown:
            ProgressView()
                .controlSize(.small)
        case .running:
            StatusDot(color: .deckGreen)
        case .stopped:
            StatusDot(color: .deckTextFaint)
        case .unavailable:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color.deckOrange)
                .font(.caption)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.deckRed)
                .font(.caption)
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch env.power.state {
        case .stopped:
            Button("Turn On") {
                env.power.requestTurnOn()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        case .running:
            Button("Turn Off") {
                env.power.requestTurnOff()
            }
            .controlSize(.small)
        case .starting, .stopping:
            Button("Cancel") {
                env.power.cancelLifecycleOperation()
            }
            .controlSize(.small)
        case .unavailable:
            Button("Installation Guide") {
                env.router.selection = .dashboard
            }
            .controlSize(.small)
        case .failed:
            HStack(spacing: 6) {
                Button("Retry") {
                    env.power.requestTurnOn()
                }
                Button("View Details") {
                    env.power.showLastFailureDetails()
                }
            }
            .controlSize(.small)
        case .unknown:
            EmptyView()
        }
    }
}

struct SidebarPowerControl_Previews: PreviewProvider {
    static var previews: some View {
        SidebarPowerControl()
            .environment(AppEnvironment.preview(running: true))
            .frame(width: 240)
            .previewDisplayName("Running")

        SidebarPowerControl()
            .environment(AppEnvironment.preview(running: false))
            .frame(width: 240)
            .previewDisplayName("Stopped")
    }
}
