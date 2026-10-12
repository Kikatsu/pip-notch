import XCTest
@testable import Pip

@MainActor
final class DiffPreviewTests: XCTestCase {
    func testExtractDiffFromUnifiedPatch() {
        let input: [String: Any] = [
            "file_path": "Sources/App/PipApp.swift",
            "patch": "--- a/Sources/App/PipApp.swift\n+++ b/Sources/App/PipApp.swift\n@@ -1,3 +1,3 @@\n-old\n+new"
        ]
        let diff = ToolSummary.extractDiff(tool: "Edit", input: input)
        XCTAssertNotNil(diff)
        XCTAssertEqual(diff?.filePath, "Sources/App/PipApp.swift")
        XCTAssertEqual(diff?.diffText, "--- a/Sources/App/PipApp.swift\n+++ b/Sources/App/PipApp.swift\n@@ -1,3 +1,3 @@\n-old\n+new")
        XCTAssertNil(diff?.oldText)
        XCTAssertNil(diff?.newText)
    }

    func testExtractDiffFromOldAndNewString() {
        let input: [String: Any] = [
            "file_path": "Theme.tsx",
            "old_string": "const theme = 'light';",
            "new_string": "const theme = 'dark';"
        ]
        let diff = ToolSummary.extractDiff(tool: "Edit", input: input)
        XCTAssertNotNil(diff)
        XCTAssertEqual(diff?.filePath, "Theme.tsx")
        XCTAssertEqual(diff?.oldText, "const theme = 'light';")
        XCTAssertEqual(diff?.newText, "const theme = 'dark';")
        XCTAssertNil(diff?.diffText)
    }

    func testExtractDiffFromTargetAndReplacementContent() {
        let input: [String: Any] = [
            "TargetFile": "/path/to/script.py",
            "TargetContent": "def old_fn(): pass",
            "ReplacementContent": "def new_fn(): return 42"
        ]
        let diff = ToolSummary.extractDiff(tool: "replace_file_content", input: input)
        XCTAssertNotNil(diff)
        XCTAssertEqual(diff?.filePath, "/path/to/script.py")
        XCTAssertEqual(diff?.oldText, "def old_fn(): pass")
        XCTAssertEqual(diff?.newText, "def new_fn(): return 42")
    }

    func testExtractDiffFromWriteContent() {
        let input: [String: Any] = [
            "file_path": "README.md",
            "content": "# New Readme Content"
        ]
        let diff = ToolSummary.extractDiff(tool: "Write", input: input)
        XCTAssertNotNil(diff)
        XCTAssertEqual(diff?.filePath, "README.md")
        XCTAssertNil(diff?.oldText)
        XCTAssertEqual(diff?.newText, "# New Readme Content")
    }

    func testNonEditToolReturnsNilDiff() {
        let input: [String: Any] = ["command": "npm test"]
        let diff = ToolSummary.extractDiff(tool: "Bash", input: input)
        XCTAssertNil(diff)
    }
}
