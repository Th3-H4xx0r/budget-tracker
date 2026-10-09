import Foundation

/// `GET /tags`.
public struct Tag: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let name: String
    /// `#rrggbb`.
    public let color: String
    public let icon: String?
    public let description: String?
    public let remindersCount: Int?

    public init(id: String, name: String, color: String = "#8e8e93", icon: String? = nil, description: String? = nil, remindersCount: Int? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.icon = icon
        self.description = description
        self.remindersCount = remindersCount
    }

    private enum CodingKeys: String, CodingKey { case id, name, color, icon, description, remindersCount }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? "#8e8e93"
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        remindersCount = try container.decodeIfPresent(Int.self, forKey: .remindersCount)
    }
}
