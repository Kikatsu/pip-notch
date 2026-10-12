import XCTest
import UserNotifications
@testable import Pip

@MainActor
final class NotificationManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        PipDefaults.register()
    }

    // MARK: - Category Configuration Tests

    func testApprovalCategoryConfiguration() {
        let category = NotificationManager.approvalNotificationCategory

        XCTAssertEqual(category.identifier, "APPROVAL_CATEGORY")
        XCTAssertEqual(category.actions.count, 3)

        // ALLOW Action
        guard let allowAction = category.actions.first(where: { $0.identifier == "ALLOW" }) else {
            XCTFail("ALLOW action not found")
            return
        }
        XCTAssertEqual(allowAction.title, "Allow")
        XCTAssertEqual(allowAction.options, [.foreground])

        // DENY Action
        guard let denyAction = category.actions.first(where: { $0.identifier == "DENY" }) else {
            XCTFail("DENY action not found")
            return
        }
        XCTAssertEqual(denyAction.title, "Deny")
        XCTAssertEqual(denyAction.options, [.destructive])

        // JUMP Action
        guard let jumpAction = category.actions.first(where: { $0.identifier == "JUMP" }) else {
            XCTFail("JUMP action not found")
            return
        }
        XCTAssertEqual(jumpAction.title, "Focus Terminal")
        XCTAssertEqual(jumpAction.options, [.foreground])
    }

    func testFinishedCategoryConfiguration() {
        let category = NotificationManager.finishedNotificationCategory

        XCTAssertEqual(category.identifier, "FINISHED_CATEGORY")
        XCTAssertEqual(category.actions.count, 1)

        guard let jumpAction = category.actions.first(where: { $0.identifier == "JUMP" }) else {
            XCTFail("JUMP action not found in finished category")
            return
        }
        XCTAssertEqual(jumpAction.title, "Focus Terminal")
        XCTAssertEqual(jumpAction.options, [.foreground])
    }

    func testDefaultCategoriesContainsBoth() {
        let categories = NotificationManager.categories
        let identifiers = Set(categories.map(\.identifier))

        XCTAssertTrue(identifiers.contains("APPROVAL_CATEGORY"))
        XCTAssertTrue(identifiers.contains("FINISHED_CATEGORY"))
    }

    // MARK: - Payload Content Generation Tests

    func testApprovalContentForTool() {
        let approvalId = UUID()
        let approval = PendingApproval(
            id: approvalId,
            sessionID: "sess-100",
            agent: .claude,
            projectName: "MyService",
            toolName: "Bash",
            title: "Wants to run a command",
            detail: "swift build",
            receivedAt: Date()
        )

        let content = NotificationManager.shared.makeApprovalContent(for: approval)

        XCTAssertEqual(content.categoryIdentifier, "APPROVAL_CATEGORY")
        XCTAssertEqual(content.title, "Wants to run a command")
        XCTAssertEqual(content.subtitle, "Claude Code · MyService")
        XCTAssertEqual(content.body, "swift build")
        XCTAssertEqual(content.sound, .default)

        XCTAssertEqual(content.userInfo["approvalID"] as? String, approvalId.uuidString)
        XCTAssertEqual(content.userInfo["sessionID"] as? String, "sess-100")
        XCTAssertEqual(content.userInfo["agent"] as? String, AgentKind.claude.rawValue)
        XCTAssertEqual(content.userInfo["projectName"] as? String, "MyService")
        XCTAssertEqual(content.userInfo["category"] as? String, "APPROVAL_CATEGORY")
    }

    func testApprovalContentForPlan() {
        let approvalId = UUID()
        let planMarkdown = "# Architectural Plan\n1. Implement notifications\n2. Add tests"
        var approval = PendingApproval(
            id: approvalId,
            sessionID: "sess-200",
            agent: .antigravity,
            projectName: "Notch",
            toolName: "ReviewPlan",
            title: "Plan ready for review",
            detail: "",
            receivedAt: Date(),
            kind: .plan(markdown: planMarkdown)
        )
        approval.agentName = "Antigravity CLI"

        let content = NotificationManager.shared.makeApprovalContent(for: approval)

        XCTAssertEqual(content.categoryIdentifier, "APPROVAL_CATEGORY")
        XCTAssertEqual(content.title, "Plan ready for review")
        XCTAssertEqual(content.subtitle, "Antigravity CLI · Notch")
        XCTAssertEqual(content.body, planMarkdown)
        XCTAssertEqual(content.sound, .default)
        XCTAssertEqual(content.userInfo["approvalID"] as? String, approvalId.uuidString)
    }

    func testApprovalContentForQuestion() {
        let approvalId = UUID()
        let question = PendingApproval.Question(
            text: "Which environment to deploy?",
            options: ["Staging", "Production"]
        )
        let approval = PendingApproval(
            id: approvalId,
            sessionID: "sess-300",
            agent: .codex,
            projectName: "Infrastructure",
            toolName: "AskUserQuestion",
            title: "Which environment to deploy?",
            detail: "",
            receivedAt: Date(),
            kind: .question([question])
        )

        let content = NotificationManager.shared.makeApprovalContent(for: approval)

        XCTAssertEqual(content.categoryIdentifier, "APPROVAL_CATEGORY")
        XCTAssertEqual(content.title, "Which environment to deploy?")
        XCTAssertEqual(content.subtitle, "Codex · Infrastructure")
        XCTAssertEqual(content.body, "Staging, Production")
        XCTAssertEqual(content.sound, .default)
    }

    func testApprovalContentFallbackWhenDetailEmpty() {
        let approvalId = UUID()
        let approval = PendingApproval(
            id: approvalId,
            sessionID: "sess-400",
            agent: .cursor,
            projectName: "EditorApp",
            toolName: "CustomTool",
            title: "Wants to use CustomTool",
            detail: "",
            receivedAt: Date(),
            kind: .tool
        )

        let content = NotificationManager.shared.makeApprovalContent(for: approval)
        XCTAssertEqual(content.body, "CustomTool")
    }

    func testFinishedContentForSession() {
        var session = AgentSession(
            id: "sess-500",
            agent: .claude,
            cwd: "/Users/dev/Notch",
            env: [:],
            stateChangedAt: Date(),
            updatedAt: Date()
        )
        session.lastMessage = "All 42 tests passed successfully."
        session.lastPrompt = "Run the unit tests"

        let content = NotificationManager.shared.makeFinishedContent(for: session)

        XCTAssertEqual(content.categoryIdentifier, "FINISHED_CATEGORY")
        XCTAssertEqual(content.title, "Claude Code finished")
        XCTAssertEqual(content.subtitle, "Notch")
        XCTAssertEqual(content.body, "All 42 tests passed successfully.")
        XCTAssertNotNil(content.sound)

        XCTAssertEqual(content.userInfo["sessionID"] as? String, "sess-500")
        XCTAssertEqual(content.userInfo["agent"] as? String, AgentKind.claude.rawValue)
        XCTAssertEqual(content.userInfo["projectName"] as? String, "Notch")
        XCTAssertEqual(content.userInfo["category"] as? String, "FINISHED_CATEGORY")
    }

    func testFinishedContentFallbackToPromptWhenMessageNil() {
        var session = AgentSession(
            id: "sess-600",
            agent: .codex,
            cwd: "/Users/dev/Project",
            env: [:],
            stateChangedAt: Date(),
            updatedAt: Date()
        )
        session.lastMessage = nil
        session.lastPrompt = "Build release binary"

        let content = NotificationManager.shared.makeFinishedContent(for: session)
        XCTAssertEqual(content.body, "Build release binary")
    }

    func testFinishedContentDefaultFallback() {
        let session = AgentSession(
            id: "sess-700",
            agent: .cursor,
            cwd: "/Users/dev/Project",
            env: [:],
            stateChangedAt: Date(),
            updatedAt: Date()
        )

        let content = NotificationManager.shared.makeFinishedContent(for: session)
        XCTAssertEqual(content.body, "Turn finished")
    }

    // MARK: - Action Handling and Bridging Tests

    func testHandleActionAllowBridgesToApprovalResolution() {
        let manager = NotificationManager()
        let approvalId = UUID()
        var resolvedId: UUID?
        var resolvedDecision: ApprovalDecision?

        manager.onResolve = { id, decision in
            resolvedId = id
            resolvedDecision = decision
        }

        manager.handleAction(
            identifier: "ALLOW",
            userInfo: ["approvalID": approvalId.uuidString, "sessionID": "s1"]
        )

        XCTAssertEqual(resolvedId, approvalId)
        XCTAssertEqual(resolvedDecision, .allow)
    }

    func testHandleActionDenyBridgesToApprovalResolution() {
        let manager = NotificationManager()
        let approvalId = UUID()
        var resolvedId: UUID?
        var resolvedDecision: ApprovalDecision?

        manager.onResolve = { id, decision in
            resolvedId = id
            resolvedDecision = decision
        }

        manager.handleAction(
            identifier: "DENY",
            userInfo: ["approvalID": approvalId.uuidString, "sessionID": "s1"]
        )

        XCTAssertEqual(resolvedId, approvalId)
        XCTAssertEqual(resolvedDecision, .deny)
    }

    func testHandleActionJumpBridgesToSessionLookup() {
        let manager = NotificationManager()
        var lookedUpSessionID: String?

        let sampleSession = AgentSession(
            id: "s1",
            agent: .claude,
            cwd: "/tmp",
            env: [:],
            stateChangedAt: Date(),
            updatedAt: Date()
        )

        manager.sessionLookup = { id in
            lookedUpSessionID = id
            return sampleSession
        }

        manager.handleAction(
            identifier: "JUMP",
            userInfo: ["sessionID": "s1"]
        )

        XCTAssertEqual(lookedUpSessionID, "s1")
    }

    // MARK: - Preference Key Tests

    func testPipDefaultsNotificationsEnabledKey() {
        XCTAssertEqual(PipDefaults.notificationsEnabled, "notificationsEnabled")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: PipDefaults.notificationsEnabled))
    }
}
