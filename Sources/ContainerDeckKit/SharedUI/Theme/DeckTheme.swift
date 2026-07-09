import SwiftUI

// The "Harbor" design system for ContainerDeck. Colors are dynamic (light/dark
// pairs) so they resolve automatically for the active appearance — including
// the appearance forced by RootView's `.preferredColorScheme`. Tokens are the
// exact values from the Harbor mockup; use these instead of semantic system
// colors so the whole app shares one palette.

extension NSColor {
    fileprivate convenience init(deckHex hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xff) / 255
        let g = CGFloat((hex >> 8) & 0xff) / 255
        let b = CGFloat(hex & 0xff) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

extension Color {
    /// A color that picks `dark`/`light` by resolving the active appearance at
    /// draw time. Only `UInt32` hex is captured, so the provider stays Sendable.
    fileprivate static func deck(dark: UInt32, light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(deckHex: dark)
                : NSColor(deckHex: light)
        })
    }

    /// Translucent white-on-dark / black-on-light (borders, hairlines).
    fileprivate static func deckOverlay(darkWhite: Double, lightBlack: Double) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1, alpha: darkWhite)
                : NSColor(white: 0, alpha: lightBlack)
        })
    }

    // Surfaces
    public static let deckBg = deck(dark: 0x161719, light: 0xf2f2f4)
    public static let deckSidebar = deck(dark: 0x1e1f22, light: 0xe9e9ee)
    public static let deckTitlebar = deck(dark: 0x26272b, light: 0xe3e3e8)
    public static let deckCard = deck(dark: 0x1e1f22, light: 0xffffff)
    public static let deckCard2 = deck(dark: 0x26272b, light: 0xf4f4f6)
    public static let deckSel = deck(dark: 0x2f3036, light: 0xdfe1e8)
    public static let deckHover = deck(dark: 0x25262a, light: 0xececef)

    // Lines
    public static let deckBorder = deckOverlay(darkWhite: 0.07, lightBlack: 0.08)
    public static let deckBorderStrong = deckOverlay(darkWhite: 0.13, lightBlack: 0.14)

    // Text
    public static let deckText = deck(dark: 0xececed, light: 0x1d1d1f)
    public static let deckTextDim = deck(dark: 0x9a9aa0, light: 0x6e6e73)
    public static let deckTextFaint = deck(dark: 0x65656b, light: 0x9a9aa0)

    // Status
    public static let deckGreen = deck(dark: 0x32d74b, light: 0x28c840)
    public static let deckRed = deck(dark: 0xff453a, light: 0xff453a)
    public static let deckYellow = deck(dark: 0xffd60a, light: 0xe0a800)
    public static let deckOrange = deck(dark: 0xff9f0a, light: 0xff9f0a)

    // Terminal / logs
    public static let deckTermBg = deck(dark: 0x0c0d10, light: 0x1b1c1f)
    public static let deckTermText = deck(dark: 0xd6dae0, light: 0xe4e7ec)

    // Accent palette (see AccentPreference for selection)
    static let deckAccentBlue = deck(dark: 0x0a84ff, light: 0x007aff)
    static let deckAccentIndigo = deck(dark: 0x5e5ce6, light: 0x5e5ce6)
    static let deckAccentGreen = deck(dark: 0x30d158, light: 0x30d158)
    static let deckAccentGraphite = deck(dark: 0x8e8e93, light: 0x8e8e93)
}

extension AccentPreference {
    /// The resolved accent color for this preference.
    public var color: Color {
        switch self {
        case .blue: .deckAccentBlue
        case .indigo: .deckAccentIndigo
        case .green: .deckAccentGreen
        case .graphite: .deckAccentGraphite
        }
    }

    /// Faded accent for selected nav rows / "in use" chips (Harbor accent-soft).
    public var softColor: Color { color.opacity(0.16) }
}

/// Shape constants from the Harbor mockup.
public enum DeckMetrics {
    public static let cardRadius: CGFloat = 12
    public static let controlRadius: CGFloat = 8
    public static let rowRadius: CGFloat = 8
    public static let chipRadius: CGFloat = 6
    public static let sectionPaddingH: CGFloat = 30
    public static let sectionPaddingV: CGFloat = 26
    public static let cardPaddingH: CGFloat = 18
    public static let cardPaddingV: CGFloat = 16
    public static let statusDot: CGFloat = 9
    public static let hairline: CGFloat = 1
}

extension Font {
    /// Uppercase faint section labels (sidebar groups, settings sections).
    public static let deckSectionLabel = Font.system(size: 11, weight: .semibold)
    /// Large tabular metric numbers (stat cards, stats tab).
    public static let deckMetric = Font.system(size: 27, weight: .bold).monospacedDigit()
}
