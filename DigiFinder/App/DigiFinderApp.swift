import SwiftUI

@main
struct DigiFinderApp: App {
    @State private var model = AppViewModel(env: .current())

    var body: some Scene {
        WindowGroup {
            MainView(model: model)
        }
    }
}
