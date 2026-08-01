import Foundation

struct PointsFormula: Equatable {
    var winnerPoints: Int
    var loserPoints: Int

    static let `default` = PointsFormula(winnerPoints: 3, loserPoints: 1)
}

func applyMatchResult(
    winnerID: UUID,
    loserID: UUID,
    formula: PointsFormula,
    to statsByProfileID: inout [UUID: PlayerStats]
) {
    var winnerStats = statsByProfileID[winnerID] ?? PlayerStats()
    winnerStats.totalPoints += formula.winnerPoints
    winnerStats.matchesPlayed += 1
    winnerStats.wins += 1
    statsByProfileID[winnerID] = winnerStats

    var loserStats = statsByProfileID[loserID] ?? PlayerStats()
    loserStats.totalPoints += formula.loserPoints
    loserStats.matchesPlayed += 1
    loserStats.losses += 1
    statsByProfileID[loserID] = loserStats
}
