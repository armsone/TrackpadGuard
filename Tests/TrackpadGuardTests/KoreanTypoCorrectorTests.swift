import XCTest
@testable import TrackpadGuard

@MainActor
final class KoreanTypoCorrectorTests: XCTestCase {
    func testConservativeModeUsesKoreanSignalFromWholePhrase() {
        let corrector = KoreanTypoCorrector()

        XCTAssertEqual(
            corrector.automaticReplacement(for: "Ehdskandp Ehddl duffuTek"),
            "똥나무에 똥이 열렸다"
        )
    }

    func testPreferKoreanModeConvertsEnglishLikePhrase() {
        let corrector = KoreanTypoCorrector()
        XCTAssertNil(corrector.automaticReplacement(for: "duffuTek duffuTek"))

        corrector.prefersKorean = true
        XCTAssertEqual(corrector.automaticReplacement(for: "duffuTek duffuTek"), "열렸다 열렸다")
    }

    func testAutomaticCorrectionStillRequiresTwoWords() {
        let corrector = KoreanTypoCorrector()
        corrector.prefersKorean = true

        XCTAssertNil(corrector.automaticReplacement(for: "wkdlejqlfflwl"))
    }
}
