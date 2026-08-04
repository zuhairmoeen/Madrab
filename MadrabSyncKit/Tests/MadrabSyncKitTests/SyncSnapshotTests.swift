import Testing
import Foundation

import MadrabScoringEngine
@testable import MadrabSyncKit

struct SyncSnapshotTests {
    @Test func roundTripsGamePhase() throws {
        let phase = SyncActivePhase.game(SyncGameScore(points: TeamPair(teamA: 2, teamB: 1)))
        #expect(try roundTrip(phase) == phase)
    }

    @Test func roundTripsSetTieBreakPhase() throws {
        let phase = SyncActivePhase.setTieBreak(SyncTieBreakScore(points: TeamPair(teamA: 5, teamB: 4)))
        #expect(try roundTrip(phase) == phase)
    }

    @Test func roundTripsMatchTieBreakPhase() throws {
        let phase = SyncActivePhase.matchTieBreak(SyncTieBreakScore(points: TeamPair(teamA: 8, teamB: 6)))
        #expect(try roundTrip(phase) == phase)
    }

    @Test func roundTripsSetScoreWithNoTieBreak() throws {
        let set = SyncSetScore(games: TeamPair(teamA: 6, teamB: 3), tieBreak: nil, winner: .teamA)
        let decoded = try roundTrip(set)
        #expect(decoded == set)
        #expect(decoded.tieBreak == nil)
    }

    @Test func roundTripsSetScoreWithTieBreak() throws {
        let set = SyncSetScore(
            games: TeamPair(teamA: 7, teamB: 6),
            tieBreak: SyncTieBreakScore(points: TeamPair(teamA: 7, teamB: 5)),
            winner: .teamB
        )
        let decoded = try roundTrip(set)
        #expect(decoded == set)
        #expect(decoded.tieBreak != nil)
    }

    @Test func roundTripsUnfinishedSetScoreWithNilWinner() throws {
        let set = SyncSetScore(games: TeamPair(teamA: 3, teamB: 2), tieBreak: nil, winner: nil)
        let decoded = try roundTrip(set)
        #expect(decoded == set)
        #expect(decoded.winner == nil)
    }

    @Test func roundTripsFullSnapshotInLivePhase() throws {
        let snapshot = SyncSnapshot(
            matchID: UUID(),
            stateRevision: 12,
            teamAPair: PairNames(first: "Alice", second: "Bob"),
            teamBPair: PairNames(first: "Cara", second: "Drew"),
            sets: [
                SyncSetScore(games: TeamPair(teamA: 6, teamB: 4), tieBreak: nil, winner: .teamA)
            ],
            currentPhase: .game(SyncGameScore(points: TeamPair(teamA: 1, teamB: 0))),
            servingTeam: .teamB,
            servingPlayer: ServingPlayer(team: .teamB, position: .first),
            matchWinner: nil,
            sessionPhase: .live,
            canUndo: true,
            lastAcknowledgedCommandID: UUID()
        )

        #expect(try roundTrip(snapshot) == snapshot)
    }

    @Test func roundTripsFinishedSnapshotWithNilCurrentPhase() throws {
        let snapshot = SyncSnapshot(
            matchID: UUID(),
            stateRevision: 40,
            teamAPair: PairNames(first: "Alice", second: "Bob"),
            teamBPair: PairNames(first: "Cara", second: "Drew"),
            sets: [
                SyncSetScore(games: TeamPair(teamA: 6, teamB: 4), tieBreak: nil, winner: .teamA),
                SyncSetScore(games: TeamPair(teamA: 6, teamB: 2), tieBreak: nil, winner: .teamA),
            ],
            currentPhase: nil,
            servingTeam: .teamA,
            servingPlayer: nil,
            matchWinner: .teamA,
            sessionPhase: .finished,
            canUndo: false,
            lastAcknowledgedCommandID: UUID()
        )

        let decoded = try roundTrip(snapshot)
        #expect(decoded == snapshot)
        #expect(decoded.currentPhase == nil)
        #expect(decoded.matchWinner == .teamA)
    }

    @Test func roundTripsSetupSnapshotWithNoMatchID() throws {
        let decoded = try roundTrip(SyncSnapshot.unavailable)
        #expect(decoded == SyncSnapshot.unavailable)
        #expect(decoded.matchID == nil)
        #expect(decoded.sessionPhase == .setup)
    }
}
