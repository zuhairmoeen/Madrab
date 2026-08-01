import Testing
import Foundation
@testable import Madrab

struct LeaderboardTests {
    private func makeTemporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("leaderboard.json")
    }

    // MARK: - LeaderboardFile / LeaderboardStore

    @Test func leaderboardFileRoundTripsThroughCodable() throws {
        let file = LeaderboardFile(
            schemaVersion: 1,
            statsByProfileID: [UUID(): PlayerStats(totalPoints: 3, matchesPlayed: 1, wins: 1, losses: 0)],
            processedMatchIDs: [UUID()]
        )

        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(LeaderboardFile.self, from: data)

        #expect(decoded == file)
    }

    @Test func loadReturnsEmptyFileWhenNoFileExists() {
        let store = LeaderboardStore(fileURL: makeTemporaryFileURL())
        #expect(store.load() == LeaderboardFile())
    }

    @Test func savedLeaderboardRoundTripsThroughLoad() throws {
        let store = LeaderboardStore(fileURL: makeTemporaryFileURL())
        let file = LeaderboardFile(statsByProfileID: [UUID(): PlayerStats(totalPoints: 1)])

        try store.save(file)

        #expect(store.load() == file)
    }

    @Test func loadResetsAndReturnsEmptyForCorruptJSON() throws {
        let fileURL = makeTemporaryFileURL()
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)

        let store = LeaderboardStore(fileURL: fileURL)

        #expect(store.load() == LeaderboardFile())
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func loadResetsAndReturnsEmptyForUnsupportedSchemaVersion() throws {
        let fileURL = makeTemporaryFileURL()
        let futureFile = LeaderboardFile(schemaVersion: 999)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(futureFile).write(to: fileURL)

        let store = LeaderboardStore(fileURL: fileURL)

        #expect(store.load() == LeaderboardFile())
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: - applyMatchResult

    @Test func applyMatchResultUpdatesWinnerAndLoserStats() {
        let winnerID = UUID()
        let loserID = UUID()
        var stats: [UUID: PlayerStats] = [:]

        applyMatchResult(winnerID: winnerID, loserID: loserID, formula: .default, to: &stats)

        #expect(stats[winnerID] == PlayerStats(totalPoints: 3, matchesPlayed: 1, wins: 1, losses: 0))
        #expect(stats[loserID] == PlayerStats(totalPoints: 1, matchesPlayed: 1, wins: 0, losses: 1))
    }

    @Test func applyMatchResultAccumulatesAcrossMultipleMatches() {
        let winnerID = UUID()
        let loserID = UUID()
        var stats: [UUID: PlayerStats] = [:]

        applyMatchResult(winnerID: winnerID, loserID: loserID, formula: .default, to: &stats)
        applyMatchResult(winnerID: loserID, loserID: winnerID, formula: .default, to: &stats)

        #expect(stats[winnerID] == PlayerStats(totalPoints: 4, matchesPlayed: 2, wins: 1, losses: 1))
        #expect(stats[loserID] == PlayerStats(totalPoints: 4, matchesPlayed: 2, wins: 1, losses: 1))
    }

    @Test func applyMatchResultDoesNotAffectUnrelatedProfiles() {
        let unrelatedID = UUID()
        var stats: [UUID: PlayerStats] = [unrelatedID: PlayerStats(totalPoints: 10)]

        applyMatchResult(winnerID: UUID(), loserID: UUID(), formula: .default, to: &stats)

        #expect(stats[unrelatedID] == PlayerStats(totalPoints: 10))
    }

    // MARK: - MatchResultRecorder

    @MainActor
    @Test func recordCompletedMatchAwardsPointsOnce() throws {
        let store = LeaderboardStore(fileURL: makeTemporaryFileURL())
        let recorder = MatchResultRecorder(store: store)
        let matchID = UUID()
        let winnerID = UUID()
        let loserID = UUID()

        try recorder.recordCompletedMatch(matchID: matchID, winnerProfileID: winnerID, loserProfileID: loserID)

        let file = store.load()
        #expect(file.processedMatchIDs.contains(matchID))
        #expect(file.statsByProfileID[winnerID] == PlayerStats(totalPoints: 3, matchesPlayed: 1, wins: 1, losses: 0))
        #expect(file.statsByProfileID[loserID] == PlayerStats(totalPoints: 1, matchesPlayed: 1, wins: 0, losses: 1))
    }

    @MainActor
    @Test func recordCompletedMatchIsIdempotentForTheSameMatchID() throws {
        let store = LeaderboardStore(fileURL: makeTemporaryFileURL())
        let recorder = MatchResultRecorder(store: store)
        let matchID = UUID()
        let winnerID = UUID()
        let loserID = UUID()

        try recorder.recordCompletedMatch(matchID: matchID, winnerProfileID: winnerID, loserProfileID: loserID)
        try recorder.recordCompletedMatch(matchID: matchID, winnerProfileID: winnerID, loserProfileID: loserID)

        let file = store.load()
        #expect(file.statsByProfileID[winnerID] == PlayerStats(totalPoints: 3, matchesPlayed: 1, wins: 1, losses: 0))
        #expect(file.statsByProfileID[loserID] == PlayerStats(totalPoints: 1, matchesPlayed: 1, wins: 0, losses: 1))
    }

    // MARK: - rankedEntries

    @Test func rankedEntriesSortsByPointsDescending() {
        let a = PlayerProfile(displayName: "A")
        let b = PlayerProfile(displayName: "B")
        let stats: [UUID: PlayerStats] = [
            a.id: PlayerStats(totalPoints: 1),
            b.id: PlayerStats(totalPoints: 5)
        ]

        let entries = rankedEntries(statsByProfileID: stats, profiles: [a, b])

        #expect(entries.map(\.profileID) == [b.id, a.id])
        #expect(entries.map(\.rank) == [1, 2])
    }

    @Test func rankedEntriesBreaksPointsTieByWins() {
        let a = PlayerProfile(displayName: "A")
        let b = PlayerProfile(displayName: "B")
        let stats: [UUID: PlayerStats] = [
            a.id: PlayerStats(totalPoints: 4, wins: 1),
            b.id: PlayerStats(totalPoints: 4, wins: 2)
        ]

        let entries = rankedEntries(statsByProfileID: stats, profiles: [a, b])

        #expect(entries.map(\.profileID) == [b.id, a.id])
    }

    @Test func rankedEntriesBreaksWinsTieByMatchesPlayed() {
        let a = PlayerProfile(displayName: "A")
        let b = PlayerProfile(displayName: "B")
        let stats: [UUID: PlayerStats] = [
            a.id: PlayerStats(totalPoints: 4, matchesPlayed: 3, wins: 1),
            b.id: PlayerStats(totalPoints: 4, matchesPlayed: 5, wins: 1)
        ]

        let entries = rankedEntries(statsByProfileID: stats, profiles: [a, b])

        #expect(entries.map(\.profileID) == [b.id, a.id])
    }

    @Test func rankedEntriesBreaksMatchesPlayedTieByLocalizedName() {
        let a = PlayerProfile(displayName: "Zoe")
        let b = PlayerProfile(displayName: "Amy")
        let stats: [UUID: PlayerStats] = [
            a.id: PlayerStats(totalPoints: 4, matchesPlayed: 2, wins: 1),
            b.id: PlayerStats(totalPoints: 4, matchesPlayed: 2, wins: 1)
        ]

        let entries = rankedEntries(statsByProfileID: stats, profiles: [a, b])

        #expect(entries.map(\.profileID) == [b.id, a.id])
    }

    @Test func rankedEntriesBreaksNameTieByUUIDStringAsFinalTieBreak() throws {
        let lowerID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let higherID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let a = PlayerProfile(id: lowerID, displayName: "Sam")
        let b = PlayerProfile(id: higherID, displayName: "Sam")
        let stats: [UUID: PlayerStats] = [
            a.id: PlayerStats(totalPoints: 4, matchesPlayed: 2, wins: 1),
            b.id: PlayerStats(totalPoints: 4, matchesPlayed: 2, wins: 1)
        ]

        let entries = rankedEntries(statsByProfileID: stats, profiles: [a, b])

        #expect(entries.map(\.profileID) == [a.id, b.id])
    }

    @Test func rankedEntriesExcludesStatsForDeletedProfiles() {
        let existing = PlayerProfile(displayName: "Existing")
        let orphanedID = UUID()
        let stats: [UUID: PlayerStats] = [
            existing.id: PlayerStats(totalPoints: 1),
            orphanedID: PlayerStats(totalPoints: 100)
        ]

        let entries = rankedEntries(statsByProfileID: stats, profiles: [existing])

        #expect(entries.map(\.profileID) == [existing.id])
    }
}
