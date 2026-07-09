import Foundation

/// Typed failures from engine and command-execution layers.
public enum ContainerEngineError: Error, Sendable, Equatable {
    case binaryNotFound
    case unsupportedPlatform
    case unsupportedVersion(String)
    case serviceNotRunning
    case permissionDenied
    case invalidInput(String)
    case commandTimedOut
    case commandCancelled

    /// Apple Container has no default kernel configured; starting requires an
    /// explicit user decision to install one (observed with CLI 1.0.0, which
    /// otherwise prompts interactively and fails under a closed stdin).
    case kernelInstallationRequired(String)

    /// The installed CLI or the current phase does not support this feature.
    case featureUnavailable(String)

    case commandFailed(
        executable: String,
        arguments: [String],
        exitCode: Int32,
        stderr: String
    )

    case decodingFailed(
        command: String,
        underlying: String
    )

    case unexpectedOutput(String)
}
