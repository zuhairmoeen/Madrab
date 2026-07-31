import Testing

import MadrabScoringEngine

struct MatchConfigurationTests {
    @Test func defaultsAreValid() throws {
        _ = try MatchConfiguration()
    }

    @Test func validCustomValuesAreAccepted() throws {
        _ = try MatchConfiguration(
            setsToWin: 3,
            gamesToWinSet: 4,
            setTiebreakTriggerGames: 4,
            setTiebreakPoints: 5,
            finalSetMode: .matchTiebreak(points: 7)
        )
    }

    @Test func fullSetFinalModeSkipsMatchTiebreakValidation() throws {
        _ = try MatchConfiguration(finalSetMode: .fullSet)
    }

    @Test func rejectsSetsToWinBelowOne() {
        do {
            _ = try MatchConfiguration(setsToWin: 0)
            Issue.record("expected invalidConfiguration(.setsToWin) to be thrown")
        } catch {
            #expect(error == .invalidConfiguration(.setsToWin))
        }
    }

    @Test func rejectsGamesToWinSetBelowOne() {
        do {
            _ = try MatchConfiguration(gamesToWinSet: 0)
            Issue.record("expected invalidConfiguration(.gamesToWinSet) to be thrown")
        } catch {
            #expect(error == .invalidConfiguration(.gamesToWinSet))
        }
    }

    @Test func rejectsSetTiebreakTriggerGamesBelowOne() {
        do {
            _ = try MatchConfiguration(setTiebreakTriggerGames: 0)
            Issue.record(
                "expected invalidConfiguration(.setTiebreakTriggerGames) to be thrown"
            )
        } catch {
            #expect(error == .invalidConfiguration(.setTiebreakTriggerGames))
        }
    }

    @Test func rejectsSetTiebreakPointsBelowTwo() {
        do {
            _ = try MatchConfiguration(setTiebreakPoints: 1)
            Issue.record("expected invalidConfiguration(.setTiebreakPoints) to be thrown")
        } catch {
            #expect(error == .invalidConfiguration(.setTiebreakPoints))
        }
    }

    @Test func rejectsMatchTiebreakPointsBelowTwo() {
        do {
            _ = try MatchConfiguration(
                finalSetMode: .matchTiebreak(points: 1)
            )
            Issue.record(
                "expected invalidConfiguration(.matchTiebreakPoints) to be thrown"
            )
        } catch {
            #expect(error == .invalidConfiguration(.matchTiebreakPoints))
        }
    }
}
