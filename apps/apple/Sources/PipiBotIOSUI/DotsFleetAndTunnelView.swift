import SwiftUI
import PipiBotKit

public struct DotsFleetAndTunnelView: View {
    @Bindable public var store: PipiAppStore
    @State private var segment: Segment = .fleet
    @State private var showSoulSheet = false

    public enum Segment: String, CaseIterable, Identifiable {
        case fleet = "Dots Fleet"
        case memory = "Memory & Soul"

        public var id: String { rawValue }
    }

    public init(store: PipiAppStore) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                    Picker("View", selection: $segment) {
                        ForEach(Segment.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    if segment == .fleet {
                        fleetContent
                    } else {
                        memoryAndEvolutionContent
                    }
                }
                .padding(.horizontal, PipiTokens.spacing16)
                .padding(.bottom, PipiTokens.spacing24)
            }

            if showSoulSheet {
                PipiSheet(
                    title: "SOUL.md & USER.md",
                    subtitle: "Auditable L2 Semantic Persona Graph",
                    detent: .expanded,
                    onClose: { showSoulSheet = false }
                ) {
                    VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                        Text(store.soulPreview.soulMd)
                            .font(PipiTokens.fontMono)
                            .foregroundStyle(PipiTokens.textPrimary)
                            .padding(PipiTokens.spacing12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(PipiTokens.bgInset)
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD))

                        Text(store.soulPreview.userMd)
                            .font(PipiTokens.fontMono)
                            .foregroundStyle(PipiTokens.textSecondary)
                            .padding(PipiTokens.spacing12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(PipiTokens.bgInset)
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD))
                    }
                }
            }
        }
    }

    // MARK: - Dots Fleet & Cloudflare $0 Tunnel

    private var fleetContent: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            PipiListCard(
                title: "Cloudflare Edge Mesh",
                subtitle: "\(store.tunnelStatus.tunnelUrl) · \(store.tunnelStatus.tunnelRttMs)ms RTT · Zero Inbound Ports",
                badgeText: String(format: "$%.2f / mo", store.tunnelStatus.freeTierQuota.monthlyCostUsd),
                badgeColor: PipiTokens.stateSuccess,
                leading: {
                    PipiDotIndicator(
                        vitality: store.tunnelStatus.tunnelConnected ? .alive : .degraded,
                        color: store.tunnelStatus.tunnelConnected ? PipiTokens.stateSuccess : PipiTokens.stateWarning,
                        size: 11
                    )
                },
                footer: {
                    let quota = store.tunnelStatus.freeTierQuota
                    VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                        quotaMeter(
                            label: "Workers",
                            detail: "\(quota.workersReqToday) / \(quota.workersDailyLimit) req/d",
                            ratio: Double(quota.workersReqToday) / Double(max(1, quota.workersDailyLimit)),
                            color: PipiTokens.soulSecondary
                        )
                        quotaMeter(
                            label: "D1 Writes",
                            detail: "\(quota.d1WritesToday) / \(quota.d1DailyWriteLimit) rows/d",
                            ratio: Double(quota.d1WritesToday) / Double(max(1, quota.d1DailyWriteLimit)),
                            color: PipiTokens.harnessPi
                        )
                        quotaMeter(
                            label: "R2 ($0 Egress)",
                            detail: String(format: "%.2f / %.0f GB", quota.r2StorageGbUsed, quota.r2StorageGbLimit),
                            ratio: quota.r2StorageGbUsed / max(1.0, quota.r2StorageGbLimit),
                            color: PipiTokens.soulPrimary
                        )
                    }
                }
            )

            Text("Dots Fleet Matrix (\(store.onlineFleetCount)/\(store.fleetNodes.count) Alive)")
                .font(PipiTokens.fontHeadline)
                .foregroundStyle(PipiTokens.textPrimary)

            ForEach(store.fleetNodes) { node in
                let kindColor = PipiTokens.color(for: node.kind)
                let vitalityColor = PipiTokens.color(for: node.vitality)

                PipiListCard(
                    title: node.displayName,
                    subtitle: "\(node.kind.displayName) · \(node.osVersion) (\(node.arch)) · \(node.activeSessionsCount) active",
                    badgeText: node.vitality.displayLabel,
                    badgeColor: vitalityColor,
                    leading: {
                        ZStack {
                            RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                .fill(kindColor.opacity(0.14))
                                .frame(width: 40, height: 40)
                            Image(systemName: node.kind.sfSymbolName)
                                .font(.system(size: PipiTokens.buttonIconMobile, weight: .semibold))
                                .foregroundStyle(kindColor)
                        }
                    },
                    trailing: {
                        PipiDotIndicator(vitality: node.vitality, color: vitalityColor, size: 10)
                    },
                    footer: {
                        HStack(spacing: PipiTokens.spacing12) {
                            Text(String(format: "CPU %.0f%%", node.cpuLoadPct))
                            Text(String(format: "RAM %.0f%%", node.memoryUsedPct))
                            if let rtt = node.tunnelRttMs {
                                Text(String(format: "RTT %.0fms", rtt))
                            }
                            Spacer()
                            Text(node.tags.joined(separator: " · "))
                        }
                        .font(PipiTokens.fontMonoSmall)
                        .foregroundStyle(PipiTokens.textMuted)
                    }
                )
            }
        }
    }

    // MARK: - 4-Tier Memory & Self-Evolution

    private var memoryAndEvolutionContent: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            PipiListCard(
                title: String(format: "Understanding Score · %.1f%%", store.understandingScore.overall),
                subtitle: String(format: "+%.1f%% since last Dreaming consolidation", store.understandingScore.deltaFromPrevious),
                badgeText: "4-Tier L0–L3",
                badgeColor: PipiTokens.evolveAccent,
                footer: {
                    HStack(spacing: PipiTokens.spacing8) {
                        PipiActionButton("Run Dreaming", systemImage: "moon.stars.fill", tone: .primary, density: .mobile) {
                            Task { await store.runNightlyDreaming() }
                        }
                        PipiActionButton("View SOUL.md", systemImage: "doc.plaintext", tone: .secondary, density: .mobile) {
                            showSoulSheet = true
                        }
                    }
                }
            )

            if let digest = store.lastDigest {
                Text("Evolution Diffs (\(digest.requiresUserReviewCount) Pending)")
                    .font(PipiTokens.fontHeadline)
                    .foregroundStyle(PipiTokens.textPrimary)

                ForEach(digest.diffs) { diff in
                    PipiListCard(
                        title: diff.title,
                        subtitle: diff.proposedValue,
                        badgeText: diff.reviewStatus.rawValue.uppercased(),
                        badgeColor: diff.reviewStatus == .approved ? PipiTokens.stateSuccess : (diff.reviewStatus == .reverted ? PipiTokens.stateError : PipiTokens.stateWarning),
                        footer: {
                            if diff.reviewStatus == .pending {
                                HStack(spacing: PipiTokens.spacing8) {
                                    PipiActionButton("Approve", systemImage: "checkmark", tone: .primary, density: .mobile) {
                                        Task { await store.reviewEvolutionDiff(diffId: diff.diffId, approve: true) }
                                    }
                                    PipiActionButton("Revert", systemImage: "arrow.uturn.backward", tone: .destructive, density: .mobile) {
                                        Task { await store.reviewEvolutionDiff(diffId: diff.diffId, approve: false) }
                                    }
                                }
                            } else {
                                Text(diff.evidenceSummary)
                                    .font(PipiTokens.fontCaption)
                                    .foregroundStyle(PipiTokens.textMuted)
                            }
                        }
                    )
                }
            }

            Text("Auto-Synthesized Pi Skills")
                .font(PipiTokens.fontHeadline)
                .foregroundStyle(PipiTokens.textPrimary)

            ForEach(store.synthesizedSkills) { skill in
                PipiListCard(
                    title: skill.name,
                    subtitle: skill.description,
                    badgeText: String(format: "%.0f%% win", skill.successRate * 100),
                    badgeColor: PipiTokens.harnessPi
                )
            }
        }
    }

    private func quotaMeter(label: String, detail: String, ratio: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(PipiTokens.fontCaption.weight(.semibold))
                    .foregroundStyle(PipiTokens.textSecondary)
                Spacer()
                Text(detail)
                    .font(PipiTokens.fontMonoSmall)
                    .foregroundStyle(PipiTokens.textMuted)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(PipiTokens.bgInset)
                    Capsule()
                        .fill(color)
                        .frame(width: max(6, geo.size.width * min(1.0, ratio)))
                }
            }
            .frame(height: 6)
        }
    }
}
