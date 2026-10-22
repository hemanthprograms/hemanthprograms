import Foundation
import SwiftData

enum NightStore {
    /// Deletes a night, its events and any saved clips.
    static func delete(_ night: Night, in context: ModelContext) {
        ClipStore.delete(night.events.compactMap(\.clipFileName))
        context.delete(night)
    }

    /// Wipes every night, plan and custom remedy, plus all clips. Built-in remedies stay.
    static func deleteAll(in context: ModelContext) {
        for night in (try? context.fetch(FetchDescriptor<Night>())) ?? [] {
            context.delete(night)
        }
        for plan in (try? context.fetch(FetchDescriptor<Plan>())) ?? [] {
            context.delete(plan)
        }
        for remedy in RemedyCatalog.allRemedies(in: context) where !remedy.isBuiltIn {
            context.delete(remedy)
        }
        ClipStore.deleteAll()
        try? context.save()
    }

    /// Nights still marked in progress at launch were cut short (the app was closed or stopped
    /// unexpectedly). Keep what the last checkpoint saved; drop nights that saved nothing.
    static func recoverInterruptedNights(in context: ModelContext) {
        let descriptor = FetchDescriptor<Night>(predicate: #Predicate<Night> { $0.isInProgress == true })
        for night in (try? context.fetch(descriptor)) ?? [] {
            if night.recordedDuration <= 0 && night.events.isEmpty {
                delete(night, in: context)
            } else {
                night.isInProgress = false
                night.wasRecovered = true
                night.recomputeTotals()
            }
        }
    }
}
