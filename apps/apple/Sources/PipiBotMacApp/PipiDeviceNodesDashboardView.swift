// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
// Dedicated "我的设备节点" (Device Nodes & Hardware Telemetry Dashboard) for PiPiBot Mac App.

import SwiftUI
import PipiBotKit
#if os(macOS)
import AppKit
#endif

struct PipiDeviceNodesDashboardView: View {
    let store: PipiAppStore
    let onSelectNodeForChat: (_ hostId: String?, _ harness: String?) -> Void
    let onInspectRemoteNode: (_ device: PipiAccountDevice) -> Void
    let onOpenRemoteSettings: () -> Void

    @State private var remoteTelemetry: [String: PipiRemoteNodeLiveTelemetry] = [:]
    @State private var isRefreshing: Bool = false
    @State private var copiedInstallCmd: Bool = false

    private var s: PipiStrings { store.strings }
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }

    private let installCommand = "curl -fsSL https://pipibot.jimizhou.com/install.sh | bash && pipibot login && pipibot up -d"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerRow

                if !store.accountClient.isSignedIn {
                    signInPromptCard
                } else {
                    kpiSummaryRow
                    nodeCardsGrid
                }
            }
            .padding(26)
            .frame(maxWidth: 1140, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(PipiTokens.bgCanvas)
        .task {
            await refreshAllTelemetry()
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(s.t("我的设备节点", "My Device Nodes"))
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(PipiTokens.textPrimary)
                if let user = store.accountClient.currentUser {
                    Text(s.t(
                        "统一账号：\(user.email ?? user.displayName) · 实时监控硬件资源并直接调度各节点 Agent Harness",
                        "Account: \(user.email ?? user.displayName) · Live hardware telemetry & remote harness dispatch"
                    ))
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.textSecondary)
                } else {
                    Text(s.t(
                        "登录 PiPiBot 统一账号后，即可在一个主控端纳管并监控所有 Mac / Linux 设备节点",
                        "Sign in to monitor and control all your enrolled Mac & Linux nodes from one control plane"
                    ))
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.textSecondary)
                }
            }

            Spacer()

            Button {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(installCommand, forType: .string)
                copiedInstallCmd = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    copiedInstallCmd = false
                }
                #endif
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: copiedInstallCmd ? "checkmark" : "terminal")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text(copiedInstallCmd ? s.t("已复制接入命令", "Copied") : s.t("复制 Linux 纳管命令", "Copy Linux Enroll"))
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(PipiTokens.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(PipiTokens.bgSurface)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(PipiTokens.borderSubtle, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(PipiPressButtonStyle(pressedScale: 0.97))

            Button {
                Task { await refreshAllTelemetry() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text(s.t("刷新遥测", "Refresh"))
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(PipiTokens.textInverse)
                .padding(.horizontal, 13)
                .frame(height: 32)
                .background(PipiTokens.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(PipiPressButtonStyle(pressedScale: 0.97))
            .disabled(isRefreshing)
            .opacity(isRefreshing ? 0.6 : 1.0)
        }
    }

    // MARK: - Sign-in Prompt

    private var signInPromptCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(PipiTokens.bgSurfaceHover)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.t("登录统一账号，纳管你的多机算力与 Agent", "Sign in to enroll your machines & agents"))
                        .font(PipiTokens.fontHeadline)
                        .foregroundStyle(PipiTokens.textPrimary)
                    Text(s.t("支持 Google、GitHub 与邮箱 6 位验证码登录，全程零知识端到端加密。", "Google, GitHub, and 6-digit email OTP with zero-knowledge E2EE."))
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)
                }
            }

            HStack(spacing: 10) {
                monochromePrimaryButton(title: s.t("浏览器一键登录（Google / GitHub）", "Sign in with Browser"), icon: "arrow.up.right") {
                    Task {
                        await store.accountClient.startBrowserOAuthLogin {
                            Task {
                                await store.syncAccountAndAutoConnectRelay()
                                await refreshAllTelemetry()
                            }
                        }
                    }
                }

                monochromeSecondaryButton(title: s.t("邮箱验证码登录", "Email OTP"), icon: "envelope") {
                    onOpenRemoteSettings()
                }
            }

            if let code = store.accountClient.pendingBrowserUserCode {
                Text(s.t("请在浏览器确认授权码：\(code)", "Confirm code in browser: \(code)"))
                    .font(PipiTokens.fontMonoSmall)
                    .foregroundStyle(PipiTokens.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(PipiTokens.bgSurfaceHover)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PipiTokens.bgSurface)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PipiTokens.borderSubtle, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - KPI Summary Row

    private var kpiSummaryRow: some View {
        let totalCount = 1 + store.enrolledRemoteDevices.count
        let onlineCount = 1 + store.enrolledRemoteDevices.filter(\.isOnline).count
        let totalHarnesses = store.usableLocalAgents.count
            + store.enrolledRemoteDevices.filter(\.isOnline).reduce(0) { $0 + $1.capabilities.count }
        let localSnap = store.telemetryMonitor.snapshot

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            kpiCard(
                icon: "server.rack",
                title: s.t("已纳管节点", "Enrolled Nodes"),
                value: "\(totalCount)",
                detail: s.t("1 台主控 · \(store.enrolledRemoteDevices.count) 台远端", "1 primary · \(store.enrolledRemoteDevices.count) remote")
            )
            kpiCard(
                icon: "checkmark.shield",
                title: s.t("实时在线", "Online Now"),
                value: "\(onlineCount) / \(totalCount)",
                detail: s.t("零知识端到端加密", "Zero-knowledge E2EE"),
                accentDot: PipiTokens.stateSuccess
            )
            kpiCard(
                icon: "bolt.horizontal",
                title: s.t("可用 Harness", "Available Harnesses"),
                value: "\(totalHarnesses)",
                detail: "Claude · Codex · Pi · AGY"
            )
            kpiCard(
                icon: "gauge.with.dots.needle.33percent",
                title: s.t("本机主控负载", "Primary Load"),
                value: String(format: "CPU %.0f%%", localSnap.cpuUsagePercent),
                detail: String(format: "内存 %.1f / %.0f GB", localSnap.memoryUsedGB, localSnap.memoryTotalGB)
            )
        }
    }

    private func kpiCard(icon: String, title: String, value: String, detail: String, accentDot: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(PipiTokens.textMuted)
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(PipiTokens.textSecondary)
                Spacer()
                if let accentDot {
                    Circle().fill(accentDot).frame(width: 7, height: 7)
                }
            }
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(PipiTokens.textPrimary)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(PipiTokens.textMuted)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PipiTokens.bgSurface)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PipiTokens.borderSubtle, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Uniform-Height Node Cards Grid

    private var nodeCardsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
            localPrimaryNodeCard

            ForEach(store.enrolledRemoteDevices) { dev in
                remoteNodeCard(dev)
            }
        }
    }

    private var localPrimaryNodeCard: some View {
        let snap = store.telemetryMonitor.snapshot
        let memRatio = snap.memoryTotalGB > 0 ? min(1.0, max(0.0, snap.memoryUsedGB / snap.memoryTotalGB)) : 0
        let cpuRatio = min(1.0, max(0.0, snap.cpuUsagePercent / 100.0))
        let localNames = store.usableLocalAgents.map(\.kind.displayName)

        return VStack(alignment: .leading, spacing: 14) {
            // Card Header
            HStack(spacing: 8) {
                Circle().fill(PipiTokens.stateSuccess).frame(width: 8, height: 8)
                Text(store.localHost.displayName(lang))
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(PipiTokens.textPrimary)
                    .lineLimit(1)
                tagPill(s.t("主控", "Primary"), highlighted: true)
                Spacer()
                Text(store.localHost.capabilities.osName)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(PipiTokens.textMuted)
            }

            // Telemetry Section (Fixed-height 2-bar block)
            VStack(alignment: .leading, spacing: 9) {
                resourceMeter(
                    label: s.t("CPU 占用", "CPU"),
                    valueText: String(format: "%.0f%%", snap.cpuUsagePercent),
                    ratio: cpuRatio
                )
                resourceMeter(
                    label: s.t("内存占用", "Memory"),
                    valueText: String(format: "%.1f / %.0f GB", snap.memoryUsedGB, snap.memoryTotalGB),
                    ratio: memRatio
                )
            }
            .frame(minHeight: 62, alignment: .top)

            // Harness Section (Always present for uniform height)
            harnessStripSection(
                title: s.t("本机已就绪 Harness", "Local Harnesses"),
                harnesses: localNames,
                isInteractive: false,
                onTapHarness: { _ in }
            )

            Spacer(minLength: 0)

            // Footer Actions
            HStack(spacing: 8) {
                monochromePrimaryButton(title: s.t("在本机对话", "Chat on Primary"), icon: "bubble.left.fill") {
                    onSelectNodeForChat(nil, nil)
                }

                Spacer()

                Text("hostId: \(store.e2eeRelayClient.hostId.prefix(10))")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(PipiTokens.textMuted)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 236, alignment: .topLeading)
        .background(PipiTokens.bgSurface)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PipiTokens.borderSubtle, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func remoteNodeCard(_ dev: PipiAccountDevice) -> some View {
        let tel = remoteTelemetry[dev.hostId]
        let harnesses = tel?.installedAgentNames ?? dev.capabilities

        return VStack(alignment: .leading, spacing: 14) {
            // Card Header
            HStack(spacing: 8) {
                Circle()
                    .fill(dev.isOnline ? PipiTokens.stateSuccess : PipiTokens.textMuted.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text(dev.name)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(PipiTokens.textPrimary)
                    .lineLimit(1)
                tagPill(dev.platform.uppercased(), highlighted: false)
                Spacer()
                Text(dev.isOnline ? (tel.map { "运行 \($0.formattedUptime)" } ?? s.t("在线", "Online")) : s.t("离线", "Offline"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(dev.isOnline ? PipiTokens.stateSuccess : PipiTokens.textMuted)
            }

            // Telemetry Section (Fixed-height block matching localPrimaryNodeCard)
            VStack(alignment: .leading, spacing: 9) {
                if let tel {
                    HStack(spacing: 10) {
                        Label("\(tel.cpuCount) 核 · \(tel.arch)", systemImage: "cpu")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(PipiTokens.textSecondary)
                        if let branch = tel.gitBranch {
                            Label("\(branch)\((tel.gitDirtyCount ?? 0) > 0 ? " *\(tel.gitDirtyCount!)" : "")", systemImage: "arrow.triangle.branch")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(PipiTokens.textMuted)
                                .lineLimit(1)
                        }
                        Spacer()
                    }

                    resourceMeter(
                        label: s.t("内存占用", "Memory"),
                        valueText: String(format: "%.1f / %.1f GB", Double(tel.usedMemoryMB) / 1024.0, Double(tel.totalMemoryMB) / 1024.0),
                        ratio: tel.memoryUsageRatio
                    )
                } else if dev.isOnline {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(s.t("正在拉取端到端硬件遥测…", "Loading E2EE telemetry…"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(PipiTokens.textMuted)
                        Capsule()
                            .fill(PipiTokens.bgSurfaceHover)
                            .frame(height: 6)
                    }
                } else {
                    Text(s.t("节点当前离线，运行 `pipibot up -d` 即可恢复在线。", "Node offline. Run `pipibot up -d` to reconnect."))
                        .font(.system(size: 11.5))
                        .foregroundStyle(PipiTokens.textMuted)
                }
            }
            .frame(minHeight: 62, alignment: .top)

            // Harness Section (Always rendered so cards have identical visual rhythm & height)
            harnessStripSection(
                title: s.t("已上报 Agent Harness", "Reported Harnesses"),
                harnesses: harnesses,
                isInteractive: dev.isOnline,
                onTapHarness: { h in
                    onSelectNodeForChat(dev.hostId, h)
                }
            )

            Spacer(minLength: 0)

            // Footer Actions
            HStack(spacing: 8) {
                monochromePrimaryButton(
                    title: s.t("选择此节点执行", "Run on Node"),
                    icon: "paperplane.fill",
                    disabled: !dev.isOnline
                ) {
                    onSelectNodeForChat(dev.hostId, harnesses.first)
                }

                monochromeSecondaryButton(
                    title: s.t("远程排查", "Inspect"),
                    icon: "stethoscope",
                    disabled: !dev.isOnline
                ) {
                    onInspectRemoteNode(dev)
                }

                Spacer()

                Text("hostId: \(dev.hostId.prefix(10))")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(PipiTokens.textMuted)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 236, alignment: .topLeading)
        .background(PipiTokens.bgSurface)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PipiTokens.borderSubtle, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Reusable Polished Components

    private func harnessStripSection(
        title: String,
        harnesses: [String],
        isInteractive: Bool,
        onTapHarness: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(PipiTokens.textMuted)

            if harnesses.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "terminal")
                        .font(.system(size: 10, weight: .medium))
                    Text(s.t("未检测到外接 CLI Harness（支持远程 Shell 排查）", "No CLI harness detected (Shell diagnostics ready)"))
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
                .foregroundStyle(PipiTokens.textMuted)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(PipiTokens.bgCanvas)
                .overlay(Capsule().stroke(PipiTokens.borderSubtle, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                .clipShape(Capsule())
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(harnesses, id: \.self) { h in
                            Button {
                                if isInteractive { onTapHarness(h) }
                            } label: {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(isInteractive ? PipiTokens.stateSuccess : PipiTokens.textMuted.opacity(0.5))
                                        .frame(width: 5, height: 5)
                                    Text(h)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(PipiTokens.textPrimary)
                                }
                                .padding(.horizontal, 9)
                                .frame(height: 24)
                                .background(PipiTokens.bgCanvas)
                                .overlay(Capsule().stroke(PipiTokens.borderSubtle, lineWidth: 1))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(!isInteractive)
                        }
                    }
                }
            }
        }
        .frame(height: 44, alignment: .topLeading)
    }

    private func resourceMeter(label: String, valueText: String, ratio: Double) -> some View {
        let clamped = min(1.0, max(0.0, ratio))
        let pct = Int((clamped * 100).rounded())
        let fillColor: Color = clamped > 0.85 ? Color.red.opacity(0.85) : (clamped > 0.65 ? PipiTokens.stateWarning : PipiTokens.stateSuccess.opacity(0.88))

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PipiTokens.textSecondary)
                Spacer()
                Text(valueText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(PipiTokens.textPrimary)
                Text("\(pct)%")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PipiTokens.textMuted)
                    .frame(minWidth: 28, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(PipiTokens.bgCanvas)
                        .overlay(Capsule().stroke(PipiTokens.borderSubtle.opacity(0.6), lineWidth: 0.5))
                    Capsule()
                        .fill(fillColor)
                        .frame(width: max(8, geo.size.width * clamped))
                }
            }
            .frame(height: 6)
        }
    }

    private func tagPill(_ text: String, highlighted: Bool) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(highlighted ? PipiTokens.textInverse : PipiTokens.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(highlighted ? PipiTokens.textPrimary : PipiTokens.bgCanvas)
            .overlay(Capsule().stroke(highlighted ? Color.clear : PipiTokens.borderSubtle, lineWidth: 1))
            .clipShape(Capsule())
    }

    private func monochromePrimaryButton(title: String, icon: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(PipiTokens.textInverse)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(PipiTokens.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1.0)
    }

    private func monochromeSecondaryButton(title: String, icon: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .medium))
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(PipiTokens.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(PipiTokens.bgCanvas)
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(PipiTokens.borderSubtle, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1.0)
    }

    private func refreshAllTelemetry() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await store.accountClient.refreshProfile()
        let onlineRemotes = store.enrolledRemoteDevices.filter(\.isOnline)
        await withTaskGroup(of: (String, PipiRemoteNodeLiveTelemetry?).self) { group in
            for dev in onlineRemotes {
                group.addTask {
                    let info = await store.fetchRemoteNodeTelemetry(device: dev)
                    return (dev.hostId, info)
                }
            }
            for await (hostId, info) in group {
                if let info {
                    remoteTelemetry[hostId] = info
                }
            }
        }
    }
}
