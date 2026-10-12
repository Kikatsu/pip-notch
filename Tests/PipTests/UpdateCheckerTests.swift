import XCTest
@testable import Pip

final class UpdateCheckerTests: XCTestCase {
    private func releases(_ entries: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: entries)
    }

    private func entry(_ tag: String, draft: Bool = false, prerelease: Bool = true) -> [String: Any] {
        ["tag_name": tag, "html_url": "https://github.com/Kikatsu/pip-notch/releases/tag/\(tag)", "draft": draft, "prerelease": prerelease]
    }

    func testComparesVersionsNumerically() {
        XCTAssertTrue(UpdateChecker.isVersion("0.1.10", newerThan: "0.1.9"))
        XCTAssertTrue(UpdateChecker.isVersion("0.2", newerThan: "0.1.9"))
        XCTAssertTrue(UpdateChecker.isVersion("1.0.0", newerThan: "0.99.99"))
        XCTAssertFalse(UpdateChecker.isVersion("0.2", newerThan: "0.2.0"))
        XCTAssertFalse(UpdateChecker.isVersion("0.1.1", newerThan: "0.1.1"))
        XCTAssertFalse(UpdateChecker.isVersion("0.1.0", newerThan: "0.1.1"))
        XCTAssertFalse(UpdateChecker.isVersion("0.2.0-beta.1", newerThan: "0.2.0"))
    }

    func testPicksHighestNewerReleaseIncludingPrereleases() {
        let data = releases([entry("v0.1.2"), entry("v0.1.10"), entry("v0.1.1"), entry("v0.1.3")])
        let release = UpdateChecker.newest(in: data, newerThan: "0.1.1")
        XCTAssertEqual(release?.version, "0.1.10")
        XCTAssertEqual(release?.url.absoluteString, "https://github.com/Kikatsu/pip-notch/releases/tag/v0.1.10")
    }

    func testSkipsDraftsAndOlderReleases() {
        let data = releases([entry("v0.3.0", draft: true), entry("v0.1.0"), entry("v0.1.1")])
        XCTAssertNil(UpdateChecker.newest(in: data, newerThan: "0.1.1"))
    }

    func testIgnoresUnexpectedResponses() {
        XCTAssertNil(UpdateChecker.newest(in: Data(#"{"message":"API rate limit exceeded"}"#.utf8), newerThan: "0.1.1"))
        XCTAssertNil(UpdateChecker.newest(in: Data("not json".utf8), newerThan: "0.1.1"))
        XCTAssertNil(UpdateChecker.newest(in: releases([["tag_name": "v9.0.0"]]), newerThan: "0.1.1"))
    }

    @MainActor
    func testTurningOffClearsAnAvailableUpdate() {
        let defaults = UserDefaults(suiteName: "UpdateCheckerTests")!
        defaults.removePersistentDomain(forName: "UpdateCheckerTests")
        let checker = UpdateChecker(currentVersion: "0.1.1", defaults: defaults)
        XCTAssertTrue(checker.isEnabled)
        checker.isEnabled = false
        XCTAssertFalse(defaults.bool(forKey: UpdateChecker.enabledKey))
        XCTAssertNil(checker.available)
    }
}
