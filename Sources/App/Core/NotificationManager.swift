import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    static let approvalCategory = "APPROVAL_CATEGORY"
    static let finishedCategory = "FINISHED_CATEGORY"
    static let inputCategory = "INPUT_CATEGORY"

    static let actionAllow = "ALLOW"
    static let actionDeny = "DENY"
    static let actionJump = "JUMP"

    private let center: UNUserNotificationCenter

    weak var store: SessionStore?
    var onResolve: ((UUID, ApprovalDecision) -> Void)?
    var sessionLookup: ((String) -> AgentSession?)?

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: PipDefaults.notificationsEnabled)
    }

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        registerCategories()
    }

    func registerAsDelegate() {
        center.delegate = self
    }

    // MARK: - Categories

    static var approvalNotificationCategory: UNNotificationCategory {
        let allow = UNNotificationAction(
            identifier: actionAllow,
            title: "Allow",
            options: [.foreground]
        )
        let deny = UNNotificationAction(
            identifier: actionDeny,
            title: "Deny",
            options: [.destructive]
        )
        let jump = UNNotificationAction(
            identifier: actionJump,
            title: "Focus Terminal",
            options: [.foreground]
        )
        return UNNotificationCategory(
            identifier: approvalCategory,
            actions: [allow, deny, jump],
            intentIdentifiers: [],
            options: []
        )
    }

    static var finishedNotificationCategory: UNNotificationCategory {
        let jump = UNNotificationAction(
            identifier: actionJump,
            title: "Focus Terminal",
            options: [.foreground]
        )
        return UNNotificationCategory(
            identifier: finishedCategory,
            actions: [jump],
            intentIdentifiers: [],
            options: []
        )
    }

    static var inputNotificationCategory: UNNotificationCategory {
        let jump = UNNotificationAction(
            identifier: actionJump,
            title: "Focus Terminal",
            options: [.foreground]
        )
        return UNNotificationCategory(
            identifier: inputCategory,
            actions: [jump],
            intentIdentifiers: [],
            options: []
        )
    }

    static var defaultCategories: Set<UNNotificationCategory> {
        [approvalNotificationCategory, finishedNotificationCategory, inputNotificationCategory]
    }

    static var categories: Set<UNNotificationCategory> {
        defaultCategories
    }

    func registerCategories() {
        center.setNotificationCategories(Self.defaultCategories)
    }

    // MARK: - Authorization

    @discardableResult
    func requestAuthorization(options: UNAuthorizationOptions = [.alert, .sound, .badge]) async throws -> Bool {
        registerCategories()
        return try await center.requestAuthorization(options: options)
    }

    func requestAuthorization(completion: @escaping @Sendable (Bool, (any Error)?) -> Void) {
        registerCategories()
        center.requestAuthorization(options: [.alert, .sound, .badge], completionHandler: completion)
    }

    // MARK: - Post Notifications

    func makeApprovalContent(for approval: PendingApproval) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = Self.approvalCategory
        content.title = approval.title
        let agent = approval.agentName ?? approval.agent.displayName
        content.subtitle = "\(agent) · \(approval.projectName)"

        switch approval.kind {
        case .tool:
            content.body = approval.detail.isEmpty ? approval.toolName : approval.detail
        case .plan(let markdown):
            let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
            content.body = trimmed.isEmpty ? "Plan ready for review" : String(trimmed.prefix(300))
        case .question(let questions):
            if let first = questions.first, !first.options.isEmpty {
                content.body = first.options.joined(separator: ", ")
            } else if !approval.detail.isEmpty {
                content.body = approval.detail
            } else {
                content.body = questions.first?.text ?? ""
            }
        }

        content.sound = .default
        content.userInfo = [
            "approvalID": approval.id.uuidString,
            "sessionID": approval.sessionID,
            "agent": approval.agent.rawValue,
            "projectName": approval.projectName,
            "category": Self.approvalCategory
        ]
        return content
    }

    func postApprovalNotification(for approval: PendingApproval) {
        guard isEnabled else { return }
        let content = makeApprovalContent(for: approval)
        let request = UNNotificationRequest(
            identifier: approval.id.uuidString,
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if let error {
                NSLog("Pip: failed to post approval notification: \(error)")
            }
        }
    }

    func removeApprovalNotification(for id: UUID) {
        let idString = id.uuidString
        center.removePendingNotificationRequests(withIdentifiers: [idString, "approval-\(idString)"])
        center.removeDeliveredNotifications(withIdentifiers: [idString, "approval-\(idString)"])
    }

    func makeFinishedContent(for session: AgentSession) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = Self.finishedCategory
        content.title = "\(session.agentName) finished"
        content.subtitle = session.projectName

        if let message = session.lastMessage, !message.isEmpty {
            content.body = message
        } else if let prompt = session.lastPrompt, !prompt.isEmpty {
            content.body = prompt
        } else {
            content.body = "Turn finished"
        }

        content.sound = .default
        content.userInfo = [
            "sessionID": session.id,
            "agent": session.agent.rawValue,
            "projectName": session.projectName,
            "category": Self.finishedCategory
        ]
        return content
    }

    func postFinishedNotification(for session: AgentSession) {
        guard isEnabled else { return }
        let content = makeFinishedContent(for: session)
        let request = UNNotificationRequest(
            identifier: "finished-\(session.id)",
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if let error {
                NSLog("Pip: failed to post finished notification: \(error)")
            }
        }
    }

    func makeNeedsInputContent(for session: AgentSession) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = Self.inputCategory
        content.title = "\(session.agentName) needs your input"
        content.subtitle = session.projectName
        content.body = session.currentTool ?? session.lastPrompt ?? "Waiting for input in terminal"
        content.sound = .default
        content.userInfo = [
            "sessionID": session.id,
            "agent": session.agent.rawValue,
            "projectName": session.projectName,
            "category": Self.inputCategory
        ]
        return content
    }

    func postNeedsInputNotification(for session: AgentSession) {
        guard isEnabled else { return }
        let content = makeNeedsInputContent(for: session)
        let request = UNNotificationRequest(
            identifier: "input-\(session.id)",
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if let error {
                NSLog("Pip: failed to post needs-input notification: \(error)")
            }
        }
    }

    // MARK: - Action Handling

    func resolveApproval(id: UUID, decision: ApprovalDecision) {
        if let onResolve {
            onResolve(id, decision)
        } else {
            store?.resolve(id, with: decision)
        }
        removeApprovalNotification(for: id)
    }

    func focusSession(id: String) {
        guard let session = sessionLookup?(id) ?? store?.sessions[id] else { return }
        TerminalJumper.focus(session)
    }

    func handleAction(identifier: String, userInfo: [AnyHashable: Any]) {
        switch identifier {
        case Self.actionAllow:
            if let idString = userInfo["approvalID"] as? String, let id = UUID(uuidString: idString) {
                resolveApproval(id: id, decision: .allow)
            }
        case Self.actionDeny:
            if let idString = userInfo["approvalID"] as? String, let id = UUID(uuidString: idString) {
                resolveApproval(id: id, decision: .deny)
            }
        case Self.actionJump, UNNotificationDefaultActionIdentifier:
            if let sessionID = userInfo["sessionID"] as? String {
                focusSession(id: sessionID)
            }
        default:
            break
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            self.handleAction(
                identifier: response.actionIdentifier,
                userInfo: response.notification.request.content.userInfo
            )
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
    }
}
