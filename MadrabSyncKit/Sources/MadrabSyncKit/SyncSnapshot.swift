import Foundation
import MadrabScoringEngine

/// Display names for the two profiles on one side of the match. Carries
/// strings only, never profile UUIDs — the Watch has no use for profile
/// identity, only for what to show.
public struct PairNames: Codable, Equatable, Sendable {
    public let first: String
    public let second: String

    public init(first: String, second: String) {
        self.first = first
        self.second = second
    }
}

// MARK: - Codable mirrors of MadrabScoringEngine's score-shape types
//
// `GameScore`, `TieBreakScore`, `SetScore`, and `ActivePhase` in
// MadrabScoringEngine are deliberately `Sendable, Equatable` only, not
// `Codable` — they're meant to be derived via replay, not serialized.
// MadrabScoringEngine's public API is not modified to add conformances;
// instead these small mirror types carry the same information across
// WatchConnectivity, built from `MatchState` on the iPhone side.

public struct SyncGameScore: Codable, Equatable, Sendable {
    public let points: TeamPair<Int>

    public init(points: TeamPair<Int>) {
        self.points = points
    }
}

public struct SyncTieBreakScore: Codable, Equatable, Sendable {
    public let points: TeamPair<Int>

    public init(points: TeamPair<Int>) {
        self.points = points
    }
}

public enum SyncActivePhase: Codable, Equatable, Sendable {
    case game(SyncGameScore)
    case setTieBreak(SyncTieBreakScore)
    case matchTieBreak(SyncTieBreakScore)
}

public struct SyncSetScore: Codable, Equatable, Sendable {
    public let games: TeamPair<Int>
    public let tieBreak: SyncTieBreakScore?
    public let winner: Team?

    public init(games: TeamPair<Int>, tieBreak: SyncTieBreakScore?, winner: Team?) {
        self.games = games
        self.tieBreak = tieBreak
        self.winner = winner
    }
}

public enum SyncSessionPhase: Codable, Equatable, Sendable {
    case setup
    case live
    case finished
}

/// The iPhone's authoritative view of the match, broadcast to the Watch
/// after every phone-originated or accepted-remote state change, and
/// returned as part of every `SyncCommandResponse`.
///
/// Deliberately excludes reachability: that's local transport state owned
/// by the Watch's own `WCSession.isReachable`, with a different lifetime
/// than "what is the match state."
public struct SyncSnapshot: Codable, Equatable, Sendable {
    public let matchID: UUID?
    public let stateRevision: Int
    public let teamAPair: PairNames
    public let teamBPair: PairNames
    public let sets: [SyncSetScore]
    public let currentPhase: SyncActivePhase?
    public let servingTeam: Team?
    public let servingPlayer: ServingPlayer?
    public let matchWinner: Team?
    public let sessionPhase: SyncSessionPhase
    public let canUndo: Bool
    public let lastAcknowledgedCommandID: UUID?

    public init(
        matchID: UUID?,
        stateRevision: Int,
        teamAPair: PairNames,
        teamBPair: PairNames,
        sets: [SyncSetScore],
        currentPhase: SyncActivePhase?,
        servingTeam: Team?,
        servingPlayer: ServingPlayer?,
        matchWinner: Team?,
        sessionPhase: SyncSessionPhase,
        canUndo: Bool,
        lastAcknowledgedCommandID: UUID?
    ) {
        self.matchID = matchID
        self.stateRevision = stateRevision
        self.teamAPair = teamAPair
        self.teamBPair = teamBPair
        self.sets = sets
        self.currentPhase = currentPhase
        self.servingTeam = servingTeam
        self.servingPlayer = servingPlayer
        self.matchWinner = matchWinner
        self.sessionPhase = sessionPhase
        self.canUndo = canUndo
        self.lastAcknowledgedCommandID = lastAcknowledgedCommandID
    }

    /// A safe default for a Watch that has no session/commandHandler wired
    /// up yet, or before the phone has produced a first real snapshot.
    public static let unavailable = SyncSnapshot(
        matchID: nil,
        stateRevision: 0,
        teamAPair: PairNames(first: "", second: ""),
        teamBPair: PairNames(first: "", second: ""),
        sets: [],
        currentPhase: nil,
        servingTeam: nil,
        servingPlayer: nil,
        matchWinner: nil,
        sessionPhase: .setup,
        canUndo: false,
        lastAcknowledgedCommandID: nil
    )
}
