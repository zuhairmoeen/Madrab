import Testing
@testable import Madrab
import MadrabScoringEngine

struct ScoreFormattingTests {
    // MARK: - pointText

    @Test func pointTextIsEmptyWhenPhaseIsNil() {
        #expect(ScoreFormatting.pointText(for: .teamA, phase: nil, deuceRule: .advantage) == "")
    }

    @Test(arguments: [
        (0, "Love"),
        (1, "15"),
        (2, "30"),
        (3, "40")
    ])
    func pointTextShowsRawPointsBelowDeuce(pointsAndExpected: (Int, String)) {
        let (points, expected) = pointsAndExpected
        let score = GameScore(points: TeamPair(teamA: points, teamB: 0))
        let phase = ActivePhase.game(score)

        #expect(ScoreFormatting.pointText(for: .teamA, phase: phase, deuceRule: .advantage) == expected)
    }

    @Test func pointTextShowsDeuceAsFortyForBothTeams() {
        let score = GameScore(points: TeamPair(teamA: 3, teamB: 3))
        let phase = ActivePhase.game(score)

        #expect(ScoreFormatting.pointText(for: .teamA, phase: phase, deuceRule: .advantage) == "40")
        #expect(ScoreFormatting.pointText(for: .teamB, phase: phase, deuceRule: .advantage) == "40")
    }

    @Test func pointTextShowsAdvantageForLeaderAndFortyForTrailer() {
        let score = GameScore(points: TeamPair(teamA: 4, teamB: 3))
        let phase = ActivePhase.game(score)

        #expect(ScoreFormatting.pointText(for: .teamA, phase: phase, deuceRule: .advantage) == "Advantage")
        #expect(ScoreFormatting.pointText(for: .teamB, phase: phase, deuceRule: .advantage) == "40")
    }

    @Test func pointTextShowsFortyForBothTeamsAtGoldenPoint() {
        let score = GameScore(points: TeamPair(teamA: 3, teamB: 3))
        let phase = ActivePhase.game(score)

        #expect(ScoreFormatting.pointText(for: .teamA, phase: phase, deuceRule: .goldenPoint) == "40")
        #expect(ScoreFormatting.pointText(for: .teamB, phase: phase, deuceRule: .goldenPoint) == "40")
    }

    @Test func pointTextShowsRawTieBreakPointsForSetTieBreak() {
        let tieBreak = TieBreakScore(points: TeamPair(teamA: 5, teamB: 2))
        let phase = ActivePhase.setTieBreak(tieBreak)

        #expect(ScoreFormatting.pointText(for: .teamA, phase: phase, deuceRule: .advantage) == "5")
        #expect(ScoreFormatting.pointText(for: .teamB, phase: phase, deuceRule: .advantage) == "2")
    }

    @Test func pointTextShowsRawTieBreakPointsForMatchTieBreak() {
        let tieBreak = TieBreakScore(points: TeamPair(teamA: 9, teamB: 8))
        let phase = ActivePhase.matchTieBreak(tieBreak)

        #expect(ScoreFormatting.pointText(for: .teamA, phase: phase, deuceRule: .advantage) == "9")
        #expect(ScoreFormatting.pointText(for: .teamB, phase: phase, deuceRule: .advantage) == "8")
    }

    // MARK: - caption

    @Test func captionIsNilWhenPhaseIsNil() {
        #expect(ScoreFormatting.caption(phase: nil, deuceRule: .advantage) == nil)
    }

    @Test func captionIsNilForRawPoints() {
        let phase = ActivePhase.game(GameScore(points: TeamPair(teamA: 1, teamB: 0)))
        #expect(ScoreFormatting.caption(phase: phase, deuceRule: .advantage) == nil)
    }

    @Test func captionIsNilForAdvantage() {
        let phase = ActivePhase.game(GameScore(points: TeamPair(teamA: 4, teamB: 3)))
        #expect(ScoreFormatting.caption(phase: phase, deuceRule: .advantage) == nil)
    }

    @Test func captionIsDeuceAtEqualFortyUnderAdvantageRule() {
        let phase = ActivePhase.game(GameScore(points: TeamPair(teamA: 3, teamB: 3)))
        #expect(ScoreFormatting.caption(phase: phase, deuceRule: .advantage) == "Deuce")
    }

    @Test func captionIsGoldenPointAtEqualFortyUnderGoldenPointRule() {
        let phase = ActivePhase.game(GameScore(points: TeamPair(teamA: 3, teamB: 3)))
        #expect(ScoreFormatting.caption(phase: phase, deuceRule: .goldenPoint) == "Golden Point")
    }

    @Test func captionIsTieBreakForSetTieBreak() {
        let phase = ActivePhase.setTieBreak(TieBreakScore(points: TeamPair(teamA: 1, teamB: 0)))
        #expect(ScoreFormatting.caption(phase: phase, deuceRule: .advantage) == "Tie-break")
    }

    @Test func captionIsMatchTieBreakForMatchTieBreak() {
        let phase = ActivePhase.matchTieBreak(TieBreakScore(points: TeamPair(teamA: 1, teamB: 0)))
        #expect(ScoreFormatting.caption(phase: phase, deuceRule: .advantage) == "Match tie-break")
    }

    // MARK: - setsScoreText

    @Test func setsScoreTextFormatsBothTeams() {
        #expect(ScoreFormatting.setsScoreText(setsWon: TeamPair(teamA: 0, teamB: 0)) == "0–0")
        #expect(ScoreFormatting.setsScoreText(setsWon: TeamPair(teamA: 2, teamB: 1)) == "2–1")
    }

    // MARK: - completedSetText

    @Test func completedSetTextShowsGamesOnlyWithoutTieBreak() {
        let set = SetScore(games: TeamPair(teamA: 6, teamB: 4), tieBreak: nil, winner: .teamA)
        #expect(ScoreFormatting.completedSetText(set) == "6-4")
    }

    @Test func completedSetTextShowsGamesOnlyWhenWinnerIsMissing() {
        let set = SetScore(
            games: TeamPair(teamA: 6, teamB: 6),
            tieBreak: TieBreakScore(points: TeamPair(teamA: 7, teamB: 5)),
            winner: nil
        )
        #expect(ScoreFormatting.completedSetText(set) == "6-6")
    }

    @Test func completedSetTextAppendsLosersTieBreakPoints() {
        let set = SetScore(
            games: TeamPair(teamA: 7, teamB: 6),
            tieBreak: TieBreakScore(points: TeamPair(teamA: 7, teamB: 5)),
            winner: .teamA
        )
        #expect(ScoreFormatting.completedSetText(set) == "7-6 (5)")
    }

    @Test func completedSetTextAppendsLosersTieBreakPointsWhenTeamBWins() {
        let set = SetScore(
            games: TeamPair(teamA: 6, teamB: 7),
            tieBreak: TieBreakScore(points: TeamPair(teamA: 8, teamB: 10)),
            winner: .teamB
        )
        #expect(ScoreFormatting.completedSetText(set) == "6-7 (8)")
    }
}
