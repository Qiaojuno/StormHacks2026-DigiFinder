import SwiftUI

/// One row of the accessible surface.
struct AccessibleSurfaceItem: Identifiable, Equatable {
    enum Style { case title, message, detail }

    let id: String
    let text: String
    /// What drag-to-hear speaks and VoiceOver reads.
    let spoken: String
    /// What a double tap does (VoiceOver hint); nil = not activatable.
    let actionHint: String?
    let style: Style
    var isHeader = false
}

/// Drag-to-hear + double-tap surface (§5.10). Without VoiceOver: dragging a finger over a row speaks it once
/// (through `onHear`), a double tap activates the row under the finger. With VoiceOver the rows are plain
/// accessibility elements (VoiceOver already explores by touch). Ignored while `isEnabled` is false (walking).
struct AccessibleSurface: View {
    let items: [AccessibleSurfaceItem]
    let isEnabled: Bool
    let onHear: (AccessibleSurfaceItem) -> Void
    let onActivate: (AccessibleSurfaceItem) -> Void

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var focusedID: String?
    @State private var frames: [String: CGRect] = [:]

    private static let space = "AccessibleSurface"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(items) { item in
                row(item)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(UISurfaceFramesKey.self) { frames = $0 }
        .simultaneousGesture(drag, including: voiceOverEnabled || !isEnabled ? .none : .all)
        .onTapGesture(count: 2, coordinateSpace: .named(Self.space)) { location in
            guard isEnabled, !voiceOverEnabled, let item = item(at: location) else { return }
            if item.actionHint != nil { onActivate(item) }
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { focusedID = nil }
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard let item = item(at: value.location) else { return }
                if item.id != focusedID {
                    focusedID = item.id
                    onHear(item)
                }
            }
    }

    private func item(at p: CGPoint) -> AccessibleSurfaceItem? {
        items.first { frames[$0.id]?.contains(p) == true }
    }

    @ViewBuilder
    private func row(_ item: AccessibleSurfaceItem) -> some View {
        Text(item.text.isEmpty ? " " : item.text)
            .font(font(item.style))
            .foregroundStyle(item.style == .detail ? UITheme.secondary : UITheme.foreground)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, minHeight: UITheme.minTarget, alignment: .leading)
            .padding(.horizontal, 8)
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: UISurfaceFramesKey.self,
                                           value: [item.id: g.frame(in: .named(Self.space))])
                })
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(UITheme.accent, lineWidth: focusedID == item.id && !voiceOverEnabled ? 3 : 0))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.spoken)
            .accessibilityHint(isEnabled ? (item.actionHint ?? "") : "")
            .accessibilityAddTraits(item.isHeader ? .isHeader : [])
            .accessibilityAction {
                if isEnabled, item.actionHint != nil { onActivate(item) }
            }
    }

    private func font(_ style: AccessibleSurfaceItem.Style) -> Font {
        switch style {
        case .title: return .largeTitle.bold()
        case .message: return .title2.weight(.semibold)
        case .detail: return .body
        }
    }
}

private struct UISurfaceFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
