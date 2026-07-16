import SwiftUI

/// Harbor's title-bar engine-status pill, adapted to the native toolbar.
/// Shows the current system state and, on click, runs the primary action for
/// that state — reusing the existing power controller (so the turn-off
/// confirmation and kernel-install alerts hosted by RootView still fire).
///
/// The pill is state-tinted (green running, red failed, orange unavailable,
/// neutral otherwise) and brightens on hover so it reads as an interactive
/// toggle rather than a flat label.
///
/// Rendered as a custom tappable element rather than a `Button` so AppKit
/// doesn't add a button hover highlight; click and VoiceOver activation are
/// wired explicitly.
///
/// This draws one capsule. On macOS 26 Tahoe the *toolbar item* also gets an
/// automatic Liquid Glass capsule background — which stacked a second, offset
/// shape behind ours — so `RootView` suppresses it with
/// `.sharedBackgroundVisibility(.hidden)` on the item.
public struct DeckToolbarPill: View {
    @Environment(AppEnvironment.self) private var env
    @State private var hovering = false

    public init() {}

    public var body: some View {
        let state = env.power.state
        let tint = tintColor(for: state)
        let actionable = isActionable(state)
        let lit = hovering && actionable

        HStack(spacing: 7) {
            if state.isTransitioning {
                ProgressView().controlSize(.small)
            } else {
                StatusDot(color: tint, size: 7, ring: 3)
            }
            Text(state.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(actionable ? Color.deckText : Color.deckTextDim)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 12)
        .background {
            Capsule()
                .fill(Color.deckCard2)
                .overlay(Capsule().fill(tint.opacity(lit ? 0.24 : 0.14)))
                .overlay(Capsule().strokeBorder(tint.opacity(lit ? 0.6 : 0.32), lineWidth: DeckMetrics.hairline))
        }
        .contentShape(Capsule())
        .onTapGesture { if actionable { primaryAction(for: state) } }
        .pointerStyle(actionable ? .link : nil)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: lit)
        .help(helpText(for: state))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Apple Container: \(state.displayName)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(actionable ? helpText(for: state) : "")
        .accessibilityAction { if actionable { primaryAction(for: state) } }
    }

    private func primaryAction(for state: ContainerSystemState) {
        switch state {
        case .stopped, .failed, .unknown:
            env.power.requestTurnOn()
        case .running:
            env.power.requestTurnOff()
        case .starting, .stopping, .unavailable:
            break
        }
    }

    private func isActionable(_ state: ContainerSystemState) -> Bool {
        switch state {
        case .stopped, .failed, .unknown: state.canTurnOn
        case .running: state.canTurnOff
        case .starting, .stopping, .unavailable: false
        }
    }

    /// The state's accent color — also tints the pill's fill and border.
    private func tintColor(for state: ContainerSystemState) -> Color {
        switch state {
        case .running: .deckGreen
        case .failed: .deckRed
        case .unavailable: .deckOrange
        case .stopped, .unknown, .starting, .stopping: .deckTextFaint
        }
    }

    private func helpText(for state: ContainerSystemState) -> String {
        switch state {
        case .running: "Turn off Apple Container"
        case .stopped, .failed, .unknown: "Turn on Apple Container"
        case .starting: "Starting…"
        case .stopping: "Stopping…"
        case .unavailable: "Apple Container is not installed"
        }
    }
}
