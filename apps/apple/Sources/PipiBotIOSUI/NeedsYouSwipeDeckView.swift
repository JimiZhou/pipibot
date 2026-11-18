import SwiftUI
import PipiBotKit

public struct NeedsYouSwipeDeckView: View {
    @Bindable public var store: PipiAppStore
    public var onHaptic: (PipiIOSCompanionRootView.HapticKind) -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var inspectedEvidence: ArtifactEvidenceRef?

    public init(
        store: PipiAppStore,
        onHaptic: @escaping (PipiIOSCompanionRootView.HapticKind) -> Void = { _ in }
    ) {
        self.store = store
        self.onHaptic = onHaptic
    }

    public var body: some View {
        ZStack {
            VStack(spacing: PipiTokens.spacing16) {
                if let topDecision = store.pendingDecisions.first {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Needs You Inbox")
                                .font(PipiTokens.fontTitle)
                                .foregroundStyle(PipiTokens.textPrimary)
                            Text("\(store.pendingDecisions.count) high-signal decisions awaiting sign-off")
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textSecondary)
                        }
                        Spacer()
                        Text("Swipe or Tap")
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.textMuted)
                            .padding(.horizontal, PipiTokens.spacing8)
                            .padding(.vertical, 4)
                            .background(PipiTokens.bgSurface)
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, PipiTokens.spacing16)

                    decisionCard(topDecision)
                        .padding(.horizontal, PipiTokens.spacing16)
                        .offset(x: dragOffset.width, y: dragOffset.height * 0.2)
                        .rotationEffect(.degrees(Double(dragOffset.width / 22.0)))
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    dragOffset = value.translation
                                }
                                .onEnded { value in
                                    if value.translation.width > 110 {
                                        let approveId = topDecision.recommendedOptionId
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            dragOffset = .zero
                                        }
                                        Task {
                                            await store.resolveDecision(topDecision.id, optionId: approveId)
                                            onHaptic(.success)
                                        }
                                    } else if value.translation.width < -110,
                                              let rejectId = topDecision.options.last?.id {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            dragOffset = .zero
                                        }
                                        Task {
                                            await store.resolveDecision(topDecision.id, optionId: rejectId)
                                            onHaptic(.medium)
                                        }
                                    } else {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            dragOffset = .zero
                                        }
                                    }
                                }
                        )

                    Spacer(minLength: 0)
                } else {
                    PipiEmptyState(
                        systemImage: "checkmark.seal.fill",
                        title: "Needs You Inbox Clear",
                        message: "Your autonomous fleet handled routine operations and surfaced zero pending escalations.",
                        buttonTitle: "Trigger Outcome Check",
                        buttonAction: {
                            if let firstId = store.outcomes.first?.id {
                                Task { await store.evaluateOutcome(firstId) }
                            }
                        }
                    )
                }
            }

            if let evidence = inspectedEvidence {
                PipiSheet(
                    title: evidence.kind.label,
                    subtitle: evidence.r2Key,
                    detent: .expanded,
                    onClose: { inspectedEvidence = nil }
                ) {
                    VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                        PipiListCard(
                            title: evidence.caption,
                            subtitle: "Zero-egress artifact hosted on Cloudflare R2 (`$0` egress) with 15m HMAC signature.",
                            badgeText: "R2 Verified",
                            badgeColor: PipiTokens.stateSuccess
                        )

                        VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                            Text("Before / After Verification Summary")
                                .font(PipiTokens.fontHeadline)
                                .foregroundStyle(PipiTokens.textPrimary)
                            Text("First visit & repeat visit recordings captured automatically on isolated staging runner. Metrics pass all target constraints.")
                                .font(PipiTokens.fontBody)
                                .foregroundStyle(PipiTokens.textSecondary)
                        }
                        .padding(PipiTokens.spacing16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(PipiTokens.bgSurface)
                        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                    }
                }
            }
        }
    }

    private func decisionCard(_ decision: NeedsYouDecision) -> some View {
        let sevColor = PipiTokens.color(for: decision.severity)

        return VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            HStack(spacing: PipiTokens.spacing8) {
                Text(decision.severity.rawValue.uppercased())
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(sevColor)
                    .padding(.horizontal, PipiTokens.spacing8)
                    .padding(.vertical, 4)
                    .background(sevColor.opacity(0.14))
                    .clipShape(Capsule())

                Text(decision.category.displayName)
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.textSecondary)
                    .padding(.horizontal, PipiTokens.spacing8)
                    .padding(.vertical, 4)
                    .background(PipiTokens.bgInset)
                    .clipShape(Capsule())

                Spacer()

                Text(decision.sourceNodeId)
                    .font(PipiTokens.fontMonoSmall)
                    .foregroundStyle(PipiTokens.textMuted)
            }

            VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                Text(decision.title)
                    .font(PipiTokens.fontTitle)
                    .foregroundStyle(PipiTokens.textPrimary)

                Text(decision.summary)
                    .font(PipiTokens.fontBody)
                    .foregroundStyle(PipiTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !decision.evidence.isEmpty {
                VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                    Text("Cloudflare R2 Evidence")
                        .font(PipiTokens.fontCaption.weight(.semibold))
                        .foregroundStyle(PipiTokens.textMuted)

                    ForEach(decision.evidence) { ref in
                        Button {
                            inspectedEvidence = ref
                            onHaptic(.light)
                        } label: {
                            HStack(spacing: PipiTokens.spacing8) {
                                Image(systemName: ref.kind == .video ? "play.rectangle.fill" : "doc.text.magnifyingglass")
                                    .font(.system(size: PipiTokens.buttonIconMobile, weight: .medium))
                                    .foregroundStyle(PipiTokens.soulSecondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ref.kind.label)
                                        .font(PipiTokens.fontCaption.weight(.semibold))
                                        .foregroundStyle(PipiTokens.textPrimary)
                                    Text(ref.caption)
                                        .font(PipiTokens.fontCaption)
                                        .foregroundStyle(PipiTokens.textSecondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(PipiTokens.textMuted)
                            }
                            .padding(PipiTokens.spacing12)
                            .background(PipiTokens.bgInset)
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(spacing: PipiTokens.spacing8) {
                ForEach(decision.options) { option in
                    let tone: PipiButtonTone = {
                        switch option.style {
                        case .primary: return .primary
                        case .secondary: return .secondary
                        case .destructive: return .destructive
                        }
                    }()
                    PipiActionButton(
                        option.label,
                        systemImage: option.style == .primary ? "checkmark.circle.fill" : (option.style == .destructive ? "xmark.circle" : "arrow.triangle.2.circlepath"),
                        tone: tone,
                        density: .mobile,
                        fullWidth: true
                    ) {
                        Task {
                            await store.resolveDecision(decision.id, optionId: option.id)
                            onHaptic(option.style == .primary ? .success : .medium)
                        }
                    }
                }
            }
        }
        .padding(PipiTokens.spacing20)
        .background(PipiTokens.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusXL, style: .continuous)
                .stroke(
                    dragOffset.width > 40
                        ? PipiTokens.stateSuccess
                        : (dragOffset.width < -40 ? PipiTokens.stateError : PipiTokens.borderSubtle),
                    lineWidth: abs(dragOffset.width) > 40 ? 2 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusXL, style: .continuous))
    }
}
