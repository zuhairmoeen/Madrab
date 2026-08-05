import Foundation
import Observation
import MadrabScoringEngine
import MadrabSyncKit

enum MatchSessionError: Error, Equatable {
    case pointsRecordingFailed
}

/// Why a scoring event could not be applied. Keeps the engine's own verdict
/// distinct from local preconditions and internal invariant breaches, so no
/// `MatchError` is ever fabricated to stand in for something the engine
/// never actually reported.
private enum ScoringApplicationError: Error {
    /// No active engine — a caller-side precondition, not an engine verdict.
    case noActiveEngine
    /// The engine explicitly rejected the event; its exact verdict is kept.
    case engineRejected(MatchError)
    /// The engine reported success but the log did not grow by exactly one
    /// event. An internal invariant breach, not anything the engine claimed.
    case unexpectedEventCount(expected: Int, actual: Int)
}

@MainActor
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
    /// Command IDs already applied to the *current* active match by a remote
    /// (Watch) command. Reset whenever the active match changes, restored
    /// from persistence on relaunch, and promoted to the durable
    /// `CommandReceipting` store before the active match is ever cleared.
    private var processedCommandIDs: Set<UUID> = []

    private let store: MatchStore
    private let resultRecorder: MatchResultRecording
    private let commandReceiptStore: CommandReceipting

    /// Dependencies default to `nil` rather than to concrete instances
    /// because a default-argument expression is evaluated in a nonisolated
    /// context, where constructing these main-actor-isolated stores would
    /// warn. Resolving them inside this `@MainActor` body is equivalent for
    /// every caller and keeps the stores' own isolation unchanged.
    init(
        store: MatchStore? = nil,
        resultRecorder: MatchResultRecording? = nil,
        commandReceiptStore: CommandReceipting? = nil
    ) {
        self.store = store ?? MatchStore()
        self.resultRecorder = resultRecorder ?? MatchResultRecorder()
        self.commandReceiptStore = commandReceiptStore ?? CommandReceiptStore()
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
        self.processedCommandIDs = []
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
        processedCommandIDs = []
        sessionError = nil

        let newEngine = MatchEngine(configuration: configuration)
        engine = newEngine
        phase = .live(newEngine.state)
        persist()
        return true
    }

    func recordPoint(for team: Team) {
        guard case .success = applyScoringEvent(.pointWon(PointWonEvent(winningTeam: team))) else { return }
        persist()
    }

    func undoLastEffectivePoint() {
        guard let engine,
              let targetID = Self.lastEffectivePointID(in: engine.events)
        else { return }
        guard case .success = applyScoringEvent(.undo(UndoEvent(targetEventID: targetID))) else { return }
        persist()
    }

    /// Applies one event to the engine and updates `phase`, without touching
    /// persistence. Assigns `self.engine` only after the engine reports
    /// success *and* the log is proven to have grown by exactly one event, so
    /// a rejected or no-op submission can never leave partially-applied state.
    ///
    /// Shared by the local (phone-originated) and remote (Watch-originated)
    /// paths so both mutate through identical logic; the two differ only in
    /// how they persist afterwards, which is the caller's responsibility.
    @discardableResult
    private func applyScoringEvent(_ event: ScoringEvent) -> Result<Void, ScoringApplicationError> {
        guard var engine else { return .failure(.noActiveEngine) }
        let previousCount = engine.events.count

        switch engine.submit(event) {
        case .failure(let error):
            return .failure(.engineRejected(error))
        case .success:
            let newCount = engine.events.count
            guard newCount == previousCount + 1 else {
                return .failure(.unexpectedEventCount(expected: previousCount + 1, actual: newCount))
            }
            self.engine = engine
            phase = .live(engine.state)
            return .success(())
        }
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
        processedCommandIDs = persisted.processedCommandIDs
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

    /// Best-effort save used by phone-originated actions, which have no
    /// caller waiting on a typed failure. Unchanged in behavior from before
    /// the sync work: a failure is swallowed and retried by the next save.
    private func persist() {
        try? persistOrThrow()
    }

    /// Saves the current event log **and** the remote-command ledger together
    /// in one atomic `MatchStore` write, propagating any failure. The remote
    /// path requires this: a scoring event and the `commandID` that produced
    /// it must never land on disk separately, or a retry after a crash could
    /// score the same command twice.
    private func persistOrThrow() throws {
        guard let engine else { return }
        let match = PersistedMatch(
            configuration: engine.configuration,
            events: engine.events,
            teamALabel: teamALabel,
            teamBLabel: teamBLabel,
            matchID: matchID,
            teamAProfileID: teamAProfileID,
            teamBProfileID: teamBProfileID,
            processedCommandIDs: processedCommandIDs
        )
        try store.save(match)
    }

    // MARK: - Watch synchronization (phone is the sole authority)

    /// The iPhone's authoritative view of the match, for broadcast to the
    /// Watch or inclusion in a `SyncCommandResponse`.
    ///
    /// `lastAcknowledgedCommandID` is the ID of a command the phone has
    /// actually applied — passed for `.accepted` and `.alreadyApplied`, and
    /// `nil` for a rejection or an ordinary phone-originated broadcast, so
    /// the Watch can never read an acknowledgement into a refusal.
    func currentSnapshot(lastAcknowledgedCommandID: UUID? = nil) -> SyncSnapshot {
        let state = engine?.state
        let sessionPhase: SyncSessionPhase
        switch phase {
        case .setup: sessionPhase = .setup
        case .live: sessionPhase = .live
        case .finished: sessionPhase = .finished
        }

        return SyncSnapshot(
            matchID: matchID,
            stateRevision: engine?.events.count ?? 0,
            // Interim: one profile per side until four-player pairs land.
            teamAPair: PairNames(first: teamALabel, second: ""),
            teamBPair: PairNames(first: teamBLabel, second: ""),
            sets: (state?.sets ?? []).map(Self.wireSetScore),
            currentPhase: state?.currentPhase.map(Self.wireActivePhase),
            servingTeam: state?.servingTeam,
            servingPlayer: state?.servingPlayer,
            matchWinner: state?.matchWinner,
            sessionPhase: sessionPhase,
            canUndo: canUndo,
            lastAcknowledgedCommandID: lastAcknowledgedCommandID
        )
    }

    private static func wireSetScore(_ set: SetScore) -> SyncSetScore {
        SyncSetScore(
            games: set.games,
            tieBreak: set.tieBreak.map { SyncTieBreakScore(points: $0.points) },
            winner: set.winner
        )
    }

    private static func wireActivePhase(_ phase: ActivePhase) -> SyncActivePhase {
        switch phase {
        case .game(let game):
            return .game(SyncGameScore(points: game.points))
        case .setTieBreak(let tieBreak):
            return .setTieBreak(SyncTieBreakScore(points: tieBreak.points))
        case .matchTieBreak(let tieBreak):
            return .matchTieBreak(SyncTieBreakScore(points: tieBreak.points))
        }
    }

    /// Validates and applies one Watch-originated command, returning the
    /// authoritative outcome plus a fresh snapshot. This is the only entry
    /// point through which the Watch can affect scoring, and it never gives
    /// the Watch authority: every mutation still runs through the same engine
    /// submission and persistence the phone itself uses.
    ///
    /// Commands are never queued. A command is either applied and durably
    /// saved before `.accepted` is returned, recognized as already applied,
    /// or rejected with an explicit reason.
    func applyRemoteCommand(_ command: SyncCommand) -> SyncCommandResponse {
        switch command.kind {
        case .requestLatestState:
            // A pure read: no mutation, no ledger access, valid in any phase,
            // and `matchID` is advisory only — a freshly launched Watch that
            // has never seen a snapshot can still ask what the truth is.
            return response(for: command, outcome: .accepted, acknowledged: true)

        case .recordPoint(let team):
            return applyRemoteScoringCommand(command, event: .pointWon(PointWonEvent(winningTeam: team)))

        case .undo:
            return applyRemoteScoringCommand(command, event: nil)
        }
    }

    /// Shared validation and application for the two mutating command kinds.
    /// `event` is `nil` for undo, whose target can only be resolved after the
    /// active match has been validated.
    private func applyRemoteScoringCommand(
        _ command: SyncCommand,
        event: ScoringEvent?
    ) -> SyncCommandResponse {
        // a. Required fields.
        guard let commandMatchID = command.matchID else {
            return response(for: command, outcome: .rejected(.malformedCommand))
        }

        // b. Durable receipts first, so a command whose match has already
        //    finished or been discarded is still recognized. A read failure
        //    is reported as such — never silently treated as "not found",
        //    which would risk applying a duplicate.
        do {
            if try commandReceiptStore.contains(matchID: commandMatchID, commandID: command.commandID) {
                return response(for: command, outcome: .alreadyApplied, acknowledged: true)
            }
        } catch {
            return response(for: command, outcome: .rejected(.persistenceFailed))
        }

        // c. Active ledger, scoped to the current match so an ID belonging to
        //    a different match can never short-circuit this one.
        if commandMatchID == matchID, processedCommandIDs.contains(command.commandID) {
            return response(for: command, outcome: .alreadyApplied, acknowledged: true)
        }

        // d. An active match must exist, and must be the one addressed.
        guard let currentEngine = engine, let activeMatchID = matchID else {
            return response(for: command, outcome: .rejected(.noLiveMatch))
        }
        guard commandMatchID == activeMatchID else {
            return response(for: command, outcome: .rejected(.wrongMatch))
        }

        // e. Live and not terminal.
        if case .finished = phase {
            return response(for: command, outcome: .rejected(.matchFinished))
        }
        guard case .live = phase else {
            return response(for: command, outcome: .rejected(.noLiveMatch))
        }
        guard !currentEngine.state.isTerminal else {
            return response(for: command, outcome: .rejected(.matchFinished))
        }

        // Once a winner exists but the log is not yet closed, further points
        // are refused while undo stays available, so an accidental
        // match-ending point can still be corrected.
        if event != nil, currentEngine.state.matchWinner != nil {
            return response(for: command, outcome: .rejected(.matchFinished))
        }

        // f. Revision must match exactly; a behind Watch gets an explicit
        //    rejection plus a fresh snapshot rather than a silent correction.
        guard command.expectedStateRevision == currentEngine.events.count else {
            return response(for: command, outcome: .rejected(.staleRevision))
        }

        // g. Resolve undo's target now that the match is known-valid.
        let resolvedEvent: ScoringEvent
        if let event {
            resolvedEvent = event
        } else {
            guard let targetID = Self.lastEffectivePointID(in: currentEngine.events) else {
                return response(for: command, outcome: .rejected(.invalidUndo))
            }
            resolvedEvent = .undo(UndoEvent(targetEventID: targetID))
        }

        // h. Apply atomically.
        return applyAtomically(command, event: resolvedEvent)
    }

    /// Mutates, records the command ID, and persists both in a single save.
    /// On any failure every touched value is restored exactly, so a retry of
    /// the same command is a clean first attempt rather than a duplicate.
    private func applyAtomically(_ command: SyncCommand, event: ScoringEvent) -> SyncCommandResponse {
        let previousEngine = engine
        let previousPhase = phase
        let previousProcessedCommandIDs = processedCommandIDs
        let previousSessionError = sessionError

        if case .failure(let error) = applyScoringEvent(event) {
            return response(for: command, outcome: .rejected(Self.rejectionReason(for: error)))
        }
        processedCommandIDs.insert(command.commandID)

        do {
            try persistOrThrow()
        } catch {
            engine = previousEngine
            phase = previousPhase
            processedCommandIDs = previousProcessedCommandIDs
            sessionError = previousSessionError
            return response(for: command, outcome: .rejected(.persistenceFailed))
        }

        return response(for: command, outcome: .accepted, acknowledged: true)
    }

    /// Maps a scoring-application failure onto the wire rejection reason,
    /// keeping the engine's own verdicts distinct from local preconditions
    /// and internal invariant breaches.
    private static func rejectionReason(for error: ScoringApplicationError) -> SyncRejectionReason {
        switch error {
        case .noActiveEngine:
            return .noLiveMatch
        case .unexpectedEventCount:
            return .malformedCommand
        case .engineRejected(let matchError):
            switch matchError {
            case .matchAlreadyDecided, .matchAlreadyFinished:
                return .matchFinished
            case .undoTargetNotFound, .undoTargetAlreadyUndone, .undoTargetNotMostRecent:
                return .invalidUndo
            case .duplicateEventID, .invalidConfiguration, .matchNotYetDecided:
                return .malformedCommand
            }
        }
    }

    private func response(
        for command: SyncCommand,
        outcome: SyncCommandOutcome,
        acknowledged: Bool = false
    ) -> SyncCommandResponse {
        SyncCommandResponse(
            commandID: command.commandID,
            outcome: outcome,
            snapshot: currentSnapshot(lastAcknowledgedCommandID: acknowledged ? command.commandID : nil)
        )
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
