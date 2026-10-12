import XCTest
@testable import Pip

@MainActor
final class ReviewAndBranchTests: XCTestCase {
    private func permission(_ tool: String, _ input: [String: Any]) -> HookEnvelope {
        HookEnvelope(agent: .claude, pid: nil, payload: [
            "hook_event_name": "PermissionRequest", "session_id": "s", "cwd": "/tmp/app", "tool_name": tool, "tool_input": input,
        ])
    }

    func testExitPlanModeBecomesAPlanReview() {
        let store = SessionStore()
        var answer: ApprovalDecision?
        store.handle(permission("ExitPlanMode", ["plan": "## Plan\n1. Add tests\n2. Ship"]), reply: { answer = $0 })
        XCTAssertEqual(store.approvals.first?.kind, .plan(markdown: "## Plan\n1. Add tests\n2. Ship"))
        XCTAssertEqual(store.approvals.first?.title, "Plan ready for review")

        store.resolve(store.approvals[0].id, with: .deny("Use SQLite instead"))
        XCTAssertEqual(answer, .deny("Use SQLite instead"))
    }

    func testAskUserQuestionShowsQuestionsAndOptions() {
        let store = SessionStore()
        store.handle(permission("AskUserQuestion", ["questions": [
            ["question": "Which database?", "options": [["label": "Postgres"], ["label": "SQLite"]]],
        ]]), reply: { _ in })
        XCTAssertEqual(store.approvals.first?.kind, .question([.init(text: "Which database?", options: ["Postgres", "SQLite"])]))
    }

    func testAttentionCarriesTheSession() {
        let store = SessionStore()
        var seen: [(SessionStore.Attention, String)] = []
        store.onAttention = { seen.append(($0, $1.projectName)) }
        store.handle(HookEnvelope(agent: .claude, pid: nil, payload: ["hook_event_name": "Stop", "session_id": "s", "cwd": "/tmp/app"]))
        XCTAssertEqual(seen.first?.0, .finished)
        XCTAssertEqual(seen.first?.1, "app")
    }

    func testParseHead() {
        XCTAssertEqual(GitInfo.parseHead("ref: refs/heads/feature/login\n"), "feature/login")
        XCTAssertEqual(GitInfo.parseHead("4f2a9c1e5b7d4e8a\n"), "4f2a9c1")
        XCTAssertNil(GitInfo.parseHead(""))
    }

    func testBranchFromNestedFolderAndWorktree() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("src/deep"), withIntermediateDirectories: true)
        try "ref: refs/heads/main\n".write(to: repo.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
        XCTAssertEqual(GitInfo.branch(at: repo.appendingPathComponent("src/deep").path), "main")

        let worktreeGit = repo.appendingPathComponent(".git/worktrees/wt")
        try FileManager.default.createDirectory(at: worktreeGit, withIntermediateDirectories: true)
        try "ref: refs/heads/fix-login\n".write(to: worktreeGit.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        let worktree = root.appendingPathComponent("wt")
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try "gitdir: \(worktreeGit.path)\n".write(to: worktree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        XCTAssertEqual(GitInfo.branch(at: worktree.path), "fix-login")
    }

    func testStoreRecordsBranch() {
        let store = SessionStore(gitBranch: { _ in "main" })
        store.handle(HookEnvelope(agent: .claude, pid: nil, payload: ["hook_event_name": "UserPromptSubmit", "session_id": "s", "cwd": "/tmp/app"]))
        XCTAssertEqual(store.sessions["s"]?.branch, "main")
    }

    func testAskUserQuestionWithStringArrayOptions() {
        let store = SessionStore()
        var answer: ApprovalDecision?
        store.handle(permission("ask_question", [
            "questions": [
                ["question": "Which deployment target?", "options": ["Production", "Staging", "Local only"]]
            ]
        ]), reply: { answer = $0 })

        XCTAssertEqual(store.approvals.first?.title, "Which deployment target?")
        XCTAssertEqual(store.approvals.first?.kind, .question([.init(text: "Which deployment target?", options: ["Production", "Staging", "Local only"])]))

        store.resolve(store.approvals[0].id, with: .deny("User selected: Production"))
        XCTAssertEqual(answer, .deny("User selected: Production"))
    }

    func testAskUserQuestionDirectFormatAndDescriptions() {
        let store = SessionStore()
        store.handle(permission("AskUserQuestion", [
            "question": "Which deployment target?",
            "options": [
                ["label": "Production", "description": "Deploy to live AWS"],
                ["label": "Staging", "description": "Deploy to staging cluster"],
                ["label": "Local only", "description": "Run locally only"]
            ]
        ]), reply: { _ in })

        guard case .question(let questions) = store.approvals.first?.kind else {
            XCTFail("Expected question kind")
            return
        }
        XCTAssertEqual(questions.first?.text, "Which deployment target?")
        XCTAssertEqual(questions.first?.options, ["Production", "Staging", "Local only"])
        XCTAssertEqual(questions.first?.descriptions["Production"], "Deploy to live AWS")
    }
}

final class PlanRenderingTests: XCTestCase {
    func testHeadingsBecomeBoldLines() {
        let rendered = String(ApprovalCard.render("## Plan\n1. Ship").characters)
        XCTAssertEqual(rendered, "Plan\n1. Ship")
    }

    func testMarkdownParserExtractsBlocks() {
        let md = """
        # Architecture Plan
        ## Step 1
        - [x] Done item
        - [ ] Pending item
        1. First task
        2. Second task
        > Critical note
        ```swift
        let x = 42
        ```
        | Col A | Col B |
        | --- | --- |
        | Val 1 | Val 2 |
        ---
        Paragraph text here.
        """
        let blocks = MarkdownParser.parse(md)
        XCTAssertTrue(blocks.contains(.heading(level: 1, text: "Architecture Plan")))
        XCTAssertTrue(blocks.contains(.heading(level: 2, text: "Step 1")))
        XCTAssertTrue(blocks.contains(.taskList(items: [(true, "Done item"), (false, "Pending item")])))
        XCTAssertTrue(blocks.contains(.orderedList(items: [(1, "First task"), (2, "Second task")])))
        XCTAssertTrue(blocks.contains(.blockquote(text: "Critical note")))
        XCTAssertTrue(blocks.contains(.codeBlock(language: "swift", code: "let x = 42")))
        XCTAssertTrue(blocks.contains(.table(headers: ["Col A", "Col B"], rows: [["Val 1", "Val 2"]])))
        XCTAssertTrue(blocks.contains(.horizontalRule))
        XCTAssertTrue(blocks.contains(.paragraph(text: "Paragraph text here.")))
    }
}
