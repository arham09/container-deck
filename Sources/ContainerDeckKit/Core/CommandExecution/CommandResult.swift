import Foundation

/// The complete outcome of a finished child process.
public struct CommandResult: Sendable {
    public let exitCode: Int32
    public let standardOutput: Data
    public let standardError: Data
    public let startedAt: Date
    public let endedAt: Date

    public init(
        exitCode: Int32,
        standardOutput: Data,
        standardError: Data,
        startedAt: Date,
        endedAt: Date
    ) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    public var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
    public var isSuccess: Bool { exitCode == 0 }

    /// Lossy UTF-8 view of stdout (invalid sequences become U+FFFD).
    public var standardOutputText: String { String(decoding: standardOutput, as: UTF8.self) }
    /// Lossy UTF-8 view of stderr (invalid sequences become U+FFFD).
    public var standardErrorText: String { String(decoding: standardError, as: UTF8.self) }
}
