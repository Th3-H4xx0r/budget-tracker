import Foundation

/// A timeline occurrence with the fields `PlannedBudgetOccurrence` leaves out:
/// `recurring_actual` rows are real transactions auto-added to the plan that stand in for
/// their recurring payment's projected occurrence, so the payment is counted once.
public struct PlannedBudgetTimelineOccurrence: Sendable, Hashable, Decodable {
    public let occurrence: PlannedBudgetOccurrence
    public let isRecurringActual: Bool
    /// `recurring_actual` only: the real transaction the entry mirrors.
    public let transactionId: String?

    private enum CodingKeys: String, CodingKey { case source, transactionId }

    public init(from decoder: any Decoder) throws {
        occurrence = try PlannedBudgetOccurrence(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isRecurringActual = (try? container.decodeIfPresent(String.self, forKey: .source)) == "recurring_actual"
        transactionId = try? container.decodeIfPresent(String.self, forKey: .transactionId)
    }

    /// Identity for the timeline: an auto-added entry once, whichever source it arrives as.
    public var timelineKey: String {
        if let id = occurrence.id, isRecurringActual || occurrence.source == .manual {
            return "entry-\(id)-\(occurrence.date)"
        }
        let owner = occurrence.id ?? occurrence.subscriptionId ?? "salary"
        return "\(occurrence.source.rawValue)-\(owner)-\(occurrence.date)"
    }

    /// Drops repeats of the same entry, preferring its `recurring_actual` form.
    public static func deduplicated(_ occurrences: [PlannedBudgetTimelineOccurrence]) -> [PlannedBudgetTimelineOccurrence] {
        let actualKeys = Set(occurrences.filter(\.isRecurringActual).map(\.timelineKey))
        var seen = Set<String>()
        return occurrences.filter { item in
            let key = item.timelineKey
            if !item.isRecurringActual && actualKeys.contains(key) { return false }
            return seen.insert(key).inserted
        }
    }
}

/// `GET /future-budgets/:id` with the timeline decoded as `PlannedBudgetTimelineOccurrence`.
@dynamicMemberLookup
public struct PlannedBudgetDetailsWithActuals: Sendable, Hashable, Decodable {
    public let details: PlannedBudgetDetails
    /// Deduplicated so each payment counts once.
    public let occurrences: [PlannedBudgetTimelineOccurrence]

    private enum CodingKeys: String, CodingKey { case occurrences }

    public init(from decoder: any Decoder) throws {
        details = try PlannedBudgetDetails(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decodeLossyArrayIfPresent([PlannedBudgetTimelineOccurrence].self, forKey: .occurrences) ?? []
        occurrences = PlannedBudgetTimelineOccurrence.deduplicated(decoded)
    }

    public subscript<Value>(dynamicMember keyPath: KeyPath<PlannedBudgetDetails, Value>) -> Value {
        details[keyPath: keyPath]
    }

    public func entry(id: String?) -> PlannedBudgetEntry? { details.entry(id: id) }
}

extension Endpoints {
    public static func plannedBudgetDetailsWithActuals(id: String) -> Endpoint<PlannedBudgetDetailsWithActuals> {
        Endpoint(.get, "/future-budgets/\(id)")
    }
}
