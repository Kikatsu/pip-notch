import XCTest
@testable import Pip

final class HookInstallerTests: XCTestCase {
    private let command = "\"/Users/me/Library/Application Support/Pip/bin/pip-bridge\" claude"

    private var existing: [String: Any] {
        [
            "model": "opus",
            "hooks": [
                "PreToolUse": [
                    ["matcher": "Bash", "hooks": [["type": "command", "command": "~/guard.sh"]]],
                ],
            ],
        ]
    }

    func testInstallKeepsUserSettingsAndHooks() {
        let result = HookInstaller.installing(into: existing, command: command)
        XCTAssertEqual(result["model"] as? String, "opus")

        let hooks = result["hooks"] as! [String: Any]
        let preToolUse = hooks["PreToolUse"] as! [[String: Any]]
        XCTAssertEqual(preToolUse.count, 2)
        XCTAssertEqual(preToolUse[0]["matcher"] as? String, "Bash")
        XCTAssertEqual(Set(hooks.keys), Set(HookInstaller.claudeEvents))
        XCTAssertTrue(HookInstaller.containsPipHooks(result))
    }

    func testOnlyPermissionRequestBlocks() {
        let hooks = HookInstaller.installing(into: [:], command: command)["hooks"] as! [String: Any]
        for event in HookInstaller.claudeEvents {
            let handler = ((hooks[event] as! [[String: Any]]).last!["hooks"] as! [[String: Any]])[0]
            if event == "PermissionRequest" {
                XCTAssertNil(handler["async"])
                XCTAssertEqual(handler["timeout"] as? Int, 600)
            } else {
                XCTAssertEqual(handler["async"] as? Bool, true, event)
            }
        }
    }

    func testInstallIsIdempotent() {
        let once = HookInstaller.installing(into: existing, command: command)
        let twice = HookInstaller.installing(into: once, command: command)
        XCTAssertEqual(NSDictionary(dictionary: once), NSDictionary(dictionary: twice))
    }

    func testUninstallRestoresOriginal() {
        let installed = HookInstaller.installing(into: existing, command: command)
        let removed = HookInstaller.removingPipHooks(from: installed)
        XCTAssertEqual(NSDictionary(dictionary: removed), NSDictionary(dictionary: existing))
        XCTAssertFalse(HookInstaller.containsPipHooks(removed))
    }

    func testUninstallFromEmptySettingsLeavesNoHooksKey() {
        let removed = HookInstaller.removingPipHooks(from: HookInstaller.installing(into: [:], command: command))
        XCTAssertTrue(removed.isEmpty)
    }

    func testFileRoundTripWritesBackup() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")
        try JSONSerialization.data(withJSONObject: existing).write(to: url)

        let installer = HookInstaller(settingsURL: url, bridgePath: "/tmp/pip-bridge")
        XCTAssertFalse(installer.isInstalled())
        try installer.install()
        XCTAssertTrue(installer.isInstalled())
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("pip-backup").path))
        try installer.uninstall()
        XCTAssertFalse(installer.isInstalled())
    }

    func testRefusesToTouchInvalidJSON() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")
        try Data("{ not json".utf8).write(to: url)

        XCTAssertThrowsError(try HookInstaller(settingsURL: url, bridgePath: "/tmp/pip-bridge").install())
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "{ not json")
    }
}
