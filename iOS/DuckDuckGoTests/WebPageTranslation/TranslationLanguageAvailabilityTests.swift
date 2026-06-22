import XCTest
@testable import DuckDuckGo

final class TranslationLanguageAvailabilityTests: XCTestCase {

    func testDisplayNameUsesLocalizedLanguageName() {
        let name = translationLanguageDisplayName(forCode: "fr", locale: Locale(identifier: "en_US"))
        XCTAssertEqual(name, "French")
    }

    func testDisplayNameFallsBackToCodeWhenUnknown() {
        let name = translationLanguageDisplayName(forCode: "zz-ZZ", locale: Locale(identifier: "en_US"))
        XCTAssertEqual(name, "zz-ZZ")
    }
}
