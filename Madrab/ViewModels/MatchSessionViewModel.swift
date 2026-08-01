import Foundation
import Observation
import MadrabScoringEngine

enum MatchSessionError: Error, Equatable {
    case pointsRecordingFailed
}

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
    private(set) var sessionError: MatchSessionError?

    private var engine: MatchEngine?
    private var matchID: UUID?
    private var teamAProfileID: UUID?
    private var teamBProfileID: UUID?

    private let store: MatchStore
    private let resultRecorder: MatchResultRecording

    init(store: MatchStore = MatchStore(), resultRecorder: MatchResultRecording? = nil) {
        self.store = store
        self.resultRecorder = resultRecorder ?? MatchResultRecorder()
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

    /// Legacy, label-only match creation. Preserved for existing callers and
    /// tests. A match started this way carries no profile linkage, so it can
    /// score, undo, and finish normally but never awards leaderboard points.
    func startMatch(
        configuration: MatchConfiguration,
        teamALabel: String,
        teamBLabel: String
    ) {
        let trimmedA = teamALabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedB = teamBLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        self.teamALabel = trimmedA.isEmpty ? "Team A" : trimmedA
        self.teamBLabel = trimmedB.isEmpty ? "Team B" : trimmedB
        self.matchID = nil
        self.teamAProfileID = nil
        self.teamBProfileID = nil
        self.sessionError = nil

        let newEngine = MatchEngine(configuration: configuration)
        engine = newEngine
        phase = .live(newEngine.state)
        persist()
    }

    /// Profile-linked match creation. Requires two distinct profiles; a
    /// fresh `matchID` is generated so the eventual completed result can be
    /// recorded exactly once.
    @discardableResult
    func startMatch(
        configuration: MatchConfiguration,
        teamAProfile: PlayerProfile,
        teamBProfile: PlayerProfile
    ) -> Bool {
        guard teamAProfile.id != teamBProfile.id else { return false }

        teamALabel = teamAProfile.displayName
        teamBLabel = teamBProfile.displayName
        matchID = UUID()
        teamAProfileID = teamAProfile.id
        teamBProfileID = teamBProfile.id
        sessionError = nil

        let newEngine = MatchEngine(configuration: configuration)
        engine = newEngine
        phase = .live(newEngine.state)
        persist()
        return true
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

    /// Crash-safe completion: the terminal event is persisted before any
    /// leaderboard side effect is attempted, and active-match persistence is
    /// only cleared once a profile-linked match's result has actually been
    /// recorded. Calling this again after a recording failure is a safe
    /// retry — the engine rejects the duplicate `FinishMatch` event as a
    /// no-op (already terminal), and `MatchResultRecorder` is independently
    /// idempotent per `matchID`.
    func finishMatch() {
        guard var engine = engine, let winner = engine.state.matchWinner else { return }

        if !engine.state.isTerminal {
            _ = engine.submit(.finishMatch(FinishMatchEvent()))
            self.engine = engine
            persist()
        }

        completeAfterRecording(winner: winner)
    }

    func returnToSetup() {
        engine = nil
        matchID = nil
        teamAProfileID = nil
        teamBProfileID = nil
        teamALabel = "Team A"
        teamBLabel = "Team B"
        sessionError = nil
        phase = .setup
        store.clear()
    }

    /// Restores a persisted match. A non-terminal match resumes live play
    /// exactly as before, including its profile linkage. A restored
    /// *terminal* match retries recording its result (a harmless no-op if
    /// already recorded) before clearing persistence; a legacy match with no
    /// profile linkage is cleared immediately without attempting to award
    /// anything. If the saved data is missing, unreadable, invalid, or
    /// cannot be replayed, the persisted file is discarded and the session
    /// is left at `.setup`.
    func restoreIfNeeded() {
        guard let persisted = store.load(),
              let restoredEngine = try? MatchEngine(
                configuration: persisted.configuration,
                events: persisted.events
              )
        else {
            store.clear()
            return
        }

        engine = restoredEngine
        matchID = persisted.matchID
        teamAProfileID = persisted.teamAProfileID
        teamBProfileID = persisted.teamBProfileID
        teamALabel = persisted.teamALabel
        teamBLabel = persisted.teamBLabel
        sessionError = nil
        phase = .live(restoredEngine.state)

        if restoredEngine.state.isTerminal, let winner = restoredEngine.state.matchWinner {
            completeAfterRecording(winner: winner)
        }
    }

    /// Shared by `finishMatch()` and `restoreIfNeeded()`. Only clears
    /// active-match persistence and transitions to `.finished` once the
    /// leaderboard side effect has succeeded (or immediately, for a legacy
    /// match with no profile linkage — there is nothing to record). On
    /// failure, the terminal active-match file is left intact and
    /// `sessionError` is set so a later retry (another call to
    /// `finishMatch()`, or another `restoreIfNeeded()` on relaunch) has
    /// something to act on.
    private func completeAfterRecording(winner: Team) {
        guard let matchID, let teamAProfileID, let teamBProfileID else {
            store.clear()
            phase = .finished(winner)
            return
        }

        let winnerProfileID = winner == .teamA ? teamAProfileID : teamBProfileID
        let loserProfileID = winner == .teamA ? teamBProfileID : teamAProfileID

        do {
            try resultRecorder.recordCompletedMatch(
                matchID: matchID,
                winnerProfileID: winnerProfileID,
                loserProfileID: loserProfileID
            )
            store.clear()
            phase = .finished(winner)
            sessionError = nil
        } catch {
            sessionError = .pointsRecordingFailed
        }
    }

    private func persist() {
        guard let engine else { return }
        let match = PersistedMatch(
            configuration: engine.configuration,
            events: engine.events,
            teamALabel: teamALabel,
            teamBLabel: teamBLabel,
            matchID: matchID,
            teamAProfileID: teamAProfileID,
            teamBProfileID: teamBProfileID
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
