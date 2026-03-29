import SwiftUI

@main
struct GemmaLocalApp: App {
    @StateObject private var llmService = LLMService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(llmService)
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .background:
                // 进入后台时释放模型以节省内存
                llmService.handleMemoryPressure()
            case .inactive:
                break
            case .active:
                break
            @unknown default:
                break
            }
        }
    }
}
