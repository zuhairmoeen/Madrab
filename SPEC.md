# Madrab — Specification

## Product

Madrab is a padel scoring application for iPhone and Apple Watch.

The complete product will eventually allow players to score padel matches from either device, work offline, restore interrupted matches, save results, and start rematches.

This specification covers Milestone 1 (complete), Milestone 2 (complete), and Milestone 3.

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

## Milestone 1 out of scope

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

## Milestone 3 objective

Build local player profiles, a points/leaderboard system, and simple top-level navigation, entirely on one iPhone with no accounts or cloud backend, using the existing Milestone 2 match flow and `MadrabScoringEngine` unmodified.

## Required profile behavior

The app must let a user:

* Create a local player profile with a required display name.
* Attach an optional profile image, falling back to generated initials when none is set.
* Edit or delete an existing profile.
* View a Profiles screen listing all saved players.
* Select two different player profiles before starting a match; the match's Team A / Team B are these profiles, replacing free-text name entry.

## Required points behavior

* Points are awarded only when a match reaches its terminal finished state via the existing Finish Match flow — never for a discarded or still-in-progress match.
* Track, per profile: total points, matches played, wins, losses.
* Initial formula: winner earns 3 points, loser earns 1 point.
* The formula must be implemented behind a single swappable unit (e.g. a dedicated points-formula type or function) so it can change later without touching call sites or stored data shape.
* Awarding points for a given completed match must be idempotent — the same match result must never be applied twice, including across relaunches after an interruption mid-write.

## Required leaderboard behavior

* A Leaderboard screen ranks all profiles with at least one recorded statistic.
* Sort key: total points descending, then wins descending, then matches played descending.
* Each row shows: rank, player name and avatar, points, wins, losses, matches played.
* An explicit empty state is shown when no completed matches exist yet.
* The leaderboard reflects a newly completed match immediately, without requiring the user to leave and return to the screen.

## Migration and persistence requirements

* Profiles, completed-match results, and leaderboard statistics are stored locally as Codable JSON, alongside — not replacing — the existing active-match persistence file.
* The existing active-match restore-on-launch behavior (Milestone 2) must continue to work unchanged; this work must never corrupt or discard an in-progress match.
* Persisted data must carry an explicit schema version. On launch, data written before Milestone 3 (no profiles/points files present) must be treated as a valid empty state — not an error, not a crash, not a reason to discard the active match.
* No database. No cloud sync.
* No browsable match-history feature — only the minimal record needed to guarantee idempotent point-awarding.

## Milestone 3 architecture requirements

* Do not modify `MadrabScoringEngine`'s scoring rules or public API.
* Points/leaderboard state is derived from stored completed-match results, not tracked as an independently mutable running total that could drift from that history.
* No third-party dependencies.

## Required tests (Milestone 3)

### Profiles

* Create profile with required display name
* Reject/validate a profile with a blank display name
* Edit an existing profile's name/avatar
* Delete a profile
* Generated-initials fallback when no image is set

### Match creation with profiles

* Starting a match requires two distinct selected profiles
* Selecting the same profile for both sides is rejected
* Team A / Team B in the resulting match map to the selected profiles

### Points

* Winner receives 3 points, loser receives 1 point, on a completed match
* No points are awarded when a match is discarded
* No points are awarded while a match is still in progress
* Points are not awarded twice for the same completed match (idempotency), including simulated relaunch
* Per-profile matches played / wins / losses update correctly

### Leaderboard

* Ranking order by points, then wins, then matches played
* Tie-break ordering with equal points and equal wins
* Empty-state display with zero completed matches
* Leaderboard reflects a match completed in the same session immediately

### Persistence and migration

* Profiles/points data round-trips through Codable JSON
* Launching with no existing profiles/points file produces empty (not crashing) state
* An in-progress active match present before this feature still restores correctly after adding profiles/points persistence
* Schema version is recorded and readable on load

## Milestone 3 verification status

Automated verification is complete and passing: all 123 `MadrabTests`, all 65 `MadrabScoringEngine` tests, and a full iPhone 17 simulator build, with no warnings from project code. The interactive manual checklist below (profile creation/edit/delete through the UI, picking profiles and starting a match, live scoring/undo/discard/finish by tapping, tab-switch behavior mid-match, and a real quit/relaunch restore) is pending the project owner's own hands-on pass in the simulator. Milestone 3 is marked complete only once that pass is done.

### Manual verification checklist

