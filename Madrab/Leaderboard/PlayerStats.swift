import Foundation

struct PlayerStats: Codable, Equatable {
    var totalPoints: Int = 0
    var matchesPlayed: Int = 0
    var wins: Int = 0
    var losses: Int = 0
}
