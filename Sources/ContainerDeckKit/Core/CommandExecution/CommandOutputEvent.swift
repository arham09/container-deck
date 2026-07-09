/// A streaming event from a running child process.
///
/// Text chunks are decoded incrementally and are not guaranteed to be
/// line-aligned; consumers must not assume one event equals one line.
public enum CommandOutputEvent: Sendable, Equatable {
    case stdout(String)
    case stderr(String)
    case completed(exitCode: Int32)
}
