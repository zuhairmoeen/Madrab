import Testing
import Foundation

@testable import MadrabSyncKit

struct SyncCommandResponseTests {
    @Test func roundTripsAccepted() throws {
        let response = SyncCommandResponse(commandID: UUID(), outcome: .accepted, snapshot: .unavailable)
        #expect(try roundTrip(response) == response)
    }

    @Test func roundTripsAlreadyApplied() throws {
        let response = SyncCommandResponse(commandID: UUID(), outcome: .alreadyApplied, snapshot: .unavailable)
        #expect(try roundTrip(response) == response)
    }

    @Test(arguments: [
        SyncRejectionReason.malformedCommand,
        .wrongMatch,
        .noLiveMatch,
        .staleRevision,
        .matchFinished,
        .invalidUndo,
        .persistenceFailed,
    ])
    func roundTripsEveryRejectionReason(_ reason: SyncRejectionReason) throws {
        let response = SyncCommandResponse(commandID: UUID(), outcome: .rejected(reason), snapshot: .unavailable)
        #expect(try roundTrip(response) == response)
    }
}
