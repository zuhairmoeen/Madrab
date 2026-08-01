# CLAUDE.md — Madrab

## Project

Madrab is a native Swift and SwiftUI padel scoring application for iPhone and Apple Watch.

Milestone 1, the headless `MadrabScoringEngine` Swift package and its automated tests, is complete.

The current development scope is Milestone 2: a SwiftUI iPhone prototype built in the existing `Madrab` app target. It must use `MadrabScoringEngine` to create, run, display, undo, restore, and finish a live match entirely on one iPhone.

Milestone 2 must not add networking, authentication, cloud sync, WatchConnectivity, authority transfer, or Apple Watch UI.

Always read `SPEC.md` before planning or modifying code.

## Required working process

For every task:

1. Read `CLAUDE.md`.
2. Read `SPEC.md`.
3. Inspect the repository.
4. Explain the implementation plan before editing.
5. Identify unresolved scoring-rule decisions.
6. Modify only files required for the approved task.
7. Build all affected targets.
8. Run all relevant tests.
9. Report changed files.
10. Report passed and failed tests.
11. Report warnings and unresolved problems honestly.

Do not claim that a build or test passed unless it was actually run.

## Current scope

Implement only the Milestone 2 iPhone prototype.

The prototype must:

* Be written in Swift and SwiftUI.
* Live in the existing `Madrab` iPhone app target.
* Use `MadrabScoringEngine` as the sole source of scoring logic.
* Let a user create a new match with configurable rules.
* Let a user run a live match by recording scoring events.
* Display derived match state as it changes.
* Let a user undo the most recent effective scoring action.
* Persist the current match configuration and scoring-event log locally as Codable JSON.
* Reconstruct `MatchEngine` and `MatchState` through deterministic replay of the persisted event log on launch.
* Let a user finish a match and see the final result.
* Clear persisted match data when the match is deliberately discarded or completed, according to the approved UI flow.
* Operate entirely on one iPhone, with no second device involved.

Persistence must be minimal:

* Support only one active match at a time.
* Store data as Codable JSON on local disk.
* Do not use a database.
* Do not sync to the cloud.
* Do not build a match-history library.

Milestone 2 must not add:

* Networking
* Authentication
* Cloud sync
* Watch Connectivity
* Authority transfer
* Apple Watch UI
* Third-party dependencies

## Architecture rules

* Event history is the source of truth.
* Match state is derived through replay.
* Do not use a mutable score object as the source of truth.
* Do not store a mutable event-effectiveness flag.
* Do not use timestamps as authoritative ordering.
* Avoid global mutable state.
* Avoid unnecessary singletons.
* Avoid force unwraps.
* Prefer Swift value types.
* Prefer explicit domain errors.
* Prefer simple implementations over speculative abstractions.
* Do not add third-party dependencies.
* Do not design synchronization architecture during Milestone 1.

## Undo rule

Undo means undo the most recent effective scoring action.

An undo event must reference the exact event ID it reverses.

Do not expose APIs for:

* Removing an arbitrary historical point
* Editing an old point
* Redo
* Reopening a terminally finished match

## Testing

Use Swift Testing for scoring-package tests.

Every scoring rule must have:

* Normal-case tests
* Boundary tests
* Edge-case tests
* Undo tests where applicable
* Deterministic replay tests

Do not delete, weaken, or skip failing tests merely to make the test suite pass.

## Do not touch

Do not implement or modify product code for:

* Apple Watch scoring screens
* Haptics
* Animations
* Database storage
* Match-history libraries
* Watch Connectivity
* Device authority
* Authority transfer
* Synchronization
* Conflict recovery
* Supabase
* Authentication
* Profiles
* Ratings
* Leaderboards
* Friends
* Matchmaking
* Court features
* Payments
* Other sports

Do not refactor unrelated Xcode-generated files.

## Planning requirement

Before implementation, produce a file-level plan covering:

* SwiftUI view structure
* State/view-model structure
* Match-creation flow
* Live-scoring flow
* Undo flow
* Persistence model (Codable schema, save/load/clear points)
* Restore-on-launch flow
* Match-finish flow
* Error and edge-case handling
* Test structure
* Detailed test matrix
* Exact files to create or modify

Do not edit files during the planning step.

## Git safety

* Do not rewrite Git history.
* Do not use destructive Git commands.
* Do not delete unrelated files.
* Never commit secrets.
* Keep each change focused.
