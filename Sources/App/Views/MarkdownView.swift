import SwiftUI
import AppKit

/// Full Markdown parser and renderer for viewing AI agent plans in the notch.
struct MarkdownView: View {
    let markdown: String

    var body: some View {
        let blocks = MarkdownParser.parse(markdown)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            headingView(level: level, text: text)
        case .paragraph(let text):
            Text(Self.inline(text))
                .font(.system(size: 12.5))
                .lineSpacing(2.5)
                .foregroundStyle(.white.opacity(0.92))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .codeBlock(let language, let code):
            MarkdownCodeBlockView(language: language, code: code)
        case .taskList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(item.checked ? Palette.green : Palette.quiet)
                            .padding(.top, 2)
                        Text(Self.inline(item.text))
                            .font(.system(size: 12))
                            .foregroundStyle(item.checked ? .white.opacity(0.7) : .white.opacity(0.95))
                            .strikethrough(item.checked, color: Palette.quiet)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.vertical, 2)
        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 7) {
                        Circle()
                            .fill(Palette.cyan.opacity(0.85))
                            .frame(width: 4.5, height: 4.5)
                            .padding(.top, 6)
                        Text(Self.inline(item))
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.vertical, 2)
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 7) {
                        Text("\(item.index).")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Palette.cyan)
                            .frame(minWidth: 16, alignment: .trailing)
                            .padding(.top, 1)
                        Text(Self.inline(item.text))
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.vertical, 2)
        case .blockquote(let text):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Palette.cyan)
                    .frame(width: 3)
                Text(Self.inline(text))
                    .font(.system(size: 12))
                    .italic()
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.vertical, 3)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))
        case .table(let headers, let rows):
            MarkdownTableView(headers: headers, rows: rows)
        case .horizontalRule:
            Divider()
                .background(Color.white.opacity(0.14))
                .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func headingView(level: Int, text: String) -> some View {
        switch level {
        case 1:
            Text(Self.inline(text))
                .font(.system(size: 15.5, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 4)
        case 2:
            Text(Self.inline(text))
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Palette.cyan)
                .padding(.top, 3)
        case 3:
            Text(Self.inline(text))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .padding(.top, 2)
        default:
            Text(Self.inline(text))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.quiet)
                .padding(.top, 1)
        }
    }

    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

// MARK: - Code Block View

private struct MarkdownCodeBlockView: View {
    let language: String?
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language?.uppercased() ?? "CODE")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Palette.cyan)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9.5))
                        Text(copied ? "Copied" : "Copy")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(copied ? Palette.green : Palette.quiet)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.03))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .textSelection(.enabled)
                    .padding(9)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.04, green: 0.06, blue: 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Table View

private struct MarkdownTableView: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 8) {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                    Text(MarkdownView.inline(header))
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(Palette.cyan)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Palette.darkCard)

            Divider().background(Palette.darkCardBorder)

            // Data rows
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 8) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(MarkdownView.inline(cell))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(index.isMultiple(of: 2) ? Color.clear : Color.white.opacity(0.02))

                if index < rows.count - 1 {
                    Divider().background(Color.white.opacity(0.05))
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.04, green: 0.06, blue: 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Palette.darkCardBorder, lineWidth: 1)
        )
    }
}

// MARK: - AST & Parser

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case codeBlock(language: String?, code: String)
    case taskList(items: [(checked: Bool, text: String)])
    case unorderedList(items: [String])
    case orderedList(items: [(index: Int, text: String)])
    case blockquote(text: String)
    case table(headers: [String], rows: [[String]])
    case horizontalRule

    static func == (lhs: MarkdownBlock, rhs: MarkdownBlock) -> Bool {
        switch (lhs, rhs) {
        case let (.heading(l1, t1), .heading(l2, t2)): return l1 == l2 && t1 == t2
        case let (.paragraph(t1), .paragraph(t2)): return t1 == t2
        case let (.codeBlock(l1, c1), .codeBlock(l2, c2)): return l1 == l2 && c1 == c2
        case let (.taskList(i1), .taskList(i2)):
            guard i1.count == i2.count else { return false }
            return zip(i1, i2).allSatisfy { $0.0.checked == $0.1.checked && $0.0.text == $0.1.text }
        case let (.unorderedList(i1), .unorderedList(i2)): return i1 == i2
        case let (.orderedList(i1), .orderedList(i2)):
            guard i1.count == i2.count else { return false }
            return zip(i1, i2).allSatisfy { $0.0.index == $0.1.index && $0.0.text == $0.1.text }
        case let (.blockquote(t1), .blockquote(t2)): return t1 == t2
        case let (.table(h1, r1), .table(h2, r2)): return h1 == h2 && r1 == r2
        case (.horizontalRule, .horizontalRule): return true
        default: return false
        }
    }
}

