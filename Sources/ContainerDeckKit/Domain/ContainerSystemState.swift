/// The application-level Apple Container system state.
///
/// Deliberately not a Boolean (spec §12): transitions, absence, and failure
/// are first-class states that every UI surface renders distinctly.
public enum ContainerSystemState: Sendable, Equatable {
    case unknown
    case unavailable
    case stopped
    case starting
    case running
    case stopping
    case failed(message: String)

    public var isTransitioning: Bool {
        switch self {
        case .starting, .stopping: true
        default: false
        }
    }

    /// Turn On is offered from these states.
    public var canTurnOn: Bool {
        switch self {
        case .stopped, .failed: true
        default: false
        }
    }

    /// Turn Off is offered from these states.
    public var canTurnOff: Bool {
        self == .running
    }

    public var displayName: String {
        switch self {
        case .unknown: "Checking…"
        case .unavailable: "Not Installed"
        case .stopped: "Stopped"
        case .starting: "Starting…"
        case .running: "Running"
        case .stopping: "Stopping…"
        case .failed: "Failed"
        }
    }

    /// Status symbol paired with text everywhere — never color alone.
    public var statusSymbol: String {
        switch self {
        case .unknown: "questionmark.circle"
        case .unavailable: "exclamationmark.triangle"
        case .stopped: "circle"
        case .starting, .stopping: "circle.dotted"
        case .running: "circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}
