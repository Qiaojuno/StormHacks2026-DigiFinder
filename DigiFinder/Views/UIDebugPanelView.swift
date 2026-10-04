import SwiftUI

/// Debug panel: typed request field, volume buttons and canned `SessionEvent` buttons (§6, Simulator).
struct UIDebugPanelView: View {
    @Bindable var debug: DebugViewModel
    @FocusState private var fieldFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Debug panel")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 8) {
                TextField("Type a request, e.g. where's the coffee", text: $debug.typedRequest)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .frame(minHeight: UITheme.minTarget)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                    .foregroundStyle(Color.black)
                    .focused($fieldFocused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .accessibilityLabel("Typed request")
                Button("Send", action: send)
                    .font(.headline)
                    .buttonStyle(UILargeButtonStyle(filled: true))
                    .frame(width: 100)
                    .disabled(debug.typedRequest.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Send typed request")
            }

            HStack(spacing: 8) {
                Button("Volume ↑", action: debug.volumeUp)
                    .accessibilityLabel("Volume up, talk")
                Button("Volume ↓", action: debug.volumeDown)
                    .accessibilityLabel("Volume down, done")
            }
            .font(.headline)
            .buttonStyle(UILargeButtonStyle())

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(debug.events) { event in
                    Button(event.title) { debug.send(event) }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(UILargeButtonStyle())
                        .accessibilityLabel(event.accessibilityLabel)
                }
            }

            if !debug.canInject {
                Text("The session runner doesn't accept typed requests or events yet.")
                    .font(.footnote)
                    .foregroundStyle(UITheme.secondary)
            }
            if !debug.lastAction.isEmpty {
                Text(debug.lastAction)
                    .font(.footnote)
                    .foregroundStyle(UITheme.secondary)
                    .accessibilityLabel("Last action: \(debug.lastAction)")
            }
        }
    }

    private func send() {
        debug.submitTyped()
        fieldFocused = false
    }
}
