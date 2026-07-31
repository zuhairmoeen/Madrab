import Testing

@testable import MadrabScoringEngine

/// Exercises `ScoreBuilder` directly (via `@testable import`) with raw
/// `[Team]` point sequences — the layer responsible for serve rotation,
/// independent of event-log mechanics.
struct ServingRotationTests {
    private func trackedConfiguration() throws -> MatchConfiguration {
        try MatchConfiguration(servingPlayerTrackingEnabled: true)
    }

    /// Requirement 1: after a normally completed set (no tie-break), the
    /// next server continues the outer per-game rotation exactly once per
    /// game played — no double-counting the set-winning game.
    @Test func firstServerAfterNormallyCompletedSet() throws {
        let configuration = try trackedConfiguration()
        // Team A wins 6 straight games, 4-0 each: a normal 6-0 set, 6 games played.
        let winners = Array(repeating: Team.teamA, count: 6 * 4)

        let state = ScoreBuilder.score(for: winners, configuration: configuration, isTerminal: false)

        #expect(state.sets.count == 1)
        #expect(state.sets[0].winner == .teamA)
        #expect(state.sets[0].games == TeamPair(teamA: 6, teamB: 0))
        // 6 games played -> outer turn 6 (even) -> teamA serves; teamA's 4th
        // service turn (index 3, odd) -> .second.
        #expect(state.servingTeam == .teamA)
        #expect(state.servingPlayer == ServingPlayer(team: .teamA, position: .second))
    }

    /// Requirement 2: a set decided by a tie-break must still advance the
    /// outer rotation by exactly one turn for the whole tie-break, not one
    /// turn per tie-break point.
    @Test func firstServerAfterSetCompletedByTieBreak() throws {
        let configuration = try trackedConfiguration()

        // 12 games alternating winner, 4-0 each, reaching 6-6.
        var winners: [Team] = []
        for i in 0..<12 {
            let winner: Team = i % 2 == 0 ? .teamA : .teamB
            winners.append(contentsOf: Array(repeating: winner, count: 4))
        }
        // Tie-break decided 7-0 by teamA.
        winners.append(contentsOf: Array(repeating: Team.teamA, count: 7))

        let state = ScoreBuilder.score(for: winners, configuration: configuration, isTerminal: false)

        #expect(state.sets.count == 1)
        #expect(state.sets[0].winner == .teamA)
        #expect(state.sets[0].games == TeamPair(teamA: 6, teamB: 6))
        #expect(state.sets[0].tieBreak?.points == TeamPair(teamA: 7, teamB: 0))
        // 12 games + 1 (the tie-break, as a whole) = outer turn 13 (odd) -> teamB serves;
        // teamB's 7th service turn (index 6, even) -> .first.
        #expect(state.servingTeam == .teamB)
        #expect(state.servingPlayer == ServingPlayer(team: .teamB, position: .first))
    }

    /// Requirement 3: entering a deciding match tie-break must not itself
    /// consume an extra outer turn beyond the set-winning game that led into it.
    @Test func firstServerAtStartOfDecidingMatchTieBreak() throws {
        let configuration = try trackedConfiguration()

        // Set 1: teamA wins 6-0 (6 games). Set 2: teamB wins 6-0 (6 games).
        // 1-1 in sets with setsToWin == 2 -> the third set is the decider,
        // and finalSetMode defaults to .matchTiebreak, so no games are played
        // in it at all before this point.
        var winners = Array(repeating: Team.teamA, count: 6 * 4)
        winners.append(contentsOf: Array(repeating: Team.teamB, count: 6 * 4))

        let state = ScoreBuilder.score(for: winners, configuration: configuration, isTerminal: false)

        #expect(state.sets.count == 2)
        #expect(state.setsWon == TeamPair(teamA: 1, teamB: 1))
        #expect(state.currentSet == nil)
        #expect(state.currentPhase == .matchTieBreak(.initial))
        // 12 games total played, 0 points yet in the breaker -> outer turn 12
        // (even) -> teamA serves; teamA's 7th service turn (index 6, even) -> .first.
        #expect(state.servingTeam == .teamA)
        #expect(state.servingPlayer == ServingPlayer(team: .teamA, position: .first))
    }
}
