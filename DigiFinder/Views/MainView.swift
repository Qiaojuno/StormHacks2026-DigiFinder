// Wave 1 stub of the MVP screen (§6). The UI agent implements the full layout.
import SwiftUI

struct MainView: View {
    let model: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.stepTitle)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text(model.lastMessage)
                .font(.title2)
            Spacer()
            Button("TALK") { model.talkTapped() }
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, minHeight: 120)
                .buttonStyle(.borderedProminent)
            Text("Volume up: talk. Volume down: done.")
                .font(.body)
        }
        .padding()
        .background(CaptureEventView(onTalk: { model.volumeUp() }, onDone: { model.volumeDown() }))
        .onAppear { model.onAppear() }
    }
}
