// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
// Native macOS Auto-Growing & Scrollable Composer Editor (NSScrollView + NSTextView).
// Fixes SwiftUI TextField(axis: .vertical) lack of wheel/trackpad scrolling and rigid height cap.

#if os(macOS)
import AppKit
import SwiftUI
import PipiBotKit

/// Auto-growing, natively scrollable multiline composer backed by `NSScrollView` + `NSTextView`.
/// - Smoothly expands height from `minHeight` up to `maxHeight` (~10–11 lines) as the user types.
/// - Seamlessly enables smooth mouse-wheel and trackpad scrolling once text exceeds `maxHeight`.
/// - Respects Chinese/Japanese/Korean IME composition (`hasMarkedText()`): Return confirms candidate instead of sending.
/// - `Return` submits; `Shift+Return` / `Option+Return` inserts a newline; `Cmd+V` optionally intercepts image/file attachments.
struct PipiAutoGrowingComposerEditor: View {
    @Binding var text: String
    let placeholder: String
    var minHeight: CGFloat = 44
    var maxHeight: CGFloat = 220
    var focusRequestToken: Int = 0
    var onFocusChanged: ((Bool) -> Void)? = nil
    var onPasteMedia: (() -> Bool)? = nil
    var onSubmit: () -> Void

    @State private var measuredHeight: CGFloat = 44

    private var clampedHeight: CGFloat {
        min(maxHeight, max(minHeight, measuredHeight))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(PipiTokens.fontBody)
                    .foregroundStyle(PipiTokens.textMuted)
                    .padding(.top, 4)
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
            }

            PipiAutoGrowingTextViewRepresentable(
                text: $text,
                measuredHeight: $measuredHeight,
                minHeight: minHeight,
                maxHeight: maxHeight,
                focusRequestToken: focusRequestToken,
                onFocusChanged: onFocusChanged,
                onPasteMedia: onPasteMedia,
                onSubmit: onSubmit
            )
        }
        .frame(height: clampedHeight)
    }
}

private struct PipiAutoGrowingTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let focusRequestToken: Int
    let onFocusChanged: ((Bool) -> Void)?
    let onPasteMedia: (() -> Bool)?
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 4
        layoutManager.addTextContainer(textContainer)

        let textView = PipiComposerNSTextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = Self.resolvedBodyFont()
        textView.textColor = NSColor(PipiTokens.textPrimary)
        textView.insertionPointColor = NSColor(PipiTokens.textPrimary)
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.minSize = NSSize(width: 0, height: minHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [
            .font: Self.resolvedBodyFont(),
            .foregroundColor: NSColor(PipiTokens.textPrimary),
            .paragraphStyle: paragraph
        ]

        textView.onSubmitKey = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onSubmit()
        }
        textView.onPasteInterceptor = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onPasteMedia?() ?? false
        }
        textView.onFocusChanged = { [weak coordinator = context.coordinator] focused in
            coordinator?.parent.onFocusChanged?(focused)
        }

        scrollView.documentView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.textView = textView
        textView.string = text
        context.coordinator.recalculateHeight()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }

        let targetFont = Self.resolvedBodyFont()
        if textView.font != targetFont {
            textView.font = targetFont
        }
        textView.textColor = NSColor(PipiTokens.textPrimary)
        textView.insertionPointColor = NSColor(PipiTokens.textPrimary)

        if textView.string != text && !textView.hasMarkedText() {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            let maxLen = (text as NSString).length
            let safeRanges = selectedRanges.compactMap { val -> NSValue? in
                let r = val.rangeValue
                let loc = min(r.location, maxLen)
                let len = min(r.length, max(0, maxLen - loc))
                return NSValue(range: NSRange(location: loc, length: len))
            }
            if !safeRanges.isEmpty {
                textView.selectedRanges = safeRanges
            }
        }

        if context.coordinator.lastFocusToken != focusRequestToken {
            context.coordinator.lastFocusToken = focusRequestToken
            if focusRequestToken > 0 {
                DispatchQueue.main.async {
                    textView.window?.makeFirstResponder(textView)
                }
            }
        }

        context.coordinator.recalculateHeight()
    }

    private static func resolvedBodyFont() -> NSFont {
        let size = max(12.5, 14.0 * PipiTokens.textScale)
        return NSFont.systemFont(ofSize: size, weight: .regular)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PipiAutoGrowingTextViewRepresentable
        weak var scrollView: NSScrollView?
        weak var textView: PipiComposerNSTextView?
        var lastFocusToken: Int = 0

        init(_ parent: PipiAutoGrowingTextViewRepresentable) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let latest = tv.string
            if parent.text != latest {
                parent.text = latest
            }
            recalculateHeight()
        }

        func recalculateHeight() {
            guard let tv = textView,
                  let layoutManager = tv.layoutManager,
                  let textContainer = tv.textContainer else { return }

            let availableWidth = max(120, (scrollView?.contentSize.width ?? tv.bounds.width))
            if abs(textContainer.containerSize.width - availableWidth) > 0.5 {
                textContainer.containerSize = NSSize(width: availableWidth, height: .greatestFiniteMagnitude)
            }
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let insetY = tv.textContainerInset.height * 2
            let extraLine: CGFloat = tv.string.hasSuffix("\n") ? (tv.font?.pointSize ?? 14) + 6 : 0
            let rawHeight = ceil(usedRect.height + insetY + extraLine + 6)
            let nextHeight = min(parent.maxHeight, max(parent.minHeight, rawHeight))

            let shouldScroll = rawHeight > parent.maxHeight
            if let scrollView {
                scrollView.hasVerticalScroller = shouldScroll
            }

            if abs(parent.measuredHeight - nextHeight) > 0.5 {
                let targetHeight = nextHeight
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if abs(self.parent.measuredHeight - targetHeight) > 0.5 {
                        self.parent.measuredHeight = targetHeight
                    }
                }
            }
        }
    }
}

final class PipiComposerNSTextView: NSTextView {
    var onSubmitKey: (() -> Void)?
    var onPasteInterceptor: (() -> Bool)?
    var onFocusChanged: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocusChanged?(true) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { onFocusChanged?(false) }
        return ok
    }

    override func keyDown(with event: NSEvent) {
        let isReturn = (event.keyCode == 36 || event.keyCode == 76)
        if isReturn {
            // Respect active IME composition (e.g., Chinese/Japanese candidate confirmation)
            if hasMarkedText() {
                super.keyDown(with: event)
                return
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.shift) || flags.contains(.option) || flags.contains(.control) {
                insertNewline(nil)
                return
            }
            onSubmitKey?()
            return
        }
        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        if onPasteInterceptor?() == true {
            return
        }
        super.paste(sender)
    }

    override func scrollWheel(with event: NSEvent) {
        // Always route wheel/trackpad scroll directly to our enclosing NSScrollView so long drafts scroll smoothly.
        if let scrollView = enclosingScrollView {
            scrollView.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}
#endif
