public struct ServingPlayer: Sendable, Equatable, Hashable, Codable {
    public let team: Team
    public let position: TeamPlayer

    public init(team: Team, position: TeamPlayer) {
        self.team = team
        self.position = position
    }
}
