import Testing
import Foundation
@testable import Madrab

struct MatchSetupValidationTests {
    @Test func cannotStartWithNoProfilesSelected() {
        #expect(MatchSetupValidation.canStart(teamAProfile: nil, teamBProfile: nil) == false)
    }

    @Test func cannotStartWithOnlyOneProfileSelected() {
        let profile = PlayerProfile(displayName: "Alex")
        #expect(MatchSetupValidation.canStart(teamAProfile: profile, teamBProfile: nil) == false)
        #expect(MatchSetupValidation.canStart(teamAProfile: nil, teamBProfile: profile) == false)
    }

    @Test func cannotStartWithTheSameProfileOnBothSides() {
        let profile = PlayerProfile(displayName: "Alex")
        #expect(MatchSetupValidation.canStart(teamAProfile: profile, teamBProfile: profile) == false)
    }

    @Test func canStartWithTwoDifferentProfiles() {
        let teamA = PlayerProfile(displayName: "Alex")
        let teamB = PlayerProfile(displayName: "Sam")
        #expect(MatchSetupValidation.canStart(teamAProfile: teamA, teamBProfile: teamB) == true)
    }

    @Test func reconciledSelectionKeepsIDWhenProfileStillExistsEvenIfRenamed() {
        let id = UUID()
        let renamed = PlayerProfile(id: id, displayName: "New Name")

        #expect(MatchSetupValidation.reconciledSelection(id, in: [renamed]) == id)
    }

    @Test func reconciledSelectionClearsIDWhenProfileNoLongerExists() {
        let deletedID = UUID()
        let otherProfile = PlayerProfile(displayName: "Still Here")

        #expect(MatchSetupValidation.reconciledSelection(deletedID, in: [otherProfile]) == nil)
    }

    @Test func reconciledSelectionStaysNilWhenNothingWasSelected() {
        #expect(MatchSetupValidation.reconciledSelection(nil, in: []) == nil)
    }
}
