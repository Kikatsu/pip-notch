import XCTest
@testable import Pip

final class DeepSeekHarnessTests: XCTestCase {
    private var dir: URL!
    private let bridge = "/Users/me/Library/Application Support/Pip/bin/pip-bridge"

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func dsh() -> AgentIntegration {
        let hooks = dir.appendingPathComponent("pip-hooks.json")
        return AgentIntegration(
            agent: .dsh, configURL: dir.appendingPathComponent("cordis.patch.yml"),
            format: .tomlBlock { _ in AgentPlugins.dshPatch(hooksPath: hooks.path) },
            detectPaths: [dir.path], note: nil,
            extraFiles: [(hooks, AgentPlugins.dshHooks(bridgePath:))]
        )
    }

    func testMountsTheClaudeHooksBridgeAndKeepsTheUsersPatch() throws {
        let patch = dir.appendingPathComponent("cordis.patch.yml")
        let users = "- id: hmr\n  disabled: true\n"
        try users.write(to: patch, atomically: true, encoding: .utf8)
        let integration = dsh()

        try integration.install(bridgePath: bridge)
        let text = try String(contentsOf: patch, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix(users))
        XCTAssertTrue(text.contains("name: '@deepseek-ai/dsh-hooks-claude-code'"))
        XCTAssertTrue(text.contains("configPath: '\(dir.appendingPathComponent("pip-hooks.json").path)'"))
        XCTAssertTrue(integration.isInstalled(bridgePath: bridge))

        let hooks = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("pip-hooks.json"))) as? [String: Any]
        let events = Set((hooks?["hooks"] as? [String: Any])?.keys.map { $0 } ?? [])
        XCTAssertEqual(events, ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop"],
                       "Only events dsh's bridge supports")

        try integration.uninstall()
        XCTAssertEqual(try String(contentsOf: patch, encoding: .utf8), users)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("pip-hooks.json").path))
    }

    func testStaleHooksFileCountsAsNotInstalled() throws {
        let integration = dsh()
        try integration.install(bridgePath: bridge)
        XCTAssertFalse(integration.isInstalled(bridgePath: "/Applications/Pip.app/Contents/MacOS/pip-bridge"),
                       "A moved bridge must be rewritten into pip-hooks.json, not only the patch block")
    }
}
