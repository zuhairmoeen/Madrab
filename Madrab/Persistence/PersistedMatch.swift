import Foundation
import MadrabScoringEngine

struct PersistedMatch: Codable, Equatable {
    let configuration: MatchConfiguration
    let events: [ScoringEvent]
    let teamALabel: String
    let teamBLabel: String
    let matchID: UUID?
    let teamAProfileID: UUID?
    let teamBProfileID: UUID?

    init(
        configuration: MatchConfiguration,
        events: [ScoringEvent],
        teamALabel: String,
        teamBLabel: String,
        matchID: UUID? = nil,
        teamAProfileID: UUID? = nil,
        teamBProfileID: UUID? = nil
    ) {
        self.configuration = configuration
        self.events = events
        self.teamALabel = teamALabel
        self.teamBLabel = teamBLabel
        self.matchID = matchID
        self.teamAProfileID = teamAProfileID
        self.teamBProfileID = teamBProfileID
    }
}
