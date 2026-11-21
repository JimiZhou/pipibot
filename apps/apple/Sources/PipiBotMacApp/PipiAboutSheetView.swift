// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.

import SwiftUI
import PipiBotKit

#if os(macOS)
import AppKit
#endif

/// Dedicated centered About view launched from Settings footer (`PiPiBot / 版本`) and macOS About menu.
public struct PipiAboutSheetView: View {
    @Bindable public var store: PipiAppStore
    public var onClose: () -> Void

    @Environment(\.pipiTextScale) private var textScale

    public init(store: PipiAppStore, onClose: @escaping () -> Void) {
        self.store = store
        self.onClose = onClose
    }

    private var s: PipiStrings { store.strings }

    public var body: some View {
        let _ = textScale
        VStack(spacing: 0) {
            // Minimal header bar with close action
            HStack {
                Text(s.aboutTitle)
                    .font(PipiTokens.fontHeadline)
                    .foregroundStyle(PipiTokens.textPrimary)
                Spacer()
                PipiGhostIconButton(
                    systemImage: "xmark",
                    size: 28,
                    iconSize: 12,
                    cornerRadius: PipiTokens.radiusPill,
                    accessibilityLabel: s.close,
                    action: onClose
                )
            }
            .padding(.horizontal, PipiTokens.spacing20)
            .padding(.vertical, PipiTokens.spacing12)
            .background(PipiTokens.bgCanvas)

            Rectangle()
                .fill(PipiTokens.borderSubtle)
                .frame(height: 1)

            ScrollView(showsIndicators: false) {
                VStack(spacing: PipiTokens.spacing20) {
                    // Centered Brand Hero: Light Porcelain Icon + Title + Version + Slogan
                    VStack(spacing: PipiTokens.spacing12) {
                        aboutHeroIcon

                        VStack(spacing: 6) {
                            Text(s.appName)
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                                .foregroundStyle(PipiTokens.textPrimary)

                            Text("\(s.versionLabel) \(store.appDisplayVersion)")
                                .font(PipiTokens.fontMonoSmall)
                                .foregroundStyle(PipiTokens.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(PipiTokens.bgElevated)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
                                )
                                .clipShape(Capsule())

                            aboutUpdateControls
                        }

                        Text(
                            s.t(
                                "个人智能体工作台 · 端侧优先 · 多助手协同",
                                "Personal AI Agent Workspace · Local-First · Multi-Agent Collaboration"
                            )
                        )
                        .font(PipiTokens.fontSubheadline.weight(.medium))
                        .foregroundStyle(PipiTokens.textSecondary)
                        .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, PipiTokens.spacing8)

                    // 1. Design Inspiration
                    aboutCard(title: s.t("设计灵感", "Design Inspiration")) {
                        Text(
                            s.t(
                                "PiPiBot 源于对「个人端侧数字团队」的长期探索：将统一大模型路由、本机原生系统能力（信息、邮件、日程、截屏录屏、本地编译打包与语音通话）、独立经验记忆、3D 空间陪伴视图以及零门槛远程操控（Cloudflare Tunnel PWA 与微信 iLink）融合于轻盈克制的原生 macOS 体验之中，让 AI 从孤立对话框演进为数据完全归属本机、可持续协作与自我进化的个人智能体工作台。",
                                "PiPiBot was inspired by the vision of a local-first personal digital team: uniting multi-model routing, native macOS system capabilities (Messages, Mail, Calendar, screen capture, local dev/build workflows, and live voice calls), isolated experiential memory, a 3D spatial presence studio, and zero-infrastructure remote control (Cloudflare Tunnel PWA & WeChat iLink) inside a calm native workspace."
                            )
                        )
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    // 2. License & Clean-Room Statement
                    aboutCard(title: s.t("开源许可（License）", "Open Source License")) {
                        VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                            HStack(spacing: PipiTokens.spacing8) {
                                Text("MIT License")
                                    .font(PipiTokens.fontSubheadline.weight(.semibold))
                                    .foregroundStyle(PipiTokens.textPrimary)
                                Spacer()
                                Text("Copyright © 2026 JimiZhou & PipiBot Contributors")
                                    .font(PipiTokens.fontMicro)
                                    .foregroundStyle(PipiTokens.textMuted)
                            }
                            Text(
                                s.t(
                                    "本仓库依据 MIT 协议开源。所有源码、提示词、界面组件与视觉资产均为独立洁净室（Clean-Room）原创实现；借鉴上游架构与交互思想时严格遵循许可边界，零拷贝任何非 MIT 项目的源码、文案模板或素材。",
                                    "Released under the MIT License. All source code, prompts, UI components, and visual assets in this repository are original clean-room implementations with zero verbatim code or assets copied from non-MIT repositories."
                                )
                            )
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                            .lineSpacing(3.5)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // 3. Upstream Acknowledgments
                    aboutCard(title: s.t("致谢上游项目", "Upstream Acknowledgments")) {
                        VStack(alignment: .leading, spacing: 0) {
                            creditRow(
                                name: "simplexai-labs/linger",
                                license: "Linger Open Source License（洁净室架构参考）",
                                detail: s.t(
                                    "架构与交互理念启发（零源码与资产复制）：7 级优先级抢占调度、双层风险审批护栏、个人实体 Wiki、助手独立经验记忆、后台分身协作与桌面通道礼让机制。",
                                    "Architectural & UX inspiration only (zero code/assets copied): priority scheduling, two-tier guardrails, personal Wiki, isolated bot memory, background delegation, and desktop yield lanes."
                                )
                            )
                            creditDivider
                            creditRow(
                                name: "simplexai-labs/PolyStrata & Niko1221/Strata",
                                license: "MIT License",
                                detail: s.t(
                                    "可选本地 MoE 推理引擎适配与模型目录集成，支持 Apple Silicon 统一内存与 SSD 按层预取。",
                                    "Optional external local MoE inference adapter and model catalog integration for Apple Silicon unified memory + SSD prefetch."
                                )
                            )
                            creditDivider
                            creditRow(
                                name: "Pi Coding Agent (@mariozechner/pi-coding-agent)",
                                license: "MIT License",
                                detail: s.t(
                                    "极简可扩展智能体内核与工具钩子设计思路启发。",
                                    "Architectural inspiration for minimalist extensible agent kernel and tool extension hooks."
                                )
                            )
                            creditDivider
                            creditRow(
                                name: "Devin Bots · OpenPencil · Cloudflare Tunnel · WeChat iLink",
                                license: "Ecosystem & Protocols",
                                detail: s.t(
                                    "结果导向待办确认范式、三层设计令牌治理规范、Cloudflare Quick Tunnel 安全隧道及微信官方 iLink Bot 接入协议。",
                                    "Outcome-oriented approvals, 3-tier design token governance, Cloudflare Quick Tunnel, and WeChat iLink Bot HTTP protocol."
                                )
                            )
                        }
                    }

                    HStack(spacing: PipiTokens.spacing12) {
                        PipiActionButton(s.close, tone: .secondary, density: .desktopCompact) {
                            onClose()
                        }
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: 540)
                .padding(.horizontal, PipiTokens.spacing24)
                .padding(.vertical, PipiTokens.spacing20)
                .frame(maxWidth: .infinity)
            }
            .pipiHideScrollbars()
            .background(PipiTokens.bgCanvas)
        }
        .preferredColorScheme(store.themeMode.colorSchemeOverride)
    }

    @ViewBuilder
    private var aboutHeroIcon: some View {
        #if os(macOS)
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let nsImage = NSImage(contentsOf: iconURL) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 82, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: PipiTokens.subtleShadow, radius: 12, y: 4)
        } else {
            fallbackHeroLogo
        }
        #else
        fallbackHeroLogo
        #endif
    }

    private var fallbackHeroLogo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(PipiTokens.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
                )
            PipiBotLogoMark(size: 56)
        }
        .frame(width: 82, height: 82)
        .shadow(color: PipiTokens.subtleShadow, radius: 12, y: 4)
    }

    private func aboutCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
            Text(title)
                .font(PipiTokens.fontCaption.weight(.semibold))
                .foregroundStyle(PipiTokens.textSecondary)

            VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PipiTokens.bgElevated)
            .overlay(
                RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                    .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func creditRow(name: String, license: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: PipiTokens.spacing8) {
                Text(name)
                    .font(PipiTokens.fontSubheadline.weight(.semibold))
                    .foregroundStyle(PipiTokens.textPrimary)
                Spacer(minLength: 8)
                Text(license)
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.textMuted)
            }
            Text(detail)
                .font(PipiTokens.fontCaption)
                .foregroundStyle(PipiTokens.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }

    private var creditDivider: some View {
        Rectangle()
            .fill(PipiTokens.borderSubtle)
            .frame(height: 1)
    }

    @ViewBuilder
    private var aboutUpdateControls: some View {
        switch store.updateManager.state {
        case .idle, .upToDate:
            HStack(spacing: PipiTokens.spacing8) {
                if case .upToDate(_, _) = store.updateManager.state {
                    Text(s.t("已是最新版本", "Up to date"))
                        .font(PipiTokens.fontMicro)
                        .foregroundStyle(PipiTokens.stateSuccess)
                }
                PipiActionButton(
                    s.t("检查更新", "Check for Updates"),
                    systemImage: "arrow.triangle.2.circlepath",
                    tone: .secondary,
                    density: .desktopCompact
                ) {
                    Task {
                        _ = await store.updateManager.checkForUpdates(currentVersion: store.appDisplayVersion, silent: false)
                    }
                }
            }
            .padding(.top, 4)

        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(s.t("正在检查 GitHub Release...", "Checking GitHub Releases..."))
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.textSecondary)
            }
            .padding(.top, 4)

        case .updateAvailable(let rel):
            VStack(spacing: 6) {
                Text(s.t("发现新版本 \(rel.tagName)", "New release \(rel.tagName) available"))
                    .font(PipiTokens.fontCaption.weight(.semibold))
                    .foregroundStyle(PipiTokens.stateSuccess)
                PipiActionButton(
                    s.t("下载并自动更新到 \(rel.tagName)", "Download & Install \(rel.tagName)"),
                    systemImage: "arrow.down.circle.fill",
                    tone: .primary,
                    density: .desktopCompact
                ) {
                    store.updateManager.downloadAndInstallUpdate(rel) {
                        store.flush()
                    }
                }
            }
            .padding(.top, 4)

        case .downloading(_, let progress):
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .frame(width: 140)
                Text(s.t("下载中 \(Int(progress * 100))%", "Downloading \(Int(progress * 100))%"))
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.textSecondary)
            }
            .padding(.top, 4)

        case .verifying:
            Text(s.t("正在校验 SHA-256 与代码签名...", "Verifying checksum & signature..."))
                .font(PipiTokens.fontMicro)
                .foregroundStyle(PipiTokens.textSecondary)
                .padding(.top, 4)

        case .installing:
            Text(s.t("正在安装并重启应用...", "Installing & relaunching..."))
                .font(PipiTokens.fontMicro)
                .foregroundStyle(PipiTokens.stateSuccess)
                .padding(.top, 4)

        case .error(let msg):
            VStack(spacing: 6) {
                Text(msg)
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.stateError)
                    .multilineTextAlignment(.center)
                PipiActionButton(
                    s.t("重试检查", "Retry"),
                    systemImage: "arrow.clockwise",
                    tone: .secondary,
                    density: .desktopCompact
                ) {
                    Task {
                        _ = await store.updateManager.checkForUpdates(currentVersion: store.appDisplayVersion, silent: false)
                    }
                }
            }
            .padding(.top, 4)
        }
    }
}
