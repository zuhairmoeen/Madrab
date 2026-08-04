import Foundation
import MadrabScoringEngine

nonisolated struct PersistedMatch: Codable, Equatable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let configuration: MatchConfiguration
    let events: [ScoringEvent]
    let teamALabel: String
    let teamBLabel: String
    let matchID: UUID?
    let teamAProfileID: UUID?
    let teamBProfileID: UUID?
    let teamAPair: PlayerPair?
    let teamBPair: PlayerPair?
    let processedCommandIDs: Set<UUID>

    init(
        configuration: MatchConfiguration,
        events: [ScoringEvent],
        teamALabel: String,
        teamBLabel: String,
        matchID: UUID? = nil,
        teamAProfileID: UUID? = nil,
        teamBProfileID: UUID? = nil,
        teamAPair: PlayerPair? = nil,
        teamBPair: PlayerPair? = nil,
        processedCommandIDs: Set<UUID> = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.configuration = configuration
        self.events = events
        self.teamALabel = teamALabel
        self.teamBLabel = teamBLabel
        self.matchID = matchID
        self.teamAProfileID = teamAProfileID
        self.teamBProfileID = teamBProfileID
        self.teamAPair = teamAPair
        self.teamBPair = teamBPair
        self.processedCommandIDs = processedCommandIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard (1...Self.currentSchemaVersion).contains(decodedVersion) else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported PersistedMatch schemaVersion \(decodedVersion); supported range is 1...\(Self.currentSchemaVersion)."
            )
        }

        schemaVersion = decodedVersion
        configuration = try container.decode(MatchConfiguration.self, forKey: .configuration)
        events = try container.decode([ScoringEvent].self, forKey: .events)
        teamALabel = try container.decode(String.self, forKey: .teamALabel)
        teamBLabel = try container.decode(String.self, forKey: .teamBLabel)
        matchID = try container.decodeIfPresent(UUID.self, forKey: .matchID)
        teamAProfileID = try container.decodeIfPresent(UUID.self, forKey: .teamAProfileID)
        teamBProfileID = try container.decodeIfPresent(UUID.self, forKey: .teamBProfileID)
        teamAPair = try container.decodeIfPresent(PlayerPair.self, forKey: .teamAPair)
        teamBPair = try container.decodeIfPresent(PlayerPair.self, forKey: .teamBPair)
        processedCommandIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .processedCommandIDs) ?? []
    }
}
