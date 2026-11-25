import SwiftUI
import PipiBotKit
#if canImport(WebKit)
import WebKit
#endif
#if os(macOS)
import AppKit
#endif

// MARK: - Inline Conversational Diagram Block (SVG / Mermaid / Chart / Canvas)

struct PipiDiagramBlockView: View {
    let kind: PipiDiagramKind
    let source: String
    let title: String?
    let isComplete: Bool
    let strings: PipiStrings
    let accent: Color

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showSource = false
    @State private var copied = false
    @State private var saved = false
    @State private var isExpandedSheet = false
    @State private var measuredHeight: CGFloat = 240

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar

            Rectangle()
                .fill(PipiTokens.borderSubtle)
                .frame(height: 1)

            if !isComplete {
                HStack(spacing: PipiTokens.spacing8) {
                    PipiDotIndicator(vitality: .busy, color: accent, size: 6)
                    Text(strings.diagramDrawing)
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, PipiTokens.spacing16)
                .padding(.vertical, 20)
                .background(PipiTokens.bgInset)
            } else if showSource {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(source)
                        .font(PipiTokens.fontMono)
                        .foregroundStyle(PipiTokens.textPrimary)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .padding(PipiTokens.spacing16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(PipiTokens.bgInset)
            } else {
                #if os(macOS) && canImport(WebKit)
                PipiDiagramWebView(
                    kind: kind,
                    source: source,
                    isDark: isDark,
                    zoomScale: 1.0,
                    onHeightChange: { h in
                        let clamped = max(110, min(860, h))
                        if abs(clamped - measuredHeight) > 4 {
                            measuredHeight = clamped
                        }
                    }
                )
                .frame(height: measuredHeight)
                .frame(maxWidth: .infinity)
                .background(PipiTokens.bgInset)
                #else
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(source)
                        .font(PipiTokens.fontMono)
                        .foregroundStyle(PipiTokens.textSecondary)
                        .padding(PipiTokens.spacing16)
                }
                .background(PipiTokens.bgInset)
                #endif
            }
        }
        .background(PipiTokens.bgInset)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .stroke(PipiTokens.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
        .sheet(isPresented: $isExpandedSheet) {
            PipiDiagramExpandedSheet(
                kind: kind,
                source: source,
                title: title,
                strings: strings
            )
        }
    }

    private var headerBar: some View {
        HStack(spacing: PipiTokens.spacing8) {
            Image(systemName: headerIconName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(PipiTokens.textMuted)

            Text(title?.isEmpty == false ? title! : kind.displayLabel)
                .font(PipiTokens.fontCaption.weight(.medium))
                .foregroundStyle(PipiTokens.textPrimary)
                .lineLimit(1)

            if let title, !title.isEmpty {
                Text("· \(kind.displayLabel)")
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.textMuted)
            }

            Spacer()

            if isComplete {
                Button {
                    withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                        showSource.toggle()
                    }
                } label: {
                    Text(showSource ? strings.diagramPreview : strings.diagramSource)
                        .font(PipiTokens.fontMicro)
                        .foregroundStyle(PipiTokens.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(PipiTokens.bgSurfaceHover, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.97))

                Button {
                    isExpandedSheet = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(PipiTokens.textSecondary)
                        .frame(width: 24, height: 22)
                        .background(PipiTokens.bgSurfaceHover, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.97))
                .help(strings.diagramExpand)

                #if os(macOS)
                Button {
                    exportDiagramSvg()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: saved ? "checkmark" : "square.and.arrow.down")
                            .font(.system(size: 11, weight: .medium))
                        Text(saved ? strings.diagramSaved : strings.diagramSaveSvg)
                            .font(PipiTokens.fontMicro)
                    }
                    .foregroundStyle(saved ? PipiTokens.stateSuccess : PipiTokens.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(PipiTokens.bgSurfaceHover, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.97))
                #endif

                Button {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(source, forType: .string)
                    #endif
                    withAnimation(PipiMotion.adaptive(PipiMotion.tactile, reduceMotion: reduceMotion)) {
                        copied = true
                    }
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                            copied = false
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                        Text(copied ? strings.copied : strings.copy)
                            .font(PipiTokens.fontMicro)
                    }
                    .foregroundStyle(copied ? PipiTokens.stateSuccess : PipiTokens.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(PipiTokens.bgSurfaceHover, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.97))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(PipiTokens.bgSurface)
    }

    private var headerIconName: String {
        switch kind {
        case .svg: return "square.on.circle"
        case .mermaid: return "point.3.connected.trianglepath.dotted"
        case .chart: return "waveform.path.ecg"
        case .canvas: return "rectangle.3.group"
        }
    }

    #if os(macOS)
    private func exportDiagramSvg() {
        let dir = PipiPersonalWikiStore.defaultStorageDirectory()
            .appendingPathComponent("deliverables", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = (kind == .svg) ? "svg" : (kind == .mermaid ? "mmd" : "html")
        let stamp = Int(Date().timeIntervalSince1970)
        let fileURL = dir.appendingPathComponent("diagram-\(stamp).\(ext)")
        try? source.write(to: fileURL, atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        withAnimation(PipiMotion.adaptive(PipiMotion.tactile, reduceMotion: reduceMotion)) {
            saved = true
        }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                saved = false
            }
        }
    }
    #endif
}

