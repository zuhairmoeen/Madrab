/// Pure padel scoring simulator. Given an ordered sequence of "which team won
/// this point" and the rules to play under, simulates games → sets →
/// tie-breaks → match tie-break → serve rotation from scratch and produces
/// the resulting `MatchState`. Has no knowledge of event IDs, duplicates, or
/// undo — those are `MatchReplayer`'s concern; this type is exercised only
/// through `MatchReplayer`/`MatchEngine`, so it stays internal.
enum ScoreBuilder {
    static func score(for winners: [Team], configuration: MatchConfiguration, isTerminal: Bool) -> MatchState {
        var completedSets: [SetScore] = []
        var setsWon = TeamPair<Int>(both: 0)
        var currentSetGames = TeamPair<Int>(both: 0)
        var currentGamePoints = GameScore.initial
        var currentSetTieBreak: TieBreakScore?
        var currentMatchTieBreak: TieBreakScore?
        var matchWinner: Team?
        // Advances exactly once per completed "outer" service turn: one
        // normal game, one set tie-break (as a whole), or one match
        // tie-break (as a whole). A tie-break's internal point-by-point
        // serve rotation (see `tiebreakBlockIndex`) never touches this.
        var outerTurn = 0

        func isDecidingSet() -> Bool {
            setsWon.teamA == configuration.setsToWin - 1 && setsWon.teamB == configuration.setsToWin - 1
        }

        var isPlayingMatchTiebreak: Bool = {
            if case .matchTiebreak = configuration.finalSetMode {
                return isDecidingSet()
            }
            return false
        }()

        func servingTeam(atTurn turn: Int) -> Team {
            turn % 2 == 0 ? configuration.initialServingTeam : configuration.initialServingTeam.opponent
        }

        func priorTurnCount(for team: Team, upToTurn turn: Int) -> Int {
            team == configuration.initialServingTeam ? (turn + 1) / 2 : turn / 2
        }

        func servingPlayer(for team: Team, atTurn turn: Int) -> TeamPlayer {
            let index = priorTurnCount(for: team, upToTurn: turn)
            return index % 2 == 0 ? configuration.initialServer[team] : configuration.initialServer[team].other
        }

        func tiebreakBlockIndex(pointsPlayed n: Int) -> Int {
            n == 0 ? 0 : 1 + (n - 1) / 2
        }

        // Records a decided set. Does NOT touch `outerTurn` — every call site
        // is responsible for advancing it exactly once, at the moment its own
        // single outer service turn (game, or tie-break-as-a-whole) completed.
        func handleSetWon(by team: Team, games: TeamPair<Int>, tieBreak: TieBreakScore?) {
            setsWon[team] += 1
            completedSets.append(SetScore(games: games, tieBreak: tieBreak, winner: team))
            currentSetGames = TeamPair(both: 0)
            currentGamePoints = .initial
            currentSetTieBreak = nil

            if setsWon[team] >= configuration.setsToWin {
                matchWinner = team
            } else if case .matchTiebreak = configuration.finalSetMode, isDecidingSet() {
                isPlayingMatchTiebreak = true
            }
        }

        for winner in winners {
            if matchWinner != nil {
                break
            }

            if isPlayingMatchTiebreak {
                let tieBreak = (currentMatchTieBreak ?? .initial).applyingPoint(wonBy: winner)
                if case .matchTiebreak(let target) = configuration.finalSetMode,
                    let tieBreakWinner = tieBreak.winner(targetPoints: target)
                {
                    outerTurn += 1
                    currentMatchTieBreak = nil
                    isPlayingMatchTiebreak = false
                    handleSetWon(by: tieBreakWinner, games: currentSetGames, tieBreak: tieBreak)
                } else {
                    currentMatchTieBreak = tieBreak
                }
                continue
            }

            if let inProgressTieBreak = currentSetTieBreak {
                let tieBreak = inProgressTieBreak.applyingPoint(wonBy: winner)
                if let tieBreakWinner = tieBreak.winner(targetPoints: configuration.setTiebreakPoints) {
                    outerTurn += 1
                    handleSetWon(by: tieBreakWinner, games: currentSetGames, tieBreak: tieBreak)
                } else {
                    currentSetTieBreak = tieBreak
                }
                continue
            }

            let newGamePoints = currentGamePoints.applyingPoint(wonBy: winner)
            guard let gameWinner = newGamePoints.winner(deuceRule: configuration.deuceRule) else {
                currentGamePoints = newGamePoints
                continue
            }

            currentGamePoints = .initial
            outerTurn += 1
            var games = currentSetGames
            games[gameWinner] += 1
            currentSetGames = games

            let winnerGames = games[gameWinner]
            let opponentGames = games[gameWinner.opponent]

            if winnerGames >= configuration.gamesToWinSet && winnerGames - opponentGames >= 2 {
                handleSetWon(by: gameWinner, games: games, tieBreak: nil)
            } else if winnerGames == opponentGames && winnerGames == configuration.setTiebreakTriggerGames {
                currentSetTieBreak = .initial
            }
        }

        let currentSet: SetScore?
        let currentPhase: ActivePhase?
        let tiebreakPointsPlayed: Int

        if matchWinner != nil {
            currentSet = nil
            currentPhase = nil
            tiebreakPointsPlayed = 0
        } else if isPlayingMatchTiebreak {
            let tieBreak = currentMatchTieBreak ?? .initial
            currentSet = nil
            currentPhase = .matchTieBreak(tieBreak)
            tiebreakPointsPlayed = tieBreak.points.teamA + tieBreak.points.teamB
        } else if let tieBreak = currentSetTieBreak {
            currentSet = SetScore(games: currentSetGames, tieBreak: tieBreak, winner: nil)
            currentPhase = .setTieBreak(tieBreak)
            tiebreakPointsPlayed = tieBreak.points.teamA + tieBreak.points.teamB
        } else {
            currentSet = SetScore(games: currentSetGames, tieBreak: nil, winner: nil)
            currentPhase = .game(currentGamePoints)
            tiebreakPointsPlayed = 0
        }

        let effectiveTurn = outerTurn + tiebreakBlockIndex(pointsPlayed: tiebreakPointsPlayed)
        let finalServingTeam = servingTeam(atTurn: effectiveTurn)
        let finalServingPlayer: ServingPlayer? = configuration.servingPlayerTrackingEnabled
            ? ServingPlayer(team: finalServingTeam, position: servingPlayer(for: finalServingTeam, atTurn: effectiveTurn))
            : nil

        return MatchState(
            sets: completedSets,
            currentSet: currentSet,
            currentPhase: currentPhase,
            setsWon: setsWon,
            servingTeam: finalServingTeam,
            servingPlayer: finalServingPlayer,
            matchWinner: matchWinner,
            isTerminal: isTerminal
        )
    }
}
