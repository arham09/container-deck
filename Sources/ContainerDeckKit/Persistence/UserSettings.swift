import Foundation
import Observation

public enum AppearancePreference: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    public var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// Brand accent tint (Harbor offers four). The `Color` mapping lives in the
/// SharedUI theme layer so persistence stays free of SwiftUI.
public enum AccentPreference: String, CaseIterable, Sendable {
    case blue
    case indigo
    case green
    case graphite

    public var displayName: String {
        switch self {
        case .blue: "Blue"
        case .indigo: "Indigo"
        case .green: "Green"
        case .graphite: "Graphite"
        }
    }
}

/// User preferences backed by `UserDefaults`.
/// Never stores secrets (spec §8) — only paths, toggles, and intervals.
@MainActor
@Observable
public final class UserSettings {
    private enum Keys {
        static let binaryPathOverride = "binaryPathOverride"
        static let lastDetectedBinaryPath = "lastDetectedBinaryPath"
        static let autoStartOnLaunch = "autoStartOnLaunch"
        static let confirmBeforeStopping = "confirmBeforeStopping"
        static let appearance = "appearance"
        static let accent = "accent"
        static let refreshIntervalSeconds = "refreshIntervalSeconds"
        static let statisticsIntervalSeconds = "statisticsIntervalSeconds"
        static let logBufferLines = "logBufferLines"
        static let showGeneratedCommands = "showGeneratedCommands"
        static let preferredTerminal = "preferredTerminal"
        static let showMenuBarExtra = "showMenuBarExtra"
    }

    private let defaults: UserDefaults

    /// Explicit binary path set by the user in Settings (search rank 1).
    public var binaryPathOverride: String? {
        didSet { defaults.set(binaryPathOverride, forKey: Keys.binaryPathOverride) }
    }

    /// Last successfully validated binary path (search rank 2).
    public var lastDetectedBinaryPath: String? {
        didSet { defaults.set(lastDetectedBinaryPath, forKey: Keys.lastDetectedBinaryPath) }
    }

    /// "Turn on Apple Container when ContainerDeck launches" — default OFF (spec §12).
    public var autoStartOnLaunch: Bool {
        didSet { defaults.set(autoStartOnLaunch, forKey: Keys.autoStartOnLaunch) }
    }

    public var confirmBeforeStopping: Bool {
        didSet { defaults.set(confirmBeforeStopping, forKey: Keys.confirmBeforeStopping) }
    }

    public var appearance: AppearancePreference {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    public var accent: AccentPreference {
        didSet { defaults.set(accent.rawValue, forKey: Keys.accent) }
    }

    public var refreshIntervalSeconds: Double {
        didSet { defaults.set(refreshIntervalSeconds, forKey: Keys.refreshIntervalSeconds) }
    }

    public var statisticsIntervalSeconds: Double {
        didSet { defaults.set(statisticsIntervalSeconds, forKey: Keys.statisticsIntervalSeconds) }
    }

    public var logBufferLines: Int {
        didSet { defaults.set(logBufferLines, forKey: Keys.logBufferLines) }
    }

    public var showGeneratedCommands: Bool {
        didSet { defaults.set(showGeneratedCommands, forKey: Keys.showGeneratedCommands) }
    }

    public var preferredTerminal: TerminalApp {
        didSet { defaults.set(preferredTerminal.rawValue, forKey: Keys.preferredTerminal) }
    }

    public var showMenuBarExtra: Bool {
        didSet { defaults.set(showMenuBarExtra, forKey: Keys.showMenuBarExtra) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.binaryPathOverride = defaults.string(forKey: Keys.binaryPathOverride)
        self.lastDetectedBinaryPath = defaults.string(forKey: Keys.lastDetectedBinaryPath)
        self.autoStartOnLaunch = defaults.bool(forKey: Keys.autoStartOnLaunch)
        self.confirmBeforeStopping = defaults.object(forKey: Keys.confirmBeforeStopping) as? Bool ?? true
        self.appearance = AppearancePreference(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        self.accent = AccentPreference(rawValue: defaults.string(forKey: Keys.accent) ?? "") ?? .blue
        self.refreshIntervalSeconds = defaults.object(forKey: Keys.refreshIntervalSeconds) as? Double ?? 30
        self.statisticsIntervalSeconds = defaults.object(forKey: Keys.statisticsIntervalSeconds) as? Double ?? 2
        self.logBufferLines = defaults.object(forKey: Keys.logBufferLines) as? Int ?? 5000
        self.showGeneratedCommands = defaults.object(forKey: Keys.showGeneratedCommands) as? Bool ?? true
        self.preferredTerminal = TerminalApp(rawValue: defaults.string(forKey: Keys.preferredTerminal) ?? "") ?? .terminal
        self.showMenuBarExtra = defaults.object(forKey: Keys.showMenuBarExtra) as? Bool ?? true
    }
}
