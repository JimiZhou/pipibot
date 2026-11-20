// PiPiBot — Clean-room MIT implementation.
// Wave 3 (#05): Meta / AlterEgo In-Chat Background Task Strip with Live Steps,
// Isolated Playground Artifacts, Mid-Flight Steer, Cancel & Resume.
// Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
// Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.

import SwiftUI
import PipiBotKit

public struct PipiAlterEgoBarView: View {
    @Bindable public var store: PipiAppStore
    public let sessionId: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedTaskIds: Set<String> = []
    @State private var steerDrafts: [String: String] = [:]

    public init(store: PipiAppStore, sessionId: String) {
        self.store = store
        self.sessionId = sessionId
    }

    private var s: PipiStrings { store.strings }
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }

    public var body: some View {
        let tasks = store.alterEgoTasks(forSession: sessionId)
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                HStack(spacing: PipiTokens.spacing8) {
                    Image(systemName: "person.2.wave.2")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PipiTokens.textSecondary)
                    Text("\(s.alterEgoSectionTitle) (\(tasks.count))")
                        .font(PipiTokens.fontCaption.weight(.semibold))
                        .foregroundStyle(PipiTokens.textPrimary)
                    Spacer()
                    let runningCount = tasks.filter { $0.status == .running || $0.status == .queued }.count
                    if runningCount > 0 {
                        HStack(spacing: 4) {
                            PipiDotIndicator(vitality: .busy, color: PipiTokens.soulPrimary, size: 5)
                            Text(s.t("\(runningCount) 个运行中", "\(runningCount) active"))
                                .font(PipiTokens.fontMicro)
                                .foregroundStyle(PipiTokens.textSecondary)
                        }
                    }
                }

                ForEach(tasks.prefix(4)) { task in
                    taskRow(task)
                }
            }
            .padding(PipiTokens.spacing12)
            .background(PipiTokens.bgElevated)
            .overlay(
                RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                    .stroke(PipiTokens.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
        }
    }

    private func taskRow(_ task: PipiAlterEgoTask) -> some View {
        let isExpanded = expandedTaskIds.contains(task.id)
        let statusColor: Color = {
            switch task.status {
            case .running, .queued: return PipiTokens.soulPrimary
            case .completed: return PipiTokens.stateSuccess
            case .failed: return PipiTokens.stateError
            case .paused, .cancelled: return PipiTokens.stateWarning
            }
        }()

        return VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
            HStack(spacing: PipiTokens.spacing8) {
                Button {
                    withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                        if isExpanded {
                            expandedTaskIds.remove(task.id)
                        } else {
                            expandedTaskIds.insert(task.id)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(PipiTokens.textMuted)
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6.5, height: 6.5)
                        Text(task.title)
                            .font(PipiTokens.fontSubheadline.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                            .lineLimit(1)
                        Text(task.status.label(lang))
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(PipiTokens.bgInset, in: Capsule())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                if task.status == .running || task.status == .queued {
                    PipiActionButton(s.cancel, tone: .ghost, density: .desktopCompact) {
                        store.cancelAlterEgoTask(id: task.id)
                    }
                } else if task.status == .cancelled || task.status == .paused || task.status == .failed {
                    PipiActionButton(s.alterEgoResumeAction, systemImage: "play.fill", tone: .secondary, density: .desktopCompact) {
                        _ = store.resumeAlterEgoTask(id: task.id)
                    }
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    if let summary = task.resultSummary, !summary.isEmpty {
                        Text(summary)
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                    }

                    if !task.steps.isEmpty {
                        ForEach(task.steps.suffix(5)) { step in
                            HStack(spacing: 6) {
                                Image(systemName: step.status == .succeeded ? "checkmark.circle.fill" : (step.status == .failed ? "xmark.circle.fill" : "clock"))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(step.status == .succeeded ? PipiTokens.stateSuccess : (step.status == .failed ? PipiTokens.stateError : PipiTokens.textMuted))
                                Text(step.title)
                                    .font(PipiTokens.fontCaption)
                                    .foregroundStyle(PipiTokens.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    if !task.artifacts.isEmpty {
                        Text("playground/\(task.id)/: \(task.artifacts.joined(separator: ", "))")
                            .font(PipiTokens.fontMonoSmall)
                            .foregroundStyle(PipiTokens.textMuted)
                            .lineLimit(2)
                    }

                    HStack(spacing: PipiTokens.spacing8) {
                        PipiTextField(
                            s.alterEgoSteerPlaceholder,
                            text: Binding(
                                get: { steerDrafts[task.id] ?? "" },
                                set: { steerDrafts[task.id] = $0 }
                            ),
                            height: 28
                        )

                        PipiActionButton(s.t("补充", "Update"), tone: .secondary, density: .desktopCompact) {
                            let note = (steerDrafts[task.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !note.isEmpty else { return }
                            store.steerAlterEgoTask(id: task.id, instruction: note)
                            steerDrafts[task.id] = ""
                        }
                    }
                }
                .padding(.leading, 16)
            }
        }
        .padding(.vertical, 4)
    }
}
