import XCTest
@testable import Pip

final class NotchDisplayTests: XCTestCase {
    func testStoredValuesRoundTrip() {
        for display in [NotchDisplay.automatic, .primary, .followPointer, .display(uuid: "37D8832A-2D66-02CA-B9F7-8F30A301B230")] {
            XCTAssertEqual(NotchDisplay(rawValue: display.rawValue), display)
        }
    }

    func testMissingValueIsAutomatic() {
        XCTAssertEqual(NotchDisplay(rawValue: nil), .automatic)
    }

    func testNoScreensPicksNothing() {
        XCTAssertNil(NotchDisplay.display(uuid: "gone").screen(among: [], pointer: .zero))
    }

    func testUnpluggedDisplayFallsBackToAutomatic() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let fallback = NotchDisplay.automatic.screen(among: screens, pointer: .zero)
        XCTAssertEqual(NotchDisplay.display(uuid: "not-connected").screen(among: screens, pointer: .zero), fallback)
    }
}
