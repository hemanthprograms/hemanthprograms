import Foundation
import SwiftData

enum AppBootstrap {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static func makeContainer() -> ModelContainer {
        let schema = Schema([Night.self, SnoreEvent.self, Remedy.self, Plan.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isRunningTests)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Couldn't open the SnoreGuard database: \(error)")
        }
    }

    /// Launch-time housekeeping: built-in remedies, nights cut short, and the demo default.
    @MainActor
    static func prepare(_ context: ModelContext) {
        RemedyCatalog.seedBuiltIns(in: context)
        NightStore.recoverInterruptedNights(in: context)
        applyDemoDefault(in: context)
        try? context.save()
    }

    /// Debug builds in the Simulator start with demo mode on, once, so every screen has data.
    @MainActor
    private static func applyDemoDefault(in context: ModelContext) {
        #if DEBUG && targetEnvironment(simulator)
        let defaults = UserDefaults.standard
        guard !isRunningTests, !defaults.bool(forKey: SettingsKey.demoDefaultApplied) else { return }
        defaults.set(true, forKey: SettingsKey.demoDefaultApplied)
        defaults.set(true, forKey: SettingsKey.demoMode)
        DemoData.seed(in: context)
        #endif
    }
}
