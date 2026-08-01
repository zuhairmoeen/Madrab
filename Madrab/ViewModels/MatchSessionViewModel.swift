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
    private let store: MatchStore

    init(store: MatchStore = MatchStore()) {
        self.store = store
    }

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
        persist()
    }

    func recordPoint(for team: Team) {
        guard var engine = engine else { return }
        _ = engine.submit(.pointWon(PointWonEvent(winningTeam: team)))
        self.engine = engine
        phase = .live(engine.state)
        persist()
    }

    func undoLastEffectivePoint() {
        guard var engine = engine,
              let targetID = Self.lastEffectivePointID(in: engine.events)
        else { return }
        _ = engine.submit(.undo(UndoEvent(targetEventID: targetID)))
        self.engine = engine
        phase = .live(engine.state)
        persist()
    }

    func finishMatch() {
        guard var engine = engine, let winner = engine.state.matchWinner else { return }
        _ = engine.submit(.finishMatch(FinishMatchEvent()))
        self.engine = engine
        phase = .finished(winner)
        store.clear()
    }

    func returnToSetup() {
        engine = nil
        teamALabel = "Team A"
        teamBLabel = "Team B"
        phase = .setup
        store.clear()
    }

    /// Attempts to restore a persisted in-progress match. If the saved data
    /// is missing, unreadable, invalid, or cannot be replayed, the persisted
    /// file is discarded and the session is left at `.setup`.
    func restoreIfNeeded() {
        guard let persisted = store.load() else { return }

        guard let restoredEngine = try? MatchEngine(
            configuration: persisted.configuration,
            events: persisted.events
        ), !restoredEngine.state.isTerminal else {
            store.clear()
            return
        }

        engine = restoredEngine
        teamALabel = persisted.teamALabel
        teamBLabel = persisted.teamBLabel
        phase = .live(restoredEngine.state)
    }

    private func persist() {
        guard let engine else { return }
        let match = PersistedMatch(
            configuration: engine.configuration,
            events: engine.events,
            teamALabel: teamALabel,
            teamBLabel: teamBLabel
        )
        try? store.save(match)
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
