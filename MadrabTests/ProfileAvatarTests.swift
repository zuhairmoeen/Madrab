import Testing
@testable import Madrab

struct ProfileAvatarTests {
    @Test func singleWordNameUsesFirstLetter() {
        #expect(ProfileInitials.initials(for: "Alex") == "A")
    }

    @Test func twoWordNameUsesBothInitials() {
        #expect(ProfileInitials.initials(for: "Alex Smith") == "AS")
    }

    @Test func threeOrMoreWordsUsesOnlyFirstTwo() {
        #expect(ProfileInitials.initials(for: "Alex Jamie Smith") == "AJ")
    }

    @Test func lowercaseInputIsUppercased() {
        #expect(ProfileInitials.initials(for: "alex smith") == "AS")
    }

    @Test func extraInternalWhitespaceIsIgnored() {
        #expect(ProfileInitials.initials(for: "Alex   Smith") == "AS")
    }

    @Test func blankNameFallsBackToPlaceholder() {
        #expect(ProfileInitials.initials(for: "") == "?")
        #expect(ProfileInitials.initials(for: "   ") == "?")
    }
}
