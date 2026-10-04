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
}

/// Large, high-contrast button: filled (TALK) or outlined (SETUP, DEBUG, debug events).
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

/// One status chip ("● LiDAR"); the state is in the symbol and the VoiceOver label, not only in color.
struct UIStatusChip: View {
    let title: String
    let isOn: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(isOn ? Color.green : UITheme.secondary)
            Text(title)
                .foregroundStyle(UITheme.foreground)
                .strikethrough(!isOn, color: UITheme.secondary)
        }
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(UITheme.panel))
        .overlay(Capsule().stroke(UITheme.border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(isOn ? "on" : "off")")
    }
}
