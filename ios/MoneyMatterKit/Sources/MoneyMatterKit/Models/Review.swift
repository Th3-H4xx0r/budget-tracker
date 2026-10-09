import Foundation

/// `GET /transactions/review/summary`.
public struct ReviewSummary: Sendable, Hashable, Decodable {
    public let unreviewedCount: Int
    public let fraudCount: Int

    public init(unreviewedCount: Int, fraudCount: Int) {
        self.unreviewedCount = unreviewedCount
        self.fraudCount = fraudCount
    }
}

struct ReviewUpdateRequest: Encodable, Sendable {
    let transactionIds: [String]
    let action: ReviewAction
}

struct ReviewUpdateResponse: Decodable {
    let updatedCount: Int
}
