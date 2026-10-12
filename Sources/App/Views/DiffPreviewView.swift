import SwiftUI
import AppKit

/// Inline visual diff and code preview for file edit and write tool requests.
struct DiffPreviewView: View {
    let diff: CodeDiff

    @State private var isExpanded = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerBar
            diffContent
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.04, green: 0.06, blue: 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "pencil.and.ruler.fill")
                .font(.system(size: 10))
                .foregroundStyle(Palette.cyan)

            Text(fileName)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            // Copy button
            Button {
                copyContent()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9.5))
                    Text(copied ? "Copied" : "Copy")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(copied ? Palette.green : Palette.quiet)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)

            // Expand / Collapse toggle
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9.5))
                    Text(isExpanded ? "Compact" : "Expand")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(Palette.cyan)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Palette.badgeBg))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Diff Content

    @ViewBuilder
    private var diffContent: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            VStack(alignment: .leading, spacing: 1) {
                if let diffText = diff.diffText, !diffText.isEmpty {
                    renderUnifiedDiff(diffText)
                } else if diff.oldText != nil || diff.newText != nil {
                    renderOldNewComparison(old: diff.oldText, new: diff.newText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        }
        .frame(maxHeight: isExpanded ? 280 : 130)
    }

    @ViewBuilder
    private func renderUnifiedDiff(_ text: String) -> some View {
        let lines = text.components(separatedBy: .newlines)
        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
            let isAdd = line.hasPrefix("+") && !line.hasPrefix("+++")
            let isDel = line.hasPrefix("-") && !line.hasPrefix("---")
            let isHunk = line.hasPrefix("@@")

            Text(line.isEmpty ? " " : line)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(isAdd ? Palette.green : isDel ? Palette.red : isHunk ? Palette.cyan : .white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    isAdd ? Palette.green.opacity(0.12) :
                    isDel ? Palette.red.opacity(0.12) :
                    isHunk ? Palette.cyan.opacity(0.08) : Color.clear
                )
        }
    }

    @ViewBuilder
    private func renderOldNewComparison(old: String?, new: String?) -> some View {
        if let old, !old.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                Text("// Removed:")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Palette.red.opacity(0.8))
                    .padding(.horizontal, 4)
                    .padding(.top, 2)

                ForEach(Array(old.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                    Text("- \(line.isEmpty ? " " : line)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Palette.red.opacity(0.12))
                }
            }
        }

        if let new, !new.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                Text(old == nil ? "// New Content:" : "// Added:")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Palette.green.opacity(0.8))
                    .padding(.horizontal, 4)
                    .padding(.top, 3)

                ForEach(Array(new.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                    Text("+ \(line.isEmpty ? " " : line)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Palette.green.opacity(0.12))
                }
            }
        }
    }

    private var fileName: String {
        let path = diff.filePath
        guard !path.isEmpty else { return "Code changes" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func copyContent() {
        let textToCopy = diff.diffText ?? diff.newText ?? diff.oldText ?? ""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToCopy, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }
}