// MARK: - Expanded Interactive Zoom Sheet

private struct PipiDiagramExpandedSheet: View {
    let kind: PipiDiagramKind
    let source: String
    let title: String?
    let strings: PipiStrings

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var zoomScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: PipiTokens.spacing12) {
                Text(title?.isEmpty == false ? title! : kind.displayLabel)
                    .font(PipiTokens.fontHeadline)
                    .foregroundStyle(PipiTokens.textPrimary)
                Spacer()
                HStack(spacing: 6) {
                    Button {
                        zoomScale = max(0.5, zoomScale - 0.25)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 26, height: 26)
                            .background(PipiTokens.bgSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.97))

                    Text("\(Int(zoomScale * 100))%")
                        .font(PipiTokens.fontMonoSmall)
                        .monospacedDigit()
                        .foregroundStyle(PipiTokens.textSecondary)
                        .frame(width: 44)

                    Button {
                        zoomScale = min(2.5, zoomScale + 0.25)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 26, height: 26)
                            .background(PipiTokens.bgSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.97))
                }

                Button(strings.close) {
                    dismiss()
                }
                .font(PipiTokens.fontCaption.weight(.medium))
                .foregroundStyle(PipiTokens.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(PipiTokens.bgSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.97))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(PipiTokens.bgElevated)

            Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)

            #if os(macOS) && canImport(WebKit)
            PipiDiagramWebView(
                kind: kind,
                source: source,
                isDark: colorScheme == .dark,
                zoomScale: zoomScale,
                onHeightChange: { _ in }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PipiTokens.bgCanvas)
            #endif
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(PipiTokens.bgCanvas)
    }
}

// MARK: - Native macOS Sandboxed WKWebView Diagram Renderer (Zero-CDN Offline SVG + Mermaid + Chart)

#if os(macOS) && canImport(WebKit)
private struct PipiDiagramWebView: NSViewRepresentable {
    let kind: PipiDiagramKind
    let source: String
    let isDark: Bool
    let zoomScale: CGFloat
    let onHeightChange: (CGFloat) -> Void

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var lastRenderKey: String = ""
        let onHeightChange: (CGFloat) -> Void

