import SwiftData
import SwiftUI

@main
struct SnoreGuardApp: App {
    private let container: ModelContainer
    @State private var recordingService: RecordingService

    init() {
        let container = AppBootstrap.makeContainer()
        AppBootstrap.prepare(container.mainContext)
        self.container = container
        _recordingService = State(initialValue: RecordingService())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(recordingService)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .modelContainer(container)
    }
}
