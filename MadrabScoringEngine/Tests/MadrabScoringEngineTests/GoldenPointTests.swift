import Testing

import MadrabScoringEngine

struct GoldenPointTests {
    private func goldenConfiguration() throws -> MatchConfiguration {
        try MatchConfiguration(deuceRule: .goldenPoint)
    }

    @Test func goldenPointReached() throws {
        var engine = MatchEngine(configuration: try goldenConfiguration())
        submitAll([Team.teamA, .teamB, .teamA, .teamB, .teamA, .teamB].map(pointEvent), to: &engine)

        let expectedScore = GameScore(points: TeamPair(teamA: 3, teamB: 3))
        #expect(engine.state.currentPhase == .game(expectedScore))
        #expect(GamePointLabel(score: expectedScore, deuceRule: .goldenPoint) == .goldenPoint)
    }

    @Test func teamAWinsGoldenPoint() throws {
        var engine = MatchEngine(configuration: try goldenConfiguration())
        submitAll(
            [Team.teamA, .teamB, .teamA, .teamB, .teamA, .teamB, .teamA].map(pointEvent),
            to: &engine
        )

        #expect(engine.state.currentSet?.games == TeamPair(teamA: 1, teamB: 0))
        #expect(engine.state.currentPhase == .game(.initial))
    }

    @Test func teamBWinsGoldenPoint() throws {
        var engine = MatchEngine(configuration: try goldenConfiguration())
        submitAll(
            [Team.teamA, .teamB, .teamA, .teamB, .teamA, .teamB, .teamB]
                .map(pointEvent),
            to: &engine
        )

        #expect(engine.state.currentSet?.games == TeamPair(teamA: 0, teamB: 1))
        #expect(engine.state.currentPhase == .game(.initial))
    }
}
