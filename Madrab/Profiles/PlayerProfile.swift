import Foundation

nonisolated struct PlayerProfile: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var displayName: String
    var avatarImageData: Data?

    init(id: UUID = UUID(), displayName: String, avatarImageData: Data? = nil) {
        self.id = id
        self.displayName = displayName
        self.avatarImageData = avatarImageData
    }
}
