// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.

import SwiftUI
import PipiBotKit

/// Ultra-compact global title bar telemetry trigger button that opens a clean runtime popover.
public struct PipiTelemetryToolbarButton: View {
    @Bindable public var store: PipiAppStore
    public var onOpenModelSettings: () -> Void

    @State private var isPresented: Bool = false

    public init(store: PipiAppStore, onOpenModelSettings: @escaping () -> Void) {
        self.store = store
        self.onOpenModelSettings = onOpenModelSettings
    }

    private var s: PipiStrings { store.strings }

    public var body: some View {
        let snap = store.telemetryMonitor.snapshot
        let isBusy = store.telemetryMonitor.isInferenceActive || store.isGeneratingReply
        let dotColor: Color = {
            if snap.cpuUsagePercent >= 88 || snap.vramUsagePercent >= 90 {
                return PipiTokens.stateError
            }
            if isBusy || snap.cpuUsagePercent >= 65 || snap.vramUsagePercent >= 78 {
                return PipiTokens.stateWarning
            }
            return PipiTokens.stateSuccess
        }()

        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
                Text("\(Int(snap.cpuUsagePercent.rounded()))%")
                    .font(PipiTokens.fontMonoSmall)
                    .monospacedDigit()
                    .foregroundStyle(PipiTokens.textPrimary)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(PipiTokens.bgElevated.opacity(0.85))
            .overlay(
                Capsule()
                    .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(s.t("系统与推理延迟监控", "System & Inference Telemetry"))
        .accessibilityLabel(s.t("运行监控", "Runtime Monitor"))
        .onAppear {
            store.telemetryMonitor.ensureBackgroundPolling()
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            PipiTelemetryPopoverView(
                store: store,
                onOpenModelSettings: {
                    isPresented = false
                    onOpenModelSettings()
                }
            )
        }
    }
}

/// Floating popover displaying live CPU, Unified GPU/VRAM, RAM, and Input/Output inference latency.
public struct PipiTelemetryPopoverView: View {
    @Bindable public var store: PipiAppStore
    public var onOpenModelSettings: () -> Void

    public init(store: PipiAppStore, onOpenModelSettings: @escaping () -> Void) {
        self.store = store
        self.onOpenModelSettings = onOpenModelSettings
    }

    private var s: PipiStrings { store.strings }

    public var body: some View {
        let snap = store.telemetryMonitor.snapshot
        let inf = store.telemetryMonitor.lastInference
        let runningPlatforms = store.localModelPlatformManager.runningPlatforms

        VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            // Header
            HStack(spacing: PipiTokens.spacing8) {
                Image(systemName: "gauge.medium")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PipiTokens.textPrimary)
                Text(s.t("运行监控", "Runtime Monitor"))
                    .font(PipiTokens.fontSubheadline.weight(.semibold))
                    .foregroundStyle(PipiTokens.textPrimary)
                Spacer()
                Text(snap.gpuName)
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.textMuted)
                    .lineLimit(1)
                Button {
                    store.telemetryMonitor.sampleNow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(PipiTokens.textSecondary)
                }
                .buttonStyle(.plain)
                .help(s.refresh)
            }

            Divider()

            // Hardware Gauges: CPU + GPU/VRAM + RAM
            VStack(alignment: .leading, spacing: 10) {
                gaugeRow(
                    title: s.t("CPU 占用", "CPU Load"),
                    valueText: String(format: "%.0f%%", snap.cpuUsagePercent),
                    fraction: snap.cpuUsagePercent / 100.0
                )

                // Micro CPU Sparkline
                if store.telemetryMonitor.cpuHistory.count > 1 {
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(Array(store.telemetryMonitor.cpuHistory.enumerated()), id: \.offset) { _, val in
                            let h = max(2, min(14, CGFloat(val / 100.0) * 14))
                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                .fill(barColor(for: val / 100.0).opacity(0.72))
                                .frame(maxWidth: .infinity)
                                .frame(height: h)
                        }
                    }
                    .frame(height: 15)
                }

                gaugeRow(
                    title: snap.isUnifiedMemory
                        ? s.t("显存 / 统一内存", "VRAM / Unified")
                        : s.t("显存占用 (VRAM)", "GPU VRAM"),
                    valueText: String(format: "%.1f / %.1f GB", snap.vramUsedGB, max(0.1, snap.vramBudgetGB)),
                    fraction: snap.vramUsagePercent / 100.0
                )

