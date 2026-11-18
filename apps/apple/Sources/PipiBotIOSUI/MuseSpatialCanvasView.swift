import SwiftUI
import PipiBotKit

public struct MuseSpatialCanvasView: View {
    @Bindable public var store: PipiAppStore
    public var onOpenHarnessSheet: () -> Void

    @State private var promptInput = ""
    @State private var showTranscriptSheet = false
    @State private var showAddCardSheet = false
    @State private var newCardTitle = ""
    @State private var newCardBody = ""
    @State private var newCardKind: MuseCardKind = .voiceNote
    @State private var newCardDomain: OutcomeDomain = .dailyLife

    public init(
        store: PipiAppStore,
        onOpenHarnessSheet: @escaping () -> Void = {}
    ) {
        self.store = store
        self.onOpenHarnessSheet = onOpenHarnessSheet
    }

    public var body: some View {
        ZStack {
            VStack(spacing: PipiTokens.spacing12) {
                headerStrip
                    .padding(.horizontal, PipiTokens.spacing16)

                // Spatial freeform tactile canvas
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        canvasGridBackground
                            .frame(width: 440, height: 360)

                        ForEach(store.museCards) { card in
                            draggableCard(card)
                        }
                    }
                    .padding(PipiTokens.spacing8)
                }
                .background(PipiTokens.bgInset)
                .overlay(
                    RoundedRectangle(cornerRadius: PipiTokens.radiusLG, style: .continuous)
                        .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusLG, style: .continuous))
                .padding(.horizontal, PipiTokens.spacing16)

