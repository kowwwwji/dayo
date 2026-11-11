import Foundation
import Testing
@testable import DayoCore

private let line = "-::~:~::~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~::~:~::-"
private let block = """
\(line)
Google Meet に参加: https://meet.google.com/abc-defg-hij
または、次の電話番号にダイヤル: (JP) +81 3-0000-0000 PIN: 123456789#
Meet の詳細: https://support.google.com/a/users/answer/9282720

このセクションは編集しないでください。
\(line)
"""

@Suite struct ConferenceNotesTests {
    @Test func notesWithoutABlockAreLeftAsTheyAre() {
        let notes = ConferenceNotes("議題: 来期の計画\nhttps://example.com/agenda")

        #expect(notes.body == "議題: 来期の計画\nhttps://example.com/agenda")
        #expect(notes.url == nil)
        #expect(notes.combined(withBody: notes.body) == "議題: 来期の計画\nhttps://example.com/agenda")
    }

    @Test func theBlockIsTakenOutOfTheBody() {
        let notes = ConferenceNotes("議題: 来期の計画\n\n\(block)")

        #expect(notes.body == "議題: 来期の計画")
        #expect(notes.url == URL(string: "https://meet.google.com/abc-defg-hij"))
    }

    @Test func notesWithOnlyABlockHaveAnEmptyBody() {
        let notes = ConferenceNotes(block)

        #expect(notes.body == "")
        #expect(notes.url == URL(string: "https://meet.google.com/abc-defg-hij"))
    }

    @Test func theEnglishBlockIsRecognisedToo() {
        let english = "\(line)\nJoin with Google Meet: https://meet.google.com/xyz-abcd-efg\n\nPlease do not edit this section.\n\(line)"
        let notes = ConferenceNotes("Agenda\n\n\(english)")

        #expect(notes.body == "Agenda")
        #expect(notes.url == URL(string: "https://meet.google.com/xyz-abcd-efg"))
    }

    @Test func anUntouchedBodyGivesBackTheOriginalNotes() {
        let original = "議題: 来期の計画\n\n\n\(block)\n"
        let notes = ConferenceNotes(original)

        #expect(notes.combined(withBody: notes.body) == original)
    }

    @Test func anEditedBodyKeepsTheBlockAfterIt() {
        let notes = ConferenceNotes("議題: 来期の計画\n\n\(block)")

        #expect(notes.combined(withBody: "議題: 再来期の計画") == "議題: 再来期の計画\n\n\(block)")
    }

    @Test func emptyingTheBodyLeavesOnlyTheBlock() {
        let notes = ConferenceNotes("議題: 来期の計画\n\n\(block)")

        #expect(notes.combined(withBody: "  \n") == block)
    }

    @Test func textAfterTheBlockStaysInTheBody() {
        let notes = ConferenceNotes("前\n\n\(block)\n後")

        #expect(notes.body == "前\n後")
        #expect(notes.combined(withBody: "前\n後") == "前\n\n\(block)\n後")
    }

    @Test(arguments: [
        "https://meet.google.com.example.com/abc",
        "https://example.com/meet.google.com",
        "http://meet.google.com/abc-defg-hij",
    ])
    func aBlockLeadingSomewhereElseStaysInTheNotes(link: String) {
        let fake = "\(line)\nGoogle Meet に参加: \(link)\n\(line)"
        let notes = ConferenceNotes("議題\n\n\(fake)")

        #expect(notes.body == "議題\n\n\(fake)")
        #expect(notes.url == nil)
    }

    @Test func aSingleSeparatorLineIsNotABlock() {
        let notes = ConferenceNotes("前\n\(line)\n後")

        #expect(notes.body == "前\n\(line)\n後")
        #expect(notes.url == nil)
    }
}
