import Foundation

/// Transport envelope shared by both devices.
///
/// WatchConnectivity carries `[String: Any]` dictionaries, so each wire model
/// travels as JSON `Data` under a single agreed key. Keeping the keys and the
/// coding here — rather than in either app target — means the phone and the
/// Watch cannot drift apart on the envelope format.
///
/// This adds no fields to any wire model; it only says how an already-defined
/// model is packed into a dictionary.
public enum SyncPayload {
    public static let commandKey = "madrab.sync.command"
    public static let responseKey = "madrab.sync.response"
    public static let snapshotKey = "madrab.sync.snapshot"

    public static func encodeCommand(_ command: SyncCommand) throws -> [String: Any] {
        [commandKey: try JSONEncoder().encode(command)]
    }

    public static func decodeCommand(from payload: [String: Any]) -> SyncCommand? {
        decode(SyncCommand.self, from: payload, key: commandKey)
    }

    public static func encodeResponse(_ response: SyncCommandResponse) throws -> [String: Any] {
        [responseKey: try JSONEncoder().encode(response)]
    }

    public static func decodeResponse(from payload: [String: Any]) -> SyncCommandResponse? {
        decode(SyncCommandResponse.self, from: payload, key: responseKey)
    }

    public static func encodeSnapshot(_ snapshot: SyncSnapshot) throws -> [String: Any] {
        [snapshotKey: try JSONEncoder().encode(snapshot)]
    }

    public static func decodeSnapshot(from payload: [String: Any]) -> SyncSnapshot? {
        decode(SyncSnapshot.self, from: payload, key: snapshotKey)
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        from payload: [String: Any],
        key: String
    ) -> T? {
        guard let data = payload[key] as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
