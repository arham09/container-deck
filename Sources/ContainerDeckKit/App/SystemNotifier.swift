import AppKit
import UserNotifications

/// Posts native completion notifications when the app is inactive (spec §12).
///
/// `UNUserNotificationCenter` requires a real app bundle; when running as a
/// bare SwiftPM executable (no bundle identifier) this degrades to a no-op
/// rather than crashing. The packaged .app gets full notifications.
@MainActor
public struct SystemNotifier {
    private let hasBundle = Bundle.main.bundleIdentifier != nil

    public init() {}

    public func requestAuthorizationIfNeeded() {
        guard hasBundle else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    /// Posts only when the app is not frontmost — foreground users already
    /// see the state change in the UI.
    public func postIfInactive(title: String, body: String) {
        guard hasBundle, !NSApplication.shared.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
