import Foundation
import SwiftData

struct PlanStepProgress: Equatable, Identifiable {
    let remedyID: UUID
    let completedNights: Int
    let requiredNights: Int

    var id: UUID { remedyID }
    var isComplete: Bool { completedNights >= requiredNights }
}

struct PlanProgress: Equatable {
    let steps: [PlanStepProgress]

    var totalNights: Int { steps.reduce(0) { $0 + $1.requiredNights } }
    var completedNights: Int { steps.reduce(0) { $0 + min($1.completedNights, $1.requiredNights) } }
    var isComplete: Bool { !steps.isEmpty && steps.allSatisfy(\.isComplete) }
    /// "Night 5 of 12": the night the user is about to record.
    var currentNight: Int { min(completedNights + 1, totalNights) }
    /// The remedy for tonight: the first step that still needs nights.
    var suggestedRemedyID: UUID? { steps.first { !$0.isComplete }?.remedyID }
}

/// The guided experiment: baseline nights first, then each chosen remedy in turn.
/// A night counts toward whichever step matches its remedy, so going off-plan for a night
/// never loses data.
enum PlanEngine {
    static let nightsPerStep = 3
    static let maxRemedies = 3

    static func progress(stepRemedyIDs: [UUID], nightsPerStep: Int, nightCounts: [UUID: Int]) -> PlanProgress {
        PlanProgress(steps: stepRemedyIDs.map { id in
            PlanStepProgress(remedyID: id, completedNights: nightCounts[id] ?? 0, requiredNights: nightsPerStep)
        })
    }

    /// Progress from the counted nights recorded since the plan started.
    static func progress(for plan: Plan, nights: [Night]) -> PlanProgress {
        var counts: [UUID: Int] = [:]
        for night in nights where night.countsTowardResults && night.startDate >= plan.createdAt {
            if let id = night.remedy?.id {
                counts[id, default: 0] += 1
            }
        }
        return progress(stepRemedyIDs: plan.stepRemedyIDs, nightsPerStep: plan.nightsPerStep, nightCounts: counts)
    }

    /// The demo plan while demo mode is on, otherwise the newest real plan.
    static func activePlan(in plans: [Plan], demoMode: Bool) -> Plan? {
        let newestFirst = plans.sorted { $0.createdAt > $1.createdAt }
        if demoMode, let demo = newestFirst.first(where: \.isDemo) {
            return demo
        }
        return newestFirst.first { !$0.isDemo }
    }

    /// Creates a plan: the baseline first, then up to `maxRemedies` remedies.
    @discardableResult
    static func createPlan(testing remedyIDs: [UUID], baselineID: UUID?, in context: ModelContext, createdAt: Date = .now, isDemo: Bool = false) -> Plan {
        let steps = (baselineID.map { [$0] } ?? []) + remedyIDs.prefix(maxRemedies)
        let plan = Plan(stepRemedyIDs: steps, createdAt: createdAt, isDemo: isDemo)
        context.insert(plan)
        return plan
    }
}