                PipiKeyValueRow(
                    key: s.t("系统物理内存", "System RAM"),
                    value: String(format: "%.1f / %.0f GB (%.0f%%)", snap.memoryUsedGB, snap.memoryTotalGB, snap.memoryUsagePercent),
                    monospaced: true
                )
            }

            Divider()

            // Inference Input / Output Latency
            VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                HStack {
                    Text(s.t("推理延迟与吞吐", "Inference Latency"))
                        .font(PipiTokens.fontCaption.weight(.semibold))
                        .foregroundStyle(PipiTokens.textSecondary)
                    Spacer()
                    if store.telemetryMonitor.isInferenceActive {
                        HStack(spacing: 4) {
                            PipiDotIndicator(vitality: .busy, color: PipiTokens.stateWarning, size: 5)
                            Text(s.t("推理中", "Active"))
                                .font(PipiTokens.fontMicro)
                                .foregroundStyle(PipiTokens.stateWarning)
                        }
                    } else if let inf {
                        Text(inf.engineLabel)
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.textMuted)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 8) {
                    latencyMetricBox(
                        label: s.t("输入延迟", "Input / TTFT"),
                        value: formatMs(inf?.inputLatencyMs)
                    )
                    latencyMetricBox(
                        label: s.t("输出延迟", "Output"),
                        value: formatMs(inf?.outputLatencyMs)
                    )
                    latencyMetricBox(
                        label: s.t("输出速率", "Speed"),
                        value: inf?.tokensPerSecond.map { String(format: "%.1f t/s", $0) } ?? "—"
                    )
                }
            }

            Divider()

            // Local Model Platform Footer
            HStack(spacing: PipiTokens.spacing8) {
                Circle()
                    .fill(runningPlatforms.isEmpty ? PipiTokens.textMuted : PipiTokens.stateSuccess)
                    .frame(width: 6, height: 6)
                Text(
                    runningPlatforms.isEmpty
                        ? s.t("当前引擎：\(store.activeEngineDisplayLabel())", "Engine: \(store.activeEngineDisplayLabel())")
                        : s.t("本地运行中：\(runningPlatforms.map(\.kind.displayName).joined(separator: " · "))", "Local Active: \(runningPlatforms.map(\.kind.displayName).joined(separator: " · "))")
                )
                .font(PipiTokens.fontMicro)
                .foregroundStyle(PipiTokens.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                Spacer(minLength: 4)
                Button(s.t("模型管理", "Models")) {
                    onOpenModelSettings()
                }
                .buttonStyle(.plain)
                .font(PipiTokens.fontMicro.weight(.semibold))
                .foregroundStyle(PipiTokens.textPrimary)
            }
        }
        .padding(14)
        .frame(width: 316)
        .background(PipiTokens.bgElevated)
        .onAppear {
            store.telemetryMonitor.beginFastPolling()
            Task { _ = await store.scanLocalModelPlatforms() }
        }
        .onDisappear {
            store.telemetryMonitor.endFastPolling()
        }
    }

    private func gaugeRow(title: String, valueText: String, fraction: Double) -> some View {
        let clamped = min(1.0, max(0.0, fraction))
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.textSecondary)
                Spacer()
                Text(valueText)
                    .font(PipiTokens.fontMonoSmall)
                    .monospacedDigit()
                    .foregroundStyle(PipiTokens.textPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(PipiTokens.bgInset)
                    Capsule()
                        .fill(barColor(for: clamped))
                        .frame(width: max(4, geo.size.width * clamped))
                }
            }
            .frame(height: 5)
        }
    }

    private func latencyMetricBox(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(PipiTokens.fontMicro)
                .foregroundStyle(PipiTokens.textMuted)
                .lineLimit(1)
            Text(value)
                .font(PipiTokens.fontMonoSmall.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(PipiTokens.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PipiTokens.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
    }

    private func barColor(for fraction: Double) -> Color {
        if fraction >= 0.88 { return PipiTokens.stateError }
        if fraction >= 0.68 { return PipiTokens.stateWarning }
        return PipiTokens.stateSuccess
    }

    private func formatMs(_ ms: Int?) -> String {
        guard let ms else { return "—" }
        if ms >= 1000 {
            return String(format: "%.2f s", Double(ms) / 1000.0)
        }
        return "\(ms) ms"
    }
}
