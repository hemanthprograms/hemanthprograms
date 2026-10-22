import SwiftUI

/// A calm night palette: deep navy, one lavender accent.
enum Theme {
    static let background = Color(red: 0.035, green: 0.047, blue: 0.11)
    static let card = Color(red: 0.086, green: 0.106, blue: 0.2)
    static let cardBorder = Color.white.opacity(0.06)
    static let accent = Color(red: 0.659, green: 0.6, blue: 1.0)
    static let secondaryText = Color.white.opacity(0.65)
    static let baselineBar = Color.white.opacity(0.35)
    static let worse = Color(red: 1.0, green: 0.62, blue: 0.52)
}

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.cardBorder))
    }
}

extension View {
    func card() -> some View {
        modifier(CardModifier())
    }

    func screenBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }
}

/// The big, rounded primary action used for "Start night" and friends.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(Theme.background)
            .background(Theme.accent.opacity(isEnabled ? 1 : 0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
