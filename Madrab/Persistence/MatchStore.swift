import Foundation

struct MatchStore {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.resolveDefaultFileURL()
    }

    func save(_ match: PersistedMatch) throws {
        let data = try JSONEncoder().encode(match)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    func load() -> PersistedMatch? {
        guard let data = try? Data(contentsOf: fileURL),
              let match = try? JSONDecoder().decode(PersistedMatch.self, from: data)
        else {
            clear()
            return nil
        }
        return match
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
            .appendingPathComponent("active-match.json")
    }
}
