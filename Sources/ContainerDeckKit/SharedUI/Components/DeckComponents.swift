import SwiftUI

// Presentational building blocks for the Harbor look. All pure views — no
// engine/environment access — so they compose freely and preview cheaply.

/// A status dot with a soft glow ring (Harbor `box-shadow: 0 0 0 3px glow`).
/// The glow is drawn as an oversized background so it doesn't take layout space.
public struct StatusDot: View {
    let color: Color
    var size: CGFloat
    var ring: CGFloat

    public init(color: Color, size: CGFloat = DeckMetrics.statusDot, ring: CGFloat = 3) {
        self.color = color
        self.size = size
        self.ring = ring
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(color.opacity(0.22))
                    .frame(width: size + ring * 2, height: size + ring * 2)
            )
    }
}

/// Uppercase, faint, letter-spaced group label (sidebar sections, settings).
public struct DeckSectionLabel: View {
    let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text.uppercased())
            .font(.deckSectionLabel)
            .tracking(0.5)
            .foregroundStyle(Color.deckTextFaint)
    }
}

/// Card surface: fill + hairline border + rounded corners. `padded` adds the
/// standard interior padding; leave it off for tables that manage their own.
public struct DeckCardModifier: ViewModifier {
    var padded: Bool
    var hoverHighlight: Bool
    @State private var hovering = false

    public func body(content: Content) -> some View {
        content
            .padding(padded
                ? EdgeInsets(
                    top: DeckMetrics.cardPaddingV, leading: DeckMetrics.cardPaddingH,
                    bottom: DeckMetrics.cardPaddingV, trailing: DeckMetrics.cardPaddingH)
                : EdgeInsets())
            .background(Color.deckCard)
            .clipShape(RoundedRectangle(cornerRadius: DeckMetrics.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DeckMetrics.cardRadius)
                    .strokeBorder(
                        hoverHighlight && hovering ? Color.deckBorderStrong : Color.deckBorder,
                        lineWidth: DeckMetrics.hairline)
            )
            .onHover { hovering = hoverHighlight ? $0 : false }
    }
}

extension View {
    public func deckCard(padded: Bool = false, hoverHighlight: Bool = false) -> some View {
        modifier(DeckCardModifier(padded: padded, hoverHighlight: hoverHighlight))
    }
}

/// Dashboard metric card: dim title, large tabular value with optional suffix,
/// and an optional footer (subtitle, honest gated note — never a fake bar).
public struct DeckStatCard<Footer: View>: View {
    let title: String
    let value: String
    let valueSuffix: String?
    /// When true, the card stretches to fill its container's height so a row of
    /// cards (e.g. the dashboard grid) is uniform even when only some have a
    /// footer. Safe only inside a height-bounded container like `LazyVGrid`.
    var fillHeight: Bool
    @ViewBuilder let footer: () -> Footer

    public init(
        title: String,
        value: String,
        valueSuffix: String? = nil,
        fillHeight: Bool = false,
        @ViewBuilder footer: @escaping () -> Footer = { EmptyView() }
    ) {
        self.title = title
        self.value = value
        self.valueSuffix = valueSuffix
        self.fillHeight = fillHeight
        self.footer = footer
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Color.deckTextDim)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(value)
                    .font(.deckMetric)
                    .foregroundStyle(Color.deckText)
                if let valueSuffix {
                    Text(valueSuffix)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.deckTextFaint)
                }
            }
            footer()
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: fillHeight ? .infinity : nil,
            alignment: .topLeading
        )
        .deckCard(padded: true)
    }
}

/// Harbor pill segmented control (e.g. All / Running / Stopped filters).
public struct DeckSegmentedControl<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T
    let accent: Color

    public init(selection: Binding<T>, accent: Color, options: [(value: T, label: String)]) {
        self._selection = selection
        self.accent = accent
        self.options = options
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.system(size: 12.5))
                        .foregroundStyle(selected ? Color.deckText : Color.deckTextDim)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 13)
                        .background(
                            RoundedRectangle(cornerRadius: DeckMetrics.chipRadius)
                                .fill(selected ? Color.deckSel : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.deckCard2)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Color.deckBorder, lineWidth: DeckMetrics.hairline)
                )
        )
    }
}

/// Small pill badge (sidebar counts, "in use" / "dangling" tags).
public struct DeckChip: View {
    let text: String
    var foreground: Color
    var background: Color

    public init(_ text: String, foreground: Color = .deckTextFaint, background: Color = .deckCard2) {
        self.text = text
        self.foreground = foreground
        self.background = background
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(Capsule().fill(background))
    }
}

struct DeckComponents_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                StatusDot(color: .deckGreen)
                StatusDot(color: .deckTextFaint)
                StatusDot(color: .deckRed)
            }
            DeckSectionLabel("Workloads")
            HStack {
                DeckStatCard(title: "Containers", value: "3", valueSuffix: " / 8")
                DeckStatCard(title: "Disk", value: "1.2 GB") {
                    Text("240 MB reclaimable")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.deckTextFaint)
                }
            }
            HStack {
                DeckChip("6")
                DeckChip("in use", foreground: .deckGreen, background: AccentPreference.blue.softColor)
            }
        }
        .padding()
        .frame(width: 460)
        .background(Color.deckBg)
    }
}
