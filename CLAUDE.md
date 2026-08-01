# CLAUDE.md — Madrab

## Project

Madrab is a native Swift and SwiftUI padel scoring application for iPhone and Apple Watch.

Milestone 1, the headless `MadrabScoringEngine` Swift package and its automated tests, is complete.

Milestone 2, the SwiftUI iPhone prototype (create/run/undo/restore/finish a live match, with local Codable-JSON persistence of the active match), is complete.

The current development scope is Milestone 3: local player profiles, a points/leaderboard system, and simple navigation between Match, Profiles, and Leaderboard — still entirely on one iPhone, still no accounts or cloud backend.

Milestone 3 must not add networking, authentication, cloud sync, WatchConnectivity, authority transfer, Apple Watch UI, or skill-rating algorithms (ELO/Glicko/MMR). The points system is a simple, swappable win/loss tally, not a rating system.

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

Implement only the Milestone 3 local profiles, points, and leaderboard system, on top of the completed Milestone 2 match flow. Always read `SPEC.md` before planning or modifying code.

## Profiles

* Let a user create, edit, and delete local player profiles.
* Require a display name per profile.
* Allow an optional profile image, with a generated initials/avatar fallback when none is set.
* Show a Profiles screen listing all saved players.
* Require selecting two different player profiles before a match can start.
* Replace the free-text Team A / Team B name fields with the two selected profiles.

## Points

* Award ranking points only when a match reaches its terminal finished state — never for a discarded or still-in-progress match.
* Track, per profile: total points, matches played, wins, losses.
* Use an initial formula of winner = 3 points, loser = 1 point.
* Implement the formula behind a single swappable unit so it can change later without touching call sites or stored data shape.
* Be idempotent: the same completed match must never award points more than once, including across relaunches.

## Leaderboard

* Show a ranked list of profiles with completed-match statistics.
* Rank by total points, breaking ties by wins, then by matches played.
* Display rank, name/avatar, points, wins, losses, and matches played per row.
* Show a clear empty state when no completed matches exist yet.
* Reflect a completed match immediately, with no separate refresh step.

## Navigation

* Add a simple top-level structure (a `TabView` unless the existing architecture suggests a better native SwiftUI structure) with three destinations: Match, Profiles, Leaderboard.
* Preserve the existing polished Madrab visual style and single accent color.

## Persistence

* Store profiles, completed-match results, and leaderboard statistics locally as Codable JSON, alongside — not replacing — the existing active-match persistence.
* Preserve the existing active-match restore-on-launch behavior exactly; this work must never corrupt or discard an in-progress match.
* Handle installs with no profiles/points data yet (pre-Milestone-3) safely as an empty, non-error state.
* Define an explicit schema-version / migration strategy for the persisted data format.
* Do not use a database. Do not sync to the cloud.
* Do not build a browsable match-history feature — only the minimal record needed to guarantee idempotent point-awarding.

## Milestone 3 out of scope

* Networking
* Authentication or accounts
* Cloud sync
* Watch Connectivity
* Authority transfer
* Apple Watch UI
* Third-party dependencies
* Skill-rating algorithms (ELO/Glicko/MMR)

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
* Watch Connectivity
* Device authority
* Authority transfer
* Synchronization
* Conflict recovery
* Supabase
* Authentication or accounts
* Skill-rating algorithms (ELO/Glicko/MMR) — distinct from the simple Milestone 3 points tally, which is in scope
* Friends
* Matchmaking
* Court features
* Payments
* Other sports

A minimal, non-browsable record needed to guarantee idempotent point-awarding is in scope; a browsable match-history library is not.

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
