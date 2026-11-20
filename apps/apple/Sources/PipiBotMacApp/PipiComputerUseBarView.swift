// PiPiBot — Clean-room MIT implementation.
// Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
// Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.

import SwiftUI
import PipiBotKit

/// Wave 5 (#09): On-demand Computer Use live status strip displayed when an agent holds
/// a Phase A Chrome Seat, a Phase B macOS Desktop Lane, has yielded to human focus, or is
/// locked by an unknown-outcome Write-Ahead Journal entry.
public struct PipiComputerUseBarView: View {
    @Bindable public var store: PipiAppStore
    public var onOpenSettings: () -> Void

    @State private var showJournal = false

    public init(
        store: PipiAppStore,
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.store = store
        self.onOpenSettings = onOpenSettings
    }

    private var s: PipiStrings { store.strings }
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }

    private var desktopLane: PipiComputerUseLaneSnapshot? {
        store.computerUseLanes.first(where: { $0.laneId == PipiComputerUseCoordinator.desktopLaneId })
    }

    private var lockedLanes: [PipiComputerUseLaneSnapshot] {
        store.computerUseLanes.filter { $0.state == .blockedUnknownOutcome }
    }

    private func dotColor(for state: PipiComputerUseLaneState) -> Color {
        switch state {
        case .idle: return PipiTokens.textMuted
        case .active: return PipiTokens.stateSuccess
        case .yieldedToHuman: return PipiTokens.stateWarning
        case .blockedUnknownOutcome: return PipiTokens.stateError
        }
    }

    public var body: some View {
        let screenState = desktopLane?.state ?? .idle
        VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
            HStack(spacing: PipiTokens.spacing8) {
                Circle()
                    .fill(dotColor(for: screenState))
                    .frame(width: 8, height: 8)

                Text(s.computerUseSectionTitle)
                    .font(PipiTokens.fontCaption.weight(.semibold))
                    .foregroundStyle(PipiTokens.textPrimary)

                // Screen lane status badge
                Text(screenState.label(lang))
                    .font(PipiTokens.fontMicro.weight(.medium))
                    .foregroundStyle(dotColor(for: screenState))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2.5)
                    .background(PipiTokens.bgSurfaceHover)
                    .clipShape(Capsule())

                // Active Phase A Chrome seats count badge
                if !store.computerUseSeats.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.system(size: 10, weight: .semibold))
                        Text(s.t("浏览器标签 \(store.computerUseSeats.count)", "Browser Seats \(store.computerUseSeats.count)"))
                            .font(PipiTokens.fontMicro)
                    }
                    .foregroundStyle(PipiTokens.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2.5)
                    .background(PipiTokens.bgSurfaceHover)
                    .clipShape(Capsule())
                }

                Spacer(minLength: 6)

                if let locked = lockedLanes.first {
                    PipiActionButton(s.computerUseUnlockLane, systemImage: "lock.open.fill", tone: .primary, density: .desktopCompact) {
                        _ = store.acknowledgeAndUnlockComputerUseLane(locked.laneId, note: "Verified in workspace")
                    }
                } else if store.computerUseYieldedToHuman {
                    PipiActionButton(s.computerUseResume, systemImage: "play.fill", tone: .secondary, density: .desktopCompact) {
                        store.resumeComputerUseAfterHumanYield()
                    }
                } else {
                    PipiActionButton(s.computerUseTakeOver, systemImage: "hand.raised.fill", tone: .secondary, density: .desktopCompact) {
                        store.humanTakeOverComputerUse()
                    }
                }

                PipiGhostIconButton(
                    systemImage: showJournal ? "chevron.up" : "list.bullet.rectangle",
                    size: 24,
                    iconSize: 11,
                    accessibilityLabel: s.computerUseJournalTitle
                ) {
                    showJournal.toggle()
                }

                PipiGhostIconButton(
                    systemImage: "gearshape",
                    size: 24,
                    iconSize: 11,
                    accessibilityLabel: s.settings,
                    action: onOpenSettings
                )

                PipiGhostIconButton(
                    systemImage: "xmark",
                    size: 24,
                    iconSize: 11,
                    accessibilityLabel: s.close
                ) {
                    store.computerUseBarPresented = false
                }
            }

            if let reason = store.computerUseYieldReason, store.computerUseYieldedToHuman {
                Text(s.t("已暂停桌面操作：\(reason)", "Desktop control paused: \(reason)"))
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.stateWarning)
            }

            if showJournal {
                VStack(alignment: .leading, spacing: 4) {
                    if store.computerUseJournal.isEmpty {
                        Text(s.t("暂无操作记录。", "No action logs yet."))
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.textMuted)
                    } else {
                        ForEach(store.computerUseJournal.prefix(6)) { entry in
                            HStack(spacing: PipiTokens.spacing8) {
                                Text(entry.laneId)
                                    .font(PipiTokens.fontMonoSmall)
                                    .foregroundStyle(PipiTokens.textMuted)
                                Text("\(entry.actionType.rawValue) · \(entry.targetApp ?? entry.targetUrl ?? "-")")
                                    .font(PipiTokens.fontCaption)
                                    .foregroundStyle(PipiTokens.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text(entry.status.label(lang))
                                    .font(PipiTokens.fontMicro)
                                    .foregroundStyle(
                                        entry.status == .committed ? PipiTokens.stateSuccess :
                                            (entry.status == .unknownOutcome || entry.status == .blockedGuardrail ? PipiTokens.stateError : PipiTokens.stateWarning)
                                    )
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(PipiTokens.composerSurface)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .stroke(PipiTokens.composerBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
        .shadow(color: PipiTokens.composerShadow, radius: 10, y: 4)
    }
}
