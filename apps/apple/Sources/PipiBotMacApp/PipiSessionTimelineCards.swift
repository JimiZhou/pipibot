import SwiftUI
import PipiBotKit

// MARK: - Isolated 5Hz/10Hz Elapsed Timer Leaf (Prevents Parent View Re-renders)

public struct PipiElapsedTimerLabel: View {
    public let startedAt: Date
    public var color: Color = PipiTokens.textMuted

    @Environment(\.pipiTextScale) private var textScale

    public init(startedAt: Date, color: Color = PipiTokens.textMuted) {
        self.startedAt = startedAt
        self.color = color
    }

    public var body: some View {
        let _ = textScale
        TimelineView(.periodic(from: startedAt, by: 0.2)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startedAt))
            Text(String(format: "%.1fs", elapsed))
                .font(PipiTokens.fontMonoSmall)
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }
}

// MARK: - Plan Checklist Card (Expanded by Default per Blueprint §7.2)

public struct PipiPlanChecklistCard: View {
    public let items: [PipiPlanItem]
    public let strings: PipiStrings
    public var accent: Color

    @Environment(\.pipiTextScale) private var textScale

    public init(items: [PipiPlanItem], strings: PipiStrings, accent: Color) {
        self.items = items
        self.strings = strings
        self.accent = accent
    }

    public var body: some View {
        let _ = textScale
        let completedCount = items.filter(\.isCompleted).count

        VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
            HStack(spacing: PipiTokens.spacing8) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(accent)

                Text(strings.planTitle)
                    .font(PipiTokens.fontCaption.weight(.semibold))
                    .foregroundStyle(PipiTokens.textPrimary)

                Spacer()

                Text("\(completedCount)/\(items.count)")
                    .font(PipiTokens.fontMonoSmall.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(completedCount == items.count ? PipiTokens.stateSuccess : PipiTokens.textMuted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(completedCount == items.count ? PipiTokens.stateSuccessBg : PipiTokens.bgInset)
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: PipiTokens.spacing8) {
                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(item.isCompleted ? PipiTokens.stateSuccess : PipiTokens.textMuted)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(item.isCompleted ? PipiTokens.textSecondary : PipiTokens.textPrimary)
                                .strikethrough(item.isCompleted, color: PipiTokens.textMuted)

                            if let detail = item.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(PipiTokens.fontMicro)
                                    .foregroundStyle(PipiTokens.textMuted)
                            }
                        }
                    }
                }
            }
        }
        .padding(PipiTokens.spacing12)
        .background(PipiTokens.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .stroke(PipiTokens.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
    }
}

// MARK: - Collapsed Consecutive Steps Disclosure Card (Collapsed by Default per Blueprint §7.2)

