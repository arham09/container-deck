/// Abstraction over child-process execution so engines and tests can
/// substitute implementations.
public protocol CommandRunning: Sendable {
    /// Runs a command to completion, collecting stdout and stderr.
    func run(_ request: CommandRequest) async throws -> CommandResult

    /// Runs a command and streams its output incrementally.
    /// The stream finishes after a `.completed` event, or throws on
    /// launch failure, timeout, or cancellation.
    func stream(_ request: CommandRequest) -> AsyncThrowingStream<CommandOutputEvent, Error>
}
