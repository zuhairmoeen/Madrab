import Testing
import Foundation
@testable import Madrab
import MadrabScoringEngine

struct PersistedMatchMigrationTests {
    private func makeConfiguration() throws -> MatchConfiguration {
        try MatchConfiguration()
    }

    private func makeCurrentMatch(
        teamAProfileID: UUID? = nil,
        teamBProfileID: UUID? = nil,
        teamAPair: PlayerPair? = nil,
        teamBPair: PlayerPair? = nil,
        processedCommandIDs: Set<UUID> = []
    ) throws -> PersistedMatch {
        PersistedMatch(
            configuration: try makeConfiguration(),
            events: [.pointWon(PointWonEvent(winningTeam: .teamA))],
            teamALabel: "Us",
            teamBLabel: "Them",
            matchID: UUID(),
            teamAProfileID: teamAProfileID,
            teamBProfileID: teamBProfileID,
            teamAPair: teamAPair,
            teamBPair: teamBPair,
            processedCommandIDs: processedCommandIDs
        )
    }

    /// Simulates a pre-sprint on-disk file by encoding a current-shape
    /// `PersistedMatch` and stripping every key this sprint added, rather
    /// than hand-authoring `MatchConfiguration`/`ScoringEvent` JSON by hand.
    private func legacyJSONData(from match: PersistedMatch) throws -> Data {
        let data = try JSONEncoder().encode(match)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "schemaVersion")
        object.removeValue(forKey: "teamAPair")
        object.removeValue(forKey: "teamBPair")
        object.removeValue(forKey: "processedCommandIDs")
        return try JSONSerialization.data(withJSONObject: object)
    }

    @Test func legacyJSONWithNoSchemaVersionDecodesAsVersion1() throws {
        let match = try makeCurrentMatch()
        let legacyData = try legacyJSONData(from: match)

        let decoded = try JSONDecoder().decode(PersistedMatch.self, from: legacyData)

        #expect(decoded.schemaVersion == 1)
    }

    @Test func legacyProfileIDsArePreserved() throws {
        let teamAProfileID = UUID()
        let teamBProfileID = UUID()
        let match = try makeCurrentMatch(teamAProfileID: teamAProfileID, teamBProfileID: teamBProfileID)
        let legacyData = try legacyJSONData(from: match)

        let decoded = try JSONDecoder().decode(PersistedMatch.self, from: legacyData)

        #expect(decoded.teamAProfileID == teamAProfileID)
        #expect(decoded.teamBProfileID == teamBProfileID)
    }

    @Test func missingPairFieldsDecodeAsNil() throws {
        let match = try makeCurrentMatch(teamAProfileID: UUID(), teamBProfileID: UUID())
        let legacyData = try legacyJSONData(from: match)

        let decoded = try JSONDecoder().decode(PersistedMatch.self, from: legacyData)

        #expect(decoded.teamAPair == nil)
        #expect(decoded.teamBPair == nil)
    }

    @Test func missingProcessedCommandIDsDecodesAsEmptySet() throws {
        let match = try makeCurrentMatch()
        let legacyData = try legacyJSONData(from: match)

        let decoded = try JSONDecoder().decode(PersistedMatch.self, from: legacyData)

        #expect(decoded.processedCommandIDs.isEmpty)
    }

    @Test func schemaVersion2MatchRoundTripsCorrectly() throws {
        let teamAPair = PlayerPair(first: UUID(), second: UUID())
        let teamBPair = PlayerPair(first: UUID(), second: UUID())
        let commandID = UUID()
        let match = try makeCurrentMatch(
            teamAPair: teamAPair,
            teamBPair: teamBPair,
            processedCommandIDs: [commandID]
        )

        let data = try JSONEncoder().encode(match)
        let decoded = try JSONDecoder().decode(PersistedMatch.self, from: data)

        #expect(decoded == match)
        #expect(decoded.schemaVersion == PersistedMatch.currentSchemaVersion)
        #expect(decoded.teamAPair == teamAPair)
        #expect(decoded.teamBPair == teamBPair)
        #expect(decoded.processedCommandIDs == [commandID])
    }

    @Test func schemaVersionZeroIsRejected() throws {
        let match = try makeCurrentMatch()
        let legacyData = try legacyJSONData(from: match)
        var object = try #require(try JSONSerialization.jsonObject(with: legacyData) as? [String: Any])
        object["schemaVersion"] = 0
        let corrupted = try JSONSerialization.data(withJSONObject: object)

        do {
            _ = try JSONDecoder().decode(PersistedMatch.self, from: corrupted)
            Issue.record("expected schemaVersion 0 to be rejected")
        } catch {
            // Decoding threw, as required — schemaVersion 0 is outside 1...currentSchemaVersion.
        }
    }

    @Test func schemaVersionAboveCurrentIsRejected() throws {
        let match = try makeCurrentMatch()
        let data = try JSONEncoder().encode(match)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["schemaVersion"] = PersistedMatch.currentSchemaVersion + 1
        let corrupted = try JSONSerialization.data(withJSONObject: object)

        do {
            _ = try JSONDecoder().decode(PersistedMatch.self, from: corrupted)
            Issue.record("expected schemaVersion above currentSchemaVersion to be rejected")
        } catch {
            // Decoding threw, as required — a future/unknown schema is not silently coerced.
        }
    }

    @Test func playerPairRoundTrips() throws {
        let pair = PlayerPair(first: UUID(), second: UUID())

        let data = try JSONEncoder().encode(pair)
        let decoded = try JSONDecoder().decode(PlayerPair.self, from: data)

        #expect(decoded == pair)
    }
}
