import Foundation
import Observation
import MadrabScoringEngine

@Observable
final class MatchSessionViewModel {
    enum Phase {
        case setup
        case live(MatchState)
        case finished(Team)
    }

    private(set) var phase: Phase = .setup
    private(set) var teamALabel = "Team A"
    private(set) var teamBLabel = "Team B"

    private var engine: MatchEngine?

    var state: MatchState? {
        switch phase {
        case .setup: return nil
        case .live(let state): return state
        case .finished: return nil
        }
    }

    var deuceRule: DeuceRule {
        engine?.configuration.deuceRule ?? .advantage
    }

    var canUndo: Bool {
        guard let engine else { return false }
        return Self.lastEffectivePointID(in: engine.events) != nil
    }

    func label(for team: Team) -> String {
        team == .teamA ? teamALabel : teamBLabel
    }

    func startMatch(
        configuration: MatchConfiguration,
        teamALabel: String,
        teamBLabel: String
    ) {
        let trimmedA = teamALabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedB = teamBLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        self.teamALabel = trimmedA.isEmpty ? "Team A" : trimmedA
        self.teamBLabel = trimmedB.isEmpty ? "Team B" : trimmedB

        let newEngine = MatchEngine(configuration: configuration)
        engine = newEngine
        phase = .live(newEngine.state)
    }

    func recordPoint(for team: Team) {
        guard var engine = engine else { return }
        _ = engine.submit(.pointWon(PointWonEvent(winningTeam: team)))
        self.engine = engine
        phase = .live(engine.state)
    }

    func undoLastEffectivePoint() {
        guard var engine = engine,
              let targetID = Self.lastEffectivePointID(in: engine.events)
        else { return }
        _ = engine.submit(.undo(UndoEvent(targetEventID: targetID)))
        self.engine = engine
        phase = .live(engine.state)
    }

    func finishMatch() {
        guard var engine = engine, let winner = engine.state.matchWinner else { return }
        _ = engine.submit(.finishMatch(FinishMatchEvent()))
        self.engine = engine
        phase = .finished(winner)
    }

    func returnToSetup() {
        engine = nil
        teamALabel = "Team A"
        teamBLabel = "Team B"
        phase = .setup
    }

    static func lastEffectivePointID(in events: [ScoringEvent]) -> EventID? {
        var stack: [EventID] = []
        for event in events {
            switch event {
            case .pointWon(let point):
                stack.append(point.id)
            case .undo(let undo):
                if stack.last == undo.targetEventID {
                    stack.removeLast()
                }
            case .finishMatch:
                break
            }
        }
        return stack.last
    }
}
