import SwiftUI
import PipiBotKit

#if os(macOS)
import AppKit
#endif

public struct PipiMarkdownView: View {
    public let content: String
    public let strings: PipiStrings
    public var accent: Color = PipiTokens.soulPrimary
    public var isStreaming: Bool = false

    @Environment(\.pipiTextScale) private var textScale

    public init(
        content: String,
        strings: PipiStrings,
        accent: Color = PipiTokens.soulPrimary,
        isStreaming: Bool = false
    ) {
        self.content = content
        self.strings = strings
        self.accent = accent
        self.isStreaming = isStreaming
    }

    public typealias Block = PipiMarkdownBlock

    public static func parseBlocksCached(_ raw: String) -> [Block] {
        PipiMarkdownParser.parseBlocksCached(raw)
    }

    public static func parseBlocks(_ raw: String) -> [Block] {
        PipiMarkdownParser.parseBlocks(raw)
    }

    public var body: some View {
        let _ = textScale
        let blocks = isStreaming ? Self.parseBlocks(content) : Self.parseBlocksCached(content)
        VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            ForEach(blocks) { block in
                switch block {
                case .thinking(_, let text, let isOpen):
                    PipiThinkingDisclosureBlock(
                        text: text,
                        isLiveStreaming: isStreaming && isOpen,
                        strings: strings,
                        accent: accent
                    )
                    .modifier(PipiBlockEntranceModifier(animate: isStreaming))

                case .prose(_, let text):
                    proseBlockView(text)

                case .diff(_, let code):
                    PipiDiffBlockView(code: code, strings: strings)
                        .padding(.vertical, 4)
                        .modifier(PipiBlockEntranceModifier(animate: isStreaming))

                case .terminal(_, let language, let code):
                    PipiTerminalBlockView(language: language, code: code, strings: strings, accent: accent)
                        .padding(.vertical, 4)
                        .modifier(PipiBlockEntranceModifier(animate: isStreaming))

                case .code(_, let language, let code):
                    PipiCodeBlockView(language: language, code: code, strings: strings)
                        .padding(.vertical, 4)
                        .modifier(PipiBlockEntranceModifier(animate: isStreaming))

                case .table(_, let headers, let rows):
                    PipiTableBlockView(headers: headers, rows: rows)
                        .padding(.vertical, 4)
                        .modifier(PipiBlockEntranceModifier(animate: isStreaming))
                }
            }

            if isStreaming {
                PipiStreamingCursor(accent: accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Rich Prose Renderer

    @ViewBuilder
    private func proseBlockView(_ raw: String) -> some View {
        let lines = raw.components(separatedBy: .newlines)
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    Spacer().frame(height: 5)
                } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                    Rectangle()
                        .fill(PipiTokens.borderSubtle)
                        .frame(height: 1)
                        .padding(.vertical, 8)
                } else if trimmed.hasPrefix("### ") {
                    inlineMarkdownText(String(trimmed.dropFirst(4)))
                        .font(PipiTokens.fontHeadline)
                        .tracking(PipiTokens.trackingHeadline)
                        .foregroundStyle(PipiTokens.textPrimary)
                        .padding(.top, 14)
                        .padding(.bottom, 2)
                } else if trimmed.hasPrefix("## ") {
                    inlineMarkdownText(String(trimmed.dropFirst(3)))
                        .font(PipiTokens.fontTitle)
                        .tracking(PipiTokens.trackingTitle)
                        .foregroundStyle(PipiTokens.textPrimary)
                        .padding(.top, 16)
                        .padding(.bottom, 2)
                } else if trimmed.hasPrefix("# ") {
                    inlineMarkdownText(String(trimmed.dropFirst(2)))
                        .font(PipiTokens.fontHero)
                        .tracking(PipiTokens.trackingHero)
                        .foregroundStyle(PipiTokens.textPrimary)
                        .padding(.top, 16)
                        .padding(.bottom, 4)
                } else if trimmed.hasPrefix("> ") {
                    HStack(alignment: .top, spacing: PipiTokens.spacing12) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(accent.opacity(0.65))
                            .frame(width: 3)
                        inlineMarkdownText(String(trimmed.dropFirst(2)))
                            .font(PipiTokens.fontBody)
                            .foregroundStyle(PipiTokens.textSecondary)
                            .lineSpacing(5.5)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PipiTokens.bgSurface.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(PipiTokens.stateSuccess)
                            .frame(width: 18, height: 22, alignment: .center)
                        inlineMarkdownText(String(trimmed.dropFirst(6)))
                            .font(PipiTokens.fontBody)
                            .foregroundStyle(PipiTokens.textSecondary)
                            .strikethrough(true, color: PipiTokens.textMuted)
                            .lineSpacing(5.5)
                    }
                    .padding(.leading, 4)
                } else if trimmed.hasPrefix("- [ ] ") {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "circle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(PipiTokens.textMuted)
                            .frame(width: 18, height: 22, alignment: .center)
                        inlineMarkdownText(String(trimmed.dropFirst(6)))
                            .font(PipiTokens.fontBody)
                            .foregroundStyle(PipiTokens.textPrimary)
                            .lineSpacing(5.5)
                    }
                    .padding(.leading, 4)
                } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(accent.opacity(0.75))
                            .frame(width: 5.5, height: 5.5)
                            .frame(width: 16, height: 22, alignment: .center)
                        inlineMarkdownText(String(trimmed.dropFirst(2)))
                            .font(PipiTokens.fontBody)
                            .foregroundStyle(PipiTokens.textPrimary)
                            .lineSpacing(5.5)
                    }
                    .padding(.leading, 4)
                } else if let ordered = parseOrderedListLine(trimmed) {
                    HStack(alignment: .top, spacing: 10) {
                        Text(ordered.prefix)
                            .font(PipiTokens.fontMono.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(PipiTokens.textMuted)
                            .frame(minWidth: 20, minHeight: 22, alignment: .trailing)
                        inlineMarkdownText(ordered.body)
                            .font(PipiTokens.fontBody)
                            .foregroundStyle(PipiTokens.textPrimary)
                            .lineSpacing(5.5)
                    }
                    .padding(.leading, 2)
                } else {
                    inlineMarkdownText(line)
                        .font(PipiTokens.fontBody)
                        .foregroundStyle(PipiTokens.textPrimary)
                        .lineSpacing(5.5)
                }
            }
        }
        .textSelection(.enabled)
    }

    private func parseOrderedListLine(_ line: String) -> (prefix: String, body: String)? {
        guard let dotIdx = line.firstIndex(of: ".") else { return nil }
        let numPart = line[..<dotIdx]
        guard !numPart.isEmpty, numPart.count <= 3, numPart.allSatisfy(\.isNumber) else { return nil }
        let afterDot = line.index(after: dotIdx)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        let bodyStart = line.index(after: afterDot)
        return ("\(numPart).", String(line[bodyStart...]))
    }

    private func inlineMarkdownText(_ raw: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(raw)
    }
}

