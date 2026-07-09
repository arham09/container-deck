import Foundation

/// Renders a command as shell-style text for *display only* (previews,
/// operation history, diagnostics). ContainerDeck never executes strings
/// produced here; execution always uses an executable URL + argument array.
public enum ShellCommandFormatter {
    public static func format(executable: URL, arguments: [String]) -> String {
        ([executable.lastPathComponent] + arguments.map(quoteIfNeeded)).joined(separator: " ")
    }

    static func quoteIfNeeded(_ argument: String) -> String {
        if argument.isEmpty { return "''" }
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./=:@,+<>"))
        if argument.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return argument
        }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
