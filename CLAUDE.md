# CLAUDE.md — Madrab Milestone 1

## Project

Madrab is a native Swift and SwiftUI padel scoring application for iPhone and Apple Watch.

The current development scope is Milestone 1 only: a headless Swift package containing the padel scoring engine and its automated tests.

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

Implement only the Milestone 1 scoring engine.

The engine must:

* Be written in Swift.
* Live in a Swift package.
* Be platform-independent.
* Use immutable events.
* Derive state through deterministic replay.
* Support the scoring rules in `SPEC.md`.
* Reject duplicate event IDs.
* Validate invalid sequences.
* Support restricted undo-by-reference.
* Include comprehensive Swift Testing tests.
* Have a small and explicit public API.

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

* SwiftUI interfaces
* iPhone scoring screens
* Apple Watch scoring screens
* Haptics
* Animations
* Local application persistence
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

* Swift package structure
* Domain types
* Event types
* Match configuration
* Derived match state
* Replay algorithm
* Validation
* Undo behavior
* Serving rules
* Public API
* Error types
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
