/// Explicit domain errors for the scoring engine. Every rejection a caller can
/// observe — from constructing an invalid `MatchConfiguration` to submitting an
/// invalid `ScoringEvent` — is represented here rather than as a generic/string error.
public enum MatchError: Error, Sendable, Equatable {
    /// `MatchConfiguration.init` was given an invalid value for the named field.
    case invalidConfiguration(InvalidConfigurationField)

    /// The submitted event's ID already exists in the history.
    case duplicateEventID
    /// An event was submitted after a `FinishMatch` event was already accepted.
    case matchAlreadyFinished
    /// A `pointWon` event was submitted after `matchWinner` was already decided
    /// (but before `FinishMatch` closed the log).
    case matchAlreadyDecided
    /// A `finishMatch` event was submitted before there is a match winner.
    case matchNotYetDecided
    /// An `undo` event's `targetEventID` does not refer to any currently- or
    /// previously-effective point event.
    case undoTargetNotFound
    /// An `undo` event's `targetEventID` refers to a point that was already undone.
    case undoTargetAlreadyUndone
    /// An `undo` event's `targetEventID` refers to a real, not-yet-undone point,
    /// but not the most recent effective one — arbitrary historical undo is not allowed.
    case undoTargetNotMostRecent
}

/// Identifies which `MatchConfiguration` field failed validation.
public enum InvalidConfigurationField: Sendable, Equatable {
    case setsToWin
    case gamesToWinSet
    case setTiebreakTriggerGames
    case setTiebreakPoints
    case matchTiebreakPoints
}
