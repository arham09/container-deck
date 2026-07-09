import Foundation

/// A presentation-ready error: concise title, plain explanation, recommended
/// action, and copyable diagnostics. Diagnostics must already be redacted;
/// nothing sensitive may reach this type.
public struct UserFacingError: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public var explanation: String
    public var recommendedAction: String
    public var diagnostics: String

    public init(
        title: String,
        explanation: String,
        recommendedAction: String,
        diagnostics: String = ""
    ) {
        self.id = UUID()
        self.title = title
        self.explanation = explanation
        self.recommendedAction = recommendedAction
        self.diagnostics = diagnostics
    }

    /// Maps a typed engine error to user-facing copy.
    public static func make(from error: ContainerEngineError, context: String? = nil) -> UserFacingError {
        switch error {
        case .binaryNotFound:
            return UserFacingError(
                title: "Apple Container Not Found",
                explanation: "ContainerDeck could not find the `container` command-line tool on this Mac.",
                recommendedAction: "Install Apple Container, or point ContainerDeck at the binary in Settings → Apple Container.",
                diagnostics: "binaryNotFound\(contextSuffix(context))"
            )
        case .unsupportedPlatform:
            return UserFacingError(
                title: "Unsupported Platform",
                explanation: "Apple Container requires a Mac with Apple silicon.",
                recommendedAction: "Run ContainerDeck on an Apple silicon Mac.",
                diagnostics: "unsupportedPlatform\(contextSuffix(context))"
            )
        case .unsupportedVersion(let version):
            return UserFacingError(
                title: "Unsupported Apple Container Version",
                explanation: "The installed Apple Container version (\(version)) is not supported by ContainerDeck.",
                recommendedAction: "Update Apple Container to a supported release.",
                diagnostics: "unsupportedVersion(\(version))\(contextSuffix(context))"
            )
        case .serviceNotRunning:
            return UserFacingError(
                title: "Apple Container Is Not Running",
                explanation: "This action requires the Apple Container system to be running.",
                recommendedAction: "Turn on Apple Container and try again.",
                diagnostics: "serviceNotRunning\(contextSuffix(context))"
            )
        case .permissionDenied:
            return UserFacingError(
                title: "Permission Denied",
                explanation: "macOS denied ContainerDeck permission to perform this operation.",
                recommendedAction: "Check the binary's permissions and try again.",
                diagnostics: "permissionDenied\(contextSuffix(context))"
            )
        case .invalidInput(let detail):
            return UserFacingError(
                title: "Invalid Input",
                explanation: detail,
                recommendedAction: "Correct the highlighted value and try again.",
                diagnostics: "invalidInput: \(detail)\(contextSuffix(context))"
            )
        case .commandTimedOut:
            return UserFacingError(
                title: "Operation Timed Out",
                explanation: "The command did not complete in the expected time and was stopped.",
                recommendedAction: "Retry, or copy the diagnostic information for further investigation.",
                diagnostics: "commandTimedOut\(contextSuffix(context))"
            )
        case .commandCancelled:
            return UserFacingError(
                title: "Operation Cancelled",
                explanation: "The operation was cancelled before it completed.",
                recommendedAction: "Retry if this was not intended.",
                diagnostics: "commandCancelled\(contextSuffix(context))"
            )
        case .kernelInstallationRequired(let message):
            return UserFacingError(
                title: "Linux Kernel Required",
                explanation: "Apple Container has no default Linux kernel configured. One must be installed before containers can run.",
                recommendedAction: "Choose “Install Kernel and Start” to download and install the recommended kernel, or install one manually with `container system kernel`.",
                diagnostics: "kernelInstallationRequired: \(message)\(contextSuffix(context))"
            )
        case .featureUnavailable(let reason):
            return UserFacingError(
                title: "Feature Unavailable",
                explanation: reason,
                recommendedAction: "No action needed.",
                diagnostics: "featureUnavailable: \(reason)\(contextSuffix(context))"
            )
        case .commandFailed(let executable, let arguments, let exitCode, let stderr):
            let command = ([URL(fileURLWithPath: executable).lastPathComponent] + arguments).joined(separator: " ")
            return UserFacingError(
                title: "Command Failed",
                explanation: "The Apple Container command did not complete successfully (exit code \(exitCode)).",
                recommendedAction: "Retry or copy the diagnostic information for further investigation.",
                diagnostics: "command: \(command)\nexit code: \(exitCode)\nstderr:\n\(stderr)\(contextSuffix(context))"
            )
        case .decodingFailed(let command, let underlying):
            return UserFacingError(
                title: "Unexpected Response",
                explanation: "ContainerDeck could not understand the output of `\(command)`. The installed Apple Container version may not be supported.",
                recommendedAction: "Check for a ContainerDeck update, or copy the diagnostics for further investigation.",
                diagnostics: "decodingFailed for \(command): \(underlying)\(contextSuffix(context))"
            )
        case .unexpectedOutput(let detail):
            return UserFacingError(
                title: "Unexpected Output",
                explanation: "Apple Container returned output that ContainerDeck did not expect.",
                recommendedAction: "Retry or copy the diagnostic information for further investigation.",
                diagnostics: "unexpectedOutput: \(detail)\(contextSuffix(context))"
            )
        }
    }

    private static func contextSuffix(_ context: String?) -> String {
        guard let context else { return "" }
        return "\ncontext: \(context)"
    }
}
