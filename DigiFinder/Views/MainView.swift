import SwiftUI

/// The app's one screen (Figma): the live 0.5× view fills the background; a dark bottom bar holds Detect (the camera
/// page, left) and Settings (right) with the record button on its top edge; Debug (top right). The camera flip is
/// automatic (gravity), so there is no flip button.
/// Settings replaces the camera view with the setup page.
/// Speech already reaches VoiceOver through the feedback service, so nothing here posts announcements.
struct MainView: View {
    @Bindable var model: AppViewModel
    @State private var showDebug = false

    var body: some View {
        ZStack {
            UITheme.background.ignoresSafeArea()
            switch model.page {
            case .home: home
            case .settings: SetupView(model: model)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { controls }
        .overlay(alignment: .topTrailing) {
            if model.page == .home { debugButton }
        }
        .overlay(alignment: .top) {
            if model.page == .home { UICaption(you: model.captionYou, app: model.captionApp, visible: model.captionVisible) }
        }
        .fullScreenCover(isPresented: $showDebug) { DebugOverlayView(model: model) }
        .foregroundStyle(UITheme.foreground)
        .background(CaptureEventView(onTalk: { model.volumeUp() }, onDone: { model.volumeDown() }))
        .onAppear { model.onAppear() }
        .task {
            // Camera availability can change after start (permission answer, configuration).
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                model.refreshStatus()
            }
        }
    }

    @ViewBuilder
    private var home: some View {
        if model.status.cameraAvailable {
            UICameraPreview(attach: model.attachPreview)
                .ignoresSafeArea()
                .accessibilityHidden(true)
        } else {
            CameraUnavailableView(debug: model.debug, showsDebugPanel: model.isSimulator, isWalking: model.isWalking)
                .padding(16)
                .padding(.top, 56)                           // room for the Debug button
        }
    }

    /// Judges' debug overlay (camera, depth, detections, threat reasons, test events). Small: not for production.
    private var debugButton: some View {
        Button { showDebug = true } label: {
            Image(systemName: "ladybug.fill")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Circle().fill(.black.opacity(0.55)))
                .overlay(Circle().stroke(UITheme.glassStroke, lineWidth: 1))
        }
        .foregroundStyle(UITheme.foreground)
        .disabled(model.isWalking)
        .padding(.trailing, 16)
        .padding(.top, 8)
        .accessibilityLabel("Debug")
        .accessibilityHint("Camera preview, depth, detections and test events.")
        .accessibilitySortPriority(1)
    }

    /// Dark bottom bar: Detect (the camera page, formerly Home) left, Settings right, the record button centred on
    /// the bar's top edge.
    private var controls: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .center) {
                UITile(title: "Detect", systemImage: "ear", selected: model.page == .home, action: model.openHome)
                    .accessibilityHint("The camera page.")
                    .accessibilitySortPriority(4)
                Spacer(minLength: Self.buttonSize)
                UITile(title: "Settings", systemImage: "slider.horizontal.3", selected: model.page == .settings,
                       action: model.openSettings)
                    .disabled(model.isWalking)
                    .accessibilitySortPriority(3)
            }
            .padding(.horizontal, 8)
            .padding(.top, 18)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(UITheme.bar)
                    .ignoresSafeArea(edges: .bottom))
            .padding(.horizontal, 4)
            .padding(.top, Self.buttonSize / 2)

            // Always usable, walking or not (owner decision): start and stop never depend on the motion guess.
            UIRecordButton(isRecording: model.isStreaming || model.isRecording, isEnabled: true, action: model.recordTapped)
                .accessibilitySortPriority(5)
        }
        .accessibilityElement(children: .contain)
    }

    static let buttonSize: CGFloat = 142
}

/// Speech caption (top centre): "You: …" and the app's last line, fading out. Hidden from VoiceOver: every line is
/// already spoken. Leaves room for the Debug button on the right.
struct UICaption: View {
    let you: String
    let app: String
    let visible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !you.isEmpty {
                Text("You: \(you)")
                    .font(.headline)
                    .foregroundStyle(UITheme.secondary)
                    .lineLimit(2)
            }
            if !app.isEmpty {
                Text(app)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(UITheme.foreground)
                    .lineLimit(2)
            }
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.6)))
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.leading, 16)
        .padding(.trailing, 72)                               // the Debug button
        .padding(.top, 8)
        .opacity(visible ? 1 : 0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: visible)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Bottom-bar style tile (Figma): icon over a bold label; selected = orange on a grey glass tile.
struct UITile: View {
    let title: String
    let systemImage: String
    let selected: Bool
    var onCamera = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .medium))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(selected ? UITheme.brand : UITheme.foreground)
            .padding(.horizontal, 10)
            .frame(minWidth: 106, minHeight: 84)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? UITheme.glass : (onCamera ? Color.black.opacity(0.45) : .clear)))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected || onCamera ? UITheme.glassStroke : .clear, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Camera-app style record button (Figma): a solid red-orange circle in a grey glass ring; while the stream runs, an
/// orange rounded square on a glass circle.
struct UIRecordButton: View {
    let isRecording: Bool
    let isEnabled: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let size = MainView.buttonSize
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .overlay(Circle().stroke(UITheme.glassStroke, lineWidth: 1.5))
                    .frame(width: size, height: size)
                RoundedRectangle(cornerRadius: isRecording ? 12 : size * 0.45, style: .continuous)
                    .fill(UITheme.brand)
                    .frame(width: isRecording ? size * 0.36 : size * 0.9, height: isRecording ? size * 0.36 : size * 0.9)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isRecording)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(isRecording ? "Stop" : "Start")
        .accessibilityHint(isRecording ? "Same as volume down: stops everything."
                                       : "Same as volume down: starts. Then press volume up to say what you're looking for.")
    }
}
