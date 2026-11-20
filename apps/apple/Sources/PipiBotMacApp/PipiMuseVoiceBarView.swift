// PiPiBot — Clean-room MIT implementation.
// Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
// Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.

import SwiftUI
import PipiBotKit

/// Personal Daily Voice & Live Voice Call Bar (Dictation · Live Phone Call · Voice Task).
/// On-device first with Echo-Gated VAD interruption, multi-voice timbre support, and optional cloud voice APIs.
public struct PipiMuseVoiceBarView: View {
    @Bindable public var store: PipiAppStore
    public var onInsertDictation: (String) -> Void
    public var onOpenVoiceSettings: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var manualVoiceText: String = ""

    public init(
        store: PipiAppStore,
        onInsertDictation: @escaping (String) -> Void = { _ in },
        onOpenVoiceSettings: @escaping () -> Void = {}
    ) {
        self.store = store
        self.onInsertDictation = onInsertDictation
        self.onOpenVoiceSettings = onOpenVoiceSettings
    }

    private var s: PipiStrings { store.strings }
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }

    private var isCapturing: Bool {
        store.voiceSessionState == .listening || store.voiceSessionState == .transcribing || store.voiceSessionState == .interrupted
    }

    private var callPersona: PipiBotPersona {
        if let pid = store.voiceCallPersonaId,
           let matched = store.personas.first(where: { $0.id == pid }) {
            return matched
        }
        return store.activePersona
    }

    private var activeTimbreLabel: String {
        let profileId = store.effectiveVoiceProfileId(for: callPersona.id)
        return PipiDailyVoiceEngine.resolveTimbre(id: profileId).displayName(lang)
    }

    private var stateDotColor: Color {
        switch store.voiceSessionState {
        case .listening, .transcribing: return PipiTokens.stateSuccess
        case .speaking: return PipiTokens.soulPrimary
        case .interrupted: return PipiTokens.stateWarning
        case .thinking: return PipiTokens.textPrimary
        case .error: return PipiTokens.stateError
        case .idle: return PipiTokens.textMuted
        }
    }

    public var body: some View {
        Group {
            if store.isVoiceCallActive {
                livePhoneCallCard
            } else {
                standardVoiceBar
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(PipiTokens.composerSurface)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .strokeBorder(
                    store.isVoiceCallActive ? PipiTokens.stateSuccess.opacity(0.45) : PipiTokens.composerBorder,
                    lineWidth: store.isVoiceCallActive ? 1.25 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
        .shadow(color: PipiTokens.composerShadow, radius: 10, y: 4)
    }

    // MARK: - Dedicated Live Phone Call Panel

    private var livePhoneCallCard: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            HStack(spacing: PipiTokens.spacing12) {
                ZStack(alignment: .bottomTrailing) {
                    PipiBotPersonaGlyph(persona: callPersona, size: 36, isSelected: true)
                    Circle()
                        .fill(store.isVoiceCallMuted ? PipiTokens.stateWarning : stateDotColor)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(PipiTokens.composerSurface, lineWidth: 1.5))
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: PipiTokens.spacing8) {
                        Text(callPersona.name(lang))
                            .font(PipiTokens.fontSubheadline.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                            .lineLimit(1)

                        Text(store.isVoiceCallMuted ? s.t("已静音", "Muted") : store.voiceSessionState.label(lang))
                            .font(PipiTokens.fontMicro.weight(.medium))
                            .foregroundStyle(store.isVoiceCallMuted ? PipiTokens.stateWarning : stateDotColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(PipiTokens.bgSurfaceHover, in: Capsule())

                        if let started = store.voiceCallStartedAt {
                            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                                let secs = max(0, Int(context.date.timeIntervalSince(started)))
                                Text(String(format: "%02d:%02d", secs / 60, secs % 60))
                                    .font(PipiTokens.fontMonoSmall)
                                    .monospacedDigit()
                                    .foregroundStyle(PipiTokens.textMuted)
                            }
                        }
                    }

                    Text(activeTimbreLabel)
                        .font(PipiTokens.fontMicro)
                        .foregroundStyle(PipiTokens.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                vadLevelMeter

                // Call Controls: Mute, Interrupt/Send, Settings, Hang Up
                HStack(spacing: PipiTokens.spacing8) {
                    Button {
                        store.toggleVoiceCallMute()
                    } label: {
                        Image(systemName: store.isVoiceCallMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(store.isVoiceCallMuted ? PipiTokens.stateWarning : PipiTokens.textPrimary)
                            .frame(width: 32, height: 32)
                            .background(PipiTokens.buttonSecondaryBg, in: Circle())
                            .overlay(Circle().strokeBorder(PipiTokens.composerBorder, lineWidth: 1))
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
                    .help(store.isVoiceCallMuted ? s.t("取消静音", "Unmute") : s.t("静音", "Mute"))

                    if store.voiceSessionState == .speaking {
                        PipiActionButton(s.t("打断", "Interrupt"), systemImage: "hand.raised.fill", tone: .secondary, density: .desktopCompact) {
                            store.interruptVoicePlayback()
                            Task { await store.startVoiceCapture(mode: .museHandsFree) }
                        }
                    } else if !store.voiceLiveTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        PipiActionButton(s.t("发送", "Send"), systemImage: "arrow.up", tone: .primary, density: .desktopCompact) {
                            Task { await store.stopVoiceCapture(commitTranscript: true) }
                        }
                    }

                    PipiGhostIconButton(
                        systemImage: "slider.horizontal.3",
                        size: 30,
                        iconSize: 12,
                        accessibilityLabel: s.settingsVoice,
                        action: onOpenVoiceSettings
                    )

                    Button {
                        store.endVoiceCall()
                    } label: {
                        Image(systemName: "phone.down.fill")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(PipiTokens.textInverse)
                            .frame(width: 36, height: 32)
                            .background(PipiTokens.stateError, in: Capsule())
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
                    .help(s.t("挂断通话", "End Call"))
                    .accessibilityLabel(s.t("挂断通话", "End Call"))
                }
            }

            // Live Speech Recognition Transcript or Error / Text Fallback
            if !store.voiceLiveTranscript.isEmpty {
                Text(store.voiceLiveTranscript)
                    .font(PipiTokens.fontBody)
                    .foregroundStyle(PipiTokens.textPrimary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(PipiTokens.bgInset, in: RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
            } else if let err = store.voiceLastError, !err.isEmpty {
                HStack(spacing: PipiTokens.spacing8) {
                    Text(err)
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.stateError)
                        .lineLimit(2)
                    Spacer()
                    PipiActionButton(s.t("重试收音", "Retry Mic"), tone: .secondary, density: .desktopCompact) {
                        Task { await store.startVoiceCapture(mode: .museHandsFree) }
                    }
                }
            } else {
                HStack(spacing: PipiTokens.spacing8) {
                    PipiTextField(
                        s.t("正在语音聆听，也可直接键入内容进行语音回复...", "Listening via mic, or type here for spoken reply..."),
                        text: $manualVoiceText,
                        height: 30
                    ) {
                        submitCallTextFallback()
                    }
                    if !manualVoiceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        PipiActionButton(s.send, systemImage: "arrow.up", tone: .primary, density: .desktopCompact) {
                            submitCallTextFallback()
                        }
                    }
                }
            }
        }
    }

    private func submitCallTextFallback() {
        let text = manualVoiceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        manualVoiceText = ""
        Task {
            _ = await store.dispatchVoiceUtterance(text, mode: .museHandsFree)
        }
    }

    // MARK: - Standard Voice Dictation & Task Bar

    private var standardVoiceBar: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            HStack(spacing: PipiTokens.spacing8) {
                Circle()
                    .fill(stateDotColor)
                    .frame(width: 8, height: 8)

                Text(store.voiceSessionState.label(lang))
                    .font(PipiTokens.fontCaption.weight(.semibold))
                    .foregroundStyle(PipiTokens.textPrimary)

                HStack(spacing: 4) {
                    Image(systemName: store.voiceEngine.lastProviderUsed.isOnDevice ? "lock.shield" : "cloud")
                        .font(.system(size: 10, weight: .semibold))
                    Text(
                        store.voiceConfig.privacyPolicy == .onDeviceOnly
                            ? s.t("仅端侧", "On-Device")
                            : (store.voiceEngine.lastProviderUsed.isOnDevice
                                ? s.t("端侧优先", "On-Device")
                                : s.t("云端接口", "Cloud API"))
                    )
                    .font(PipiTokens.fontMicro)
                }
                .foregroundStyle(PipiTokens.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(PipiTokens.bgSurfaceHover)
                .clipShape(Capsule())

                Spacer(minLength: 6)

                HStack(spacing: 4) {
                    ForEach(PipiVoiceInteractionMode.allCases) { mode in
                        let selected = store.voiceActiveMode == mode
                        Button {
                            if mode == .museHandsFree {
                                Task { await store.startVoiceCall() }
                            } else {
                                store.voiceActiveMode = mode
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: mode.iconName)
                                    .font(.system(size: 10, weight: .semibold))
                                Text(mode.label(lang))
                                    .font(PipiTokens.fontMicro.weight(selected ? .semibold : .regular))
                            }
                            .foregroundStyle(selected ? PipiTokens.textInverse : PipiTokens.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(selected ? PipiTokens.soulPrimary : PipiTokens.bgSurfaceHover)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))
                    }
                }

                PipiGhostIconButton(
                    systemImage: "slider.horizontal.3",
                    size: 24,
                    iconSize: 11,
                    accessibilityLabel: s.settingsVoice,
                    action: onOpenVoiceSettings
                )

                PipiGhostIconButton(
                    systemImage: "xmark",
                    size: 24,
                    iconSize: 11,
                    accessibilityLabel: s.close
                ) {
                    Task {
                        await store.stopVoiceCapture(commitTranscript: false)
                        store.interruptVoicePlayback()
                        store.voiceIsOverlayPresented = false
                    }
                }
            }

            HStack(spacing: PipiTokens.spacing12) {
                vadLevelMeter

                VStack(alignment: .leading, spacing: 3) {
                    if !store.voiceLiveTranscript.isEmpty {
                        Text(store.voiceLiveTranscript)
                            .font(PipiTokens.fontBody)
                            .foregroundStyle(PipiTokens.textPrimary)
                            .lineLimit(3)
                    } else if let err = store.voiceLastError, !err.isEmpty {
                        Text(err)
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.stateError)
                            .lineLimit(2)
                    } else {
                        Text(s.t("点击麦克风开始语音输入，或切换至「语音通话」进行实时对话", "Click microphone to speak, or switch to Voice Call for live conversation"))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textMuted)
                    }
                }

                Spacer(minLength: 6)

                if store.voiceSessionState == .speaking {
                    PipiActionButton(
                        s.t("停止播报", "Interrupt"),
                        systemImage: "hand.raised.fill",
                        tone: .secondary,
                        density: .desktopCompact
                    ) {
                        store.interruptVoicePlayback()
                        Task { await store.startVoiceCapture(mode: store.voiceActiveMode) }
                    }
                } else if isCapturing {
                    PipiActionButton(
                        s.t("完成", "Done"),
                        systemImage: "stop.circle.fill",
                        tone: .primary,
                        density: .desktopCompact
                    ) {
                        Task {
                            let text = store.voiceLiveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                            if store.voiceActiveMode == .dictation {
                                await store.stopVoiceCapture(commitTranscript: false)
                                if !text.isEmpty {
                                    onInsertDictation(text)
                                }
                            } else {
                                await store.stopVoiceCapture(commitTranscript: true)
                            }
                        }
                    }
                } else {
                    PipiActionButton(
                        s.t("开始说话", "Start"),
                        systemImage: "mic.fill",
                        tone: .primary,
                        density: .desktopCompact
                    ) {
                        Task { await store.startVoiceCapture(mode: store.voiceActiveMode) }
                    }
                }
            }

            if store.voiceActiveMode == .voiceToTask {
                HStack(spacing: PipiTokens.spacing8) {
                    PipiTextField(
                        s.t("输入或口述任务内容", "Speak or type a task"),
                        text: $manualVoiceText,
                        height: 30
                    )

                    let effectivePayload = store.voiceLiveTranscript.isEmpty ? manualVoiceText : store.voiceLiveTranscript
                    let disabled = effectivePayload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                    PipiActionButton(s.t("后台执行", "Background"), systemImage: "person.2.wave.2", tone: .secondary, density: .desktopCompact) {
                        let text = effectivePayload
                        manualVoiceText = ""
                        Task { _ = await store.dispatchVoiceUtterance(text, mode: .voiceToTask, explicitAction: .delegateAlterEgo) }
                    }
                    .disabled(disabled)

                    PipiActionButton(s.t("记入待办", "To-Do"), systemImage: "checklist", tone: .ghost, density: .desktopCompact) {
                        let text = effectivePayload
                        manualVoiceText = ""
                        Task { _ = await store.dispatchVoiceUtterance(text, mode: .voiceToTask, explicitAction: .createTrackingItem) }
                    }
                    .disabled(disabled)

                    PipiActionButton(s.t("记入笔记", "Note"), systemImage: "note.text", tone: .ghost, density: .desktopCompact) {
                        let text = effectivePayload
                        manualVoiceText = ""
                        Task { _ = await store.dispatchVoiceUtterance(text, mode: .voiceToTask, explicitAction: .appendPocketNote) }
                    }
                    .disabled(disabled)
                }
            }
        }
    }

    private var vadLevelMeter: some View {
        let clamped = min(1.0, max(0.0, store.voiceInputLevel * 8.0))
        return HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { idx in
                let threshold = Double(idx + 1) * 0.18
                let active = (isCapturing && !store.isVoiceCallMuted && clamped >= threshold) || store.voiceSessionState == .speaking
                let barHeight: CGFloat = active ? CGFloat(8 + idx * 3) : 6
                Capsule()
                    .fill(active ? stateDotColor : PipiTokens.borderStrong)
                    .frame(width: 3, height: barHeight)
                    .animation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion), value: active)
            }
        }
        .frame(width: 28, height: 22)
    }
}
