import Foundation

struct ProfileStore {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.resolveDefaultFileURL()
    }

    func load() -> ProfilesFile {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(ProfilesFile.self, from: data),
              file.schemaVersion == ProfilesFile.currentSchemaVersion
        else {
            clear()
            return ProfilesFile()
        }
        return file
    }

    func save(_ file: ProfilesFile) throws {
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
            .appendingPathComponent("profiles.json")
    }
}
