import SwiftUI
import DigiFinderCore

/// One-sheet setup (§5.13): speech speed and voice, units, tones and danger vibrations, detail level,
/// the first-launch walkthrough and the licenses.
struct SetupView: View {
    let model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var voices: [UIVoiceOption] = []

    var body: some View {
        @Bindable var store = model.settings
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
                    Picker("Speech speed", selection: $store.settings.speechSpeed) {
                        ForEach(UISpeechSpeed.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Voice", selection: $store.settings.voiceIdentifier) {
                        Text("Best available").tag(String?.none)
                        ForEach(voices) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    header("Speech")
                } footer: {
                    Text("English voices only. Download enhanced voices in Settings, Accessibility, Spoken Content.")
                }

                Section {
                    Picker("Distances in", selection: $store.settings.units) {
                        ForEach(UIDistanceUnits.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Distances in")
                } header: {
                    header("Units")
                }

                Section {
                    Toggle("Tones", isOn: $store.settings.tonesEnabled)
                        .accessibilityHint("Listening beep, done chime and scan ticks.")
                    Toggle("Danger vibrations", isOn: $store.settings.dangerHapticsEnabled)
                        .accessibilityHint("Strong vibrations before a danger alert. Recommended on.")
                } header: {
                    header("Sounds and vibrations")
                } footer: {
                    Text("Only danger vibrates. Keep danger vibrations on.")
                }

                Section {
                    Picker("Detail level", selection: $store.settings.detail) {
                        ForEach(Verbosity.uiChoices, id: \.rawValue) { Text($0.uiTitle).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Detail level")
                } header: {
                    header("Detail")
                } footer: {
                    Text("Brief skips optional lines such as category names.")
                }

                Section {
                    NavigationLink("Licenses") { LicensesView() }
                }
            }
            .environment(\.defaultMinListRowHeight, UITheme.minTarget)
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.headline)
                        .frame(minWidth: UITheme.minTarget, minHeight: 44)
                }
            }
        }
        .onAppear { if voices.isEmpty { voices = UIVoiceOption.englishVoices() } }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }
}
