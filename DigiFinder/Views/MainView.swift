import SwiftUI

/// MVP screen (§6): step, last spoken line, TALK, hint, status chips, SETUP and DEBUG.
/// Speech already reaches VoiceOver through the feedback service, so nothing here posts announcements.
struct MainView: View {
    @Bindable var model: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AccessibleSurface(
                items: surfaceItems,
                isEnabled: !model.isWalking,
                onHear: { model.hear($0.spoken) },
                onActivate: activate)
                .frame(maxHeight: model.status.cameraAvailable ? .infinity : nil)
                .fixedSize(horizontal: false, vertical: !model.status.cameraAvailable)

            if !model.status.cameraAvailable {
                CameraUnavailableView(debug: model.debug, showsDebugPanel: model.isSimulator,
                                      isWalking: model.isWalking)
                    .frame(maxHeight: .infinity)
            }

            controls
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(UITheme.background.ignoresSafeArea())
        .foregroundStyle(UITheme.foreground)
        .background(CaptureEventView(onTalk: { model.volumeUp() }, onDone: { model.volumeDown() }))
        .onAppear { model.onAppear() }
        .task {
            // Status chips: capabilities and connectivity change without a session update.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                model.refreshStatus()
            }
        }
        .sheet(isPresented: $model.showSetup) {
            SetupView(model: model)
        }
        .fullScreenCover(isPresented: $model.showDebug) {
            DebugOverlayView(model: model)
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Button(action: model.talkTapped) {
                Text("TALK")
                    .font(.largeTitle.weight(.heavy))
            }
            .buttonStyle(UILargeButtonStyle(filled: true, minHeight: 120))
            .accessibilityLabel("Talk")
            .accessibilityHint(model.isWalking
                ? "Ignored while walking. Use volume up."
                : "Same as volume up. Then speak, and press volume down when done.")

            Text(model.isWalking ? "Walking: use volume ↑ to talk" : model.hint)
                .font(.headline)
                .foregroundStyle(UITheme.secondary)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(model.isWalking
                    ? "Walking. Use volume up to talk."
                    : "Volume up to talk. Volume down when done.")

            chips

            HStack(spacing: 12) {
                Button(action: model.openSetup) {
                    Text("SETUP").font(.title3.bold())
                }
                .accessibilityLabel("Setup")
                .accessibilityHint("Speech, units, tones, detail level and the walkthrough.")

                Button(action: model.openDebug) {
                    Text("DEBUG").font(.title3.bold())
                }
                .accessibilityLabel("Debug")
                .accessibilityHint("Camera preview, depth and test events.")
            }
            .buttonStyle(UILargeButtonStyle())
            .disabled(model.isWalking)
        }
    }

    private var chips: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chipViews }
            VStack(alignment: .leading, spacing: 6) { chipViews }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Status")
    }

    @ViewBuilder
    private var chipViews: some View {
        UIStatusChip(title: "LiDAR", isOn: model.status.hasLiDAR)
        UIStatusChip(title: "Offline DB", isOn: model.status.hasOfflineDatabase)
        UIStatusChip(title: "Online", isOn: model.status.isOnline)
    }

    private var surfaceItems: [AccessibleSurfaceItem] {
        [
            AccessibleSurfaceItem(id: "step", text: model.stepTitle, spoken: model.stepTitle,
                                  actionHint: "Double tap to talk.", style: .title, isHeader: true),
            AccessibleSurfaceItem(id: "message", text: model.lastMessage,
                                  spoken: model.lastMessage.isEmpty ? "Nothing spoken yet." : model.lastMessage,
                                  actionHint: "Double tap to repeat.", style: .message),
        ]
    }

    private func activate(_ item: AccessibleSurfaceItem) {
        switch item.id {
        case "step": model.talkTapped()
        case "message": model.repeatLast()
        default: break
        }
    }
}
