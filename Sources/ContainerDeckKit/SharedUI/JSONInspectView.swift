import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Raw-JSON inspector (spec §18): collapsible tree, type-colored values,
/// search, copy, and save-to-file. Unknown fields are preserved because the
/// tree renders the raw payload, not the decoded model.
struct JSONInspectView: View {
    let rawJSON: String
    /// Suggested file name for "Save…".
    var suggestedFileName: String = "inspect.json"

    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Filter keys and values", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Spacer()
                Button("Copy", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(rawJSON, forType: .string)
                }
                .labelStyle(.iconOnly)
                .help("Copy raw JSON")
                Button("Save…", systemImage: "square.and.arrow.down") {
                    save()
                }
                .labelStyle(.iconOnly)
                .help("Save raw JSON to a file")
            }

            if let roots = JSONNode.parse(rawJSON) {
                let filtered = search.isEmpty ? roots : roots.compactMap { $0.filtered(by: search) }
                if filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else {
                    List(filtered, children: \.children) { node in
                        HStack(spacing: 6) {
                            Text(node.key)
                                .font(.callout.monospaced())
                                .foregroundStyle(Color.deckTextDim)
                            if let value = node.displayValue {
                                Text(value)
                                    .font(.callout.monospaced())
                                    .foregroundStyle(node.valueColor)
                                    .textSelection(.enabled)
                                    .lineLimit(3)
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                }
            } else {
                ScrollView {
                    Text(rawJSON)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = suggestedFileName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? Data(rawJSON.utf8).write(to: url)
    }
}

/// Parsed JSON tree node for `List(children:)` disclosure.
struct JSONNode: Identifiable {
    enum Kind {
        case string, number, bool, null, object, array
    }

    let id = UUID()
    var key: String
    var kind: Kind
    var displayValue: String?
    var children: [JSONNode]?

    var valueColor: Color {
        switch kind {
        case .string: .deckGreen
        case .number: .deckAccentBlue
        case .bool: .deckOrange
        case .null: Color.deckTextFaint
        case .object, .array: Color.deckTextDim
        }
    }

    static func parse(_ raw: String) -> [JSONNode]? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        return [node(key: "root", value: object)]
    }

    static func node(key: String, value: Any) -> JSONNode {
        switch value {
        case let dictionary as [String: Any]:
            let children = dictionary.keys.sorted().map { node(key: $0, value: dictionary[$0]!) }
            return JSONNode(
                key: key,
                kind: .object,
                displayValue: "{\(dictionary.count)}",
                children: children.isEmpty ? nil : children
            )
        case let array as [Any]:
            let children = array.enumerated().map { node(key: "[\($0.offset)]", value: $0.element) }
            return JSONNode(
                key: key,
                kind: .array,
                displayValue: "[\(array.count)]",
                children: children.isEmpty ? nil : children
            )
        case let string as String:
            return JSONNode(key: key, kind: .string, displayValue: "\"\(string)\"", children: nil)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return JSONNode(key: key, kind: .bool, displayValue: number.boolValue ? "true" : "false", children: nil)
            }
            return JSONNode(key: key, kind: .number, displayValue: "\(number)", children: nil)
        case is NSNull:
            return JSONNode(key: key, kind: .null, displayValue: "null", children: nil)
        default:
            return JSONNode(key: key, kind: .string, displayValue: "\(value)", children: nil)
        }
    }

    /// Keeps nodes matching the query, or nodes with matching descendants.
    func filtered(by query: String) -> JSONNode? {
        let matches = key.localizedCaseInsensitiveContains(query)
            || (displayValue?.localizedCaseInsensitiveContains(query) ?? false)
        let filteredChildren = children?.compactMap { $0.filtered(by: query) }
        if matches || !(filteredChildren?.isEmpty ?? true) {
            var copy = self
            copy.children = (filteredChildren?.isEmpty ?? true) ? children : filteredChildren
            return copy
        }
        return nil
    }
}
