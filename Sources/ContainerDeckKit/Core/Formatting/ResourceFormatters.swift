import Foundation

/// Shared human-readable formatting for resource values.
public enum ResourceFormatters {
    public static func bytes(_ count: Int64) -> String {
        count.formatted(.byteCount(style: .memory))
    }

    public static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(1)))
    }

    public static func relativeDate(_ date: Date, relativeTo reference: Date = Date()) -> String {
        date.formatted(.relative(presentation: .named)).description
    }

    public static func duration(_ interval: TimeInterval) -> String {
        Duration.seconds(interval).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))
    }
}
