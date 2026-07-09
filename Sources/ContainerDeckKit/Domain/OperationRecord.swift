import Foundation

/// A user-visible operation shown in the operation panel and recent activity.
///
/// Named `OperationRecord` (not the spec's `Operation`) to avoid colliding
/// with `Foundation.Operation`.
public struct OperationRecord: Sendable, Equatable, Identifiable, Codable {
    public enum Kind: String, Sendable, Codable {
        case startSystem
        case stopSystem
        case refresh
        case other
    }

    public enum Status: Sendable, Equatable, Codable {
        case running
        case succeeded
        case failed(String)
        case cancelled

        public var isFinished: Bool {
            self != .running
        }
    }

    public let id: UUID
    public var title: String
    public var kind: Kind
    /// Redacted, display-only command line. Never executed.
    public var redactedCommand: String?
    public var startedAt: Date
    public var endedAt: Date?
    public var status: Status
    /// Current phase description, e.g. "Waiting for the system to report running".
    public var phase: String?
    /// Bounded, redacted output excerpt (stdout + stderr interleaved).
    public var outputExcerpt: String

    public init(
        id: UUID = UUID(),
        title: String,
        kind: Kind,
        redactedCommand: String? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        status: Status = .running,
        phase: String? = nil,
        outputExcerpt: String = ""
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.redactedCommand = redactedCommand
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.phase = phase
        self.outputExcerpt = outputExcerpt
    }

    public var duration: TimeInterval? {
        guard let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }
}
