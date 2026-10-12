import XCTest
import Darwin
@testable import Pip

@MainActor
final class BugFixTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func event(_ name: String, session: String = "s1", agent: AgentKind = .claude, pid: pid_t? = nil, _ extra: [String: Any] = [:]) -> HookEnvelope {
        var payload: [String: Any] = ["hook_event_name": name, "session_id": session, "cwd": "/tmp/api-server"]
        payload.merge(extra) { _, new in new }
        return HookEnvelope(agent: agent, pid: pid, payload: payload)
    }

    // MARK: - 1. Custom Agent Blocking & Envelope decoding

    func testCustomAgentBlockingInHookEnvelope() {
        // Custom / unknown agent sending PermissionRequest
        let env1 = HookEnvelope(
            agent: .unknown,
            pid: 999,
            payload: ["hook_event_name": "PermissionRequest", "session_id": "custom-1"],
            isBlocking: true
        )
        XCTAssertTrue(env1.isBlocking)

        // Envelope decoded from JSON data with blocking flag
        let json: [String: Any] = [
            "v": 1,
            "agent": "custom-cli",
            "pid": 999,
            "blocking": true,
            "payload": ["hook_event_name": "PermissionRequest", "session_id": "custom-1"]
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let env2 = HookEnvelope(data: data)
        XCTAssertNotNil(env2)
        XCTAssertTrue(env2!.isBlocking)

        // Non-blocking agent (Kimi / Qwen) normalized to Notification
        let kimiPayload: [String: Any] = ["hook_event_name": "PermissionRequest", "session_id": "kimi-1"]
        let kimiEnv = HookEnvelope(agent: .kimi, pid: 999, payload: kimiPayload)
        XCTAssertFalse(kimiEnv.isBlocking)
    }

    // MARK: - 2. BridgeConnection deinit cleanup

    func testBridgeConnectionDeinitClosesFDWithoutLeak() {
        var fds: [Int32] = [0, 0]
        let rc = socketpair(AF_UNIX, SOCK_STREAM, 0, &fds)
        XCTAssertEqual(rc, 0)

        // Allocate connection and abandon it in an inner scope
        do {
            _ = BridgeConnection(fd: fds[0])
        }

        // fds[0] was deallocated without calling finish(); its deinit should have closed fds[0]
        var byte: UInt8 = 0
        let n = read(fds[1], &byte, 1)
        // Reading from fds[1] should return 0 (EOF) because fds[0] was closed
        XCTAssertEqual(n, 0)
        close(fds[1])
    }

    // MARK: - 3. onApprovalRemoved callback

    func testOnApprovalRemovedTriggeredOnResolveAbandonedAndCancel() {
        let store = SessionStore()
        var removedIDs: [UUID] = []
        store.onApprovalRemoved = { removedIDs.append($0) }

        // Test resolve
        let id1 = store.handle(event("PermissionRequest", ["tool_name": "Bash"]), at: t0, reply: { _ in })!
        store.resolve(id1, with: .allow)
        XCTAssertEqual(removedIDs, [id1])

        // Test abandon
        let id2 = store.handle(event("PermissionRequest", ["tool_name": "Edit"]), at: t0, reply: { _ in })!
        store.approvalAbandoned(id2)
        XCTAssertEqual(removedIDs, [id1, id2])

        // Test cancel on turn Stop
        let id3 = store.handle(event("PermissionRequest", ["tool_name": "Write"]), at: t0, reply: { _ in })!
        store.handle(event("Stop"), at: t0)
        XCTAssertEqual(removedIDs, [id1, id2, id3])
    }

    // MARK: - 4. Finished Session Persists During Tick

    func testFinishedSessionPersistsDuringTickWhenProcessExits() {
        let store = SessionStore(isProcessAlive: { _ in false }) // Process is dead immediately
        store.handle(event("SessionStart", pid: 12345), at: t0)
        store.handle(event("UserPromptSubmit", pid: 12345), at: t0)
        store.handle(event("Stop", pid: 12345), at: t0)

        XCTAssertEqual(store.sessions["s1"]?.state, .finished)

        // Tick immediately while finishedDisplay has not passed
        store.tick(at: t0.addingTimeInterval(1))
        XCTAssertNotNil(store.sessions["s1"], "Session should not be pruned immediately before finishedDisplay")

        // Tick after finishedDisplay expires
        store.tick(at: t0.addingTimeInterval(SessionStore.finishedDisplay + 1))
        XCTAssertNil(store.sessions["s1"], "Session should be cleaned up after finishedDisplay")
    }

    func testLimitRingsResetsNow() {
        XCTAssertEqual(LimitStrip.resetText(resetsAt: nil, now: t0), "used")
        XCTAssertEqual(LimitStrip.resetText(resetsAt: t0.addingTimeInterval(-10), now: t0), "resets now")
        XCTAssertEqual(LimitStrip.resetText(resetsAt: t0, now: t0), "resets now")
        XCTAssertEqual(LimitStrip.resetText(resetsAt: t0.addingTimeInterval(45), now: t0), "resets in 1m")
        XCTAssertEqual(LimitStrip.resetText(resetsAt: t0.addingTimeInterval(3660), now: t0), "resets in 1h 1m")
    }

    // MARK: - 5. Clear Inactive Sessions Includes RateLimited

    func testClearInactiveSessionsIncludesRateLimited() {
        let store = SessionStore()
        store.handle(event("StopFailure", session: "s-rl", ["error": "rate_limit"]), at: t0)
        XCTAssertEqual(store.sessions["s-rl"]?.state, .rateLimited)
        XCTAssertTrue(store.hasInactiveSessions)

        store.clearInactiveSessions()
        XCTAssertNil(store.sessions["s-rl"])
        XCTAssertFalse(store.hasInactiveSessions)
    }

    // MARK: - 6. Extract Questions False Positive Prevention

    func testExtractQuestionsDoesNotFalsePositiveOnPromptWithoutChoices() {
        let store = SessionStore()

        // generate_image tool with a "prompt" argument
        let id1 = store.handle(
            event("PermissionRequest", ["tool_name": "generate_image", "tool_input": ["prompt": "A sunset over mountains"]]),
            at: t0, reply: { _ in }
        )!
        let approval1 = store.approvals.first { $0.id == id1 }!
        if case .question = approval1.kind {
            XCTFail("generate_image with prompt should not be classified as a question card")
        }

        // ask_user tool with a "prompt" argument
        let id2 = store.handle(
            event("PermissionRequest", ["tool_name": "AskUser", "tool_input": ["prompt": "Which file do you want to edit?"]]),
            at: t0, reply: { _ in }
        )!
        let approval2 = store.approvals.first { $0.id == id2 }!
        if case .question = approval2.kind {
            // Success
        } else {
            XCTFail("AskUser should be classified as a question card")
        }

        // Generic tool with options provided
        let id3 = store.handle(
            event("PermissionRequest", ["tool_name": "custom_prompt", "tool_input": ["prompt": "Choose a model", "options": ["Claude", "Codex"]]]),
            at: t0, reply: { _ in }
        )!
        let approval3 = store.approvals.first { $0.id == id3 }!
        if case .question(let questions) = approval3.kind {
            XCTAssertEqual(questions.first?.options, ["Claude", "Codex"])
        } else {
            XCTFail("Tool with prompt and options should be classified as a question card")
        }
    }

    // MARK: - 7. Markdown Heading Requires Space

    func testMarkdownHeadingRequiresSpace() {
        // "#include <stdio.h>" should be a paragraph, not a heading
        let blocks1 = MarkdownParser.parse("#include <stdio.h>")
        XCTAssertEqual(blocks1, [.paragraph(text: "#include <stdio.h>")])

        // "#tag" should be a paragraph
        let blocks2 = MarkdownParser.parse("#tag")
        XCTAssertEqual(blocks2, [.paragraph(text: "#tag")])

        // "# Real Heading" should be a heading
        let blocks3 = MarkdownParser.parse("# Real Heading")
        XCTAssertEqual(blocks3, [.heading(level: 1, text: "Real Heading")])
    }

    // MARK: - 8. Markdown Table Column Padding & Truncation

    func testMarkdownTablePadsAndTruncatesColumns() {
        let markdown = """
        | Col1 | Col2 | Col3 |
        | --- | --- | --- |
        | A | B |
        | 1 | 2 | 3 | 4 |
        """
        let blocks = MarkdownParser.parse(markdown)
        guard case .table(let headers, let rows) = blocks.first else {
            XCTFail("Expected table block")
            return
        }
        XCTAssertEqual(headers, ["Col1", "Col2", "Col3"])
        XCTAssertEqual(rows.count, 2)
        // Row 1 padded with empty string to match header count 3
        XCTAssertEqual(rows[0], ["A", "B", ""])
        // Row 2 truncated to match header count 3
        XCTAssertEqual(rows[1], ["1", "2", "3"])
    }

    // MARK: - 9. Git Worktree CRLF Handling

    func testGitWorktreeCRLF() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let gitDir = tempDir.appendingPathComponent("real-git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try "ref: refs/heads/feature-crlf\r\n".write(to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)

        // Worktree directory containing .git file with \r\n
        let wtDir = tempDir.appendingPathComponent("worktree")
        try FileManager.default.createDirectory(at: wtDir, withIntermediateDirectories: true)
        try "gitdir: \(gitDir.path)\r\n".write(to: wtDir.appendingPathComponent(".git"), atomically: true, encoding: .utf8)

        let branch = GitInfo.branch(at: wtDir.path)
        XCTAssertEqual(branch, "feature-crlf")
    }

    // MARK: - 10. Codex Usage UTF-8 Boundary Seek

    func testCodexUsageUTF8BoundarySeek() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("rollout-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        // Create a file > 262,144 bytes with multi-byte unicode near the seek boundary
        var content = String(repeating: "Line of filler text 🚀 testing utf8 boundary\n", count: 6500)
        content += "{\"timestamp\":\"2026-10-12T06:00:00Z\",\"rate_limits\":{\"primary\":{\"used_percent\":45.0,\"resets_in_seconds\":3600}}}\n"
        try content.write(to: tempFile, atomically: true, encoding: .utf8)

        let limits = CodexUsage.parse(tailOf: tempFile, modified: Date())
        XCTAssertFalse(limits.isEmpty)
        XCTAssertEqual(limits.first?.usedPercent, 45.0)
    }

    // MARK: - 11. NotchViewModel Carousel Current Approval

    func testNotchViewModelCurrentApproval() {
        let store = SessionStore()
        let vm = NotchViewModel(notchSize: CGSize(width: 200, height: 32))

        let id1 = store.handle(event("PermissionRequest", session: "s1", ["tool_name": "Bash"]), at: t0, reply: { _ in })!
        let id2 = store.handle(event("PermissionRequest", session: "s2", ["tool_name": "Edit"]), at: t0, reply: { _ in })!

        XCTAssertEqual(vm.currentApproval(in: store)?.id, id1)

        vm.selectedApprovalIndex = 1
        XCTAssertEqual(vm.currentApproval(in: store)?.id, id2)

        // Clamping out of range
        vm.selectedApprovalIndex = 99
        XCTAssertEqual(vm.currentApproval(in: store)?.id, id2)
    }
}