                // Voice barge-in & Multi-harness quick composer
                composerStrip
                    .padding(.horizontal, PipiTokens.spacing16)
                    .padding(.bottom, PipiTokens.spacing8)
            }

            if showTranscriptSheet {
                PipiSheet(
                    title: "Multi-Harness Transcript",
                    subtitle: "Routed via \(store.activeHarness.displayName)",
                    detent: .expanded,
                    onClose: { showTranscriptSheet = false }
                ) {
                    VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                        ForEach(store.chatMessages) { msg in
                            PipiListCard(
                                title: msg.role == .user ? "You" : msg.harness.displayName,
                                subtitle: msg.content,
                                badgeText: msg.role == .user ? "Input" : msg.harness.shortLabel,
                                badgeColor: msg.role == .user ? PipiTokens.textSecondary : PipiTokens.color(for: msg.harness)
                            )
                        }
                    }
                }
            }

            if showAddCardSheet {
                PipiFormSheet(
                    title: "Pin Muse Spatial Card",
                    subtitle: "Combine life notes, work tasks & infra pins",
                    detent: .compact,
                    submitLabel: "Pin to Canvas",
                    submitIcon: "pin.fill",
                    onCancel: { showAddCardSheet = false },
                    onSubmit: {
                        store.addMuseCard(
                            title: newCardTitle,
                            body: newCardBody,
                            kind: newCardKind,
                            domain: newCardDomain
                        )
                        newCardTitle = ""
                        newCardBody = ""
                        showAddCardSheet = false
                    }
                ) {
                    VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                        TextField("Card title (e.g., Grocery & NAS Check)", text: $newCardTitle)
                            .textFieldStyle(.plain)
                            .padding(PipiTokens.spacing12)
                            .background(PipiTokens.bgSurface)
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM))

                        TextField("Details or voice memo note", text: $newCardBody, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.plain)
                            .padding(PipiTokens.spacing12)
                            .background(PipiTokens.bgSurface)
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM))

                        HStack {
                            Picker("Kind", selection: $newCardKind) {
                                ForEach(MuseCardKind.allCases, id: \.rawValue) { k in
                                    Text(k.displayName).tag(k)
                                }
                            }
                            Picker("Domain", selection: $newCardDomain) {
                                ForEach(OutcomeDomain.allCases) { d in
                                    Text(d.displayName).tag(d)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var headerStrip: some View {
        HStack(spacing: PipiTokens.spacing8) {
            Button(action: onOpenHarnessSheet) {
                HStack(spacing: PipiTokens.spacing8) {
                    Circle()
                        .fill(PipiTokens.color(for: store.activeHarness))
                        .frame(width: 8, height: 8)
                    Text(store.activeHarness.displayName)
                        .font(PipiTokens.fontCaption.weight(.semibold))
                        .foregroundStyle(PipiTokens.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PipiTokens.textMuted)
                }
                .padding(.horizontal, PipiTokens.spacing12)
                .frame(height: PipiTokens.buttonHeightDesktop)
                .background(PipiTokens.bgSurface)
                .overlay(Capsule().stroke(PipiTokens.borderSubtle, lineWidth: 1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            PipiActionButton("Pin Card", systemImage: "plus", tone: .secondary, density: .desktopCompact) {
                showAddCardSheet = true
            }

            PipiActionButton("Log (\(store.chatMessages.count))", systemImage: "text.bubble", tone: .secondary, density: .desktopCompact) {
                showTranscriptSheet = true
            }
        }
    }

    private var canvasGridBackground: some View {
        Canvas { context, size in
            let step: CGFloat = 24
            var x: CGFloat = 12
            while x < size.width {
                var y: CGFloat = 12
                while y < size.height {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)),
                        with: .color(PipiTokens.borderSubtle)
                    )
                    y += step
                }
                x += step
            }
        }
    }

    private func draggableCard(_ card: MuseCardItem) -> some View {
        let domainColor = PipiTokens.color(for: card.domain)

        return VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
            HStack(spacing: PipiTokens.spacing8) {
                Text(card.kind.displayName.uppercased())
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(domainColor)
                Spacer()
                if let harness = card.harness {
                    Text(harness.shortLabel)
                        .font(PipiTokens.fontMonoSmall)
                        .foregroundStyle(PipiTokens.color(for: harness))
                }
            }

            Text(card.title)
                .font(PipiTokens.fontSubheadline.weight(.semibold))
                .foregroundStyle(PipiTokens.textPrimary)
                .lineLimit(2)

            Text(card.body)
                .font(PipiTokens.fontCaption)
                .foregroundStyle(PipiTokens.textSecondary)
                .lineLimit(3)
        }
        .padding(PipiTokens.spacing12)
        .frame(width: 176, alignment: .leading)
        .background(PipiTokens.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .stroke(domainColor.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
        .offset(x: card.offsetX, y: card.offsetY)
        .gesture(
            DragGesture()
                .onChanged { value in
                    store.moveMuseCard(
                        id: card.id,
                        x: card.offsetX + value.translation.width * 0.25,
                        y: card.offsetY + value.translation.height * 0.25
                    )
                }
        )
    }

    private var composerStrip: some View {
        HStack(spacing: PipiTokens.spacing8) {
            Button {
                store.avatarEngine.setState(.voiceInterrupted)
                store.noticeBanner = "Voice barge-in listening (tap Send or Speak)"
            } label: {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(PipiTokens.soulPrimary)
                    .frame(width: PipiTokens.buttonHeightMobile, height: PipiTokens.buttonHeightMobile)
                    .background(PipiTokens.bgSurface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            TextField("Interrupt or ask \(store.activeHarness.shortLabel)...", text: $promptInput)
                .textFieldStyle(.plain)
                .padding(.horizontal, PipiTokens.spacing12)
                .frame(height: PipiTokens.buttonHeightMobile)
                .background(PipiTokens.bgSurface)
                .overlay(RoundedRectangle(cornerRadius: PipiTokens.radiusMD).stroke(PipiTokens.borderSubtle, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD))

            PipiActionButton("Send", systemImage: "arrow.up", tone: .primary, density: .mobile) {
                let prompt = promptInput
                promptInput = ""
                Task {
                    await store.sendChatMessage(prompt)
                    showTranscriptSheet = true
                }
            }
        }
    }
}
