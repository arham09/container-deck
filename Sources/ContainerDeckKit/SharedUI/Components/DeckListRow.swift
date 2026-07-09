import SwiftUI
import AppKit

// Docker-Desktop-style flat row list primitives. Rows are edge-to-edge inside a
// card, with a subtle hover/selection highlight and an action cluster that fades
// in on the trailing edge when the row is hovered or selected. Column alignment
// is the caller's responsibility: header cells and row cells use the same width
// tokens plus these shared `padH`/`colSpacing` constants.

public enum DeckList {
    public static let rowHeight: CGFloat = 46
    public static let padH: CGFloat = 14
    public static let colSpacing: CGFloat = 12
}

/// A row whose content is clickable to open and whose trailing `actions` reveal
/// only while the pointer is over the row — the highlight and actions disappear
/// as soon as the pointer leaves, and a click never leaves the row "stuck" lit.
/// Pass `onOpen: nil` for rows that have no detail to open.
struct DeckHoverRow<Content: View, Actions: View>: View {
    var onOpen: (() -> Void)?
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions

    @State private var hovering = false

    private var background: Color { hovering ? .deckHover : .clear }

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DeckList.padH)
            .frame(height: DeckList.rowHeight)
            .contentShape(Rectangle())
            .onTapGesture { onOpen?() }
            .background(background)
            .overlay(alignment: .trailing) {
                HStack(spacing: 0) {
                    // Fade the columns behind out from under the action cluster.
                    LinearGradient(
                        colors: [background.opacity(0), background],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: 26)
                    HStack(spacing: 2) { actions() }
                        .padding(.trailing, DeckList.padH - 4)
                        .background(background)
                }
                .frame(height: DeckList.rowHeight)
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
            }
            .animation(.easeOut(duration: 0.1), value: hovering)
            .onHover { hovering = $0 }
    }
}

/// A compact icon button for a row's trailing action cluster.
struct DeckRowIconButton: View {
    let systemImage: String
    let help: String
    var tint: Color = .deckTextDim
    var disabled = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(disabled ? Color.deckTextFaint : tint)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(hovering && !disabled ? Color.deckBorderStrong : .clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// The "⋯" overflow menu for a row's trailing action cluster.
struct DeckRowMenu<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.deckTextDim)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More actions")
    }
}

/// An uppercase column-label cell for a list's header row. `width == nil` makes
/// the column flexible so it lines up with a matching flexible row cell.
struct DeckColHeader: View {
    let title: String
    var width: CGFloat?
    var alignment: Alignment = .leading

    init(_ title: String, width: CGFloat? = nil, alignment: Alignment = .leading) {
        self.title = title
        self.width = width
        self.alignment = alignment
    }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(Color.deckTextFaint)
            .lineLimit(1)
            .modifier(ColumnWidth(width: width, alignment: alignment))
    }
}

/// Applies either a fixed or a flexible width, matching header and row cells.
struct ColumnWidth: ViewModifier {
    var width: CGFloat?
    var alignment: Alignment

    func body(content: Content) -> some View {
        if let width {
            content.frame(width: width, alignment: alignment)
        } else {
            content.frame(maxWidth: .infinity, alignment: alignment)
        }
    }
}

extension View {
    /// Sets a list column's width (fixed or flexible) so it aligns with the
    /// matching `DeckColHeader`.
    func deckColumn(width: CGFloat? = nil, alignment: Alignment = .leading) -> some View {
        modifier(ColumnWidth(width: width, alignment: alignment))
    }

    /// Hover tooltip that reveals a cell's full value when it's truncated.
    /// SwiftUI's `.help(_:)` is swallowed by the row's tap gesture on macOS, so
    /// this overlays a click-through AppKit view that owns the tooltip tracking
    /// rect directly. An empty string attaches nothing.
    func deckTooltip(_ text: String) -> some View {
        overlay {
            if !text.isEmpty {
                TooltipCarrier(text: text).accessibilityHidden(true)
            }
        }
    }
}

/// A transparent AppKit view whose sole job is to carry a tooltip. It returns
/// `nil` from `hitTest` so clicks pass straight through to the row beneath,
/// while its tooltip tracking rect keeps working regardless of SwiftUI gestures.
private struct TooltipCarrier: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSView {
        let view = ClickThroughView()
        view.toolTip = text
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.toolTip = text
    }

    private final class ClickThroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

struct DeckListRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 0) {
            HStack(spacing: DeckList.colSpacing) {
                Color.clear.frame(width: 10)
                DeckColHeader("Name")
                DeckColHeader("Status", width: 90)
                DeckColHeader("Actions", width: 96)
            }
            .padding(.horizontal, DeckList.padH)
            .frame(height: 30)
            ForEach(["web-api", "db", "worker"], id: \.self) { name in
                DeckHoverRow(onOpen: {}) {
                    HStack(spacing: DeckList.colSpacing) {
                        StatusDot(color: name == "worker" ? .deckTextFaint : .deckGreen, size: 8, ring: 2)
                            .frame(width: 10)
                        Text(name).foregroundStyle(Color.deckText).deckColumn()
                        Text(name == "worker" ? "Exited" : "Running")
                            .foregroundStyle(Color.deckTextDim)
                            .deckColumn(width: 90)
                        Color.clear.deckColumn(width: 96)
                    }
                    .font(.system(size: 13))
                } actions: {
                    DeckRowIconButton(systemImage: "play.fill", help: "Start", tint: .deckGreen) {}
                    DeckRowIconButton(systemImage: "trash", help: "Delete", tint: .deckRed) {}
                    DeckRowMenu { Button("Inspect") {} }
                }
            }
        }
        .frame(width: 460)
        .background(Color.deckCard)
    }
}
