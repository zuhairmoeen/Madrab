import Testing
import Foundation
@testable import Madrab
import MadrabScoringEngine

struct MatchStoreTests {
    private func makeTemporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("active-match.json")
    }

    private func makePersistedMatch() throws -> PersistedMatch {
        PersistedMatch(
            configuration: try MatchConfiguration(),
            events: [.pointWon(PointWonEvent(winningTeam: .teamA))],
            teamALabel: "Us",
            teamBLabel: "Them"
        )
    }

    @Test func loadReturnsNilWhenNoFileExists() {
        let store = MatchStore(fileURL: makeTemporaryFileURL())
        #expect(store.load() == nil)
    }

    @Test func savedMatchRoundTripsThroughLoad() throws {
        let store = MatchStore(fileURL: makeTemporaryFileURL())
        let match = try makePersistedMatch()

        try store.save(match)

        #expect(store.load() == match)
    }

    @Test func savingAgainOverwritesThePreviousMatch() throws {
        let store = MatchStore(fileURL: makeTemporaryFileURL())
        try store.save(try makePersistedMatch())

        let secondEvents: [ScoringEvent] = [
            .pointWon(PointWonEvent(winningTeam: .teamA)),
            .pointWon(PointWonEvent(winningTeam: .teamB))
        ]
        let second = PersistedMatch(
            configuration: try MatchConfiguration(),
            events: secondEvents,
            teamALabel: "Us",
            teamBLabel: "Them"
        )
        try store.save(second)

        #expect(store.load() == second)
    }

    @Test func loadDeletesAndReturnsNilForUnreadableJSON() throws {
        let fileURL = makeTemporaryFileURL()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not valid json".utf8).write(to: fileURL)

        let store = MatchStore(fileURL: fileURL)

        #expect(store.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func clearRemovesThePersistedFile() throws {
        let fileURL = makeTemporaryFileURL()
        let store = MatchStore(fileURL: fileURL)
        try store.save(try makePersistedMatch())
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        store.clear()

        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(store.load() == nil)
    }

    @Test func persistedMatchReplaysToTheSameEngineState() throws {
        let store = MatchStore(fileURL: makeTemporaryFileURL())
        let configuration = try MatchConfiguration()

        var engine = MatchEngine(configuration: configuration)
        _ = engine.submit(.pointWon(PointWonEvent(winningTeam: .teamA)))
        _ = engine.submit(.pointWon(PointWonEvent(winningTeam: .teamA)))

        try store.save(PersistedMatch(
            configuration: configuration,
            events: engine.events,
            teamALabel: "Us",
            teamBLabel: "Them"
        ))

        let restored = try #require(store.load())
        let restoredEngine = try MatchEngine(configuration: restored.configuration, events: restored.events)

        #expect(restoredEngine.state == engine.state)
    }
}
