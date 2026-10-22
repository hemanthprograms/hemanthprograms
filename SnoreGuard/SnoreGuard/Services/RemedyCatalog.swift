import Foundation
import SwiftData

enum RemedyCatalog {
    struct BuiltIn {
        let key: String
        let name: String
        let symbol: String
        let phrase: String
        let isBaseline: Bool
    }

    static let baselineKey = "baseline"

    static let builtIns: [BuiltIn] = [
        BuiltIn(key: baselineKey, name: "No remedy", symbol: "moon.zzz", phrase: "Sleeping without a remedy", isBaseline: true),
        BuiltIn(key: "side", name: "Sleep on side", symbol: "bed.double", phrase: "Sleeping on your side", isBaseline: false),
        BuiltIn(key: "no-alcohol", name: "No alcohol after 7pm", symbol: "wineglass", phrase: "Skipping alcohol after 7pm", isBaseline: false),
        BuiltIn(key: "nasal-strip", name: "Nasal strip", symbol: "nose", phrase: "A nasal strip", isBaseline: false),
        BuiltIn(key: "extra-pillow", name: "Extra pillow", symbol: "square.stack.3d.up", phrase: "An extra pillow", isBaseline: false),
        BuiltIn(key: "nasal-rinse", name: "Nasal rinse before bed", symbol: "drop", phrase: "A nasal rinse before bed", isBaseline: false),
    ]

    /// Symbols offered for remedies the user adds.
    static let customSymbols = ["sparkles", "leaf", "pills", "mouth", "cup.and.saucer", "wind", "humidity", "figure.walk", "heart", "star"]

    /// Inserts any built-in remedy that isn't stored yet. Safe to call on every launch.
    static func seedBuiltIns(in context: ModelContext) {
        let existingKeys = Set(allRemedies(in: context).compactMap(\.key))
        for (index, item) in builtIns.enumerated() where !existingKeys.contains(item.key) {
            context.insert(Remedy(
                name: item.name,
                symbol: item.symbol,
                phrase: item.phrase,
                key: item.key,
                isBaseline: item.isBaseline,
                isBuiltIn: true,
                sortOrder: index
            ))
        }
    }

    static func allRemedies(in context: ModelContext) -> [Remedy] {
        (try? context.fetch(FetchDescriptor<Remedy>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
    }

    static func remedy(withKey key: String, in context: ModelContext) -> Remedy? {
        allRemedies(in: context).first { $0.key == key }
    }

    /// Adds a user-defined remedy. Returns `nil` for an empty name.
    @discardableResult
    static func addCustom(name: String, symbol: String, in context: ModelContext) -> Remedy? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let nextOrder = (allRemedies(in: context).map(\.sortOrder).max() ?? 0) + 1
        let remedy = Remedy(name: trimmed, symbol: symbol, sortOrder: max(nextOrder, 100))
        context.insert(remedy)
        return remedy
    }
}
