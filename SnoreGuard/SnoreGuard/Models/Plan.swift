import Foundation
import SwiftData

/// A guided experiment: a few baseline nights, then a few nights of each chosen remedy.
@Model
final class Plan {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    /// Remedy IDs in the order they should be tested, baseline first.
    var stepRemedyIDs: [UUID] = []
    var nightsPerStep: Int = 3
    var isDemo: Bool = false

    init(stepRemedyIDs: [UUID], nightsPerStep: Int = PlanEngine.nightsPerStep, createdAt: Date = .now, isDemo: Bool = false) {
        self.stepRemedyIDs = stepRemedyIDs
        self.nightsPerStep = nightsPerStep
        self.createdAt = createdAt
        self.isDemo = isDemo
    }
}
