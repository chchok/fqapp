import SwiftUI

@main
struct XiaomanReadingApp: App {
    var body: some Scene {
        WindowGroup {
            XiaomanReadingView()
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .defaultSize(width: 1000, height: 720)
        #endif
    }
}