        init(onHeightChange: @escaping (CGFloat) -> Void) {
            self.onHeightChange = onHeightChange
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "heightChanged", let num = message.body as? Double, num > 40 {
                let h = CGFloat(num)
                DispatchQueue.main.async { [weak self] in
                    self?.onHeightChange(h)
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onHeightChange: onHeightChange)
    }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "heightChanged")
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.websiteDataStore = .nonPersistent()

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.setValue(false, forKey: "drawsBackground")
        return wv
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let key = "\(kind.rawValue)|\(isDark)|\(Int(zoomScale * 100))|\(source.hashValue)"
        guard context.coordinator.lastRenderKey != key else { return }
        context.coordinator.lastRenderKey = key
        let html = Self.buildHtmlDocument(kind: kind, source: source, isDark: isDark, zoomScale: zoomScale)
        webView.loadHTMLString(html, baseURL: nil)
    }

    static func buildHtmlDocument(kind: PipiDiagramKind, source: String, isDark: Bool, zoomScale: CGFloat) -> String {
        let pal = PipiDiagramThemePalette.resolved(isDark: isDark)
        let payloadDict: [String: String] = [
            "kind": kind.rawValue,
            "source": source,
            "bgCanvas": pal.bgCanvas,
            "bgSurface": pal.bgSurface,
            "bgInset": pal.bgInset,
            "borderSubtle": pal.borderSubtle,
            "borderStrong": pal.borderStrong,
            "textPrimary": pal.textPrimary,
            "textSecondary": pal.textSecondary,
            "textMuted": pal.textMuted,
            "accent": pal.accent,
            "warn": pal.warn,
            "ok": pal.ok,
            "danger": pal.danger
        ]
        let payloadJSON = (try? JSONSerialization.data(withJSONObject: payloadDict))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let safePayloadJSON = payloadJSON.replacingOccurrences(of: "</script>", with: "<\\/script>")

        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8" />
        <style>
          :root {
            --bg-canvas: \(pal.bgCanvas);
            --bg-surface: \(pal.bgSurface);
            --bg-inset: \(pal.bgInset);
            --border-subtle: \(pal.borderSubtle);
            --border-strong: \(pal.borderStrong);
            --text-primary: \(pal.textPrimary);
            --text-secondary: \(pal.textSecondary);
            --text-muted: \(pal.textMuted);
            --accent: \(pal.accent);
            --warn: \(pal.warn);
            --ok: \(pal.ok);
            --danger: \(pal.danger);
          }
          * { box-sizing: border-box; }
          html, body {
            margin: 0;
            padding: 0;
            background: transparent;
            color: var(--text-primary);
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", sans-serif;
            overflow-x: auto;
            overflow-y: hidden;
          }
          #stage {
            padding: 16px;
            transform-origin: top left;
            transform: scale(\(String(format: "%.2f", zoomScale)));
            width: \(String(format: "%.2f%%", 100.0 / max(0.5, zoomScale)));
          }
          #stage svg {
            display: block;
            max-width: 100%;
            height: auto;
            margin: 0 auto;
          }
        </style>
        </head>
        <body>
          <div id="stage"></div>
          <script>
          (function() {
            const cfg = \(safePayloadJSON);
            const stage = document.getElementById('stage');

            function esc(s) {
              return String(s || '')
                .replaceAll('&', '&amp;')
                .replaceAll('<', '&lt;')
                .replaceAll('>', '&gt;')
                .replaceAll('"', '&quot;');
            }

            function parseNodeTok(raw) {
              const clsM = raw.trim().match(/:::([a-zA-Z0-9_-]+)$/);
              const cls = clsM ? clsM[1].toLowerCase() : '';
              const tok = raw.trim().replace(/:::([a-zA-Z0-9_-]+)$/, '');
              const shapes = [
                { re: /^([A-Za-z0-9_.-]+)\\s*\\(\\[([\\s\\S]+?)\\]\\)$/, shape: 'stadium' },
                { re: /^([A-Za-z0-9_.-]+)\\s*\\(([\\s\\S]+?)\\)$/, shape: 'round' },
                { re: /^([A-Za-z0-9_.-]+)\\s*\\{([\\s\\S]+?)\\}$/, shape: 'diamond' },
                { re: /^([A-Za-z0-9_.-]+)\\s*\\[([\\s\\S]+?)\\]$/, shape: 'rect' }
              ];
              for (const p of shapes) {
                const m = tok.match(p.re);
                if (m) {
                  const inner = m[2].trim().replace(/^["']|["']$/g, '');
                  const parts = inner.split(/<br\\s*\\/?>|\\\\n/i).map(x => x.trim()).filter(Boolean);
                  return { id: m[1], label: parts[0] || inner, sub: parts.length > 1 ? parts.slice(1).join(' · ') : '', shape: p.shape, cls };
                }
              }
              return { id: tok, label: tok, sub: '', shape: 'round', cls };
            }

            function clsStyle(cls) {
              if (!cls) return {};
              if (/warn|gold|amber|yellow|highlight|focus|key/.test(cls)) return { hi: 'warn' };
              if (/accent|blue|primary|active/.test(cls)) return { hi: 'accent' };
              if (/ok|green|success|pass/.test(cls)) return { hi: 'ok' };
              if (/err|red|danger|fail/.test(cls)) return { hi: 'danger' };
              if (/dash|gate|fallback|guard|muted/.test(cls)) return { dashed: true };
              return {};
            }

            function renderMermaidFlow(src) {
              const lines = src.replace(/\\r\\n/g, '\\n').split('\\n').map(l => l.trim()).filter(l => l && !l.startsWith('%%'));
              const dm = (lines[0] || '').match(/^(?:flowchart|graph)\\s+(LR|RL|TD|TB|BT)\\b/i);
              const dir = dm ? dm[1].toUpperCase() : 'LR';
              const nodes = new Map();
              const edges = [];
              const styles = new Map();

              function ensure(raw) {
                const p = parseNodeTok(raw);
                const cs = clsStyle(p.cls);
                if (!nodes.has(p.id)) {
                  nodes.set(p.id, { id: p.id, label: p.label, sub: p.sub, shape: cs.dashed ? 'dashed' : p.shape, hi: cs.hi || '', rank: 0 });
                } else {
                  const n = nodes.get(p.id);
                  if (p.label !== p.id && n.label === n.id) n.label = p.label;
                  if (p.sub && !n.sub) n.sub = p.sub;
                  if (cs.hi) n.hi = cs.hi;
                  if (cs.dashed) n.shape = 'dashed';
                }
                return p.id;
              }

              for (let i = 1; i < lines.length; i++) {
                const l = lines[i];
                if (/^(?:subgraph|end|direction|classDef)\\b/i.test(l)) continue;
                const cm = l.match(/^class\\s+([^\\s]+)\\s+([A-Za-z0-9_-]+)/i);
                if (cm) {
                  const cs = clsStyle(cm[2].toLowerCase());
                  cm[1].split(',').forEach(id => styles.set(id.trim(), cs));
                  continue;
                }
                const sm = l.match(/^style\\s+([A-Za-z0-9_.-]+)\\s+(.+)$/i);
                if (sm) {
                  const css = sm[2].toLowerCase();
                  styles.set(sm[1], {
                    dashed: css.includes('stroke-dasharray'),
                    hi: css.includes('fbbf24') || css.includes('f59e0b') || css.includes('gold') ? 'warn'
                      : css.includes('34d399') || css.includes('10b981') ? 'ok'
                      : css.includes('4c8df6') || css.includes('2563eb') ? 'accent' : ''
                  });
                  continue;
                }
                const em = l.match(/^(.+?)\\s*(-->|-.->|==>|--\\s+[^-]+\\s+-->|-\\.\\s+[^.]+\\s+\\.->)\\s*(?:\\|([^|]+)\\|\\s*)?(.+)$/);
                if (em) {
                  const from = ensure(em[1]);
                  const arrow = em[2].trim();
                  let lbl = (em[3] || '').trim();
                  if (!lbl) {
                    const im = arrow.match(/^--\\s+(.+?)\\s+-->$/) || arrow.match(/^-\\.\\s+(.+?)\\s+\\.->$/);
                    if (im) lbl = im[1].trim();
                  }
                  const to = ensure(em[4]);
                  edges.push({ from, to, label: lbl, dashed: arrow.includes('-.') });
                  continue;
                }
                if (/^[A-Za-z0-9_.-]+[\\[(\\{]/.test(l)) ensure(l);
              }

              for (const [id, st] of styles.entries()) {
                const n = nodes.get(id);
                if (!n) continue;
                if (st.hi) n.hi = st.hi;
                if (st.dashed) n.shape = 'dashed';
              }

              const list = Array.from(nodes.values());
              const indeg = new Map(list.map(n => [n.id, 0]));
              const adj = new Map(list.map(n => [n.id, []]));
              edges.forEach(e => {
                if (e.from !== e.to && adj.has(e.from) && indeg.has(e.to)) {
                  adj.get(e.from).push(e.to);
                  indeg.set(e.to, indeg.get(e.to) + 1);
                }
              });
              const q = list.filter(n => indeg.get(n.id) === 0).map(n => n.id);
              if (!q.length && list[0]) q.push(list[0].id);
              const vis = new Set();
              while (q.length) {
                const cur = q.shift();
                if (vis.has(cur)) continue;
                vis.add(cur);
                const cn = nodes.get(cur);
                for (const nxt of (adj.get(cur) || [])) {
                  const nn = nodes.get(nxt);
                  if (!vis.has(nxt)) nn.rank = Math.max(nn.rank, cn.rank + 1);
                  indeg.set(nxt, indeg.get(nxt) - 1);
                  if (indeg.get(nxt) <= 0 && !vis.has(nxt)) q.push(nxt);
                }
              }

              const horiz = dir === 'LR' || dir === 'RL';
              const nW = 166, nH = 60, gX = horiz ? 62 : 42, gY = horiz ? 42 : 54, pad = 28;
              const byRank = new Map();
              let maxR = 0, maxB = 1;
              list.forEach(n => {
                maxR = Math.max(maxR, n.rank);
                if (!byRank.has(n.rank)) byRank.set(n.rank, []);
                byRank.get(n.rank).push(n);
              });
              byRank.forEach(arr => { maxB = Math.max(maxB, arr.length); });

              const W = horiz ? pad * 2 + (maxR + 1) * nW + maxR * gX : pad * 2 + maxB * nW + (maxB - 1) * gX;
              const H = horiz ? pad * 2 + maxB * nH + (maxB - 1) * gY : pad * 2 + (maxR + 1) * nH + maxR * gY;
              const pos = new Map();
              byRank.forEach((arr, r) => {
                const er = (dir === 'RL' || dir === 'BT') ? (maxR - r) : r;
                arr.forEach((n, idx) => {
                  if (horiz) {
                    const colH = arr.length * nH + (arr.length - 1) * gY;
                    pos.set(n.id, { x: pad + er * (nW + gX), y: (H - colH) / 2 + idx * (nH + gY) });
                  } else {
                    const rowW = arr.length * nW + (arr.length - 1) * gX;
                    pos.set(n.id, { x: (W - rowW) / 2 + idx * (nW + gX), y: pad + er * (nH + gY) });
                  }
                });
              });

              const out = [
                `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${Math.max(360, W)} ${Math.max(110, H)}">`,
                `<defs><marker id="pa" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M 0 1.5 L 10 5 L 0 8.5 z" fill="${cfg.borderStrong}"/></marker></defs>`
              ];
              edges.forEach(e => {
                const a = pos.get(e.from), b = pos.get(e.to);
                if (!a || !b) return;
                let x1, y1, x2, y2;
                if (Math.abs(a.x - b.x) >= Math.abs(a.y - b.y)) {
                  x1 = a.x <= b.x ? a.x + nW : a.x; y1 = a.y + nH / 2;
                  x2 = a.x <= b.x ? b.x : b.x + nW; y2 = b.y + nH / 2;
                } else {
                  x1 = a.x + nW / 2; y1 = a.y <= b.y ? a.y + nH : a.y;
                  x2 = b.x + nW / 2; y2 = a.y <= b.y ? b.y : b.y + nH;
                }
                const mx = (x1 + x2) / 2, my = (y1 + y2) / 2;
                const d = (Math.abs(y1 - y2) < 2 || Math.abs(x1 - x2) < 2) ? `M ${x1} ${y1} L ${x2} ${y2}` : `M ${x1} ${y1} C ${mx} ${y1}, ${mx} ${y2}, ${x2} ${y2}`;
                out.push(`<path d="${d}" fill="none" stroke="${cfg.borderStrong}" stroke-width="1.5" ${e.dashed ? 'stroke-dasharray="5 4"' : ''} marker-end="url(#pa)"/>`);
                if (e.label) out.push(`<text x="${mx}" y="${my - 8}" text-anchor="middle" font-size="11.5" fill="${cfg.textSecondary}">${esc(e.label)}</text>`);
              });

              list.forEach(n => {
                const p = pos.get(n.id);
                if (!p) return;
                const stroke = n.hi === 'warn' ? cfg.warn : n.hi === 'accent' ? cfg.accent : n.hi === 'ok' ? cfg.ok : n.hi === 'danger' ? cfg.danger : cfg.borderSubtle;
                const tFill = n.hi ? stroke : cfg.textPrimary;
                const rx = n.shape === 'stadium' ? nH / 2 : n.shape === 'rect' ? 6 : 10;
                const sw = n.hi ? 2 : 1.25;
                const dash = n.shape === 'dashed' ? 'stroke-dasharray="5 4"' : '';
                out.push(`<g><rect x="${p.x}" y="${p.y}" width="${nW}" height="${nH}" rx="${rx}" fill="${cfg.bgSurface}" stroke="${stroke}" stroke-width="${sw}" ${dash}/>` +
                  `<text x="${p.x + nW / 2}" y="${p.y + (n.sub ? 25 : 34)}" text-anchor="middle" font-size="13.5" font-weight="500" fill="${tFill}">${esc(n.label)}</text>` +
                  (n.sub ? `<text x="${p.x + nW / 2}" y="${p.y + 44}" text-anchor="middle" font-size="11.5" fill="${cfg.textSecondary}" font-family="ui-monospace,Menlo,monospace">${esc(n.sub)}</text>` : '') +
                  `</g>`);
              });
              out.push('</svg>');
              return out.join('');
            }

            function renderMermaidSeq(src) {
              const lines = src.replace(/\\r\\n/g, '\\n').split('\\n').map(l => l.trim()).filter(l => l && !l.startsWith('%%') && !/^sequenceDiagram/i.test(l));
              const ps = [], msgs = [];
              const addP = p => { const c = p.trim(); if (c && !ps.includes(c)) ps.push(c); };
              lines.forEach(l => {
                const pm = l.match(/^participant\\s+(.+?)(?:\\s+as\\s+(.+))?$/i);
                if (pm) { addP(pm[2] || pm[1]); return; }
                const mm = l.match(/^([^:-]+?)\\s*(-->>|->>|-->|->)\\s*([^:]+?)\\s*:\\s*(.*)$/);
                if (mm) { addP(mm[1]); addP(mm[3]); msgs.push({ from: mm[1].trim(), to: mm[3].trim(), label: (mm[4] || '').trim(), dashed: mm[2].startsWith('--') }); }
              });
              const colW = 160, padX = 44, topY = 20, boxH = 36, stepY = 46;
              const W = Math.max(360, padX * 2 + Math.max(1, ps.length) * colW);
              const H = topY + boxH + Math.max(1, msgs.length) * stepY + 42;
              const cx = name => padX + ps.indexOf(name) * colW + colW / 2;
              const out = [
                `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}">`,
                `<defs><marker id="sa" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M 0 1.5 L 10 5 L 0 8.5 z" fill="${cfg.accent}"/></marker></defs>`
              ];
              ps.forEach(p => {
                const x = cx(p);
                out.push(`<line x1="${x}" y1="${topY + boxH}" x2="${x}" y2="${H - 18}" stroke="${cfg.borderSubtle}" stroke-dasharray="4 4" stroke-width="1.2"/>`);
                out.push(`<rect x="${x - 62}" y="${topY}" width="124" height="${boxH}" rx="8" fill="${cfg.bgSurface}" stroke="${cfg.borderStrong}" stroke-width="1.2"/>`);
                out.push(`<text x="${x}" y="${topY + 22}" text-anchor="middle" font-size="13" font-weight="500" fill="${cfg.textPrimary}">${esc(p)}</text>`);
              });
              msgs.forEach((m, i) => {
                const y = topY + boxH + 30 + i * stepY, x1 = cx(m.from), x2 = cx(m.to);
                out.push(`<line x1="${x1}" y1="${y}" x2="${x2}" y2="${y}" stroke="${cfg.accent}" stroke-width="1.5" ${m.dashed ? 'stroke-dasharray="5 4"' : ''} marker-end="url(#sa)"/>`);
                out.push(`<text x="${(x1 + x2) / 2}" y="${y - 8}" text-anchor="middle" font-size="11.5" fill="${cfg.textSecondary}">${esc(m.label)}</text>`);
              });
              out.push('</svg>');
              return out.join('');
            }

            function renderXyChart(src) {
              const lines = src.replace(/\\r\\n/g, '\\n').split('\\n').map(l => l.trim()).filter(Boolean);
              let title = '';
              const series = [];
              const colors = [cfg.accent, cfg.textSecondary, cfg.warn, cfg.ok];
              lines.forEach(l => {
                const tm = l.match(/^title\\s+"([^"]+)"/i);
                if (tm) { title = tm[1]; return; }
                const sm = l.match(/^(line|bar)\\s+\\[([^\\]]+)\\]/i);
                if (sm) {
                  const vals = sm[2].split(',').map(v => Number(v.trim())).filter(Number.isFinite);
                  if (vals.length) series.push({ kind: sm[1].toLowerCase(), vals, color: colors[series.length % colors.length] });
                }
              });
              const W = 680, H = 220, pL = 40, pR = 20, pT = title ? 36 : 20, pB = 26, pw = W - pL - pR, ph = H - pT - pB;
              const all = series.flatMap(s => s.vals);
              const minV = all.length ? Math.min(...all) : 0, maxV = all.length ? Math.max(...all) : 1, span = maxV - minV || 1;
              const xOf = (i, len) => pL + (len <= 1 ? pw / 2 : (i / (len - 1)) * pw);
              const yOf = v => pT + ph - ((v - minV) / span) * ph;
              const out = [`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}">`, `<line x1="${pL}" y1="${pT + ph}" x2="${W - pR}" y2="${pT + ph}" stroke="${cfg.borderSubtle}" stroke-width="1"/>`];
              if (title) out.push(`<text x="${pL}" y="22" font-size="13" font-weight="500" fill="${cfg.textPrimary}">${esc(title)}</text>`);
              series.forEach(s => {
                if (s.kind === 'bar') {
                  const bw = Math.max(8, (pw / Math.max(2, s.vals.length)) * 0.55);
                  s.vals.forEach((v, i) => {
                    const cx = xOf(i, s.vals.length), y = yOf(v);
                    out.push(`<rect x="${cx - bw / 2}" y="${y}" width="${bw}" height="${Math.max(2, pT + ph - y)}" rx="3" fill="${s.color}" opacity="0.82"/>`);
                  });
                } else {
                  const pts = s.vals.map((v, i) => `${xOf(i, s.vals.length).toFixed(1)},${yOf(v).toFixed(1)}`).join(' ');
                  out.push(`<polyline fill="none" stroke="${s.color}" stroke-width="2" stroke-linejoin="round" points="${pts}"/>`);
                }
              });
              out.push('</svg>');
              return out.join('');
            }

            if (cfg.kind === 'svg' || cfg.kind === 'canvas') {
              stage.innerHTML = cfg.source;
            } else {
              const t = (cfg.source || '').trim();
              if (/^sequenceDiagram\\b/i.test(t)) stage.innerHTML = renderMermaidSeq(t);
              else if (/^xychart(?:-beta)?\\b/i.test(t) || cfg.kind === 'chart') stage.innerHTML = renderXyChart(t);
              else stage.innerHTML = renderMermaidFlow(t);
            }

            function reportHeight() {
              const rect = stage.getBoundingClientRect();
              const h = Math.ceil(Math.max(rect.height, stage.scrollHeight) + 6);
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.heightChanged) {
                window.webkit.messageHandlers.heightChanged.postMessage(h);
              }
            }
            reportHeight();
            setTimeout(reportHeight, 60);
            if (typeof ResizeObserver !== 'undefined') {
              new ResizeObserver(reportHeight).observe(stage);
            }
          })();
          </script>
        </body>
        </html>
        """
    }
}
#endif