public struct PipiCollapsedStepsCard: View {
    public let steps: [PipiStepEvent]
    public let strings: PipiStrings
    public var accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pipiTextScale) private var textScale
    @State private var isExpanded: Bool = false

    public init(steps: [PipiStepEvent], strings: PipiStrings, accent: Color) {
        self.steps = steps
        self.strings = strings
        self.accent = accent
    }

    public var body: some View {
        let _ = textScale
        let hasRunning = steps.contains { $0.status == .running }
        let hasFailure = steps.contains { $0.status == .failed }
        let totalDurationMs = steps.compactMap(\.durationMs).reduce(0, +)

        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(PipiMotion.adaptive(PipiMotion.smooth, reduceMotion: reduceMotion)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: PipiTokens.spacing8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(PipiTokens.textMuted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    if hasRunning {
                        PipiDotIndicator(vitality: .busy, color: accent, size: 6)
                    } else {
                        Image(systemName: hasFailure ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(hasFailure ? PipiTokens.stateWarning : PipiTokens.stateSuccess)
                    }

                    Text(strings.stepsCountLabel(steps.count))
                        .font(PipiTokens.fontCaption.weight(.medium))
                        .foregroundStyle(PipiTokens.textPrimary)

                    if let latest = steps.last, hasRunning {
                        Text("· \(latest.verbPhrase)")
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if totalDurationMs > 0 {
                        Text(totalDurationMs < 1000 ? "\(totalDurationMs)ms" : String(format: "%.1fs", Double(totalDurationMs) / 1000.0))
                            .font(PipiTokens.fontMonoSmall)
                            .monospacedDigit()
                            .foregroundStyle(PipiTokens.textMuted)
                    }
                }
                .padding(.horizontal, PipiTokens.spacing12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(PipiPressButtonStyle(pressedScale: 0.99))

            if isExpanded {
                Rectangle()
                    .fill(PipiTokens.borderSubtle)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(steps) { step in
                        stepRow(step)
                    }
                }
                .padding(PipiTokens.spacing12)
            }
        }
        .background(PipiTokens.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .stroke(hasRunning ? accent.opacity(0.32) : PipiTokens.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
    }

    private func stepRow(_ step: PipiStepEvent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: PipiTokens.spacing8) {
            Group {
                switch step.status {
                case .running:
                    PipiDotIndicator(vitality: .busy, color: accent, size: 5)
                case .succeeded:
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(PipiTokens.stateSuccess)
                case .failed:
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(PipiTokens.stateError)
                }
            }
            .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.verbPhrase)
                    .font(PipiTokens.fontCaption.weight(.medium))
                    .foregroundStyle(PipiTokens.textPrimary)
                    .lineLimit(1)

                if let detail = step.detail, !detail.isEmpty {
                    Text(detail)
                        .font(PipiTokens.fontMonoSmall)
                        .foregroundStyle(PipiTokens.textMuted)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if let exitCode = step.exitCode, exitCode != 0 {
                Text("\(strings.exitCodeLabel) \(exitCode)")
                    .font(PipiTokens.fontMonoSmall)
                    .foregroundStyle(PipiTokens.stateError)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(PipiTokens.stateErrorBg)
                    .clipShape(Capsule())
            }

            if let dur = step.formattedDuration {
                Text(dur)
                    .font(PipiTokens.fontMonoSmall)
                    .monospacedDigit()
                    .foregroundStyle(PipiTokens.textMuted)
            }
        }
    }
}

// MARK: - Collapsed File Changes Card (Tapping Opens Diff in Inspector)

public struct PipiFileChangesCard: View {
    public let changes: [PipiFileChange]
    public let strings: PipiStrings
    public var accent: Color
    public var onSelectChange: (PipiFileChange) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pipiTextScale) private var textScale
    @State private var isExpanded: Bool = false

    public init(
        changes: [PipiFileChange],
        strings: PipiStrings,
        accent: Color,
        onSelectChange: @escaping (PipiFileChange) -> Void
    ) {
        self.changes = changes
        self.strings = strings
        self.accent = accent
        self.onSelectChange = onSelectChange
    }

    public var body: some View {
        let totalAdds = changes.map(\.additions).reduce(0, +)
        let totalDels = changes.map(\.deletions).reduce(0, +)

        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(PipiMotion.adaptive(PipiMotion.smooth, reduceMotion: reduceMotion)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: PipiTokens.spacing8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(PipiTokens.textMuted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Image(systemName: "doc.badge.gearshape")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(accent)

                    Text(strings.filesChangedCountLabel(changes.count))
                        .font(PipiTokens.fontCaption.weight(.medium))
                        .foregroundStyle(PipiTokens.textPrimary)

                    Spacer()

                    if totalAdds > 0 {
                        Text("+\(totalAdds)")
                            .font(PipiTokens.fontMonoSmall.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(PipiTokens.stateSuccess)
                    }
                    if totalDels > 0 {
                        Text("-\(totalDels)")
                            .font(PipiTokens.fontMonoSmall.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(PipiTokens.stateError)
                    }
                }
                .padding(.horizontal, PipiTokens.spacing12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(PipiPressButtonStyle(pressedScale: 0.99))

            if isExpanded {
                Rectangle()
                    .fill(PipiTokens.borderSubtle)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(changes) { change in
                        Button {
                            onSelectChange(change)
                        } label: {
                            HStack(spacing: PipiTokens.spacing8) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 11))
                                    .foregroundStyle(PipiTokens.textMuted)
                                Text(change.fileName)
                                    .font(PipiTokens.fontMonoSmall.weight(.medium))
                                    .foregroundStyle(PipiTokens.textPrimary)
                                    .lineLimit(1)
                                Text(change.path)
                                    .font(PipiTokens.fontMonoSmall)
                                    .foregroundStyle(PipiTokens.textMuted)
                                    .lineLimit(1)
                                    .truncationMode(.head)

                                Spacer(minLength: 8)

                                if change.additions > 0 {
                                    Text("+\(change.additions)")
                                        .font(PipiTokens.fontMonoSmall.weight(.semibold))
                                        .foregroundStyle(PipiTokens.stateSuccess)
                                }
                                if change.deletions > 0 {
                                    Text("-\(change.deletions)")
                                        .font(PipiTokens.fontMonoSmall.weight(.semibold))
                                        .foregroundStyle(PipiTokens.stateError)
                                }
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(PipiTokens.textMuted)
                            }
                            .padding(.horizontal, PipiTokens.spacing8)
                            .padding(.vertical, 5)
                            .background(PipiTokens.bgInset.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                        }
                        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.99))
                    }
                }
                .padding(PipiTokens.spacing8)
            }
        }
        .background(PipiTokens.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .stroke(PipiTokens.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
    }
}

// MARK: - Inline Approval Card (Blueprint §7.2 — High-Contrast + Primary/Secondary Actions)

public struct PipiInlineApprovalCard: View {
    public let approval: PipiSessionApproval
    public let strings: PipiStrings
    public var onResolve: (String) -> Void

    @Environment(\.pipiTextScale) private var textScale

    public init(
        approval: PipiSessionApproval,
        strings: PipiStrings,
        onResolve: @escaping (String) -> Void
    ) {
        self.approval = approval
        self.strings = strings
        self.onResolve = onResolve
    }

    public var body: some View {
        let _ = textScale
        let isPending = approval.status == .pending

        VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            HStack(spacing: PipiTokens.spacing8) {
                Circle()
                    .fill(isPending ? PipiTokens.stateWarning : (approval.status == .approved ? PipiTokens.stateSuccess : PipiTokens.textMuted))
                    .frame(width: 8, height: 8)

                Text(strings.needsYouLabel)
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(isPending ? PipiTokens.stateWarning : PipiTokens.textSecondary)
                    .textCase(.uppercase)

                Spacer()

                if !isPending {
                    let statusText: String = {
                        switch approval.status {
                        case .approved: return strings.approvalApprovedBadge
                        case .denied: return strings.approvalDeniedBadge
                        case .expired: return strings.approvalExpiredBadge
                        case .pending: return ""
                        }
                    }()
                    Text(statusText)
                        .font(PipiTokens.fontMicro)
                        .foregroundStyle(approval.status == .approved ? PipiTokens.stateSuccess : PipiTokens.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(approval.status == .approved ? PipiTokens.stateSuccessBg : PipiTokens.bgInset)
                        .clipShape(Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(approval.question)
                    .font(PipiTokens.fontSubheadline.weight(.semibold))
                    .foregroundStyle(PipiTokens.textPrimary)

                if let detail = approval.detail, !detail.isEmpty {
                    Text(detail)
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)
                }
            }

            if isPending {
                HStack(spacing: PipiTokens.spacing8) {
                    ForEach(approval.options) { opt in
                        let tone: PipiButtonTone = {
                            switch opt.style {
                            case .primary: return .primary
                            case .secondary: return .secondary
                            case .destructive: return .destructive
                            }
                        }()
                        PipiActionButton(
                            opt.label,
                            systemImage: opt.style == .primary ? "checkmark" : nil,
                            tone: tone,
                            density: .desktopCompact
                        ) {
                            onResolve(opt.id)
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(PipiTokens.spacing12)
        .background(isPending ? PipiTokens.stateWarningBg : PipiTokens.bgSurface.opacity(0.8))
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .stroke(isPending ? PipiTokens.stateWarning.opacity(0.45) : PipiTokens.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
    }
}

// MARK: - Summary + Evidence Card (Blueprint §7.2)

public struct PipiSummaryEvidenceCard: View {
    public let summary: PipiSessionSummaryInfo
    public let strings: PipiStrings

    public init(summary: PipiSessionSummaryInfo, strings: PipiStrings) {
        self.summary = summary
        self.strings = strings
    }

    public var body: some View {
        HStack(spacing: PipiTokens.spacing8) {
            Image(systemName: summary.exitCode == 0 || summary.exitCode == nil ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(summary.exitCode == 0 || summary.exitCode == nil ? PipiTokens.stateSuccess : PipiTokens.stateWarning)

            Text(strings.summaryTitle)
                .font(PipiTokens.fontCaption.weight(.semibold))
                .foregroundStyle(PipiTokens.textPrimary)

            if let exitCode = summary.exitCode {
                Text("\(strings.exitCodeLabel) \(exitCode)")
                    .font(PipiTokens.fontMonoSmall)
                    .foregroundStyle(exitCode == 0 ? PipiTokens.stateSuccess : PipiTokens.stateError)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(exitCode == 0 ? PipiTokens.stateSuccessBg : PipiTokens.stateErrorBg)
                    .clipShape(Capsule())
            }

            if summary.changedFilesCount > 0 {
                Text(strings.filesChangedCountLabel(summary.changedFilesCount))
                    .font(PipiTokens.fontMonoSmall)
                    .foregroundStyle(PipiTokens.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(PipiTokens.bgInset)
                    .clipShape(Capsule())
            }

            if let testSummary = summary.testSummary, !testSummary.isEmpty {
                Text(testSummary)
                    .font(PipiTokens.fontMonoSmall)
                    .foregroundStyle(PipiTokens.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if let durationMs = summary.durationMs, durationMs > 0 {
                Text(durationMs < 1000 ? "\(durationMs)ms" : String(format: "%.1fs", Double(durationMs) / 1000.0))
                    .font(PipiTokens.fontMonoSmall)
                    .monospacedDigit()
                    .foregroundStyle(PipiTokens.textMuted)
            }
        }
        .padding(.horizontal, PipiTokens.spacing12)
        .padding(.vertical, 8)
        .background(PipiTokens.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .stroke(PipiTokens.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
    }
}

// MARK: - Actionable Error Card (Retry / Switch Engine / Engine Settings)

public struct PipiActionableErrorCard: View {
    public let message: PipiChatMessage
    public let store: PipiAppStore
    public var onRetry: () -> Void
    public var onSwitchEngine: (PipiExecutionTarget) -> Void
    public var onOpenSettings: (PipiSettingsTab) -> Void

    @Environment(\.pipiTextScale) private var textScale

    public init(
        message: PipiChatMessage,
        store: PipiAppStore,
        onRetry: @escaping () -> Void,
        onSwitchEngine: @escaping (PipiExecutionTarget) -> Void,
        onOpenSettings: @escaping (PipiSettingsTab) -> Void
    ) {
        self.message = message
        self.store = store
        self.onRetry = onRetry
        self.onSwitchEngine = onSwitchEngine
        self.onOpenSettings = onOpenSettings
    }

    private var s: PipiStrings { store.strings }

    public var body: some View {
        let _ = textScale
        VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            HStack(alignment: .top, spacing: PipiTokens.spacing8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PipiTokens.stateWarning)
                    .padding(.top, 2)

                Text(message.content)
                    .font(PipiTokens.fontBody)
                    .foregroundStyle(PipiTokens.textPrimary)
                    .textSelection(.enabled)
                    .lineSpacing(3)
            }

            HStack(spacing: PipiTokens.spacing8) {
                if message.isNoEngineGuide {
                    PipiActionButton(
                        s.openAIEngineSettings,
                        systemImage: "gearshape",
                        tone: .primary,
                        density: .desktopCompact
                    ) {
                        onOpenSettings(.aiEngine)
                    }
                } else {
                    PipiActionButton(
                        s.retryAction,
                        systemImage: "arrow.clockwise",
                        tone: .primary,
                        density: .desktopCompact
                    ) {
                        onRetry()
                    }

                    if !store.readyLLMProviders.isEmpty || !store.usableLocalAgents.isEmpty {
                        Menu {
                            if !store.readyLLMProviders.isEmpty {
                                Section(s.cloudAndLocalLLMs) {
                                    ForEach(store.readyLLMProviders) { cfg in
                                        Button("\(cfg.name) · \(cfg.modelId)") {
                                            onSwitchEngine(.llm(providerId: cfg.id))
                                        }
                                    }
                                }
                            }
                            if !store.usableLocalAgents.isEmpty {
                                Section(s.localAgents) {
                                    ForEach(store.usableLocalAgents) { ag in
                                        Button(ag.kind.displayName) {
                                            onSwitchEngine(.localAgent(ag.kind))
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: PipiTokens.buttonGapDesktop) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(s.switchEngineAction)
                                    .font(PipiTokens.fontCaption.weight(.semibold))
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundStyle(PipiTokens.textMuted)
                            }
                            .foregroundStyle(PipiTokens.textPrimary)
                            .padding(.horizontal, PipiTokens.spacing12)
                            .frame(height: PipiTokens.buttonHeightDesktop)
                            .background(PipiTokens.buttonSecondaryBg)
                            .overlay(
                                RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                    .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                        }
                        .pipiPlainMenu()
                        .fixedSize()
                    }

                    PipiActionButton(
                        s.engineSettingsShort,
                        systemImage: "gearshape",
                        tone: .ghost,
                        density: .desktopCompact
                    ) {
                        onOpenSettings(.aiEngine)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(PipiTokens.spacing12)
        .background(PipiTokens.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .stroke(PipiTokens.stateWarning.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
    }
}
