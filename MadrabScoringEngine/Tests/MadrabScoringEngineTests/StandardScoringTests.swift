import Testing

import MadrabScoringEngine

struct StandardScoringTests {
    @Test func loveToGame() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        submitAll(straightPoints(.teamA, count: 4), to: &engine)

        #expect(engine.state.currentSet?.games == TeamPair(teamA: 1, teamB: 0))
        #expect(engine.state.currentPhase == .game(.initial))
    }

    @Test func deuce() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        submitAll([Team.teamA, .teamB, .teamA, .teamB, .teamA, .teamB].map(pointEvent), to: &engine)

        let expectedScore = GameScore(points: TeamPair(teamA: 3, teamB: 3))
        #expect(engine.state.currentPhase == .game(expectedScore))
        #expect(GamePointLabel(score: expectedScore, deuceRule: .advantage) == .deuce)
    }

    @Test func advantageGained() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        submitAll(
            [Team.teamA, .teamB, .teamA, .teamB, .teamA, .teamB, .teamA].map(pointEvent),
            to: &engine
        )

        let expectedScore = GameScore(points: TeamPair(teamA: 4, teamB: 3))
        #expect(engine.state.currentPhase == .game(expectedScore))
        #expect(
            GamePointLabel(score: expectedScore, deuceRule: .advantage)
                == .advantage(.teamA)
        )
    }

    @Test func advantageLost() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        submitAll(
            [Team.teamA, .teamB, .teamA, .teamB, .teamA, .teamB, .teamA, .teamB]
                .map(pointEvent),
            to: &engine
        )

        let expectedScore = GameScore(points: TeamPair(teamA: 4, teamB: 4))
        #expect(engine.state.currentPhase == .game(expectedScore))
        #expect(
            GamePointLabel(score: expectedScore, deuceRule: .advantage)
                == .deuce
        )
    }

    @Test func repeatedDeuce() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        // 3-3 (deuce), advantage A -> deuce, advantage B -> deuce, advantage A -> game A.
        let sequence: [Team] = [
            .teamA, .teamB, .teamA, .teamB, .teamA, .teamB,
            .teamA, .teamB,
            .teamB, .teamA,
            .teamA, .teamA,
        ]
        submitAll(sequence.map(pointEvent), to: &engine)

        #expect(engine.state.currentSet?.games == TeamPair(teamA: 1, teamB: 0))
        #expect(engine.state.currentPhase == .game(.initial))
    }

    @Test func gameCompletionRequiresWinByTwo() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        submitAll(
            [Team.teamA, .teamA, .teamA, .teamB, .teamB, .teamB, .teamA]
                .map(pointEvent),
            to: &engine
        )

        #expect(engine.state.currentSet?.games == TeamPair(teamA: 0, teamB: 0))
        let expectedScore = GameScore(points: TeamPair(teamA: 4, teamB: 3))
        #expect(engine.state.currentPhase == .game(expectedScore))
        #expect(
            GamePointLabel(score: expectedScore, deuceRule: .advantage)
                == .advantage(.teamA)
        )
    }
}
