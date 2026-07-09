import Foundation

/// Removes sensitive values from anything that is displayed, logged, or
/// persisted: command previews, operation history, diagnostics.
public enum SecretRedactor {
    public static let placeholder = "<redacted>"

    /// Flags whose *next* argument is entirely sensitive.
    static let sensitiveValueFlags: Set<String> = [
        "--password", "-p", "--secret", "--token", "--apikey", "--api-key",
    ]

    /// Flags whose next argument is `KEY=VALUE` where only VALUE is sensitive.
    /// All environment values are redacted, not just password-looking ones.
    static let environmentFlags: Set<String> = [
        "-e", "--env",
    ]

    /// Returns a display-safe copy of an argument array.
    public static func redactArguments(_ arguments: [String]) -> [String] {
        var redacted: [String] = []
        redacted.reserveCapacity(arguments.count)
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if environmentFlags.contains(argument), index + 1 < arguments.count {
                redacted.append(argument)
                redacted.append(redactKeyValuePair(arguments[index + 1]))
                index += 2
                continue
            }
            if sensitiveValueFlags.contains(argument), index + 1 < arguments.count {
                redacted.append(argument)
                redacted.append(placeholder)
                index += 2
                continue
            }
            if let equalsRange = argument.range(of: "="),
               sensitiveValueFlags.contains(String(argument[argument.startIndex..<equalsRange.lowerBound])) {
                // --password=value form
                redacted.append(String(argument[argument.startIndex..<equalsRange.lowerBound]) + "=" + placeholder)
                index += 1
                continue
            }
            redacted.append(argument)
            index += 1
        }
        return redacted
    }

    /// Redacts the value part of `KEY=VALUE`; a bare `KEY` passes through.
    public static func redactKeyValuePair(_ pair: String) -> String {
        guard let equalsIndex = pair.firstIndex(of: "=") else { return pair }
        return String(pair[pair.startIndex..<equalsIndex]) + "=" + placeholder
    }

    /// Replaces every occurrence of the given secrets in free-form text.
    public static func redactText(_ text: String, secrets: [String]) -> String {
        var result = text
        for secret in secrets where !secret.isEmpty {
            result = result.replacingOccurrences(of: secret, with: placeholder)
        }
        return result
    }
}
