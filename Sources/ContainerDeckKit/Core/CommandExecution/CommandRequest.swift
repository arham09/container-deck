import Foundation

/// A description of a single child-process invocation.
///
/// Commands are always executed directly through an executable URL and an
/// argument array — never through a shell. `redactedArguments` is the
/// display-safe representation used in previews, logs, diagnostics, and
/// operation history; it defaults to `arguments` when nothing is sensitive.
public struct CommandRequest: Sendable {
    public var executable: URL
    public var arguments: [String]
    /// Merged over the inherited process environment.
    public var environmentOverrides: [String: String]
    public var workingDirectory: URL?
    /// Data written to the child's stdin. stdin is always closed after writing
    /// (or immediately when nil) so interactive prompts can never hang the app.
    public var standardInput: Data?
    public var timeout: Duration?
    /// Display-safe argument list. Never used for execution.
    public var redactedArguments: [String]

    public init(
        executable: URL,
        arguments: [String] = [],
        environmentOverrides: [String: String] = [:],
        workingDirectory: URL? = nil,
        standardInput: Data? = nil,
        timeout: Duration? = nil,
        redactedArguments: [String]? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environmentOverrides = environmentOverrides
        self.workingDirectory = workingDirectory
        self.standardInput = standardInput
        self.timeout = timeout
        self.redactedArguments = redactedArguments ?? arguments
    }

    /// Human-readable, redacted command line for display purposes only.
    public var displayCommand: String {
        ShellCommandFormatter.format(executable: executable, arguments: redactedArguments)
    }
}
