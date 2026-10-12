import XCTest
@testable import Pip

@MainActor
final class TerminalJumperTests: XCTestCase {
    func testHostAppsLabelFromTermProgram() {
        XCTAssertEqual(HostApps.label(env: ["TERM_PROGRAM": "ghostty"], pid: nil), "Ghostty")
        XCTAssertEqual(HostApps.label(env: ["TERM_PROGRAM": "Apple_Terminal"], pid: nil), "Terminal")
        XCTAssertEqual(HostApps.label(env: ["TERM_PROGRAM": "iTerm.app"], pid: nil), "iTerm2")
        XCTAssertEqual(HostApps.label(env: ["TERM_PROGRAM": "WezTerm"], pid: nil), "WezTerm")
    }

    func testHostAppsLabelFromKittyEnv() {
        XCTAssertEqual(HostApps.label(env: ["KITTY_WINDOW_ID": "3"], pid: nil), "Kitty")
        XCTAssertEqual(HostApps.label(env: ["TERM": "xterm-kitty"], pid: nil), "Kitty")
    }

    func testHostAppsLabelFromAlacrittyEnv() {
        XCTAssertEqual(HostApps.label(env: ["ALACRITTY_WINDOW_ID": "100"], pid: nil), "Alacritty")
        XCTAssertEqual(HostApps.label(env: ["TERM": "alacritty"], pid: nil), "Alacritty")
    }

    func testHostAppsLabelFromBundleID() {
        XCTAssertEqual(HostApps.label(env: ["__CFBundleIdentifier": "com.mitchellh.ghostty"], pid: nil), "Ghostty")
        XCTAssertEqual(HostApps.label(env: ["__CFBundleIdentifier": "org.alacritty"], pid: nil), "Alacritty")
        XCTAssertEqual(HostApps.label(env: ["__CFBundleIdentifier": "net.kovidgoyal.kitty"], pid: nil), "Kitty")
        XCTAssertEqual(HostApps.label(env: ["__CFBundleIdentifier": "com.google.antigravity"], pid: nil), "Antigravity")
    }

    func testTerminateProcessInvalidPID() {
        // PID 9999999 should safely return false without crashing
        let result = TerminalJumper.terminateProcess(pid: 9999999)
        XCTAssertFalse(result)
    }
}
