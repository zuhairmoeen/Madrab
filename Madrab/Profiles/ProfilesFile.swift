import Foundation

struct ProfilesFile: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = 1
    var profiles: [PlayerProfile] = []
}
