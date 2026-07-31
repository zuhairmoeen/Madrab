import Testing

import MadrabScoringEngine

struct SetsAndMatchTests {
    @Test func normalSetCompletion() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        submitAll(
            gameWinners([.teamB, .teamB, .teamB, .teamA, .teamA, .teamA, .teamA, .teamA, .teamA]),
            to: &engine
        )

        #expect(engine.state.sets.count == 1)
        #expect(engine.state.sets[0].winner == .teamA)
        #expect(engine.state.sets[0].games == TeamPair(teamA: 6, teamB: 3))
        #expect(engine.state.sets[0].tieBreak == nil)
    }

    @Test func straightSetsVictory() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        submitAll(gameWinners(Array(repeating: Team.teamA, count: 12)), to: &engine)

        #expect(engine.state.matchWinner == .teamA)
        #expect(engine.state.setsWon == TeamPair(teamA: 2, teamB: 0))
        #expect(engine.state.sets.count == 2)
        #expect(engine.state.currentPhase == nil)
        #expect(engine.state.currentSet == nil)
    }

    @Test func threeSetMatch() throws {
        let configuration = try MatchConfiguration(finalSetMode: .fullSet)
        var engine = MatchEngine(configuration: configuration)

        var winners: [Team] = Array(repeating: .teamA, count: 6)
        winners.append(contentsOf: Array(repeating: .teamB, count: 6))
        winners.append(contentsOf: Array(repeating: .teamA, count: 6))

        submitAll(gameWinners(winners), to: &engine)

        #expect(engine.state.sets.count == 3)
        #expect(engine.state.matchWinner == .teamA)
        #expect(engine.state.setsWon == TeamPair(teamA: 2, teamB: 1))
    }

    @Test func bestOfThreeMatchCompletionViaSubmit() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        let events = gameWinners(Array(repeating: Team.teamA, count: 12))

        for event in events {
            #expect(engine.submit(event).isSuccess)
        }

        #expect(engine.state.matchWinner == .teamA)
        #expect(engine.events.count == events.count)
    }

    @Test func finalSetConfigurationFullSet() throws {
        let configuration = try MatchConfiguration(finalSetMode: .fullSet)
        var engine = MatchEngine(configuration: configuration)

        var winners: [Team] = Array(repeating: .teamA, count: 6)
        winners.append(contentsOf: Array(repeating: .teamB, count: 6))
        submitAll(gameWinners(winners), to: &engine)

        #expect(engine.state.setsWon == TeamPair(teamA: 1, teamB: 1))
        #expect(engine.state.currentSet == SetScore(games: TeamPair(teamA: 0, teamB: 0), tieBreak: nil, winner: nil))
        #expect(engine.state.currentPhase == .game(.initial))
    }

    @Test func finalSetConfigurationMatchTiebreak() throws {
        let configuration = try MatchConfiguration(
            finalSetMode: .matchTiebreak(points: 10)
        )
        var engine = MatchEngine(configuration: configuration)

        var winners: [Team] = Array(repeating: .teamA, count: 6)
        winners.append(contentsOf: Array(repeating: .teamB, count: 6))
        submitAll(gameWinners(winners), to: &engine)

        #expect(engine.state.setsWon == TeamPair(teamA: 1, teamB: 1))
        #expect(engine.state.currentSet == nil)
        #expect(engine.state.currentPhase == .matchTieBreak(.initial))
    }
}
