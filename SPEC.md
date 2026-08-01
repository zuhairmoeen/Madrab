# Madrab — Specification

## Product

Madrab is a padel scoring application for iPhone and Apple Watch.

The complete product will eventually allow players to score padel matches from either device, work offline, restore interrupted matches, save results, and start rematches.

This specification covers Milestone 1 (complete) and Milestone 2.

## Milestone 1 objective

Build a headless, platform-independent Swift package that calculates padel match state by replaying an ordered stream of immutable scoring events.

Milestone 1 has no user interface.

## Required scoring rules

The scoring engine must support:

* Love, 15, 30, and 40
* Deuce
* Advantage scoring
* Golden-point scoring
* Games
* Sets
* Best-of-three sets
* Standard tie-breaks
* Match tie-breaks
* Configurable final-set behavior
* Serving team
* Serving player when enabled
* Match completion

Any unclear padel scoring rule must be reported before implementation.

## Architecture requirements

* Events are immutable.
* Each event has a unique event ID.
* Event history is the source of truth.
* Current score is derived by replaying events.
* Replaying the same events must always produce the same state.
* Duplicate event IDs must not duplicate points.
* Invalid event sequences must return clear errors.
* Timestamps must not control scoring order.
* No third-party dependencies.

The scoring package must not import:

* SwiftUI
* UIKit
* WatchKit
* Watch Connectivity
* iPhone-specific frameworks
* watchOS-specific frameworks

## Undo rules

For Milestone 1, Undo means:

> Undo the most recent effective scoring action.

Requirements:

* An undo event references the exact event ID it reverses.
* The engine must not allow arbitrary historical point editing.
* Duplicate delivery of the same undo event must be idempotent.
* Undo referencing a nonexistent event must be rejected.
* Undo referencing an already-undone event must be rejected.
* A new point after undo must replay correctly.
* Undoing a game-winning point must restore the previous game state.
* Undoing a set-winning point must restore the previous set state.
* No point or undo may be accepted after a terminal finish event.

Event effectiveness must be calculated during replay. It must not be stored as a mutable Boolean value.

## Required tests

Tests must cover:

### Standard scoring

* Love to game
* Deuce
* Advantage gained
* Advantage lost
* Repeated deuce
* Game completion

### Golden point

* Golden point reached
* Team A wins golden point
* Team B wins golden point

### Sets and matches

* Normal set completion
* Straight-sets victory
* Three-set match
* Best-of-three match completion
* Final-set configuration

### Tie-breaks

* Standard tie-break
* Win by two points
* Extended tie-break
* Match tie-break
* Tie-break serving behavior

### Replay and validation

* Deterministic replay
* Duplicate event rejection
* Invalid sequence rejection
* Restoration through replay
* Event after terminal finish rejection

### Undo

* Undo latest effective point
* Duplicate undo delivery
* Undo nonexistent event
* Undo already-undone event
* Point after undo
* Undo game-winning point
* Undo set-winning point
* Undo match-winning point
* Undo after terminal finish rejection

## Completion criteria

Milestone 1 is complete only when:

1. The Swift package builds.
2. All scoring tests pass.
3. All replay tests pass.
4. All undo tests pass.
5. The package contains no UI code.
6. The package contains no platform-specific code.
7. There are no third-party dependencies.
8. The same event history always produces the same state.
9. The existing iPhone and Watch targets still build.
10. Unresolved scoring decisions are documented honestly.

## Out of scope

Do not implement:

* iPhone screens
* Apple Watch screens
* SwiftUI scoring interfaces
* Haptics
* Animations
* Local application storage
* Watch Connectivity
* Device authority
* Authority transfer
* Cross-device synchronization
* Supabase
* Accounts
* Player profiles
* Ratings
* Leaderboards
* Matchmaking
* Court booking
* Payments
* Other sports

## Milestone 2 objective

Build a SwiftUI iPhone prototype, in the existing `Madrab` app target, that uses `MadrabScoringEngine` to create, run, display, undo, restore, and finish a live padel match entirely on one iPhone.

Milestone 2 has no networking, no second device, and no cloud services.

## Required prototype behavior

The prototype must let a user:

* Create a new match with configurable rules.
* Run a live match by recording scoring events through `MadrabScoringEngine`.
* View derived match state as it changes.
* Undo the most recent effective scoring action.
* Finish a match and see the final result.

## Persistence requirements

* Persist the current match configuration and scoring-event log locally as Codable JSON.
* Support only one active match at a time.
* Reconstruct `MatchEngine` and `MatchState` through deterministic replay of the persisted event log when the app relaunches.
* Clear persisted match data when the match is deliberately discarded or completed.
* Do not use a database.
* Do not sync persisted data to the cloud.
* Do not build a match-history library.

## Milestone 2 architecture requirements

* The prototype must use `MadrabScoringEngine` as its sole source of scoring logic.
* The prototype must not modify `MadrabScoringEngine`'s public API.
* The prototype must not add third-party dependencies.
* Match state displayed in the UI must be derived from the engine's replay, not tracked separately.

## Required tests (Milestone 2)

### Persistence

* Save match configuration and event log after each scoring event
* Round-trip Codable encode/decode of match configuration and event log
* Restore in-progress match after relaunch via replay
* No persisted match on first launch

### Lifecycle

* Clear persisted data when a match is deliberately discarded
* Clear persisted data when a match is completed
* Only one active match persisted at a time

### UI-to-engine wiring

* Creating a match produces a valid `MatchEngine` configuration
* Recording a scoring action calls the engine and updates displayed state
* Undo calls the engine's undo API and updates displayed state
* Finishing a match reflects the engine's terminal state

## Milestone 2 completion criteria

Milestone 2 is complete only when:

1. The iPhone app builds.
2. A user can create, run, undo, restore, and finish a match entirely within the app.
3. An in-progress match survives app termination and relaunch via replay of persisted events.
4. Persisted match data is Codable JSON only, with no database.
5. Persisted data is cleared when a match is discarded or completed.
6. No networking, authentication, cloud sync, Watch Connectivity, authority transfer, or Apple Watch UI is present.
7. No third-party dependencies were added.
8. The `MadrabScoringEngine` package and its tests still build and pass unmodified.
9. Unresolved UI or persistence decisions are documented honestly.

## Milestone 2 out of scope

Do not implement:

* Apple Watch UI
* Watch Connectivity
* Networking
* Authentication
* Cloud sync
* Authority transfer
* Device synchronization
* Conflict recovery
* Supabase
* Accounts
* Player profiles
* Ratings
* Leaderboards
* Matchmaking
* Court booking
* Payments
* Other sports
* Third-party dependencies
* Haptics
* Animations
* Database storage
* Match-history library