// MARK: - Subtle Per-Block Entrance Motion (Active Turns Only, Respects Reduce Motion)

private struct PipiBlockEntranceModifier: ViewModifier {
    let animate: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(!animate || appeared ? 1.0 : 0.0)
            .offset(y: (!animate || appeared || reduceMotion) ? 0 : 6)
            .onAppear {
                guard animate && !appeared else { return }
                withAnimation(PipiMotion.adaptive(PipiMotion.smooth, reduceMotion: reduceMotion)) {
                    appeared = true
                }
            }
    }
}

// MARK: - 1. Collapsible Thinking / Reasoning Disclosure Block (Codex / Claude / Antigravity Style)

private struct PipiThinkingDisclosureBlock: View {
    let text: String
    let isLiveStreaming: Bool
    let strings: PipiStrings
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded: Bool = false

    var body: some View {
        let expanded = isLiveStreaming || isExpanded

        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(PipiMotion.adaptive(PipiMotion.drawer, reduceMotion: reduceMotion)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: PipiTokens.spacing8) {
                    if isLiveStreaming {
                        PipiDotIndicator(vitality: .busy, color: accent, size: 6)
                    } else {
                        Image(systemName: "brain")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(PipiTokens.textMuted)
                    }

                    Text(isLiveStreaming ? strings.thinkingInProgress : strings.thoughtProcess)
                        .font(PipiTokens.fontCaption.weight(.medium))
                        .foregroundStyle(isLiveStreaming ? accent : PipiTokens.textSecondary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PipiTokens.textMuted)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(.horizontal, PipiTokens.spacing12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(PipiPressButtonStyle(pressedScale: 0.99))

            if expanded && !text.isEmpty {
                Rectangle()
                    .fill(PipiTokens.borderSubtle)
                    .frame(height: 1)

                Text(text)
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.textSecondary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .padding(PipiTokens.spacing12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .background(PipiTokens.bgSurface.opacity(0.65))
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .stroke(isLiveStreaming ? accent.opacity(0.32) : PipiTokens.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
    }
}

// MARK: - 2. Diff / Patch Highlight Block (+N / -M Badges + Semantic Row Tinting)

private struct PipiDiffBlockView: View {
    let code: String
    let strings: PipiStrings

    @State private var copied = false

    private var lines: [String] { code.components(separatedBy: .newlines) }
    private var additionsCount: Int { lines.filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count }
    private var deletionsCount: Int { lines.filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: PipiTokens.spacing8) {
                Image(systemName: "plus.forwardslash.minus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PipiTokens.textMuted)

                Text(strings.diffChanges)
                    .font(PipiTokens.fontMonoSmall.weight(.semibold))
                    .foregroundStyle(PipiTokens.textSecondary)

                if additionsCount > 0 {
                    Text("+\(additionsCount)")
                        .font(PipiTokens.fontMonoSmall.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(PipiTokens.stateSuccess)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(PipiTokens.stateSuccessBg)
                        .clipShape(Capsule())
                }

                if deletionsCount > 0 {
                    Text("-\(deletionsCount)")
                        .font(PipiTokens.fontMonoSmall.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(PipiTokens.stateError)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(PipiTokens.stateErrorBg)
                        .clipShape(Capsule())
                }

                Spacer()

                PipiBlockCopyButton(copied: $copied, text: code, strings: strings)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(PipiTokens.bgSurface)

            Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        let isAdd = line.hasPrefix("+") && !line.hasPrefix("+++")
                        let isDel = line.hasPrefix("-") && !line.hasPrefix("---")
                        let isHunk = line.hasPrefix("@@") || line.hasPrefix("diff --git")

                        Text(line.isEmpty ? " " : line)
                            .font(PipiTokens.fontMono)
                            .foregroundStyle(
                                isAdd ? PipiTokens.stateSuccess
                                : (isDel ? PipiTokens.stateError
                                   : (isHunk ? PipiTokens.stateInfo : PipiTokens.textPrimary))
                            )
                            .padding(.horizontal, PipiTokens.spacing16)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                isAdd ? PipiTokens.stateSuccessBg
                                : (isDel ? PipiTokens.stateErrorBg
                                   : (isHunk ? PipiTokens.stateInfoBg : Color.clear))
                            )
                    }
                }
                .padding(.vertical, 14)
                .textSelection(.enabled)
            }
            .scrollIndicators(.hidden)
        }
        .background(PipiTokens.bgInset)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .stroke(PipiTokens.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
    }
}

// MARK: - 3. Terminal / Shell Command Block

private struct PipiTerminalBlockView: View {
    let language: String
    let code: String
    let strings: PipiStrings
    let accent: Color

    @State private var copied = false

    var body: some View {
        let lines = code.components(separatedBy: .newlines)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: PipiTokens.spacing8) {
                Image(systemName: "terminal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)

                Text(language.isEmpty ? strings.terminalOutput : language)
                    .font(PipiTokens.fontMonoSmall.weight(.semibold))
                    .foregroundStyle(PipiTokens.textSecondary)

                Spacer()

                PipiBlockCopyButton(copied: $copied, text: code, strings: strings)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(PipiTokens.bgSurface)

            Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if trimmed.hasPrefix("$ ") || trimmed.hasPrefix("# ") {
                            HStack(spacing: 6) {
                                Text(String(trimmed.prefix(1)))
                                    .foregroundStyle(accent)
                                Text(String(trimmed.dropFirst(2)))
                                    .foregroundStyle(PipiTokens.textPrimary)
                            }
                            .font(PipiTokens.fontMono)
                        } else {
                            Text(line.isEmpty ? " " : line)
                                .font(PipiTokens.fontMono)
                                .foregroundStyle(trimmed.hasPrefix("#") ? PipiTokens.textMuted : PipiTokens.textPrimary)
                        }
                    }
                }
                .padding(PipiTokens.spacing16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .scrollIndicators(.hidden)
        }
        .background(PipiTokens.bgInset)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .stroke(PipiTokens.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
    }
}

// MARK: - 4. Standard Code Block (Line Count + Smooth Collapse for Long Snippets)

private struct PipiCodeBlockView: View {
    let language: String
    let code: String
    let strings: PipiStrings

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false
    @State private var collapsed = false

    private var lineCount: Int {
        code.components(separatedBy: .newlines).count
    }

    var body: some View {
        let isLong = lineCount > 24

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: PipiTokens.spacing8) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(PipiTokens.textMuted)

                Text(language.isEmpty ? "code" : language.lowercased())
                    .font(PipiTokens.fontMonoSmall.weight(.semibold))
                    .foregroundStyle(PipiTokens.textSecondary)

                Text("\(lineCount)L")
                    .font(PipiTokens.fontMonoSmall)
                    .monospacedDigit()
                    .foregroundStyle(PipiTokens.textMuted)

                Spacer()

                if isLong {
                    Button {
                        withAnimation(PipiMotion.adaptive(PipiMotion.smooth, reduceMotion: reduceMotion)) {
                            collapsed.toggle()
                        }
                    } label: {
                        Text(collapsed ? strings.expandCode : strings.collapseCode)
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.textMuted)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(PipiTokens.bgSurfaceHover.opacity(0.7))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.94))
                }

                PipiBlockCopyButton(copied: $copied, text: code, strings: strings)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(PipiTokens.bgSurface)

            if !collapsed {
                Rectangle()
                    .fill(PipiTokens.borderSubtle)
                    .frame(height: 1)

                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(PipiTokens.fontMono)
                        .foregroundStyle(PipiTokens.textPrimary)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .padding(PipiTokens.spacing16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(PipiTokens.bgInset)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .stroke(PipiTokens.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
    }
}

// MARK: - 5. Structured Markdown Table Block

private struct PipiTableBlockView: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        Text(header)
                            .font(PipiTokens.fontCaption.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                            .padding(.horizontal, PipiTokens.spacing12)
                            .padding(.vertical, PipiTokens.spacing8)
                            .frame(minWidth: 110, maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(PipiTokens.bgSurface)

                ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                    Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)
                    HStack(spacing: 0) {
                        ForEach(0..<headers.count, id: \.self) { colIdx in
                            let cell = colIdx < row.count ? row[colIdx] : ""
                            Text(cell)
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textSecondary)
                                .padding(.horizontal, PipiTokens.spacing12)
                                .padding(.vertical, PipiTokens.spacing8)
                                .frame(minWidth: 110, maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .background(rowIdx.isMultiple(of: 2) ? Color.clear : PipiTokens.bgSurface.opacity(0.35))
                }
            }
            .textSelection(.enabled)
        }
        .scrollIndicators(.hidden)
        .background(PipiTokens.bgInset.opacity(0.55))
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .stroke(PipiTokens.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
    }
}

// MARK: - Shared Block Copy Button (Unified PipiMotion.tactile / snappy)

private struct PipiBlockCopyButton: View {
    @Binding var copied: Bool
    let text: String
    let strings: PipiStrings

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            #endif
            withAnimation(PipiMotion.adaptive(PipiMotion.tactile, reduceMotion: reduceMotion)) {
                copied = true
            }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                    copied = false
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(copied ? strings.copied : strings.copyCode)
                    .font(PipiTokens.fontMicro)
            }
            .foregroundStyle(copied ? PipiTokens.stateSuccess : PipiTokens.textSecondary)
            .padding(.horizontal, PipiTokens.spacing8)
            .padding(.vertical, 3)
            .background(PipiTokens.bgSurfaceHover)
            .clipShape(Capsule())
        }
        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.94))
    }
}

// MARK: - Streaming Cursor

private struct PipiStreamingCursor: View {
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Capsule()
            .fill(accent)
            .frame(width: 6, height: 14)
            .opacity(reduceMotion ? 0.85 : (pulse ? 0.22 : 0.95))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.50).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
