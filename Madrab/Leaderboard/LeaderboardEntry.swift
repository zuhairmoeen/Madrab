import Foundation

struct LeaderboardEntry: Identifiable, Equatable {
    var id: UUID { profileID }
    let profileID: UUID
    let displayName: String
    let avatarImageData: Data?
    let stats: PlayerStats
    let rank: Int
}

/// Deterministic ranking: total points desc, then wins desc, then matches
/// played desc, then localized display name asc, then UUID string asc as a
/// final stable tie-break. Profiles that no longer exist (deleted) are
/// excluded even if orphaned stats remain.
func rankedEntries(
    statsByProfileID: [UUID: PlayerStats],
    profiles: [PlayerProfile]
) -> [LeaderboardEntry] {
    let profilesByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

    let unranked: [(PlayerProfile, PlayerStats)] = statsByProfileID.compactMap { profileID, stats in
        guard let profile = profilesByID[profileID] else { return nil }
        return (profile, stats)
    }

    let sorted = unranked.sorted { lhs, rhs in
        if lhs.1.totalPoints != rhs.1.totalPoints {
            return lhs.1.totalPoints > rhs.1.totalPoints
        }
        if lhs.1.wins != rhs.1.wins {
            return lhs.1.wins > rhs.1.wins
        }
        if lhs.1.matchesPlayed != rhs.1.matchesPlayed {
            return lhs.1.matchesPlayed > rhs.1.matchesPlayed
        }
        let nameComparison = lhs.0.displayName.localizedStandardCompare(rhs.0.displayName)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }
        return lhs.0.id.uuidString < rhs.0.id.uuidString
    }

    return sorted.enumerated().map { index, pair in
        LeaderboardEntry(
            profileID: pair.0.id,
            displayName: pair.0.displayName,
            avatarImageData: pair.0.avatarImageData,
            stats: pair.1,
            rank: index + 1
        )
    }
}
