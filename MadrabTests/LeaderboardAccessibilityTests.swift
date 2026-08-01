import Testing
import Foundation
@testable import Madrab

struct LeaderboardAccessibilityTests {
    @Test func summaryIncludesAllDisplayedStatistics() {
        let entry = LeaderboardEntry(
            profileID: UUID(),
            displayName: "Alex",
            avatarImageData: nil,
            stats: PlayerStats(totalPoints: 7, matchesPlayed: 3, wins: 2, losses: 1),
            rank: 1
        )

        let summary = LeaderboardAccessibility.summary(for: entry)

        #expect(summary.contains("Rank 1"))
        #expect(summary.contains("Alex"))
        #expect(summary.contains("7 points"))
        #expect(summary.contains("2 wins"))
        #expect(summary.contains("1 losses"))
        #expect(summary.contains("3 matches played"))
    }

    @Test func summaryDoesNotLeakInternalPersistenceDetails() {
        let entry = LeaderboardEntry(
            profileID: UUID(),
            displayName: "Alex",
            avatarImageData: nil,
            stats: PlayerStats(totalPoints: 1, matchesPlayed: 1, wins: 1, losses: 0),
            rank: 2
        )

        let summary = LeaderboardAccessibility.summary(for: entry)

        #expect(!summary.lowercased().contains("processedmatchid"))
        #expect(!summary.lowercased().contains("uuid"))
        #expect(!summary.contains(entry.profileID.uuidString))
    }
}
