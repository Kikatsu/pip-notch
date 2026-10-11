import XCTest
@testable import Pip

@MainActor
final class InteractionTests: XCTestCase {
    func testReactionsOverrideMoodOnlyWhilePlaying() {
        let identity = CGSize(width: 1, height: 1)
        XCTAssertEqual(CharacterView.react(.working, nil, age: 0).0, .working)
        XCTAssertEqual(CharacterView.react(.asleep, .hello, age: 0.2).0, .idle, "opening the notch wakes it")
        XCTAssertEqual(CharacterView.react(.working, .poke, age: 0.3).0, .finished, "a poke makes it giggle")
        XCTAssertNotEqual(CharacterView.react(.working, .poke, age: 0.1).1, identity, "and squish")
        XCTAssertEqual(CharacterView.react(.working, .approve, age: 0.5).0, .finished)
        XCTAssertEqual(CharacterView.react(.working, .deny, age: 0.5).0, .rateLimited)
        XCTAssertEqual(CharacterView.react(.working, .poke, age: 5).0, .working, "back to normal afterwards")
        XCTAssertEqual(CharacterView.react(.working, .poke, age: 5).1, identity)
    }

    func testExpandingSaysHello() {
        let model = NotchViewModel(notchSize: CGSize(width: 180, height: 32))
        let store = SessionStore()
        store.handle(HookEnvelope(agent: .claude, pid: nil, payload: ["hook_event_name": "PermissionRequest", "session_id": "s", "tool_name": "Bash"]), reply: { _ in })
        model.updateExpansion(store: store)
        XCTAssertTrue(model.isExpanded)
        XCTAssertEqual(model.face.reaction, .hello)
    }

    func testLimitDisplayModes() {
        let usage = UsageStore(codexHome: URL(fileURLWithPath: "/nonexistent"))
        usage.updateClaude(["five_hour": ["used_percentage": 85], "seven_day": ["used_percentage": 40]])
        XCTAssertEqual(usage.shown(.always).count, 2)
        XCTAssertEqual(usage.shown(.whenLow).map(\.window), [.fiveHour])
        XCTAssertTrue(usage.shown(.never).isEmpty)
    }
}
