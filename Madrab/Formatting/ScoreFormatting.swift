import MadrabScoringEngine

enum ScoreFormatting {
    static func pointText(for team: Team, phase: ActivePhase?, deuceRule: DeuceRule) -> String {
        guard let phase else { return "" }
        switch phase {
        case .game(let score):
            return pointText(for: team, label: GamePointLabel(score: score, deuceRule: deuceRule))
        case .setTieBreak(let tieBreak), .matchTieBreak(let tieBreak):
            return "\(tieBreak.points[team])"
        }
    }

    private static func pointText(for team: Team, label: GamePointLabel) -> String {
        switch label {
        case .raw(let points):
            return rawPointText(points[team])
        case .deuce:
            return "40"
        case .advantage(let leader):
            return leader == team ? "Advantage" : "40"
        case .goldenPoint:
            return "40"
        }
    }

    private static func rawPointText(_ point: RawPoint) -> String {
        switch point {
        case .love: return "Love"
        case .fifteen: return "15"
        case .thirty: return "30"
        case .forty: return "40"
        }
    }

    static func caption(phase: ActivePhase?, deuceRule: DeuceRule) -> String? {
        guard let phase else { return nil }
        switch phase {
        case .game(let score):
            switch GamePointLabel(score: score, deuceRule: deuceRule) {
            case .deuce: return "Deuce"
            case .goldenPoint: return "Golden Point"
            case .raw, .advantage: return nil
            }
        case .setTieBreak:
            return "Tie-break"
        case .matchTieBreak:
            return "Match tie-break"
        }
    }

    static func setsScoreText(setsWon: TeamPair<Int>) -> String {
        "\(setsWon.teamA)–\(setsWon.teamB)"
    }

    static func completedSetText(_ set: SetScore) -> String {
        let gamesText = "\(set.games.teamA)-\(set.games.teamB)"
        guard let tieBreak = set.tieBreak, let winner = set.winner else {
            return gamesText
        }
        let loserPoints = tieBreak.points[winner.opponent]
        return "\(gamesText) (\(loserPoints))"
    }
}
