import SwiftUI

@main
struct TFBoardViewerApp: App {
    var body: some Scene {
        WindowGroup {
            WindowRootView()
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowStyle(.titleBar)
    }
}

private struct WindowRootView: View {
    @State private var state = AppState()

    var body: some View {
        ContentView()
            .environment(state)
    }
}
