import SwiftUI

/// Symbol + text state indicator. Symbols always accompany text so state is
/// never conveyed by color alone (spec §12).
public struct SystemStateBadge: View {
    let state: ContainerSystemState

    public init(state: ContainerSystemState) {
        self.state = state
    }

    public var body: some View {
        HStack(spacing: 5) {
            if state.isTransitioning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: state.statusSymbol)
                    .foregroundStyle(symbolColor)
                    .font(.caption)
            }
            Text(state.displayName)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Apple Container is \(state.displayName)")
    }

    private var symbolColor: Color {
        switch state {
        case .running: .deckGreen
        case .failed: .deckRed
        case .unavailable: .deckOrange
        case .stopped, .unknown, .starting, .stopping: Color.deckTextDim
        }
    }
}

// PreviewProvider (not #Preview) so the package builds without Xcode's
// preview-macros plugin; Xcode's canvas renders these all the same.
struct SystemStateBadge_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading, spacing: 8) {
            SystemStateBadge(state: .unknown)
            SystemStateBadge(state: .unavailable)
            SystemStateBadge(state: .stopped)
            SystemStateBadge(state: .starting)
            SystemStateBadge(state: .running)
            SystemStateBadge(state: .stopping)
            SystemStateBadge(state: .failed(message: "Start Failed"))
        }
        .padding()
        .previewDisplayName("States")
    }
}
