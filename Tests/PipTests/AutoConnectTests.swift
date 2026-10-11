import XCTest
@testable import Pip

@MainActor
final class AutoConnectTests: XCTestCase {
    private var dir: URL!
    private var defaults: UserDefaults!
    private let bridge = "/Applications/Pip.app/pip-bridge"

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: "pip.tests.\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// A Codex-like agent that is "installed" when its folder exists, and a plugin agent that isn't installed.
    private func makeModel() -> (IntegrationsModel, codexConfig: URL, piFile: URL) {
        let codexDir = dir.appendingPathComponent("codex")
        try? FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        let codexConfig = codexDir.appendingPathComponent("hooks.json")
        let piFile = dir.appendingPathComponent("pi/extensions/pip.ts")
        let codexFormat = AgentIntegration.all.first { $0.agent == .codex }!.format
        let model = IntegrationsModel(integrations: [
            AgentIntegration(agent: .codex, configURL: codexConfig, format: codexFormat, detectPaths: [codexDir.path], note: nil),
            AgentIntegration(agent: .pi, configURL: piFile, format: .ownedFile(AgentPlugins.pi), detectPaths: [dir.appendingPathComponent("pi").path], note: nil),
        ], defaults: defaults)
        model.bridgePath = bridge
        return (model, codexConfig, piFile)
    }

    func testConnectsOnlyDetectedAgents() {
        let (model, _, piFile) = makeModel()
        model.connectDetected()
        XCTAssertEqual(model.connected, [.codex])
        XCTAssertEqual(model.autoConnected, [.codex])
        XCTAssertFalse(FileManager.default.fileExists(atPath: piFile.path), "Pi isn't installed, so nothing is written")
    }

    func testPicksUpAgentsInstalledLater() throws {
        let (model, _, _) = makeModel()
        model.connectDetected()
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("pi"), withIntermediateDirectories: true)
        model.connectDetected()
        XCTAssertEqual(model.connected, [.codex, .pi])
    }

    func testManualDisconnectIsRespected() {
        let (model, _, _) = makeModel()
        model.connectDetected()
        model.setConnected(model.integrations[0], false)
        model.connectDetected()
        XCTAssertFalse(model.connected.contains(.codex))

        model.setConnected(model.integrations[0], true)
        XCTAssertTrue(model.connected.contains(.codex), "Connecting by hand clears the opt-out")
    }

    func testRepairsHooksAnUpdateRemoved() throws {
        let (model, codexConfig, _) = makeModel()
        model.connectDetected()
        try Data(#"{"hooks":{}}"#.utf8).write(to: codexConfig)
        model.refresh()
        XCTAssertFalse(model.connected.contains(.codex))
        model.connectDetected()
        XCTAssertTrue(model.connected.contains(.codex))
    }

    func testRepointsHooksWhenTheBridgeMoves() throws {
        let (model, codexConfig, _) = makeModel()
        model.connectDetected()
        model.bridgePath = "/Users/me/Applications/Pip.app/pip-bridge"
        model.connectDetected()
        let text = try String(contentsOf: codexConfig, encoding: .utf8)
        XCTAssertTrue(text.contains("/Users/me/Applications/Pip.app/pip-bridge"))
        XCTAssertFalse(text.contains("\"\(bridge)\""), "old hooks are replaced, not duplicated")
    }

    func testTurningAutoConnectOffStopsIt() {
        let (model, _, _) = makeModel()
        model.autoConnect = false
        model.connectDetected()
        XCTAssertTrue(model.connected.isEmpty)
    }
}