enum MarkdownParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Fenced code block
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = String(trimmed.prefix(3))
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                let language = lang.isEmpty ? nil : lang
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    let next = lines[i]
                    if next.trimmingCharacters(in: .whitespaces).hasPrefix(marker) {
                        i += 1
                        break
                    }
                    codeLines.append(next)
                    i += 1
                }
                blocks.append(.codeBlock(language: language, code: codeLines.joined(separator: "\n")))
                continue
            }

            // Horizontal rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.horizontalRule)
                i += 1
                continue
            }

            // Heading
            if let (level, text) = parseHeading(trimmed) {
                blocks.append(.heading(level: level, text: text))
                i += 1
                continue
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count {
                    let nextTrimmed = lines[i].trimmingCharacters(in: .whitespaces)
                    if nextTrimmed.hasPrefix(">") {
                        let content = String(nextTrimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                        quoteLines.append(content)
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.blockquote(text: quoteLines.joined(separator: " ")))
                continue
            }

            // Table
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && i + 1 < lines.count {
                let nextTrimmed = lines[i + 1].trimmingCharacters(in: .whitespaces)
                if nextTrimmed.hasPrefix("|") && nextTrimmed.contains("-") {
                    let headers = parseTableRow(trimmed)
                    var rows: [[String]] = []
                    i += 2 // skip header and separator
                    while i < lines.count {
                        let rowTrimmed = lines[i].trimmingCharacters(in: .whitespaces)
                        if rowTrimmed.hasPrefix("|") && rowTrimmed.hasSuffix("|") {
                            var row = parseTableRow(rowTrimmed)
                            if row.count < headers.count {
                                row.append(contentsOf: Array(repeating: "", count: headers.count - row.count))
                            } else if row.count > headers.count {
                                row = Array(row.prefix(headers.count))
                            }
                            rows.append(row)
                            i += 1
                        } else {
                            break
                        }
                    }
                    blocks.append(.table(headers: headers, rows: rows))
                    continue
                }
            }

            // Task list (- [ ] or - [x])
            if isTaskItem(trimmed) {
                var items: [(checked: Bool, text: String)] = []
                while i < lines.count {
                    let itemTrimmed = lines[i].trimmingCharacters(in: .whitespaces)
                    if let task = parseTaskItem(itemTrimmed) {
                        items.append(task)
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.taskList(items: items))
                continue
            }

            // Ordered list (1. item)
            if let first = parseOrderedItem(trimmed) {
                var items: [(index: Int, text: String)] = [first]
                i += 1
                while i < lines.count {
                    let itemTrimmed = lines[i].trimmingCharacters(in: .whitespaces)
                    if let item = parseOrderedItem(itemTrimmed) {
                        items.append(item)
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.orderedList(items: items))
                continue
            }

            // Unordered list (- item or * item)
            if isUnorderedItem(trimmed) {
                var items: [String] = []
                while i < lines.count {
                    let itemTrimmed = lines[i].trimmingCharacters(in: .whitespaces)
                    if isUnorderedItem(itemTrimmed) {
                        let text = String(itemTrimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                        items.append(text)
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.unorderedList(items: items))
                continue
            }

            // Standard paragraph: consume non-empty contiguous lines
            var paragraphLines: [String] = []
            while i < lines.count {
                let currentTrimmed = lines[i].trimmingCharacters(in: .whitespaces)
                if currentTrimmed.isEmpty || parseHeading(currentTrimmed) != nil || currentTrimmed.hasPrefix("```") ||
                    currentTrimmed.hasPrefix(">") || isTaskItem(currentTrimmed) || isUnorderedItem(currentTrimmed) ||
                    parseOrderedItem(currentTrimmed) != nil || (currentTrimmed.hasPrefix("|") && currentTrimmed.hasSuffix("|")) {
                    break
                }
                paragraphLines.append(currentTrimmed)
                i += 1
            }
            if !paragraphLines.isEmpty {
                blocks.append(.paragraph(text: paragraphLines.joined(separator: " ")))
            } else {
                blocks.append(.paragraph(text: trimmed))
                i += 1
            }
        }

        return blocks
    }

    private static func parseHeading(_ s: String) -> (level: Int, text: String)? {
        guard s.hasPrefix("#") else { return nil }
        var level = 0
        for ch in s {
            if ch == "#" { level += 1 } else { break }
        }
        guard level > 0 && level <= 6 else { return nil }
        let remainder = s.dropFirst(level)
        guard remainder.isEmpty || remainder.first?.isWhitespace == true else { return nil }
        return (level, remainder.trimmingCharacters(in: .whitespaces))
    }

    private static func isTaskItem(_ s: String) -> Bool {
        s.hasPrefix("- [ ]") || s.hasPrefix("- [x]") || s.hasPrefix("- [X]") ||
        s.hasPrefix("* [ ]") || s.hasPrefix("* [x]") || s.hasPrefix("* [X]")
    }

    private static func parseTaskItem(_ s: String) -> (checked: Bool, text: String)? {
        guard isTaskItem(s) else { return nil }
        let checked = s.contains("[x]") || s.contains("[X]")
        let text = String(s.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        return (checked, text)
    }

    private static func isUnorderedItem(_ s: String) -> Bool {
        (s.hasPrefix("- ") || s.hasPrefix("* ") || s.hasPrefix("+ ")) && !isTaskItem(s)
    }

    private static func parseOrderedItem(_ s: String) -> (index: Int, text: String)? {
        guard let dotIndex = s.firstIndex(of: ".") ?? s.firstIndex(of: ")") else { return nil }
        let numStr = String(s[..<dotIndex]).trimmingCharacters(in: .whitespaces)
        guard let num = Int(numStr), num > 0, num < 1000 else { return nil }
        let remainder = String(s[s.index(after: dotIndex)...]).trimmingCharacters(in: .whitespaces)
        return (num, remainder)
    }

    private static func parseTableRow(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|") && trimmed.hasSuffix("|") else { return [] }
        let content = trimmed.dropFirst().dropLast()
        return content.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
