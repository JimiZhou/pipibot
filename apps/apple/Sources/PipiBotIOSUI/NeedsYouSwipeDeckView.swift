// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
//
// Fluid Physics Swipe Deck for High-Signal Human Decisions:
// Stacked card depth, velocity-aware momentum projection, directional intent stamps, and tactile haptics.

import SwiftUI
import PipiBotKit

public struct NeedsYouSwipeDeckView: View {
    @Bindable public var store: PipiAppStore
    public var onHaptic: (PipiIOSCompanionRootView.HapticKind) -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var crossedThreshold: Bool = false
    @State private var inspectedEvidence: ArtifactEvidenceRef?

    public init(
        store: PipiAppStore,
        onHaptic: @escaping (PipiIOSCompanionRootView.HapticKind) -> Void = { _ in }
    ) {
        self.store = store
        self.onHaptic = onHaptic
    }

    private var s: PipiStrings { store.strings }

    public var body: some View {
        ZStack {
            VStack(spacing: PipiTokens.spacing16) {
                let pending = store.pendingDecisions
                if let topDecision = pending.first {
                    HStack(alignment: .firstTextBaseline) {
                        Text(s.t("待你拍板", "Needs your call"))
                            .font(PipiTokens.fontHeadline)
                            .foregroundStyle(PipiTokens.textPrimary)

                        Text("\(pending.count)")
                            .font(PipiTokens.fontMonoSmall)
                            .monospacedDigit()
                            .foregroundStyle(PipiTokens.textMuted)

                        Spacer()

                        Text(s.t("右滑通过 · 左滑跳过", "Right approve · Left skip"))
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.textMuted)
                    }
                    .padding(.horizontal, PipiTokens.spacing16)

                    // Stacked card deck with 1:1 depth interpolation during drag
                    let progress = min(1.0, abs(dragOffset.width) / 140.0)
                    ZStack {
                        ForEach(Array(pending.prefix(3).enumerated().reversed()), id: \.element.id) { idx, decision in
                            if idx == 0 {
                                decisionCard(decision, isTop: true, dragProgress: progress)
                                    .offset(x: dragOffset.width, y: dragOffset.height * 0.18)
                                    .rotationEffect(.degrees(Double(dragOffset.width / 26.0)))
                                    .gesture(
                                        DragGesture(minimumDistance: 10)
                                            .onChanged { value in
                                                dragOffset = value.translation
                                                let nowCrossed = abs(value.translation.width) > 95
                                                if nowCrossed != crossedThreshold {
                                                    crossedThreshold = nowCrossed
                                                    if nowCrossed { onHaptic(.light) }
                                                }
                                            }
                                            .onEnded { value in
                                                // Apple Fluid momentum projection: honor flick velocity via predictedEndTranslation
                                                let projectedX = value.predictedEndTranslation.width
                                                let commitApprove = value.translation.width > 100 || projectedX > 190
                                                let commitSkip = value.translation.width < -100 || projectedX < -190
                                                crossedThreshold = false

                                                if commitApprove {
                                                    let approveId = topDecision.recommendedOptionId
                                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                                        dragOffset = CGSize(width: 440, height: 18)
                                                    }
                                                    Task {
                                                        try? await Task.sleep(for: .milliseconds(160))
                                                        dragOffset = .zero
                                                        await store.resolveDecision(topDecision.id, optionId: approveId)
                                                        onHaptic(.success)
                                                    }
                                                } else if commitSkip, let rejectId = topDecision.options.last?.id {
                                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                                        dragOffset = CGSize(width: -440, height: 18)
                                                    }
                                                    Task {
                                                        try? await Task.sleep(for: .milliseconds(160))
                                                        dragOffset = .zero
                                                        await store.resolveDecision(topDecision.id, optionId: rejectId)
                                                        onHaptic(.medium)
                                                    }
                                                } else {
                                                    // Critically damped settle (zero distracting bounce on cancel)
                                                    withAnimation(.spring(response: 0.28, dampingFraction: 1.0)) {
                                                        dragOffset = .zero
                                                    }
                                                }
                                            }
                                    )
                            } else {
                                let baseScale = 1.0 - (CGFloat(idx) * 0.045)
                                let liftedScale = baseScale + (CGFloat(progress) * 0.045)
                                let baseY = CGFloat(idx) * 10.0
                                let liftedY = max(0, baseY - (CGFloat(progress) * 10.0))
                                decisionCard(decision, isTop: false, dragProgress: 0)
                                    .scaleEffect(liftedScale)
                                    .offset(y: liftedY)
                                    .opacity(idx == 1 ? 0.72 + (0.28 * progress) : 0.42)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                    .padding(.horizontal, PipiTokens.spacing16)
                    .padding(.bottom, PipiTokens.spacing16)
                } else {
                    VStack(spacing: PipiTokens.spacing12) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(PipiTokens.textMuted)
                        Text(s.approvalsEmptyTitle)
                            .font(PipiTokens.fontHeadline)
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text(s.approvalsEmptyMessage)
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                    .padding(.horizontal, PipiTokens.spacing20)
                    .background(PipiTokens.bgCanvas, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                    )
                    .padding(.horizontal, PipiTokens.spacing16)
                }
            }

            if let evidence = inspectedEvidence {
                PipiSheet(
                    title: evidence.kind.label,
                    subtitle: evidence.caption,
                    detent: .expanded,
                    onClose: { inspectedEvidence = nil }
                ) {
                    VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                        PipiListCard(
                            title: evidence.caption,
                            subtitle: s.t("已通过 PipiBot 安全同步", "Verified attachment from PipiBot"),
                            badgeText: s.t("已验证", "Verified"),
                            badgeColor: PipiTokens.stateSuccess
                        )
                    }
                }
            }
        }
    }

    private func decisionCard(_ decision: NeedsYouDecision, isTop: Bool, dragProgress: Double) -> some View {
        let sevColor = PipiTokens.color(for: decision.severity)
        let isApproving = isTop && dragOffset.width > 36
        let isSkipping = isTop && dragOffset.width < -36
        let borderColor: Color = isApproving
            ? PipiTokens.stateSuccess
            : (isSkipping ? PipiTokens.stateError : PipiTokens.sheetBorder)

        return VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            HStack(spacing: PipiTokens.spacing8) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(sevColor)
                        .frame(width: 6, height: 6)
                    Text(decision.category.displayName)
                        .font(PipiTokens.fontMicro)
                        .foregroundStyle(PipiTokens.textSecondary)
                }

                Spacer()

                if isApproving {
                    Text(s.t("通过", "Approve"))
                        .font(PipiTokens.fontMicro.weight(.medium))
                        .foregroundStyle(PipiTokens.stateSuccess)
                        .opacity(dragProgress)
                } else if isSkipping {
                    Text(s.t("跳过", "Skip"))
                        .font(PipiTokens.fontMicro.weight(.medium))
                        .foregroundStyle(PipiTokens.stateError)
                        .opacity(dragProgress)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(decision.title)
                    .font(PipiTokens.fontHeadline)
                    .foregroundStyle(PipiTokens.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(decision.summary)
                    .font(PipiTokens.fontBody)
                    .foregroundStyle(PipiTokens.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !decision.evidence.isEmpty {
                VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                    ForEach(decision.evidence) { ref in
                        Button {
                            inspectedEvidence = ref
                            onHaptic(.light)
                        } label: {
                            HStack(spacing: PipiTokens.spacing8) {
                                Image(systemName: ref.kind == .video ? "play.rectangle" : "doc.text")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(PipiTokens.textSecondary)

                                Text(ref.caption)
                                    .font(PipiTokens.fontCaption)
                                    .foregroundStyle(PipiTokens.textPrimary)
                                    .lineLimit(1)

                                Spacer()

                                Text(s.t("查看", "View"))
                                    .font(PipiTokens.fontMicro.weight(.medium))
                                    .foregroundStyle(PipiTokens.textInverse)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(PipiTokens.soulPrimary, in: Capsule())
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(PipiTokens.bgSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.98))
                    }
                }
            }

            // Clean two-button action bar for effortless thumb reach
            HStack(spacing: PipiTokens.spacing8) {
                ForEach(decision.options.prefix(2)) { option in
                    let isPrimary = option.style == .primary || option.id == decision.recommendedOptionId
                    Button {
                        Task {
                            await store.resolveDecision(decision.id, optionId: option.id)
                            onHaptic(isPrimary ? .success : .medium)
                        }
                    } label: {
                        Text(option.label)
                            .font(PipiTokens.fontSubheadline)
                            .foregroundStyle(isPrimary ? PipiTokens.textInverse : PipiTokens.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(isPrimary ? PipiTokens.soulPrimary : PipiTokens.bgSurface, in: Capsule())
                            .overlay(
                                Capsule().stroke(isPrimary ? Color.clear : PipiTokens.borderSubtle, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))
                }
            }
        }
        .padding(PipiTokens.spacing20)
        .background(PipiTokens.bgCanvas, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(borderColor, lineWidth: isApproving || isSkipping ? 1.5 : 1)
        )
        .shadow(color: isTop ? PipiTokens.sheetShadow : .clear, radius: 12, x: 0, y: 4)
    }
}
