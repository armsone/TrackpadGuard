import XCTest
@testable import TrackpadGuard

final class LineTranslationTests: XCTestCase {
    func testRequestRemovesAllWhitespaceAndPicksDirection() {
        let korean = ManualTextConversion.lineTranslationRequest(for: "  오늘 날씨가  좋다 ")
        XCTAssertEqual(korean, .init(compact: "오늘날씨가좋다", direction: .koreanToEnglish))
        let english = ManualTextConversion.lineTranslationRequest(for: "Good morning")
        XCTAssertEqual(english, .init(compact: "Goodmorning", direction: .englishToKorean))
        XCTAssertNil(ManualTextConversion.lineTranslationRequest(for: "   "))
        XCTAssertNil(ManualTextConversion.lineTranslationRequest(for: "123 !?"))
        XCTAssertNil(ManualTextConversion.lineTranslationRequest(for: "こんにちは"))
    }

    func testCurrentLinePrefixUsesLastLineBreakAndKeepsSpaces() {
        XCTAssertEqual(ManualTextConversion.currentLinePrefix(fromWindow: "앞줄\n 이 줄 ", windowReachesStart: false), .prefix(" 이 줄 "))
        XCTAssertEqual(ManualTextConversion.currentLinePrefix(fromWindow: "a\r\nb c", windowReachesStart: false), .prefix("b c"))
        XCTAssertEqual(ManualTextConversion.currentLinePrefix(fromWindow: "한 줄", windowReachesStart: true), .prefix("한 줄"))
        XCTAssertEqual(ManualTextConversion.currentLinePrefix(fromWindow: "잘린 줄", windowReachesStart: false), .tooLong)
        let long = String(repeating: "가", count: ManualTextConversion.maxLinePrefixUTF16 + 1)
        XCTAssertEqual(ManualTextConversion.currentLinePrefix(fromWindow: long, windowReachesStart: true), .tooLong)
    }

    func testAcceptedTranslationTrimsOuterOnlyAndRejectsUnchanged() {
        let ko = ManualTextConversion.LineRequest(compact: "오늘날씨가좋다", direction: .koreanToEnglish)
        XCTAssertEqual(ManualTextConversion.acceptedLineTranslation(" The weather is nice. \n", for: ko, originalLine: "오늘 날씨가 좋다"), "The weather is nice.")
        XCTAssertNil(ManualTextConversion.acceptedLineTranslation("오늘날씨가좋다", for: ko, originalLine: "오늘 날씨가 좋다"))
        XCTAssertNil(ManualTextConversion.acceptedLineTranslation("날씨 nice", for: ko, originalLine: "오늘 날씨가 좋다"))
        XCTAssertNil(ManualTextConversion.acceptedLineTranslation("a\nb", for: ko, originalLine: "오늘 날씨가 좋다"))
        let en = ManualTextConversion.LineRequest(compact: "Goodmorning", direction: .englishToKorean)
        XCTAssertEqual(ManualTextConversion.acceptedLineTranslation("좋은 아침", for: en, originalLine: "Good morning"), "좋은 아침")
        XCTAssertNil(ManualTextConversion.acceptedLineTranslation("Good morning", for: en, originalLine: "Good morning"))
    }
}