* Empty Profiles state
* Create two profiles
* Edit a profile name
* Duplicate/blank names rejected
* Match tab immediately sees the shared profiles
* Same profile cannot be selected for both sides
* Start a match with two profiles
* Scoring, undo, discard, restore, and finish still work
* Completed match awards winner 3 points and loser 1 point
* Leaderboard updates after completion
* Leaderboard rank and statistics are correct
* Profile rename is reflected in Match and Leaderboard
* Active-match profile deletion is blocked
* Deleting an inactive profile removes its leaderboard row/stats
* Switching tabs does not reset the active match
* Relaunch restores an unfinished match
* Light and dark mode remain readable

## Milestone 3 completion criteria

Milestone 3 is complete only when:

1. The iPhone app builds.
2. A user can create, edit, and delete player profiles.
3. A match cannot start without two distinct selected profiles.
4. Completed matches award points exactly once, using the swappable formula.
5. The leaderboard ranks correctly and updates immediately after a completed match.
6. The existing active-match persistence and restore-on-launch behavior (Milestone 2) is unchanged and unbroken.
7. All persisted data is Codable JSON with an explicit schema version, with no database.
8. No networking, authentication/accounts, cloud sync, Watch Connectivity, authority transfer, or Apple Watch UI is present.
9. No third-party dependencies were added.
10. The `MadrabScoringEngine` package and its tests still build and pass unmodified.
11. Unresolved UI or persistence decisions are documented honestly.

## Milestone 3 out of scope

Do not implement:

* Apple Watch UI
* Watch Connectivity
* Networking
* Authentication or accounts
* Cloud sync
* Authority transfer
* Device synchronization
* Conflict recovery
* Supabase
* Skill-rating algorithms (ELO/Glicko/MMR)
* Friends
* Matchmaking
* Court booking
* Payments
* Other sports
* Third-party dependencies
* Haptics
* Animations
* Database storage
* Browsable match-history library

For the duration of the Watch Synchronization Sprint (see below), "Apple
Watch UI," "Watch Connectivity," and "Device synchronization" are in scope.
"Animations" is in scope only for the Watch companion's UI and the
live-scoring visual transition described in that section — not a general
license elsewhere. "Authority transfer," "Conflict recovery," and any second
offline scoring authority remain out of scope even during this sprint.

## Watch Synchronization Sprint (post-Milestone-3, time-boxed)

Adds a real Apple Watch companion app, phone-authoritative live sync via
WatchConnectivity, local four-player (two-pair) matches, a 50-point win
formula, and basic local recent-match history — on top of the unmodified
Milestone 3 profile/leaderboard system and the unmodified
`MadrabScoringEngine` Team A/Team B model.

### Authority model
The iPhone is the sole scoring authority; this is not superseded by this
sprint. The Watch sends commands; the iPhone validates, applies, persists,
and returns an explicit accepted/alreadyApplied/rejected outcome plus the
authoritative snapshot. An unreachable iPhone makes the Watch read-only — no
second offline scoring authority, and no authority transfer, is implemented.

### Sync command validation
The iPhone rejects, with an explicit reason: malformed/unsupported commands,
wrong-match commands, commands with no live match, stale state revisions,
commands after match finish, and invalid undo requests. A duplicate command
ID — including one whose match has since finished or been discarded — is
answered as "already applied," not an error; this protection is persisted
per active match and, once a match ends, via a small durable command-receipt
record, so a lost-reply retry is recognized correctly and never double-scores.

### Four-player matches
A new match requires four distinct local profiles, arranged as two pairs
(Team A: two profiles, Team B: two profiles). The scoring engine's Team A/
Team B model is unmodified; pairing is an app-layer concept only. A match
persisted before this sprint (exactly one profile per team) is never
discarded on migration — it restores and finishes normally, but does not
participate in the points system either way.

### Points
Each player on the winning pair receives 50 points on match completion.
Discarded or in-progress matches award nothing. Awarding is idempotent per
match, including across relaunch.

### Recent match history
The last 10 completed matches are stored locally for display only — not a
browsable/searchable history library.

### Out of scope for this sprint
Real accounts, cloud sync, real cross-device username search, online
friend/leaderboard features, weekly tasks, badges, advanced analytics,
production multi-authority conflict resolution, App Store security work,
and any form of authority transfer between iPhone and Watch.

## Milestone 4 (planned, not yet scoped)

The next planned milestone after Milestone 3 is incorporating user feedback and suggestions. No objective, requirements, or architecture for Milestone 4 exist yet, and none should be implemented until it is explicitly scoped and requested.
