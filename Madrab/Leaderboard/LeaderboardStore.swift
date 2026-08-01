import Foundation

struct LeaderboardStore {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.resolveDefaultFileURL()
    }

    func load() -> LeaderboardFile {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(LeaderboardFile.self, from: data),
              file.schemaVersion == LeaderboardFile.currentSchemaVersion
        else {
            clear()
            return LeaderboardFile()
        }
        return file
    }

    func save(_ file: LeaderboardFile) throws {
        let data = try JSONEncoder().encode(file)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func resolveDefaultFileURL() -> URL {
        let directory = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory

        return directory
            .appendingPathComponent("Madrab", isDirectory: true)
            .appendingPathComponent("leaderboard.json")
    }
}
