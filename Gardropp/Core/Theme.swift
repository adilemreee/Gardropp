import SwiftUI

/// Design tokens for the whole app: a warm, paper-like neutral palette with
/// near-black primary actions, matching the reference styling.
enum Theme {
    enum Radius {
        static let chip: CGFloat = 14
        static let card: CGFloat = 22
        static let sheet: CGFloat = 28
        static let tile: CGFloat = 18
    }

    enum Spacing {
        static let gutter: CGFloat = 20
        static let section: CGFloat = 28
    }
}

extension Color {
    private static func dynamic(light: UInt, dark: UInt) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// Page background.
    static let canvas = dynamic(light: 0xF4F2EE, dark: 0x111111)
    /// Cards, chips and image wells sitting on the canvas.
    static let surface = dynamic(light: 0xEAE7E1, dark: 0x1D1D1E)
    /// A slightly raised surface, used for grouped rows.
    static let surfaceElevated = dynamic(light: 0xFFFFFF, dark: 0x252526)
    /// Primary button / active chip fill.
    static let ink = dynamic(light: 0x141414, dark: 0xF2F0EC)
    /// Text on top of `ink`.
    static let onInk = dynamic(light: 0xFAF9F7, dark: 0x141414)
    static let textPrimary = dynamic(light: 0x141414, dark: 0xF2F0EC)
    static let textSecondary = dynamic(light: 0x86827B, dark: 0x9B9791)
    static let hairline = dynamic(light: 0xDCD8D1, dark: 0x323233)
    static let positive = dynamic(light: 0x3F6B4A, dark: 0x7FB58C)
}

private extension UIColor {
    convenience init(hex: UInt) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    /// Parses "#RRGGBB" / "RRGGBB"; falls back to grey when the string is junk.
    init(hexString: String) {
        var cleaned = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            self = Color(red: 0.5, green: 0.5, blue: 0.5)
            return
        }
        self = Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

// MARK: - Reusable building blocks

/// The pill used for filters and attribute tags.
struct ChipLabel: View {
    let title: String
    var caption: String?
    var isSelected: Bool = false
    var symbol: String?

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 13, weight: .medium))
            }
            if let caption {
                VStack(spacing: 1) {
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondary)
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                }
            } else {
                Text(title).font(.system(size: 15, weight: .medium))
            }
        }
        .foregroundStyle(isSelected ? Color.onInk : Color.textPrimary)
        .padding(.horizontal, caption == nil ? 16 : 14)
        .padding(.vertical, caption == nil ? 9 : 8)
        .background(isSelected ? Color.ink : Color.surface, in: .rect(cornerRadius: Theme.Radius.chip))
    }
}

/// Full-width black action button.
struct PrimaryButtonStyle: ButtonStyle {
    var isEnabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.onInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.ink.opacity(isEnabled ? 1 : 0.35), in: .rect(cornerRadius: Theme.Radius.tile))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Quiet secondary button that sits next to the primary one.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Color.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.surface, in: .rect(cornerRadius: Theme.Radius.tile))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Circular icon button used for close / back / more.
struct CircularIconButton: View {
    let symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 38, height: 38)
                .background(Color.surface, in: .circle)
        }
        .buttonStyle(.plain)
    }
}

extension View {
    func cardBackground(_ radius: CGFloat = Theme.Radius.card) -> some View {
        background(Color.surface, in: .rect(cornerRadius: radius))
    }
}
