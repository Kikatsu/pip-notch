import SwiftUI

/// The request at the front of the queue: a tool to allow, a plan to review, or a question.
struct ApprovalCard: View {
    let approval: PendingApproval
    let position: Int
    let total: Int
    let actions: NotchActions
    @State private var feedback = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Circle().fill(Palette.amber).frame(width: 7, height: 7)
                AgentBadge(agent: approval.agent)
                Text("\(approval.agentName ?? approval.agent.displayName) · \(approval.projectName)")
                    .lineLimit(1)
                Spacer(minLength: 8)
                if total > 1 { Text("\(position) of \(total)") }
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Palette.quiet)

            Text(approval.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            switch approval.kind {
            case .tool: toolBody
            case .plan(let markdown): planBody(markdown)
            case .question(let questions): questionBody(questions)
            }
        }
        .id(approval.id)
    }

    // MARK: Tool call

    @ViewBuilder
    private var toolBody: some View {
        if !approval.detail.isEmpty {
            Text(approval.detail)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(4)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.faint))
        }
        HStack(spacing: 8) {
            PillButton(title: "Deny", shortcut: "⌃⌥⌫", prominent: false) { actions.resolve(approval.id, .deny) }
            PillButton(title: "Allow", shortcut: "⌃⌥↩", prominent: true) { actions.resolve(approval.id, .allow) }
        }
        .padding(.top, 2)
        footer
    }

    // MARK: Plan review

    @ViewBuilder
    private func planBody(_ markdown: String) -> some View {
        ScrollView {
            Text(Self.render(markdown))
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.92))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(11)
        }
        .frame(maxHeight: 150)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.faint))

        TextField("What should change? (optional)", text: $feedback, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .foregroundStyle(.white)
            .lineLimit(1...3)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.15)))
            .onSubmit(keepPlanning)

        HStack(spacing: 8) {
            PillButton(title: "Keep planning", shortcut: "⌃⌥⌫", prominent: false, action: keepPlanning)
            PillButton(title: "Approve plan", shortcut: "⌃⌥↩", prominent: true) { actions.resolve(approval.id, .allow) }
        }
        footer
    }

    private func keepPlanning() {
        let note = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        actions.resolve(approval.id, .deny(note.isEmpty
            ? "The user wants to keep planning. Ask what they'd like to change."
            : "The user wants changes to the plan: \(note)"))
    }

    /// Markdown with line breaks kept; headings and lists stay readable as plain lines.
    static func render(_ markdown: String) -> AttributedString {
        // Inline parsing keeps line breaks; turn "## Heading" lines into bold lines so they still read as headings.
        let text = markdown.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let trimmed = line.drop { $0 == " " }
            guard trimmed.hasPrefix("#") else { return String(line) }
            let title = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? "" : "**\(title)**"
        }.joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(markdown)
    }

    // MARK: Question

    @ViewBuilder
    private func questionBody(_ questions: [PendingApproval.Question]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(questions.prefix(3).enumerated()), id: \.offset) { _, question in
                VStack(alignment: .leading, spacing: 4) {
                    Text(question.text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                    ForEach(question.options, id: \.self) { option in
                        Label(option, systemImage: "circle")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.quiet)
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.faint))

        PillButton(title: "Answer in terminal", shortcut: "⌃⌥↩", prominent: true) { actions.answerInTerminal(approval) }
    }

    // MARK: Shared

    private var footer: some View {
        HStack {
            Button("Answer in terminal") { actions.answerInTerminal(approval) }
            Spacer()
            Button("Later") { actions.dismissApprovals() }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Palette.quiet)
    }
}

struct PillButton: View {
    let title: String
    var shortcut: String?
    let prominent: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 14, weight: .semibold))
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 10.5, weight: .medium))
                        .opacity(0.5)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .foregroundStyle(prominent ? Color.black : Color.white)
            .background(
                Capsule().fill(prominent ? Color.white.opacity(hovering ? 0.85 : 1) : Color.white.opacity(hovering ? 0.2 : 0.13))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
