import Foundation

nonisolated struct LeaderboardFile: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = 1
    var statsByProfileID: [UUID: PlayerStats] = [:]
    var processedMatchIDs: Set<UUID> = []
}
