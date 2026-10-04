import SwiftUI
import DigiFinderCore

/// The Settings page (owner decision): only the walkthrough (how the app works now) and the credits at the very
/// bottom. Detect (bottom bar) returns to the camera view.
struct SetupView: View {
    let model: AppViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Array(UIWalkthrough.lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        model.playWalkthrough()
                    } label: {
                        Label("Play walkthrough", systemImage: "play.circle.fill")
                            .font(.headline)
                    }
                    .accessibilityHint("Speaks these instructions aloud.")
                } header: {
                    header("How it works")
                }

                Section {
                    ForEach(UICredits.entries) { UICreditRow(entry: $0) }
                } header: {
                    header("Credits")
                }
            }
            .environment(\.defaultMinListRowHeight, UITheme.minTarget)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }
}
