import SwiftUI
import AppKit

/// The request at the front of the queue: a tool to allow, a plan to review, or a question.
struct ApprovalCard: View {
    let approval: PendingApproval
    let position: Int
    let total: Int
    let actions: NotchActions
    var onPrevious: (() -> Void)? = nil
    var onNext: (() -> Void)? = nil

    @State private var feedback = ""
    @State private var customAnswer = ""
    @State private var isExpandedPreview = false
    @State private var copiedPlan = false
    @State private var isCommandExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            headerRow

            switch approval.kind {
            case .tool:
                Text(approval.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                toolBody
            case .plan(let markdown):
                Text(approval.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                planBody(markdown)
            case .question(let questions):
                let questionTitle = questions.first?.text ?? approval.title
                Text(questionTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                questionBody(questions)
            }
        }
        .id(approval.id)
    }

    // MARK: - Header

    @ViewBuilder
    private var headerRow: some View {
        if case .question = approval.kind {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.cyan)
                Text("\(approval.agentName ?? approval.agent.displayName) asks")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.cyan)
                Spacer(minLength: 8)
                Text(approval.projectName)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.quiet)
                    .lineLimit(1)
                if total > 1 {
                    carouselIndicator
                }
            }
        } else {
            HStack(spacing: 7) {
                Circle().fill(Palette.amber).frame(width: 7, height: 7)
                AgentBadge(agent: approval.agent)
                Text("\(approval.agentName ?? approval.agent.displayName) · \(approval.projectName)")
                    .lineLimit(1)
                Spacer(minLength: 8)
                if total > 1 {
                    carouselIndicator
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Palette.quiet)
        }
    }

    @ViewBuilder
    private var carouselIndicator: some View {
        HStack(spacing: 4) {
            if let onPrevious {
                Button(action: onPrevious) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.quiet)
                        .padding(2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Previous approval")
            }
            Text("\(position) of \(total)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.quiet)
            if let onNext {
                Button(action: onNext) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.quiet)
                        .padding(2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Next approval")
            }
        }
    }

    // MARK: - Tool call

    @ViewBuilder
    private var toolBody: some View {
        if let risk = approval.risk {
            if risk.level == .dangerous {
                HStack(spacing: 6) {
                    Text("⚠️ High Risk: \(risk.reason)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Palette.red)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.red.opacity(0.15))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Palette.red, lineWidth: 1.5)
                )
            } else if risk.level == .caution {
                HStack(spacing: 6) {
                    Text("⚡ Caution: \(risk.reason)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Palette.amber)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.amber.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Palette.amber, lineWidth: 1)
                )
            }
        }

        if let diff = approval.diff {
            DiffPreviewView(diff: diff)
        } else if !approval.detail.isEmpty {
            let lines = approval.detail.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count > 3 {
                Text(lines.prefix(3).joined(separator: "\n"))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.faint))

                DisclosureGroup("Inspect Full Command", isExpanded: $isCommandExpanded) {
                    ScrollView {
                        Text(approval.detail)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.92))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 180)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.4)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .padding(.top, 4)
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.cyan)
            } else {
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
        }
        HStack(spacing: 8) {
            PillButton(title: "Deny", shortcut: "⌃⌥⌫", prominent: false) { actions.resolve(approval.id, .deny) }
            PillButton(title: "Allow", shortcut: "⌃⌥↩", prominent: true) { actions.resolve(approval.id, .allow) }
        }
        .padding(.top, 2)
        footer
    }

    // MARK: - Plan review

    @ViewBuilder
    private func planBody(_ markdown: String) -> some View {
        VStack(spacing: 8) {
            // Plan controls bar
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.cyan)
                    Text("Markdown Plan Preview")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.quiet)
                }
                Spacer()

                // Copy plan button
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                    copiedPlan = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedPlan = false }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: copiedPlan ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(copiedPlan ? "Copied" : "Copy")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(copiedPlan ? Palette.green : Palette.quiet)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)

                // Expand / Collapse preview toggle
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isExpandedPreview.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isExpandedPreview ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10))
                        Text(isExpandedPreview ? "Compact" : "Expand")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(Palette.cyan)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Palette.badgeBg))
                }
                .buttonStyle(.plain)
            }

            // Full Markdown Scroll View
            ScrollView {
                MarkdownView(markdown: markdown)
                    .padding(11)
            }
            .frame(maxHeight: isExpandedPreview ? 330 : 160)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(red: 0.04, green: 0.06, blue: 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )

            // Quick feedback suggestion chips
            quickFeedbackChips

            // Feedback input field
            HStack(spacing: 6) {
                TextField("What should change? (type to revise without leaving notch)", text: $feedback, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white)
                    .lineLimit(1...3)
                    .onSubmit(keepPlanning)

                if !feedback.isEmpty {
                    Button {
                        feedback = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.quiet)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(feedback.isEmpty ? Color.white.opacity(0.15) : Palette.cyan.opacity(0.6), lineWidth: 1)
            )

            // Action buttons
            HStack(spacing: 8) {
                if !feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    PillButton(title: "Send Feedback", shortcut: "⌘↩", prominent: true, action: keepPlanning)
                    PillButton(title: "Approve plan", shortcut: "⌃⌥↩", prominent: false) { actions.resolve(approval.id, .allow) }
                } else {
                    PillButton(title: "Keep planning", shortcut: "⌃⌥⌫", prominent: false, action: keepPlanning)
                    PillButton(title: "Approve plan", shortcut: "⌃⌥↩", prominent: true) { actions.resolve(approval.id, .allow) }
                }
            }
        }
        footer
    }

    private var quickFeedbackChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                suggestionChip("+ Add tests")
                suggestionChip("⚡ Simplify approach")
                suggestionChip("🔒 Security & edge cases")
                suggestionChip("📝 Add docs")
            }
            .padding(.vertical, 1)
        }
    }

    private func suggestionChip(_ tag: String) -> some View {
        Button {
            if feedback.isEmpty {
                feedback = tag
            } else if !feedback.contains(tag) {
                feedback = "\(feedback); \(tag)"
            }
        } label: {
            Text(tag)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.cyan)
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Palette.badgeBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Palette.darkCardBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
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

    // MARK: - Question

    @ViewBuilder
    private func questionBody(_ questions: [PendingApproval.Question]) -> some View {
        let first = questions.first
        let options = first?.options ?? []

        VStack(alignment: .leading, spacing: 8) {
            // Options stack matching notch style
            if !options.isEmpty {
                VStack(spacing: 7) {
                    ForEach(Array(options.prefix(5).enumerated()), id: \.offset) { index, option in
                        QuestionOptionButton(
                            index: index,
                            title: option,
                            description: first?.descriptions[option]
                        ) {
                            chooseOption(option)
                        }
                    }
                }
            }

            // Custom answer text input
            HStack(spacing: 6) {
                TextField("Or type custom answer without leaving notch...", text: $customAnswer)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .onSubmit(submitCustomAnswer)

                if !customAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: submitCustomAnswer) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Palette.cyan)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
        }
        .padding(.top, 2)

        footer
    }

    private func chooseOption(_ option: String) {
        actions.resolve(approval.id, .deny("User selected: \(option)"))
    }

    private func submitCustomAnswer() {
        let trimmed = customAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        actions.resolve(approval.id, .deny("User answered: \(trimmed)"))
    }

    // MARK: - Shared Footer

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

// MARK: - Question Option Button

struct QuestionOptionButton: View {
    let index: Int
    let title: String
    var description: String? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Shortcut badge: [⌘1], [⌘2], [⌘3]
                Text("⌘\(index + 1)")
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Palette.cyan)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Palette.badgeBg)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(hovering ? 1.0 : 0.92))
                        .lineLimit(2)
                    if let description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.quiet)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovering ? Color(red: 0.08, green: 0.16, blue: 0.20) : Palette.darkCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(hovering ? Palette.cyan.opacity(0.7) : Palette.darkCardBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
    }
}

// MARK: - Pill Button

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
