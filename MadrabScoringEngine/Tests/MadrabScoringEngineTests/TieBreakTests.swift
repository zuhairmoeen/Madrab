import Testing

import MadrabScoringEngine

struct TieBreakTests {
    private func alternatingGameWinners(count: Int) -> [Team] {
        (0..<count).map { $0 % 2 == 0 ? Team.teamA : Team.teamB }
    }

    @Test func standardTieBreak() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        submitAll(gameWinners(alternatingGameWinners(count: 12)), to: &engine)

        #expect(engine.state.currentSet?.games == TeamPair(teamA: 6, teamB: 6))
        #expect(engine.state.currentPhase == .setTieBreak(.initial))

        submitAll(straightPoints(.teamA, count: 7), to: &engine)

        #expect(engine.state.sets.count == 1)
        #expect(engine.state.sets[0].winner == .teamA)
        #expect(engine.state.sets[0].tieBreak?.points == TeamPair(teamA: 7, teamB: 0))
    }

    @Test func tieBreakRequiresWinByTwoPoints() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        submitAll(gameWinners(alternatingGameWinners(count: 12)), to: &engine)

        // Alternate to 6-6 inside the tie-break.
        submitAll(alternatingGameWinners(count: 12).map(pointEvent), to: &engine)
        #expect(engine.state.sets.isEmpty)
        #expect(
            engine.state.currentSet?.tieBreak?.points
                == TeamPair(teamA: 6, teamB: 6)
        )

        // 7-6 is not enough to win.
        submitAll([pointEvent(.teamA)], to: &engine)
        #expect(engine.state.sets.isEmpty)
        #expect(
            engine.state.currentSet?.tieBreak?.points
                == TeamPair(teamA: 7, teamB: 6)
        )

        // 8-6 wins by two.
        submitAll([pointEvent(.teamA)], to: &engine)
        #expect(engine.state.sets.count == 1)
        #expect(engine.state.sets[0].tieBreak?.points == TeamPair(teamA: 8, teamB: 6))
    }

    @Test func extendedTieBreakContinuesUncapped() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        submitAll(gameWinners(alternatingGameWinners(count: 12)), to: &engine)

        // Alternate to 10-10 inside the tie-break.
        submitAll(alternatingGameWinners(count: 20).map(pointEvent), to: &engine)
        #expect(engine.state.sets.isEmpty)
        #expect(engine.state.currentSet?.tieBreak?.points == TeamPair(teamA: 10, teamB: 10))

        // Two more straight points finally wins it 12-10.
        submitAll(straightPoints(.teamA, count: 2), to: &engine)
        #expect(engine.state.sets.count == 1)
        #expect(
            engine.state.sets[0].tieBreak?.points
                == TeamPair(teamA: 12, teamB: 10)
        )
    }

    @Test func matchTieBreakDecidesMatchDirectly() throws {
        let configuration = try MatchConfiguration(
            finalSetMode: .matchTiebreak(points: 10)
        )
        var engine = MatchEngine(configuration: configuration)

        var winners: [Team] = Array(repeating: .teamA, count: 6)
        winners.append(contentsOf: Array(repeating: .teamB, count: 6))
        submitAll(gameWinners(winners), to: &engine)
        #expect(engine.state.currentPhase == .matchTieBreak(.initial))

        submitAll(straightPoints(.teamA, count: 10), to: &engine)

        #expect(engine.state.matchWinner == .teamA)
        #expect(engine.state.sets.count == 3)
        #expect(
            engine.state.sets[2].tieBreak?.points
                == TeamPair(teamA: 10, teamB: 0)
        )
        #expect(engine.state.currentSet == nil)
        #expect(engine.state.currentPhase == nil)
    }

    @Test func tieBreakServingRotatesOneThenEveryTwoPoints() throws {
        let configuration = try MatchConfiguration(
            servingPlayerTrackingEnabled: true
        )
        var engine = MatchEngine(configuration: configuration)
        submitAll(gameWinners(alternatingGameWinners(count: 12)), to: &engine)

        // 12 games played (outer turn 12, even) -> teamA serves the first tie-break point.
        #expect(engine.state.servingTeam == .teamA)

        engine.submit(pointEvent(.teamA))
        // 1 point played -> block 1 (turn 13, odd) -> teamB.
        #expect(engine.state.servingTeam == .teamB)

        engine.submit(pointEvent(.teamA))
        // 2 points played -> still block 1 (turn 13) -> teamB again.
        #expect(engine.state.servingTeam == .teamB)

        engine.submit(pointEvent(.teamA))
        // 3 points played -> block 2 (turn 14, even) -> teamA.
        #expect(engine.state.servingTeam == .teamA)
    }
}
