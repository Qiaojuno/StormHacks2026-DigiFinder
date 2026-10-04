import SwiftUI

/// High-contrast palette and sizes shared by the screens (§6: high contrast, ≥ 60 pt targets).
enum UITheme {
    static let background = Color.black
    static let foreground = Color.white
    static let secondary = Color(white: 0.85)
    static let accent = Color.yellow
    static let onAccent = Color.black
    static let panel = Color(white: 0.14)
    static let border = Color(white: 0.7)
    static let minTarget: CGFloat = 60
    /// Main screen (Figma): the record button and selected tab, and the bottom bar.
    static let brand = Color(red: 0.886, green: 0.325, blue: 0.227)       // #E2533A
    static let bar = Color(red: 0.13, green: 0.094, blue: 0.086)          // #211816
    static let glass = Color.white.opacity(0.16)
    static let glassStroke = Color.white.opacity(0.22)
}

/// Large, high-contrast button for the debug panel: filled or outlined.
struct UILargeButtonStyle: ButtonStyle {
    var filled = false
    var minHeight: CGFloat = UITheme.minTarget
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .multilineTextAlignment(.center)
            .foregroundStyle(filled ? UITheme.onAccent : UITheme.foreground)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(filled ? UITheme.accent : UITheme.panel))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(filled ? Color.clear : UITheme.border, lineWidth: 2))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}
