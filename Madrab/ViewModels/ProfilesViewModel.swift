import Foundation
import Observation

enum ProfileValidationError: LocalizedError, Equatable {
    case blankName
    case duplicateName(String)

    var errorDescription: String? {
        switch self {
        case .blankName:
            return "Enter a display name."
        case .duplicateName(let name):
            return "A profile named \"\(name)\" already exists."
        }
    }
}

enum ProfileDeletionError: LocalizedError, Equatable {
    case inUseByActiveMatch
    case persistenceFailed

    var errorDescription: String? {
        switch self {
        case .inUseByActiveMatch:
            return "This profile is part of the current match and can't be deleted."
        case .persistenceFailed:
            return "Couldn't delete this profile. Please try again."
        }
    }
}

@MainActor
@Observable
final class ProfilesViewModel {
    private(set) var profiles: [PlayerProfile]
    private(set) var lastError: (any Error)?

    private let store: ProfileStore
    private let activeMatchStore: MatchStore
    private let statsPurger: LeaderboardStatsPurging

    init(
        store: ProfileStore? = nil,
        activeMatchStore: MatchStore? = nil,
        statsPurger: LeaderboardStatsPurging? = nil
    ) {
        let resolvedStore = store ?? ProfileStore()
        self.store = resolvedStore
        self.activeMatchStore = activeMatchStore ?? MatchStore()
        self.statsPurger = statsPurger ?? LeaderboardStatsPurger()
        self.profiles = resolvedStore.load().profiles
    }

    @discardableResult
    func createProfile(displayName: String, avatarImageData: Data? = nil) -> PlayerProfile? {
        lastError = nil
        guard let trimmed = validatedName(displayName) else { return nil }

        let profile = PlayerProfile(displayName: trimmed, avatarImageData: avatarImageData)
        let updated = profiles + [profile]

        guard persist(updated) else { return nil }
        profiles = updated
        return profile
    }

    @discardableResult
    func updateProfile(id: UUID, displayName: String, avatarImageData: Data?) -> Bool {
        lastError = nil
        guard profiles.contains(where: { $0.id == id }) else { return false }
        guard let trimmed = validatedName(displayName, excluding: id) else { return false }

        var updated = profiles
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return false }
        updated[index] = PlayerProfile(id: id, displayName: trimmed, avatarImageData: avatarImageData)

        guard persist(updated) else { return false }
        profiles = updated
        return true
    }

    /// Purges leaderboard stats before removing the profile itself, so a
    /// failure never leaves the profile list out of sync with what's on
    /// disk, and never falsely reports success.
    @discardableResult
    func deleteProfile(id: UUID) -> Bool {
        lastError = nil

        if let activeMatch = activeMatchStore.load(),
           activeMatch.teamAProfileID == id || activeMatch.teamBProfileID == id {
            lastError = ProfileDeletionError.inUseByActiveMatch
            return false
        }

        guard profiles.contains(where: { $0.id == id }) else { return false }

        do {
            try statsPurger.removeStats(forProfileID: id)
        } catch {
            lastError = ProfileDeletionError.persistenceFailed
            return false
        }

        let updated = profiles.filter { $0.id != id }
        guard persist(updated) else {
            lastError = ProfileDeletionError.persistenceFailed
            return false
        }

        profiles = updated
        return true
    }

    private func validatedName(_ rawName: String, excluding excludedID: UUID? = nil) -> String? {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = ProfileValidationError.blankName
            return nil
        }

        let isDuplicate = profiles.contains { profile in
            profile.id != excludedID && profile.displayName.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        guard !isDuplicate else {
            lastError = ProfileValidationError.duplicateName(trimmed)
            return nil
        }

        return trimmed
    }

    private func persist(_ updatedProfiles: [PlayerProfile]) -> Bool {
        do {
            try store.save(ProfilesFile(profiles: updatedProfiles))
            return true
        } catch {
            lastError = error
            return false
        }
    }
}
