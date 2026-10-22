import Foundation
import SwiftData

/// Something the user tries for one night to see if it reduces their snoring.
/// The built-in "No remedy" entry (`isBaseline`) is what every other remedy is compared against.
@Model
final class Remedy {
    var id: UUID = UUID()
    /// Stable identifier for built-in remedies; `nil` for ones the user added.
    var key: String?
    var name: String = ""
    var symbol: String = "sparkles"
    /// Sentence-start phrase used in summaries, e.g. "Sleeping on your side".
    var phrase: String = ""
    var isBaseline: Bool = false
    var isBuiltIn: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Night.remedy)
    var nights: [Night] = []

    init(
        name: String,
        symbol: String,
        phrase: String? = nil,
        key: String? = nil,
        isBaseline: Bool = false,
        isBuiltIn: Bool = false,
        sortOrder: Int = 0
    ) {
        self.name = name
        self.symbol = symbol
        self.phrase = phrase ?? name
        self.key = key
        self.isBaseline = isBaseline
        self.isBuiltIn = isBuiltIn
        self.sortOrder = sortOrder
    }
}
