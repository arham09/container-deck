import AppKit
import Foundation

/// Supported external terminals (spec §22). No embedded terminal emulator.
public enum TerminalApp: String, CaseIterable, Sendable {
    case terminal
    case iterm2
    case ghostty
    case warp
    case copyOnly

    public var displayName: String {
        switch self {
        case .terminal: "Terminal.app"
        case .iterm2: "iTerm2"
        case .ghostty: "Ghostty"
        case .warp: "Warp"
        case .copyOnly: "Copy command only"
        }
    }

    var bundleIdentifier: String? {
        switch self {
        case .terminal: "com.apple.Terminal"
        case .iterm2: "com.googlecode.iterm2"
        case .ghostty: "com.mitchellh.ghostty"
        case .warp: "dev.warp.Warp-Stable"
        case .copyOnly: nil
        }
    }
}

@MainActor
public protocol TerminalLaunching: Sendable {
    /// Opens `command` in the user's preferred terminal. Returns a short
    /// user-facing note (e.g. "Command copied") when the command was not
    /// executed directly.
    func open(command: String, preference: TerminalApp) throws -> String?
}

/// Launches the preferred terminal. AppleScript is used only for
/// Terminal.app and iTerm2, which require it for running a command in a new
/// window (documented, isolated here — spec §22). Ghostty and Warp expose no
/// stable scripting interface, so the command is copied and the app opened.
@MainActor
public struct ExternalTerminalLauncher: TerminalLaunching {
    public init() {}

    public func open(command: String, preference: TerminalApp) throws -> String? {
        switch preference {
        case .copyOnly:
            copy(command)
            return "Command copied to the clipboard."
        case .terminal:
            try runAppleScript(
                """
                tell application "Terminal"
                    activate
                    do script "\(escaped(command))"
                end tell
                """
            )
            return nil
        case .iterm2:
            try runAppleScript(
                """
                tell application "iTerm"
                    activate
                    set newWindow to (create window with default profile)
                    tell current session of newWindow
                        write text "\(escaped(command))"
                    end tell
                end tell
                """
            )
            return nil
        case .ghostty, .warp:
            copy(command)
            guard let bundleID = preference.bundleIdentifier,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                throw ContainerEngineError.invalidInput(
                    "\(preference.displayName) is not installed. The command was copied to the clipboard."
                )
            }
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
            return "Command copied — paste it into \(preference.displayName)."
        }
    }

    private func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    private func escaped(_ command: String) -> String {
        command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func runAppleScript(_ source: String) throws {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw ContainerEngineError.unexpectedOutput("Could not build the terminal script.")
        }
        script.executeAndReturnError(&errorInfo)
        if let errorInfo, let message = errorInfo[NSAppleScript.errorMessage] as? String {
            throw ContainerEngineError.commandFailed(
                executable: "osascript",
                arguments: [],
                exitCode: -1,
                stderr: message
            )
        }
    }
}
