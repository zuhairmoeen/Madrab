# Madrab — Milestone 1 Specification

## Product

Madrab is a padel scoring application for iPhone and Apple Watch.

The complete product will eventually allow players to score padel matches from either device, work offline, restore interrupted matches, save results, and start rematches.

This specification covers Milestone 1 only.

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
