import Testing
import Foundation

import MadrabScoringEngine
@testable import MadrabSyncKit

struct SyncCommandTests {
    @Test func roundTripsRecordPoint() throws {
        let command = SyncCommand(
            matchID: UUID(),
            commandID: UUID(),
            expectedStateRevision: 3,
            kind: .recordPoint(.teamA),
            sentAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(try roundTrip(command) == command)
    }

    @Test func roundTripsUndo() throws {
        let command = SyncCommand(
            matchID: UUID(),
            commandID: UUID(),
            expectedStateRevision: 5,
            kind: .undo
        )

        #expect(try roundTrip(command) == command)
    }

    @Test func roundTripsRequestLatestStateWithNilMatchID() throws {
        let command = SyncCommand(
            matchID: nil,
            commandID: UUID(),
            expectedStateRevision: 0,
            kind: .requestLatestState
        )

        let decoded = try roundTrip(command)
        #expect(decoded == command)
        #expect(decoded.matchID == nil)
    }

    @Test func roundTripsWithNilSentAt() throws {
        let command = SyncCommand(
            matchID: UUID(),
            commandID: UUID(),
            expectedStateRevision: 0,
            kind: .recordPoint(.teamB),
            sentAt: nil
        )

        #expect(try roundTrip(command) == command)
    }
}
