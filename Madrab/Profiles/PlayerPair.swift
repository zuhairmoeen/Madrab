import Foundation

/// Two distinct player profiles occupying one side (Team A or Team B) of a
/// four-player match. Pairing is an app-layer concept only — the scoring
/// engine's Team A / Team B model is unmodified and unaware of pairs.
nonisolated struct PlayerPair: Codable, Equatable {
    let first: UUID
    let second: UUID
}
