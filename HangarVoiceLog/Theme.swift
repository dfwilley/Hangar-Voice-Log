import SwiftUI
import UIKit

/// Colors and type matching the web Hangar Log: zinc-chromate primer green on steel.
enum Theme {
    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static let bg = dynamic(0xECEFEE, 0x111715)
    static let card = dynamic(0xFFFFFF, 0x19211F)
    static let ink = dynamic(0x1C2626, 0xE3EBE9)
    static let muted = dynamic(0x5A6866, 0x93A3A0)
    static let line = dynamic(0xCDD5D3, 0x2C3835)
    static let field = dynamic(0xF5F7F6, 0x141B19)
    static let accent = dynamic(0x7C9E37, 0xA3C65A)
    static let accentInk = dynamic(0x17210A, 0x121A06)
    static let accentSoft = dynamic(0xE6EFD3, 0x25301A)
    static let warn = dynamic(0xB8352B, 0xF07A6E)
    static let warnSoft = dynamic(0xF8E1DE, 0x3A1E1B)
    static let steel = dynamic(0x33413F, 0x0B100F)
    static let onSteel = Color(UIColor(hex: 0xEEF3F1))

    // Fonts scale with the iPhone's text size setting.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("BarlowCondensed-Bold", size: size, relativeTo: style)
    }
    static func body(_ size: CGFloat = 17, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Barlow-Regular", size: size, relativeTo: style)
    }
    static func bodySemibold(_ size: CGFloat = 17, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Barlow-SemiBold", size: size, relativeTo: style)
    }
    static func data(_ size: CGFloat = 17, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("IBMPlexMono-Medium", size: size, relativeTo: style)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Reusable pieces

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
    }
}

struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 11)
            .frame(minHeight: 46)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
    func field() -> some View { modifier(FieldStyle()) }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.bodySemibold(12, relativeTo: .caption))
            .tracking(1.4)
            .foregroundStyle(Theme.muted)
    }
}

struct CardTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.display(24))
            .tracking(0.5)
            .foregroundStyle(Theme.ink)
    }
}

struct FieldLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.bodySemibold(14, relativeTo: .subheadline))
            .foregroundStyle(Theme.ink)
    }
}

struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.bodySemibold(15, relativeTo: .subheadline))
                .foregroundStyle(selected ? Theme.accentInk : Theme.ink)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(selected ? Theme.accent : Theme.field, in: Capsule())
                .overlay(Capsule().stroke(selected ? Theme.accent : Theme.line, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct HangarButtonStyle: ButtonStyle {
    enum Kind { case primary, plain, danger }
    var kind: Kind = .plain
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.bodySemibold(16, relativeTo: .callout))
            .padding(.horizontal, 16)
            .frame(minHeight: 46)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(border, lineWidth: 1.5))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.5)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Theme.accentInk
        case .plain: return Theme.ink
        case .danger: return Theme.warn
        }
    }
    private var background: Color {
        switch kind {
        case .primary: return Theme.accent
        case .plain: return Theme.card
        case .danger: return .clear
        }
    }
    private var border: Color {
        switch kind {
        case .primary: return Theme.accent
        case .plain: return Theme.line
        case .danger: return .clear
        }
    }
}

/// Lays out chips left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
