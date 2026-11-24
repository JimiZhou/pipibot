// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
//
// Read-Only Consumer Transparency Sheet: Agent Sandbox Execution Activity.
// The mobile sandbox shell & Apple JavaScriptCore engine exist strictly for autonomous
// Agent execution (`run_shell` / `run_script`) — users never type raw shell commands.
// This quiet warm-paper sheet lets curious users audit what the Agent ran on-device or
// relayed over E2EE to an enrolled Mac/Linux host.

import SwiftUI
import PipiBotKit

public struct PipiIOSTerminalSheetView: View {
    @Bindable public var store: PipiAppStore
    public var onDismiss: () -> Void
    public var onHaptic: (PipiIOSCompanionRootView.HapticKind) -> Void

    @State private var terminalLog = PipiMobileTerminalLog.shared

    public init(
        store: PipiAppStore,
        onDismiss: @escaping () -> Void,
        onHaptic: @escaping (PipiIOSCompanionRootView.HapticKind) -> Void = { _ in }
    ) {
        self.store = store
        self.onDismiss = onDismiss
        self.onHaptic = onHaptic
    }

    private var s: PipiStrings { store.strings }
    private var onlineRemoteHostsCount: Int {
        store.enrolledRemoteDevices.filter(\.isOnline).count
    }

    public var body: some View {
        VStack(spacing: 0) {
            activityHeader
            Rectangle()
                .fill(PipiTokens.borderSubtle)
                .frame(height: 1)

            activityFeed
        }
        .background(PipiTokens.bgWindowTray.ignoresSafeArea())
    }

    // MARK: - Quiet Consumer Header

    private var activityHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.t("助手沙箱执行记录", "Agent sandbox activity"))
                    .font(PipiTokens.fontSubheadline.weight(.medium))
                    .foregroundStyle(PipiTokens.textPrimary)

                HStack(spacing: 6) {
                    Circle()
                        .fill(PipiTokens.stateSuccess)
                        .frame(width: 6, height: 6)
                    Text(
                        onlineRemoteHostsCount > 0
                            ? s.t(
                                "本机沙箱就绪 · \(onlineRemoteHostsCount) 台远程节点在线",
                                "Sandbox ready · \(onlineRemoteHostsCount) remote online"
                            )
                            : s.t("本机 POSIX + JSC 沙箱由助手自动调度", "Managed automatically by your assistant")
                    )
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.textMuted)
                    .lineLimit(1)
                }
            }

            Spacer()

            if !terminalLog.entries.isEmpty {
                Button {
                    terminalLog.clear()
                    onHaptic(.light)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(PipiTokens.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(PipiTokens.bgCanvas, in: Circle())
                        .overlay(Circle().stroke(PipiTokens.sheetBorder, lineWidth: 1))
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
                .accessibilityLabel(s.t("清空执行记录", "Clear activity log"))
            }

            Button {
                onHaptic(.light)
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PipiTokens.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(PipiTokens.bgCanvas, in: Circle())
                    .overlay(Circle().stroke(PipiTokens.sheetBorder, lineWidth: 1))
            }
            .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
            .accessibilityLabel(s.t("关闭", "Close"))
        }
        .padding(.horizontal, PipiTokens.spacing16)
        .padding(.vertical, 14)
    }

    // MARK: - Read-Only Activity Stream

    private var activityFeed: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                    if terminalLog.entries.isEmpty {
                        emptyInfoCard
                    } else {
                        ForEach(terminalLog.entries) { entry in
                            executionRecordCard(entry)
                                .id(entry.id)
                        }
                    }
                }
                .padding(.horizontal, PipiTokens.spacing16)
                .padding(.vertical, PipiTokens.spacing16)
            }
            .onChange(of: terminalLog.entries.count) { _, _ in
                if let lastId = terminalLog.entries.last?.id {
                    withAnimation(PipiMotion.open) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "cpu")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(PipiTokens.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(PipiTokens.bgSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(s.t("后台自动运行，无需手动操作", "Autonomous agent runtime"))
                        .font(PipiTokens.fontSubheadline.weight(.medium))
                        .foregroundStyle(PipiTokens.textPrimary)
                    Text(s.t("仅对助手开放的隔离执行环境", "Isolated execution sandbox for your assistant"))
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textMuted)
                }
            }

            Text(s.t(
                "当你让助手做数据计算、整理本地文件、解析表格或排查远程服务器时，它会自动在 iPhone 沙箱或已配对的 Mac/Linux 节点上执行，并把每一步运行结果透明记录在这里。",
                "When your assistant runs calculations, parses data, organizes files, or troubleshoots your Mac/Linux host, every sandbox step is logged transparently here — no command line required."
            ))
            .font(PipiTokens.fontCaption)
            .foregroundStyle(PipiTokens.textSecondary)
            .lineSpacing(4)
        }
        .padding(PipiTokens.spacing16)
        .pipiAppleCard(cornerRadius: 16, elevated: false)
    }

    private func executionRecordCard(_ entry: PipiTerminalTranscriptEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(entry.exitCode == 0 ? PipiTokens.stateSuccess : PipiTokens.stateError)
                    .frame(width: 6, height: 6)
                Text(entry.targetLabel)
                    .font(PipiTokens.fontMicro.weight(.medium))
                    .foregroundStyle(PipiTokens.textMuted)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(entry.exitCode == 0 ? "\(entry.durationMs)ms" : "exit \(entry.exitCode) · \(entry.durationMs)ms")
                    .font(PipiTokens.fontMicro)
                    .monospacedDigit()
                    .foregroundStyle(entry.exitCode == 0 ? PipiTokens.textMuted : PipiTokens.stateError)
            }

            Text(entry.command)
                .font(PipiTokens.fontMonoSmall.weight(.medium))
                .foregroundStyle(PipiTokens.textPrimary)
                .lineSpacing(2.5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !entry.output.isEmpty {
                Rectangle()
                    .fill(PipiTokens.borderSubtle)
                    .frame(height: 1)

                Text(entry.output)
                    .font(PipiTokens.fontMonoSmall)
                    .foregroundStyle(entry.exitCode == 0 ? PipiTokens.textSecondary : PipiTokens.stateError)
                    .lineSpacing(3.5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .pipiAppleCard(cornerRadius: 14, elevated: false)
    }
}
