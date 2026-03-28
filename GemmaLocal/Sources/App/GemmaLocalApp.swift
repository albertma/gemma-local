import SwiftUI

@main
struct GemmaLocalApp: App {
    @StateObject private var llmService = LLMService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(llmService)
        }
    }
}
