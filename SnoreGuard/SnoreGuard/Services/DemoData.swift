import Foundation
import SwiftData

/// Twelve realistic sample nights so every screen can be shown without sleeping.
///
/// The story: four baseline nights, four nights on the side (a clear win), three with a nasal
/// strip (a small, uncertain drop) and one with an extra pillow (too early to tell).
/// Generation is seeded, so the demo looks the same every time.
enum DemoData {
    struct NightSpec {
        let daysAgo: Int
        let remedyKey: String
        /// Target snore minutes per hour.
        let perHour: Double
    }

    static let specs: [NightSpec] = [
        NightSpec(daysAgo: 12, remedyKey: RemedyCatalog.baselineKey, perHour: 14.2),
        NightSpec(daysAgo: 11, remedyKey: RemedyCatalog.baselineKey, perHour: 11.8),
        NightSpec(daysAgo: 10, remedyKey: RemedyCatalog.baselineKey, perHour: 16.1),
        NightSpec(daysAgo: 9, remedyKey: RemedyCatalog.baselineKey, perHour: 13.5),
        NightSpec(daysAgo: 8, remedyKey: "side", perHour: 8.1),
        NightSpec(daysAgo: 7, remedyKey: "side", perHour: 9.6),
        NightSpec(daysAgo: 6, remedyKey: "side", perHour: 7.2),
        NightSpec(daysAgo: 5, remedyKey: "side", perHour: 8.8),
        NightSpec(daysAgo: 4, remedyKey: "nasal-strip", perHour: 11.9),
        NightSpec(daysAgo: 3, remedyKey: "nasal-strip", perHour: 11.2),
        NightSpec(daysAgo: 2, remedyKey: "nasal-strip", perHour: 12.6),
        NightSpec(daysAgo: 1, remedyKey: "extra-pillow", perHour: 12.9),
    ]

    static let planKeys = [RemedyCatalog.baselineKey, "side", "nasal-strip", "extra-pillow"]

    /// Replaces any existing demo data with a fresh set of demo nights and a demo plan.
    static func seed(in context: ModelContext, now: Date = .now) {
        remove(from: context)
        RemedyCatalog.seedBuiltIns(in: context)
        let remedies = RemedyCatalog.allRemedies(in: context)
        func findRemedy(_ key: String) -> Remedy? { remedies.first { $0.key == key } }

        var generator = SplitMix64(seed: 42)
        let calendar = Calendar.current
        var today = calendar.startOfDay(for: now)
        if calendar.component(.hour, from: now) < 9, let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
            // Before 9 AM, "last night" hasn't finished yet.
            today = yesterday
        }

        var earliestStart = now
        for spec in specs {
            guard let remedy = findRemedy(spec.remedyKey),
                  let day = calendar.date(byAdding: .day, value: -spec.daysAgo, to: today) else { continue }
            let start = day.addingTimeInterval(22.5 * 3600 + Double.random(in: 0...4_500, using: &generator))
            let duration = Double.random(in: 6.6...8.0, using: &generator) * 3600
            let events = makeEvents(totalSnoreSeconds: spec.perHour * duration / 60, nightDuration: duration, generator: &generator)

            let night = Night(startDate: start, threshold: DetectionConfig.defaultThreshold, source: .demo, isDemo: true)
            context.insert(night)
            night.remedy = remedy
            for event in events {
                night.addEvent(event, in: context)
            }
            night.endDate = start.addingTimeInterval(duration)
            night.recordedDuration = duration
            night.recomputeTotals()
            earliestStart = min(earliestStart, start)
        }

        PlanEngine.createPlan(
            testing: planKeys.dropFirst().compactMap { findRemedy($0)?.id },
            baselineID: findRemedy(RemedyCatalog.baselineKey)?.id,
            in: context,
            createdAt: earliestStart.addingTimeInterval(-3600),
            isDemo: true
        )
        try? context.save()
    }

    static func remove(from context: ModelContext) {
        let nights = (try? context.fetch(FetchDescriptor<Night>(predicate: #Predicate<Night> { $0.isDemo == true }))) ?? []
        for night in nights {
            NightStore.delete(night, in: context)
        }
        let plans = (try? context.fetch(FetchDescriptor<Plan>(predicate: #Predicate<Plan> { $0.isDemo == true }))) ?? []
        for plan in plans {
            context.delete(plan)
        }
        try? context.save()
    }

    /// Spreads snoring across the night in 5-minute slots, heavier in two "bouts" (early and
    /// late in the night), with short events separated by quiet gaps longer than the merge gap.
    static func makeEvents(totalSnoreSeconds: Double, nightDuration: TimeInterval, generator: inout SplitMix64) -> [DetectedEvent] {
        let slotLength: TimeInterval = 300
        let slotCount = max(1, Int(nightDuration / slotLength))
        let weights = (0..<slotCount).map { index -> Double in
            let x = (Double(index) + 0.5) / Double(slotCount)
            let bouts = exp(-pow((x - 0.35) / 0.18, 2)) + 0.8 * exp(-pow((x - 0.7) / 0.15, 2))
            return 0.15 + bouts * Double.random(in: 0.6...1.4, using: &generator)
        }
        let weightSum = weights.reduce(0, +)

        var events: [DetectedEvent] = []
        var carry: TimeInterval = 0
        for (index, weight) in weights.enumerated() {
            var remaining = totalSnoreSeconds * weight / weightSum + carry
            let slotStart = Double(index) * slotLength + Double.random(in: 0...15, using: &generator)
            // Keep a quiet gap after the previous slot's last event, or the two would have merged.
            var cursor = max(slotStart, (events.last?.end ?? -.infinity) + DetectionConfig.mergeGap + 1)
            let slotEnd = Double(index + 1) * slotLength
            while remaining >= DetectionConfig.minimumEventDuration {
                let duration = min(remaining, Double.random(in: 15...55, using: &generator))
                guard cursor + duration <= slotEnd else { break }
                let confidence = Double.random(in: 0.62...0.97, using: &generator)
                events.append(DetectedEvent(start: cursor, duration: duration, peakConfidence: confidence))
                remaining -= duration
                cursor += duration + DetectionConfig.mergeGap + Double.random(in: 1...20, using: &generator)
            }
            carry = remaining
        }
        return events
    }
}
