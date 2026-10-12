import XCTest
@testable import Pip

@MainActor
final class SessionStoreTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func event(_ name: String, session: String = "s1", _ extra: [String: Any] = [:]) -> HookEnvelope {
        var payload: [String: Any] = ["hook_event_name": name, "session_id": session, "cwd": "/tmp/api-server"]
        payload.merge(extra) { _, new in new }
        return HookEnvelope(agent: .claude, pid: nil, payload: payload)
    }

    func testNoSessionsIsAsleep() {
        XCTAssertEqual(SessionStore().mood, .asleep)
    }

    func testPromptMakesSessionWorkWithTool() {
        let store = SessionStore()
        store.handle(event("UserPromptSubmit", ["prompt": "Fix tests\nmore detail"]), at: t0)
        store.handle(event("PreToolUse", ["tool_name": "Bash", "tool_input": ["command": "npm test"]]), at: t0)

        let session = store.sessions["s1"]
        XCTAssertEqual(session?.state, .working)
        XCTAssertEqual(session?.lastPrompt, "Fix tests")
        XCTAssertEqual(session?.currentTool, "Bash · npm test")
        XCTAssertEqual(session?.projectName, "api-server")
        XCTAssertEqual(store.mood, .working)
    }

    func testPermissionRequestQueuesApprovalAndReplies() {
        let store = SessionStore()
        var attention: [SessionStore.Attention] = []
        store.onAttention = { kind, _ in attention.append(kind) }
        var answered: ApprovalDecision?

        let id = store.handle(
            event("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "rm -rf dist"]]),
            at: t0, reply: { answered = $0 }
        )

        XCTAssertNotNil(id)
        XCTAssertEqual(store.mood, .needsYou)
        XCTAssertEqual(store.approvals.first?.title, "Wants to run a command")
        XCTAssertEqual(store.approvals.first?.detail, "rm -rf dist")
        XCTAssertEqual(attention.count, 1)

        store.resolve(id!, with: .allow)
        XCTAssertEqual(answered, .allow)
        XCTAssertTrue(store.approvals.isEmpty)
    }

    func testAbandonedApprovalIsDroppedWithoutReply() {
        let store = SessionStore()
        var answered = false
        let id = store.handle(event("PermissionRequest", ["tool_name": "Write"]), at: t0, reply: { _ in answered = true })!
        store.approvalAbandoned(id)
        XCTAssertTrue(store.approvals.isEmpty)
        XCTAssertFalse(answered)
    }

    func testStopFinishesThenSettlesToIdle() {
        let store = SessionStore()
        store.handle(event("UserPromptSubmit"), at: t0)
        store.handle(event("Stop", ["last_assistant_message": "Done.\nDetails"]), at: t0.addingTimeInterval(90))

        XCTAssertEqual(store.sessions["s1"]?.state, .finished)
        XCTAssertEqual(store.sessions["s1"]?.lastMessage, "Done.")
        XCTAssertEqual(store.sessions["s1"]?.lastDuration, 90)
        XCTAssertEqual(store.mood, .finished)

        store.tick(at: t0.addingTimeInterval(90 + SessionStore.finishedDisplay + 1))
        XCTAssertEqual(store.mood, .idle)
    }

    func testStopPassesThroughPendingApprovals() {
        let store = SessionStore()
        var answered: ApprovalDecision?
        store.handle(event("PermissionRequest", ["tool_name": "Bash"]), at: t0, reply: { answered = $0 })
        store.handle(event("Stop"), at: t0)
        XCTAssertEqual(answered, .passthrough)
        XCTAssertTrue(store.approvals.isEmpty)
    }

    func testStopFailureDistinguishesRateLimit() {
        let store = SessionStore()
        store.handle(event("StopFailure", session: "a", ["error": "rate_limit"]), at: t0)
        store.handle(event("StopFailure", session: "b", ["error": "server_error", "error_details": "500"]), at: t0)
        XCTAssertEqual(store.sessions["a"]?.state, .rateLimited)
        XCTAssertEqual(store.sessions["b"]?.state, .error)
        XCTAssertEqual(store.sessions["b"]?.errorText, "500")
        XCTAssertEqual(store.mood, .error, "error outranks rate limit")
    }

    func testMostUrgentMoodWins() {
        let store = SessionStore()
        store.handle(event("UserPromptSubmit", session: "a"), at: t0)
        store.handle(event("Notification", session: "b", ["notification_type": "agent_needs_input"]), at: t0)
        XCTAssertEqual(store.mood, .needsYou)
        XCTAssertEqual(store.orderedSessions.first?.id, "b")
    }

    func testEventsArrivingAfterSessionEndDontReviveIt() {
        let store = SessionStore()
        // A quick session whose hooks raced: the end landed first.
        store.handle(event("SessionEnd", session: "quick"), at: t0)
        store.handle(event("UserPromptSubmit", session: "quick"), at: t0.addingTimeInterval(0.1))
        store.handle(event("SessionStart", session: "quick"), at: t0.addingTimeInterval(0.2))
        XCTAssertNil(store.sessions["quick"])

        // Once the grace period has passed, the same id can start again (e.g. a resumed session).
        let later = t0.addingTimeInterval(SessionStore.endedGrace + 1)
        store.tick(at: later)
        store.handle(event("SessionStart", session: "quick"), at: later)
        XCTAssertNotNil(store.sessions["quick"])
    }

    func testSessionEndAndDeadProcessesRemoveSessions() {
        var alive = true
        let store = SessionStore(isProcessAlive: { _ in alive })
        store.handle(HookEnvelope(agent: .claude, pid: 4242, payload: ["hook_event_name": "SessionStart", "session_id": "p"]), at: t0)
        store.handle(event("SessionStart", session: "q"), at: t0)
        store.handle(event("SessionEnd", session: "q"), at: t0)
        XCTAssertEqual(Set(store.sessions.keys), ["p"])

        alive = false
        store.tick(at: t0)
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertEqual(store.mood, .asleep)
    }

    func testEnvelopeDecodesBridgeLine() throws {
        let line = #"{"v":1,"agent":"claude","pid":321,"env":{"TERM_PROGRAM":"ghostty"},"payload":{"hook_event_name":"PermissionRequest","session_id":"x"}}"#
        let envelope = try XCTUnwrap(HookEnvelope(data: Data(line.utf8)))
        XCTAssertEqual(envelope.agent, .claude)
        XCTAssertEqual(envelope.pid, 321)
        XCTAssertEqual(envelope.env["TERM_PROGRAM"], "ghostty")
        XCTAssertTrue(envelope.isBlocking)
    }
}
