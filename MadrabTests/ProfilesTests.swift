import Testing
import Foundation
@testable import Madrab

struct ProfilesTests {
    private func makeTemporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("profiles.json")
    }

    @Test func profilesFileRoundTripsThroughCodable() throws {
        let profile = PlayerProfile(displayName: "Alex", avatarImageData: Data([1, 2, 3]))
        let file = ProfilesFile(schemaVersion: 1, profiles: [profile])

        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(ProfilesFile.self, from: data)

        #expect(decoded == file)
    }

    @Test func loadReturnsEmptyFileWhenNoFileExists() {
        let store = ProfileStore(fileURL: makeTemporaryFileURL())
        #expect(store.load() == ProfilesFile())
    }

    @Test func savedProfilesRoundTripThroughLoad() throws {
        let store = ProfileStore(fileURL: makeTemporaryFileURL())
        let file = ProfilesFile(profiles: [PlayerProfile(displayName: "Sam")])

        try store.save(file)

        #expect(store.load() == file)
    }

    @Test func loadResetsAndReturnsEmptyForCorruptJSON() throws {
        let fileURL = makeTemporaryFileURL()
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)

        let store = ProfileStore(fileURL: fileURL)

        #expect(store.load() == ProfilesFile())
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func loadResetsAndReturnsEmptyForUnsupportedSchemaVersion() throws {
        let fileURL = makeTemporaryFileURL()
        let futureFile = ProfilesFile(schemaVersion: 999, profiles: [PlayerProfile(displayName: "Future")])
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(futureFile).write(to: fileURL)

        let store = ProfileStore(fileURL: fileURL)

        #expect(store.load() == ProfilesFile())
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }
}
