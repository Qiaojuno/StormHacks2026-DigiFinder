import SwiftUI

/// The app's one screen: the live 0.5× view fills the background, a record button sits at the bottom with Home
/// (left) and Settings (right) under it. Settings replaces the camera view with the setup page.
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
        .overlay(alignment: .topLeading) {
            if model.page == .home { flipButton }
        }
        .alert(model.isCameraFlipped ? "Turn the camera back to normal?" : "Flip the camera?",
               isPresented: $model.showFlipConfirm) {
            Button("Cancel", role: .cancel) { model.cancelFlip() }
            Button("Confirm") { model.confirmFlip() }
        } message: {
            Text(model.isCameraFlipped ? "Use this if the phone now hangs right side up."
                                       : "Use this if the phone hangs upside down on the lanyard.")
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
                .padding(.top, 44)                           // room for the Debug button
        }
    }

    /// Flip the camera for lanyards that hang the phone upside down (always confirmed, read aloud).
    private var flipButton: some View {
        Button(action: model.flipTapped) {
            Label(model.isCameraFlipped ? "Flipped" : "Flip", systemImage: "arrow.triangle.2.circlepath.camera.fill")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Capsule().fill(.black.opacity(0.55)))
        }
        .foregroundStyle(model.isCameraFlipped ? UITheme.accent : UITheme.foreground)
        .disabled(model.isWalking)
        .padding(.leading, 16)
        .padding(.top, 8)
        .accessibilityLabel(model.isCameraFlipped ? "Camera flipped" : "Flip camera")
        .accessibilityHint("Use if the phone hangs upside down. Asks to confirm.")
    }

    /// Judges' debug overlay (camera, depth, detections, threat reasons, test events).
    private var debugButton: some View {
        Button { showDebug = true } label: {
            Label("Debug", systemImage: "ladybug.fill")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Capsule().fill(.black.opacity(0.55)))
        }
        .foregroundStyle(UITheme.foreground)
        .disabled(model.isWalking)
        .padding(.trailing, 16)
        .padding(.top, 8)
        .accessibilityHint("Camera preview, depth, detections and test events.")
    }

    private var controls: some View {
        VStack(spacing: 16) {
            // Always usable, walking or not (owner decision): start and stop never depend on the motion guess.
            UIRecordButton(isRecording: model.isStreaming || model.isRecording, isEnabled: true, action: model.recordTapped)
            HStack {
                pageButton("Home", systemImage: "house.fill", page: .home, action: model.openHome)
                Spacer()
                pageButton("Settings", systemImage: "gearshape.fill", page: .settings, action: model.openSettings)
                    .disabled(model.isWalking)
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom))
    }

    private func pageButton(_ title: String, systemImage: String, page: UIPage, action: @escaping () -> Void) -> some View {
        let selected = model.page == page
        return Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.title2)
                Text(title).font(.footnote.weight(.semibold))
            }
            .frame(minWidth: UITheme.minTarget, minHeight: UITheme.minTarget)
            .foregroundStyle(selected ? UITheme.accent : UITheme.foreground)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Camera-app style record button: a red circle in a white ring; while recording, a red rounded square.
struct UIRecordButton: View {
    let isRecording: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 6)
                    .frame(width: 84, height: 84)
                RoundedRectangle(cornerRadius: isRecording ? 8 : 35)
                    .fill(Color.red)
                    .frame(width: isRecording ? 36 : 70, height: isRecording ? 36 : 70)
            }
            .frame(width: 96, height: 96)
            .contentShape(Circle())
            .animation(.easeInOut(duration: 0.2), value: isRecording)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(isRecording ? "Stop" : "Start")
        .accessibilityHint(isRecording ? "Same as volume down: stops everything."
                                       : "Same as volume up. Then say what you're looking for.")
    }
}
