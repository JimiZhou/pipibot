// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
//
// Apple-Native Flagship Floating Voice Companion Sheet:
// Soft ambient aura behind the living procedural avatar, Apple Music-style edge-faded
// borderless transcript, centered glass segmented switcher, and Liquid Glass controls.

import SwiftUI
import PipiBotKit

public struct PipiIOSVoiceSheetView: View {
    @Bindable public var store: PipiAppStore
    public var onDismiss: () -> Void
    public var onHaptic: (PipiIOSCompanionRootView.HapticKind) -> Void

    @State private var activePane: Int = 0 // 0 = Live Transcript, 1 = Quick Ask
    @State private var quickAskDraft: String = ""
    @State private var elapsedSeconds: Int = 0
    @State private var timerTask: Task<Void, Never>?

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
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }
    private var activeAccent: Color { PipiTokens.color(for: store.activePersona.accent) }

    private var formattedTimer: String {
        let mins = elapsedSeconds / 60
        let secs = elapsedSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private var liveStatusLabel: String {
        if store.isVoiceCallActive {
            return store.isVoiceCallMuted
                ? s.t("已静音", "Muted")
                : s.t("语音通话中", "In voice call")
        }
        switch store.voiceSessionState {
        case .listening:
            return s.t("正在聆听…", "Listening…")
        case .transcribing:
            return s.t("正在转写…", "Transcribing…")
        case .speaking:
            return s.t("正在回复…", "Speaking…")
        default:
            return s.t("轻点下方开始对话", "Tap below to speak")
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Drag Handle & Quiet Borderless Header
            VStack(spacing: PipiTokens.spacing12) {
                Capsule()
                    .fill(PipiTokens.borderStrong.opacity(0.65))
                    .frame(width: 36, height: 4)
                    .padding(.top, 10)

                HStack(spacing: PipiTokens.spacing8) {
                    Circle()
                        .fill(store.isVoiceCallActive || store.voiceSessionState == .listening ? PipiTokens.stateError : PipiTokens.stateSuccess)
                        .frame(width: 6.5, height: 6.5)

                    Text(store.activePersona.name(lang))
                        .font(PipiTokens.fontSubheadline.weight(.medium))
                        .foregroundStyle(PipiTokens.textPrimary)

                    Text(formattedTimer)
                        .font(PipiTokens.fontMonoSmall)
                        .monospacedDigit()
                        .foregroundStyle(PipiTokens.textMuted)

                    Spacer()

                    Button {
                        onHaptic(.light)
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(PipiTokens.textSecondary)
                            .frame(width: 30, height: 30)
                            .background(PipiTokens.bgSurface, in: Circle())
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
                }
                .padding(.horizontal, PipiTokens.spacing20)
            }

            // Living Procedural Avatar Stage with Soft Optical Radial Aura
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                stops: [
                                    .init(color: PipiTokens.voiceAuraPrimary, location: 0.0),
                                    .init(color: PipiTokens.voiceAuraSecondary, location: 0.48),
                                    .init(color: Color.clear, location: 1.0)
                                ],
                                center: .center,
                                startRadius: 20,
                                endRadius: 96
                            )
                        )
                        .frame(width: 192, height: 192)

                    PipiAvatarView(
                        engine: store.avatarEngine,
                        size: 108,
                        accentOverride: activeAccent,
                        personaAccent: store.activePersona.accent,
                        motif: PipiPersonaMotif.resolve(for: store.activePersona)
                    )
                }
                .padding(.top, 8)

                Text(liveStatusLabel)
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.textSecondary)
            }

            // Apple Native Centered Segmented Pill Switcher
            HStack(spacing: 2) {
                paneSegmentButton(title: s.t("实时转写", "Transcript"), index: 0)
                paneSegmentButton(title: s.t("顺手提问", "Ask"), index: 1)
            }
            .padding(3)
            .background(PipiTokens.bgSurface, in: Capsule())
            .frame(width: 196)
            .padding(.top, 16)

            // Pane Content — Borderless Editorial Lyrics with Soft Top/Bottom Edge Fade
            if activePane == 0 {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        let transcript = store.voiceLiveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !transcript.isEmpty {
                            Text(transcript)
                                .font(PipiTokens.fontBody)
                                .foregroundStyle(PipiTokens.textPrimary)
                                .lineSpacing(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if let latest = store.activeConversation?.messages.last {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(latest.role == .user ? s.t("你刚才说", "You said") : store.activePersona.name(lang))
                                    .font(PipiTokens.fontMicro.weight(.medium))
                                    .foregroundStyle(PipiTokens.textMuted)
                                formattedTranscriptBody(latest.content)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(s.t("直接开口说任务、想法或日程，PiPi 会边听边整理并帮你推进到底。", "Speak naturally about any task, idea, or reminder. PiPi listens, transcribes, and executes end-to-end."))
                                .font(PipiTokens.fontBody)
                                .foregroundStyle(PipiTokens.textMuted)
                                .lineSpacing(5)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 12)
                        }
                    }
                    .padding(.horizontal, PipiTokens.spacing24)
                    .padding(.vertical, 18)
                }
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black, location: 0.08),
                            .init(color: .black, location: 0.84),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            } else {
                VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                    Text(s.t("不打断语音，顺手发一条文字指令给助手", "Send a quick follow-up without interrupting voice mode"))
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)

                    HStack(spacing: PipiTokens.spacing8) {
                        TextField(s.t("顺手记一笔或派个任务…", "Ask something or assign a task…"), text: $quickAskDraft)
                            .textFieldStyle(.plain)
                            .font(PipiTokens.fontBody)
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background(PipiTokens.bgSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                        Button {
                            let clean = quickAskDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !clean.isEmpty else { return }
                            quickAskDraft = ""
                            onHaptic(.light)
                            Task { await store.sendPersonalMessage(clean) }
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(PipiTokens.textInverse)
                                .frame(width: 40, height: 40)
                                .background(PipiTokens.soulPrimary, in: Circle())
                        }
                        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
                    }

                    Spacer()
                }
                .padding(.horizontal, PipiTokens.spacing24)
                .padding(.vertical, 18)
            }

            // Bottom Apple Liquid Glass Tactile Controls
            HStack(spacing: 14) {
                Button {
                    onHaptic(.light)
                    store.toggleVoiceCallMute()
                } label: {
                    Image(systemName: store.isVoiceCallMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(store.isVoiceCallMuted ? PipiTokens.stateError : PipiTokens.textPrimary)
                        .frame(width: 52, height: 52)
                        .pipiLiquidGlassCapsule()
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
                .accessibilityLabel(store.isVoiceCallMuted ? s.t("取消静音", "Unmute") : s.t("静音", "Mute"))

                Button {
                    onHaptic(.medium)
                    if store.isVoiceCallActive {
                        store.endVoiceCall()
                        onDismiss()
                    } else {
                        Task { await store.startVoiceCall(with: store.activePersona.id) }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: store.isVoiceCallActive ? "phone.down.fill" : "waveform")
                            .font(.system(size: 16, weight: .medium))
                        Text(store.isVoiceCallActive ? s.t("结束通话", "End call") : s.t("开始语音对话", "Start voice"))
                            .font(PipiTokens.fontSubheadline.weight(.medium))
                    }
                    .foregroundStyle(PipiTokens.textInverse)
                    .padding(.horizontal, 26)
                    .frame(height: 52)
                    .background(store.isVoiceCallActive ? PipiTokens.stateError : PipiTokens.soulPrimary, in: Capsule())
                    .shadow(color: PipiTokens.shadowKey, radius: 12, x: 0, y: 4)
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.95))
            }
            .padding(.horizontal, PipiTokens.spacing20)
            .padding(.top, 8)
            .padding(.bottom, 22)
        }
        .background(PipiTokens.bgCanvas.ignoresSafeArea())
        .onAppear {
            timerTask?.cancel()
            timerTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    if store.isVoiceCallActive || store.voiceSessionState == .listening || store.voiceSessionState == .speaking {
                        elapsedSeconds += 1
                    }
                }
            }
        }
        .onDisappear {
            timerTask?.cancel()
            timerTask = nil
        }
    }

    @ViewBuilder
    private func formattedTranscriptBody(_ raw: String) -> some View {
        let lines = raw.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.prefix(5).enumerated()), id: \.offset) { _, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") || trimmed.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(PipiTokens.textMuted.opacity(0.6))
                            .frame(width: 4, height: 4)
                            .offset(y: -2)
                        inlineMarkdownText(String(trimmed.dropFirst(2)))
                    }
                } else {
                    inlineMarkdownText(trimmed)
                }
            }
        }
    }

    private func inlineMarkdownText(_ text: String) -> some View {
        Group {
            if let parsed = try? AttributedString(
                markdown: text,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) {
                Text(parsed)
            } else {
                Text(text)
            }
        }
        .font(PipiTokens.fontBody)
        .foregroundStyle(PipiTokens.textPrimary)
        .lineSpacing(4.5)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func paneSegmentButton(title: String, index: Int) -> some View {
        let isSelected = activePane == index
        return Button {
            withAnimation(PipiMotion.press) {
                activePane = index
            }
            onHaptic(.light)
        } label: {
            Text(title)
                .font(PipiTokens.fontCaption.weight(isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(isSelected ? PipiTokens.cardSurface : Color.clear, in: Capsule())
                .shadow(color: isSelected ? PipiTokens.shadowAmbient : .clear, radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}
