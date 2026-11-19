import SwiftUI
import PipiBotKit

#if os(macOS)
import AppKit
#endif

public struct PipiProjectEditorSheet: View {
    @Bindable public var store: PipiAppStore
    public let existing: PipiProject?
    public let onDismiss: () -> Void

    @Environment(\.pipiTextScale) private var textScale
    @State private var name: String = ""
    @State private var accent: PipiPersonaAccent = .iris
    @State private var workspacePath: String = ""
    @State private var instructions: String = ""
    @State private var permissionOverride: PipiPermissionTier? = nil

    public init(
        store: PipiAppStore,
        existing: PipiProject?,
        onDismiss: @escaping () -> Void
    ) {
        self.store = store
        self.existing = existing
        self.onDismiss = onDismiss
    }

    private var s: PipiStrings { store.strings }
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }

    public var body: some View {
        let _ = textScale
        VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            HStack(spacing: PipiTokens.spacing12) {
                RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                    .fill(PipiTokens.color(for: accent).opacity(0.16))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: "folder.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(PipiTokens.color(for: accent))
                    )

                Text(existing == nil ? s.newProject : s.editProject)
                    .font(PipiTokens.fontTitle)
                    .tracking(PipiTokens.trackingTitle)
                    .foregroundStyle(PipiTokens.textPrimary)

                Spacer()

                PipiGhostIconButton(
                    systemImage: "xmark",
                    size: 28,
                    iconSize: 12,
                    cornerRadius: PipiTokens.radiusPill,
                    accessibilityLabel: s.close
                ) {
                    onDismiss()
                }
            }

            VStack(alignment: .leading, spacing: PipiTokens.spacing4) {
                Text(s.projectNameLabel)
                    .font(PipiTokens.fontCaption.weight(.semibold))
                    .foregroundStyle(PipiTokens.textSecondary)
                TextField(s.projectNamePlaceholder, text: $name)
                    .textFieldStyle(.plain)
                    .font(PipiTokens.fontBody)
                    .foregroundStyle(PipiTokens.textPrimary)
                    .padding(.horizontal, PipiTokens.spacing12)
                    .frame(height: 36)
                    .background(PipiTokens.bgSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                            .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
            }

            VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                Text(s.personaAccent)
                    .font(PipiTokens.fontCaption.weight(.semibold))
                    .foregroundStyle(PipiTokens.textSecondary)

                HStack(spacing: PipiTokens.spacing8) {
                    ForEach(PipiPersonaAccent.allCases) { option in
                        let c = PipiTokens.color(for: option)
                        let selected = accent == option
                        Button {
                            accent = option
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(c)
                                    .frame(width: 10, height: 10)
                                Text(option.label(lang))
                                    .font(PipiTokens.fontCaption.weight(selected ? .semibold : .medium))
                                    .foregroundStyle(selected ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(selected ? c.opacity(0.14) : PipiTokens.bgSurface)
                            .overlay(
                                Capsule()
                                    .stroke(selected ? c.opacity(0.6) : PipiTokens.borderSubtle, lineWidth: 1)
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))
                    }
                }
            }

            #if os(macOS)
            VStack(alignment: .leading, spacing: PipiTokens.spacing4) {
                Text(s.projectFolderLabel)
                    .font(PipiTokens.fontCaption.weight(.semibold))
                    .foregroundStyle(PipiTokens.textSecondary)

                HStack(spacing: PipiTokens.spacing8) {
                    Text(workspacePath.isEmpty ? s.t("未绑定目录（使用默认工作目录）", "None (uses default workspace)") : workspacePath)
                        .font(PipiTokens.fontMonoSmall)
                        .foregroundStyle(workspacePath.isEmpty ? PipiTokens.textMuted : PipiTokens.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, PipiTokens.spacing12)
                        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                        .background(PipiTokens.bgSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))

                    PipiActionButton(s.chooseFolder, systemImage: "folder", tone: .secondary, density: .desktopCompact) {
                        chooseFolder()
                    }

                    if !workspacePath.isEmpty {
                        PipiGhostIconButton(
                            systemImage: "xmark.circle.fill",
                            size: 28,
                            iconSize: 13,
                            accessibilityLabel: s.clearFilter
                        ) {
                            workspacePath = ""
                        }
                    }
                }
            }
            #endif

            VStack(alignment: .leading, spacing: PipiTokens.spacing4) {
                Text(s.projectInstructionsLabel)
                    .font(PipiTokens.fontCaption.weight(.semibold))
                    .foregroundStyle(PipiTokens.textSecondary)

                TextEditor(text: $instructions)
                    .font(PipiTokens.fontBody)
                    .scrollContentBackground(.hidden)
                    .padding(PipiTokens.spacing8)
                    .frame(height: 110)
                    .background(PipiTokens.bgSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                            .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
            }

            VStack(alignment: .leading, spacing: PipiTokens.spacing4) {
                Text(s.projectPermissionOverrideTitle)
                    .font(PipiTokens.fontCaption.weight(.semibold))
                    .foregroundStyle(PipiTokens.textSecondary)

                Picker("", selection: $permissionOverride) {
                    Text(s.followBotDefaultPermission).tag(Optional<PipiPermissionTier>.none)
                    ForEach(PipiPermissionTier.allCases) { tier in
                        Text(tier.label(lang)).tag(Optional(tier))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Spacer(minLength: 4)

            HStack {
                PipiActionButton(s.cancel, tone: .secondary, density: .desktopCompact) {
                    onDismiss()
                }
                Spacer()
                let canSave = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                PipiActionButton(s.save, systemImage: "checkmark", tone: .primary, density: .desktopCompact) {
                    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanName.isEmpty else { return }
                    let project = PipiProject(
                        id: existing?.id ?? "proj_\(UUID().uuidString.prefix(8).lowercased())",
                        name: cleanName,
                        accent: accent,
                        workspacePath: workspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : workspacePath,
                        instructions: instructions,
                        permissionTierOverride: permissionOverride,
                        isCollapsed: existing?.isCollapsed ?? false,
                        createdAt: existing?.createdAt ?? ISO8601DateFormatter().string(from: Date())
                    )
                    store.upsertProject(project)
                    if existing == nil {
                        _ = store.createConversation(projectId: project.id)
                    }
                    onDismiss()
                }
                .disabled(!canSave)
            }
        }
        .padding(PipiTokens.spacing24)
        .background(PipiTokens.bgElevated)
        .preferredColorScheme(store.themeMode.colorSchemeOverride)
        .onAppear {
            if let existing {
                name = existing.name
                accent = existing.accent
                workspacePath = existing.workspacePath ?? ""
                instructions = existing.instructions
                permissionOverride = existing.permissionTierOverride
            }
        }
    }

    #if os(macOS)
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if !workspacePath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: workspacePath)
        } else {
            panel.directoryURL = URL(fileURLWithPath: store.workspaceDirectory)
        }
        if panel.runModal() == .OK, let url = panel.url {
            workspacePath = url.path
        }
    }
    #endif
}
