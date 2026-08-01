import MadrabScoringEngine

struct PersistedMatch: Codable, Equatable {
    let configuration: MatchConfiguration
    let events: [ScoringEvent]
    let teamALabel: String
    let teamBLabel: String
}
