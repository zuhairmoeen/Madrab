/// Immutable rules a match is played under. Passed alongside the event log to
/// `MatchEngine`/`MatchReplayer` — configuration is never itself an event.
public struct MatchConfiguration: Sendable, Equatable, Hashable, Codable {
    /// Number of sets a team must win to win the match (best-of-three = 2).
    public let setsToWin: Int
    /// Number of games a team must win to win a standard set.
    public let gamesToWinSet: Int
    /// Game count (per team) at which a standard set tie-break is triggered.
    public let setTiebreakTriggerGames: Int
    /// Target points for a standard set tie-break (win by two, uncapped).
    public let setTiebreakPoints: Int
    /// Deuce behavior for games (advantage vs. golden point).
    public let deuceRule: DeuceRule
    /// How the deciding set is played.
    public let finalSetMode: FinalSetMode
    /// Whether the engine tracks and rotates an individual serving player
    /// within each team, in addition to the serving team.
    public let servingPlayerTrackingEnabled: Bool
    /// Which team serves first.
    public let initialServingTeam: Team
    /// Which player on each team serves that team's first service turn.
    /// Ignored unless `servingPlayerTrackingEnabled` is true.
    public let initialServer: TeamPair<TeamPlayer>

    /// Validates the given values and constructs a configuration, or throws
    /// `MatchError.invalidConfiguration` naming the first invalid field.
    /// Invalid values are rejected outright — never clamped or silently corrected.
    public init(
        setsToWin: Int = 2,
        gamesToWinSet: Int = 6,
        setTiebreakTriggerGames: Int = 6,
        setTiebreakPoints: Int = 7,
        deuceRule: DeuceRule = .advantage,
        finalSetMode: FinalSetMode = .matchTiebreak(points: 10),
        servingPlayerTrackingEnabled: Bool = false,
        initialServingTeam: Team = .teamA,
        initialServer: TeamPair<TeamPlayer> = TeamPair(both: .first)
    ) throws(MatchError) {
        guard setsToWin >= 1 else {
            throw .invalidConfiguration(.setsToWin)
        }
        guard gamesToWinSet >= 1 else {
            throw .invalidConfiguration(.gamesToWinSet)
        }
        guard setTiebreakTriggerGames >= 1 else {
            throw .invalidConfiguration(.setTiebreakTriggerGames)
        }
        guard setTiebreakPoints >= 2 else {
            throw .invalidConfiguration(.setTiebreakPoints)
        }
        if case .matchTiebreak(let points) = finalSetMode, points < 2 {
            throw .invalidConfiguration(.matchTiebreakPoints)
        }

        self.setsToWin = setsToWin
        self.gamesToWinSet = gamesToWinSet
        self.setTiebreakTriggerGames = setTiebreakTriggerGames
        self.setTiebreakPoints = setTiebreakPoints
        self.deuceRule = deuceRule
        self.finalSetMode = finalSetMode
        self.servingPlayerTrackingEnabled = servingPlayerTrackingEnabled
        self.initialServingTeam = initialServingTeam
        self.initialServer = initialServer
    }
}
