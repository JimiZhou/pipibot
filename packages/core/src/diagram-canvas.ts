/**
 * @pipibot/core - diagram-canvas.ts
 *
 * PiPiBot — Clean-room MIT implementation.
 * Inline Conversational Diagram & Canvas Engine (T3 Code + OMP `pi-canvas` / `pi-diagram` parity).
 *
 * Capabilities:
 * - Extracts fenced (`svg`, `mermaid`, `diagram`, `canvas`, `chart`) and standalone raw `<svg>` blocks
 *   from assistant Markdown messages.
 * - Strict SVG sanitizer (strips `<script>`, `on*` event attributes, `javascript:` URIs, `<foreignObject>`).
 * - Zero-dependency offline Mermaid -> SVG compiler (flowchart/graph TD|LR|BT|RL with highlighted/dashed
 *   nodes & edge labels, sequenceDiagram, stateDiagram-v2, xychart-beta waveform/signal plots).
 * - Zero-dependency Terminal Unicode ASCII renderer for OMP-style CLI output (`pipibot diagram render`).
 * - Theme-adaptive standalone HTML Canvas exporter for browser/WebView inspection.
 *
 * Runtime dependencies: strictly Node built-ins (`node:*`) only.
 */

export type DiagramKind = 'svg' | 'mermaid' | 'canvas' | 'chart';
export type DiagramThemeMode = 'dark' | 'light';

export interface ExtractedDiagramBlock {
  index: number;
  kind: DiagramKind;
  title?: string;
  source: string;
  rawMatch: string;
  startOffset: number;
  endOffset: number;
}

export interface FlowchartNode {
  id: string;
  label: string;
  subtitle?: string;
  shape: 'rect' | 'round' | 'stadium' | 'diamond' | 'dashed';
  highlight?: 'accent' | 'warn' | 'ok' | 'danger';
  rank: number;
  order: number;
}

export interface FlowchartEdge {
  from: string;
  to: string;
  label?: string;
  dashed: boolean;
}

export interface ParsedFlowchart {
  direction: 'LR' | 'RL' | 'TD' | 'TB' | 'BT';
  nodes: FlowchartNode[];
  edges: FlowchartEdge[];
}

export interface DiagramThemePalette {
  bgCanvas: string;
  bgSurface: string;
  bgInset: string;
  borderSubtle: string;
  borderStrong: string;
  textPrimary: string;
  textSecondary: string;
  textMuted: string;
  accent: string;
  accentBg: string;
  warn: string;
  warnBg: string;
  ok: string;
  okBg: string;
  danger: string;
  dangerBg: string;
}

export const DIAGRAM_PALETTES: Record<DiagramThemeMode, DiagramThemePalette> = {
  dark: {
    bgCanvas: '#0F1012',
    bgSurface: '#181A1E',
    bgInset: '#141518',
    borderSubtle: '#2E3038',
    borderStrong: '#4A4D58',
    textPrimary: '#F5F5F7',
    textSecondary: '#A1A1A6',
    textMuted: '#6E6E73',
    accent: '#4C8DF6',
    accentBg: 'rgba(76, 141, 246, 0.14)',
    warn: '#FBBF24',
    warnBg: 'rgba(251, 191, 36, 0.14)',
    ok: '#34D399',
    okBg: 'rgba(52, 211, 153, 0.14)',
    danger: '#FB7185',
    dangerBg: 'rgba(251, 113, 133, 0.14)',
  },
  light: {
    bgCanvas: '#FFFFFF',
    bgSurface: '#F8F8F9',
    bgInset: '#F2F2F5',
    borderSubtle: '#E2E2E8',
    borderStrong: '#C4C4CE',
    textPrimary: '#171717',
    textSecondary: '#515154',
    textMuted: '#86868B',
    accent: '#2563EB',
    accentBg: 'rgba(37, 99, 235, 0.10)',
    warn: '#B45309',
    warnBg: 'rgba(180, 83, 9, 0.10)',
    ok: '#047857',
    okBg: 'rgba(4, 120, 87, 0.10)',
    danger: '#B91C1C',
    dangerBg: 'rgba(185, 28, 28, 0.10)',
  },
};

// ---------------------------------------------------------------------------
// 1. Markdown Extraction & SVG Sanitization
// ---------------------------------------------------------------------------

function escapeXml(str: string): string {
  return str
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function parseFenceTitle(infoString: string): string | undefined {
  const quoted = infoString.match(/title\s*=\s*"([^"]+)"/i) ?? infoString.match(/title\s*=\s*'([^']+)'/i);
  if (quoted?.[1]) return quoted[1].trim();
  const bare = infoString.match(/title\s*=\s*(\S+)/i);
  return bare?.[1]?.trim();
}

function extractSvgTitle(svg: string): string | undefined {
  const m = svg.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  return m?.[1]?.trim() || undefined;
}

export function sanitizeSvg(rawSvg: string): string {
  let out = rawSvg.trim();
  // Remove dangerous tags completely
  out = out.replace(/<script\b[\s\S]*?<\/script>/gi, '');
  out = out.replace(/<foreignObject\b[\s\S]*?<\/foreignObject>/gi, '');
  out = out.replace(/<iframe\b[\s\S]*?<\/iframe>/gi, '');
  out = out.replace(/<object\b[\s\S]*?<\/object>/gi, '');
  out = out.replace(/<embed\b[^>]*\/?>/gi, '');
  // Strip inline event handlers (onclick=, onload=, onerror=, etc.)
  out = out.replace(/\s+on[a-z]+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)/gi, '');
  // Neutralize javascript: / data:text/html URIs in href / xlink:href / src
  out = out.replace(/(xlink:href|href|src)\s*=\s*["']\s*(?:javascript:|data:text\/html)[^"']*["']/gi, '$1="#"');
  return out;
}

export function extractDiagramBlocks(markdown: string): ExtractedDiagramBlock[] {
  const blocks: ExtractedDiagramBlock[] = [];
  const normalized = markdown.replace(/\r\n/g, '\n');

  // Pass 1: Fenced code blocks (svg, mermaid, diagram, canvas, chart, html-diagram, xml with <svg)
  const fenceRe = /```([^\n]*)\n([\s\S]*?)```/g;
  const coveredRanges: Array<[number, number]> = [];
  let match: RegExpExecArray | null;

  while ((match = fenceRe.exec(normalized)) !== null) {
    const info = (match[1] ?? '').trim();
    const body = (match[2] ?? '').trim();
    const langToken = (info.split(/\s+/)[0] ?? '').toLowerCase();
    const startOffset = match.index;
    const endOffset = match.index + match[0].length;
    coveredRanges.push([startOffset, endOffset]);

    let kind: DiagramKind | null = null;
    if (langToken === 'svg' || (langToken === 'xml' && /^<svg\b/i.test(body))) {
      kind = 'svg';
    } else if (langToken === 'mermaid' || langToken === 'mmd') {
      kind = 'mermaid';
    } else if (langToken === 'chart' || langToken === 'xychart' || langToken === 'plot') {
      kind = 'chart';
    } else if (langToken === 'canvas' || langToken === 'diagram' || langToken === 'html-diagram') {
      kind = 'canvas';
    }

    if (kind && body.length > 0) {
      const title = parseFenceTitle(info) ?? (kind === 'svg' ? extractSvgTitle(body) : undefined);
      blocks.push({
        index: blocks.length,
        kind,
        title,
        source: kind === 'svg' ? sanitizeSvg(body) : body,
        rawMatch: match[0],
        startOffset,
        endOffset,
      });
    }
  }

  // Pass 2: Standalone raw `<svg ...>...</svg>` outside fenced blocks
  const svgRe = /<svg\b[\s\S]*?<\/svg>/gi;
  while ((match = svgRe.exec(normalized)) !== null) {
    const startOffset = match.index;
    const endOffset = match.index + match[0].length;
    const overlaps = coveredRanges.some(([s, e]) => startOffset >= s && startOffset < e);
    if (overlaps) continue;
    const cleaned = sanitizeSvg(match[0]);
    blocks.push({
      index: blocks.length,
      kind: 'svg',
      title: extractSvgTitle(cleaned),
      source: cleaned,
      rawMatch: match[0],
      startOffset,
      endOffset,
    });
  }

  blocks.sort((a, b) => a.startOffset - b.startOffset);
  return blocks.map((b, idx) => ({ ...b, index: idx }));
}

// ---------------------------------------------------------------------------
// 2. Zero-Dependency Mermaid Flowchart / Sequence / State / XYChart Parser
// ---------------------------------------------------------------------------

function parseNodeToken(raw: string): {
  id: string;
  label?: string;
  subtitle?: string;
  shape?: FlowchartNode['shape'];
} {
  const token = raw.trim().replace(/:::([a-zA-Z0-9_-]+)$/, '');
  // Match shapes: id["label"], id(["label"]), id("label"), id{"label"}, id[label]
  const patterns: Array<{ re: RegExp; shape: FlowchartNode['shape'] }> = [
    { re: /^([A-Za-z0-9_.-]+)\s*\(\[([\s\S]+?)\]\)$/, shape: 'stadium' },
    { re: /^([A-Za-z0-9_.-]+)\s*\(([\s\S]+?)\)$/, shape: 'round' },
    { re: /^([A-Za-z0-9_.-]+)\s*\{([\s\S]+?)\}$/, shape: 'diamond' },
    { re: /^([A-Za-z0-9_.-]+)\s*\[([\s\S]+?)\]$/, shape: 'rect' },
  ];
  for (const { re, shape } of patterns) {
    const m = token.match(re);
    if (m?.[1] && m[2]) {
      const inner = m[2].trim().replace(/^["']|["']$/g, '');
      const parts = inner.split(/<br\s*\/?>|\\n/i).map((s) => s.trim()).filter(Boolean);
      return {
        id: m[1],
        label: parts[0] ?? inner,
        subtitle: parts.length > 1 ? parts.slice(1).join(' · ') : undefined,
        shape,
      };
    }
  }
  const idOnly = token.match(/^([A-Za-z0-9_.-]+)$/);
  return { id: idOnly?.[1] ?? token };
}

function extractInlineClass(raw: string): string | undefined {
  const m = raw.trim().match(/:::([a-zA-Z0-9_-]+)$/);
  return m?.[1]?.toLowerCase();
}

function mapClassHighlight(cls?: string): { highlight?: FlowchartNode['highlight']; dashed?: boolean } {
  if (!cls) return {};
  if (/warn|gold|amber|yellow|highlight|focus|key/.test(cls)) return { highlight: 'warn' };
  if (/accent|blue|primary|active/.test(cls)) return { highlight: 'accent' };
  if (/ok|green|success|pass/.test(cls)) return { highlight: 'ok' };
  if (/err|red|danger|fail/.test(cls)) return { highlight: 'danger' };
  if (/dash|gate|fallback|guard|muted/.test(cls)) return { dashed: true };
  return {};
}

export function parseMermaidFlowchart(source: string): ParsedFlowchart {
  const lines = source
    .replace(/\r\n/g, '\n')
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l.length > 0 && !l.startsWith('%%'));

  let direction: ParsedFlowchart['direction'] = 'LR';
  const header = lines[0] ?? '';
  const dirMatch = header.match(/^(?:flowchart|graph)\s+(LR|RL|TD|TB|BT)\b/i);
  if (dirMatch?.[1]) {
    direction = dirMatch[1].toUpperCase() as ParsedFlowchart['direction'];
  }

  const nodeMap = new Map<string, FlowchartNode>();
  const edges: FlowchartEdge[] = [];
  const styleHighlights = new Map<string, { highlight?: FlowchartNode['highlight']; dashed?: boolean }>();

  const ensureNode = (rawTok: string): string => {
    const inlineCls = extractInlineClass(rawTok);
    const parsed = parseNodeToken(rawTok);
    const existing = nodeMap.get(parsed.id);
    const clsStyle = mapClassHighlight(inlineCls);
    if (!existing) {
      nodeMap.set(parsed.id, {
        id: parsed.id,
        label: parsed.label ?? parsed.id,
        subtitle: parsed.subtitle,
        shape: clsStyle.dashed ? 'dashed' : (parsed.shape ?? 'round'),
        highlight: clsStyle.highlight,
        rank: 0,
        order: nodeMap.size,
      });
    } else {
      if (parsed.label && existing.label === existing.id) {
        existing.label = parsed.label;
      }
      if (parsed.subtitle && !existing.subtitle) {
        existing.subtitle = parsed.subtitle;
      }
      if (parsed.shape) existing.shape = clsStyle.dashed ? 'dashed' : parsed.shape;
      if (clsStyle.highlight) existing.highlight = clsStyle.highlight;
    }
    return parsed.id;
  };

  for (let i = 1; i < lines.length; i += 1) {
    const line = lines[i]!;
    if (/^(?:subgraph|end|direction)\b/i.test(line)) continue;

    // `class A,B highlight` or `style A stroke:#... stroke-dasharray:...`
    const classStmt = line.match(/^class\s+([^\s]+)\s+([A-Za-z0-9_-]+)/i);
    if (classStmt?.[1] && classStmt[2]) {
      const mapped = mapClassHighlight(classStmt[2].toLowerCase());
      for (const id of classStmt[1].split(',').map((s) => s.trim())) {
        styleHighlights.set(id, mapped);
      }
      continue;
    }
    const styleStmt = line.match(/^style\s+([A-Za-z0-9_.-]+)\s+(.+)$/i);
    if (styleStmt?.[1] && styleStmt[2]) {
      const css = styleStmt[2].toLowerCase();
      const dashed = css.includes('stroke-dasharray');
      const highlight: FlowchartNode['highlight'] | undefined =
        css.includes('f59e0b') || css.includes('fbbf24') || css.includes('gold') || css.includes('yellow')
          ? 'warn'
          : css.includes('34d399') || css.includes('10b981') || css.includes('green')
            ? 'ok'
            : css.includes('4c8df6') || css.includes('2563eb') || css.includes('blue')
              ? 'accent'
              : undefined;
      styleHighlights.set(styleStmt[1], { highlight, dashed });
      continue;
    }
    if (/^classDef\b/i.test(line)) continue;

    // Parse edges: `A -->|label| B`, `A -. label .-> B`, `A -- label --> B`, `A --> B`
    const edgeRe = /^(.+?)\s*(-->|-.->|==>|--\s+[^-]+\s+-->|-\.\s+[^.]+\s+\.->)\s*(?:\|([^|]+)\|\s*)?(.+)$/;
    const edgeMatch = line.match(edgeRe);
    if (edgeMatch?.[1] && edgeMatch[2] && edgeMatch[4]) {
      const fromId = ensureNode(edgeMatch[1]);
      const arrow = edgeMatch[2].trim();
      let label = edgeMatch[3]?.trim();
      if (!label) {
        const inlineLabel = arrow.match(/^--\s+(.+?)\s+-->$/) ?? arrow.match(/^-\.\s+(.+?)\s+\.->$/);
        if (inlineLabel?.[1]) label = inlineLabel[1].trim();
      }
      const dashed = arrow.includes('-.');
      const toId = ensureNode(edgeMatch[4]);
      edges.push({ from: fromId, to: toId, label, dashed });
      continue;
    }

    // Standalone node declaration
    if (/^[A-Za-z0-9_.-]+[\[(\{]/.test(line)) {
      ensureNode(line);
    }
  }

  for (const [id, st] of styleHighlights.entries()) {
    const node = nodeMap.get(id);
    if (!node) continue;
    if (st.highlight) node.highlight = st.highlight;
    if (st.dashed) node.shape = 'dashed';
  }

  // Assign topological ranks (longest-path DAG layering with cycle guard)
  const nodes = Array.from(nodeMap.values());
  const indegree = new Map<string, number>();
  const adj = new Map<string, string[]>();
  for (const n of nodes) {
    indegree.set(n.id, 0);
    adj.set(n.id, []);
  }
  for (const e of edges) {
    if (e.from === e.to) continue;
    adj.get(e.from)?.push(e.to);
    indegree.set(e.to, (indegree.get(e.to) ?? 0) + 1);
  }
  const queue: string[] = [];
  for (const n of nodes) {
    if ((indegree.get(n.id) ?? 0) === 0) queue.push(n.id);
  }
  if (queue.length === 0 && nodes[0]) queue.push(nodes[0].id);

  const visited = new Set<string>();
  while (queue.length > 0) {
    const cur = queue.shift()!;
    if (visited.has(cur)) continue;
    visited.add(cur);
    const curNode = nodeMap.get(cur)!;
    for (const nxt of adj.get(cur) ?? []) {
      const nxtNode = nodeMap.get(nxt);
      if (!nxtNode) continue;
      if (!visited.has(nxt)) {
        nxtNode.rank = Math.max(nxtNode.rank, curNode.rank + 1);
      }
      const deg = (indegree.get(nxt) ?? 1) - 1;
      indegree.set(nxt, deg);
      if (deg <= 0 && !visited.has(nxt)) queue.push(nxt);
    }
  }

  // Group by rank and assign intra-rank order
  const rankCounts = new Map<number, number>();
  for (const n of nodes) {
    const idx = rankCounts.get(n.rank) ?? 0;
    n.order = idx;
    rankCounts.set(n.rank, idx + 1);
  }

  return { direction, nodes, edges };
}

// ---------------------------------------------------------------------------
// 3. Mermaid / Chart -> Crisp Vector SVG Compiler (Offline, Zero-Dependency)
// ---------------------------------------------------------------------------

function renderFlowchartSvg(source: string, theme: DiagramThemeMode): string {
  const pal = DIAGRAM_PALETTES[theme];
  const parsed = parseMermaidFlowchart(source);
  const horizontal = parsed.direction === 'LR' || parsed.direction === 'RL';

  const nodeW = 168;
  const nodeH = 62;
  const gapX = horizontal ? 64 : 44;
  const gapY = horizontal ? 44 : 58;
  const pad = 32;

  const ranks = new Map<number, FlowchartNode[]>();
  let maxRank = 0;
  for (const n of parsed.nodes) {
    maxRank = Math.max(maxRank, n.rank);
    const list = ranks.get(n.rank) ?? [];
    list.push(n);
    ranks.set(n.rank, list);
  }

  let maxBreadth = 1;
  for (const list of ranks.values()) {
    maxBreadth = Math.max(maxBreadth, list.length);
  }

  const totalW = horizontal
    ? pad * 2 + (maxRank + 1) * nodeW + maxRank * gapX
    : pad * 2 + maxBreadth * nodeW + (maxBreadth - 1) * gapX;
  const totalH = horizontal
    ? pad * 2 + maxBreadth * nodeH + (maxBreadth - 1) * gapY
    : pad * 2 + (maxRank + 1) * nodeH + maxRank * gapY;

  const coords = new Map<string, { x: number; y: number }>();
  for (const [rank, list] of ranks.entries()) {
    const effRank = parsed.direction === 'RL' || parsed.direction === 'BT' ? maxRank - rank : rank;
    const count = list.length;
    for (let idx = 0; idx < count; idx += 1) {
      const n = list[idx]!;
      if (horizontal) {
        const colH = count * nodeH + (count - 1) * gapY;
        const startY = (totalH - colH) / 2;
        coords.set(n.id, {
          x: pad + effRank * (nodeW + gapX),
          y: startY + idx * (nodeH + gapY),
        });
      } else {
        const rowW = count * nodeW + (count - 1) * gapX;
        const startX = (totalW - rowW) / 2;
        coords.set(n.id, {
          x: startX + idx * (nodeW + gapX),
          y: pad + effRank * (nodeH + gapY),
        });
      }
    }
  }

  const edgeSvgs: string[] = [];
  for (const e of parsed.edges) {
    const a = coords.get(e.from);
    const b = coords.get(e.to);
    if (!a || !b) continue;

    let x1: number;
    let y1: number;
    let x2: number;
    let y2: number;

    if (Math.abs(a.x - b.x) >= Math.abs(a.y - b.y)) {
      if (a.x <= b.x) {
        x1 = a.x + nodeW;
        y1 = a.y + nodeH / 2;
        x2 = b.x;
        y2 = b.y + nodeH / 2;
      } else {
        x1 = a.x;
        y1 = a.y + nodeH / 2;
        x2 = b.x + nodeW;
        y2 = b.y + nodeH / 2;
      }
    } else if (a.y <= b.y) {
      x1 = a.x + nodeW / 2;
      y1 = a.y + nodeH;
      x2 = b.x + nodeW / 2;
      y2 = b.y;
    } else {
      x1 = a.x + nodeW / 2;
      y1 = a.y;
      x2 = b.x + nodeW / 2;
      y2 = b.y + nodeH;
    }

    const mx = (x1 + x2) / 2;
    const my = (y1 + y2) / 2;
    const dashAttr = e.dashed ? ' stroke-dasharray="5 4"' : '';
    const d =
      Math.abs(y1 - y2) < 2 || Math.abs(x1 - x2) < 2
        ? `M ${x1} ${y1} L ${x2} ${y2}`
        : `M ${x1} ${y1} C ${mx} ${y1}, ${mx} ${y2}, ${x2} ${y2}`;

    edgeSvgs.push(
      `<path d="${d}" fill="none" stroke="${pal.borderStrong}" stroke-width="1.5"${dashAttr} marker-end="url(#pipi-arrow)" />`,
    );
    if (e.label) {
      edgeSvgs.push(
        `<text x="${mx}" y="${my - 8}" text-anchor="middle" font-size="11.5" fill="${pal.textSecondary}" font-family="-apple-system,BlinkMacSystemFont,sans-serif">${escapeXml(e.label)}</text>`,
      );
    }
  }

  const nodeSvgs: string[] = [];
  for (const n of parsed.nodes) {
    const pos = coords.get(n.id);
    if (!pos) continue;
    const stroke =
      n.highlight === 'warn'
        ? pal.warn
        : n.highlight === 'accent'
          ? pal.accent
          : n.highlight === 'ok'
            ? pal.ok
            : n.highlight === 'danger'
              ? pal.danger
              : pal.borderSubtle;
    const fill =
      n.highlight === 'warn'
        ? pal.warnBg
        : n.highlight === 'accent'
          ? pal.accentBg
          : n.highlight === 'ok'
            ? pal.okBg
            : n.highlight === 'danger'
              ? pal.dangerBg
              : pal.bgSurface;
    const titleFill =
      n.highlight === 'warn'
        ? pal.warn
        : n.highlight === 'accent'
          ? pal.accent
          : n.highlight === 'ok'
            ? pal.ok
            : pal.textPrimary;
    const strokeW = n.highlight ? '2' : '1.25';
    const dash = n.shape === 'dashed' ? ' stroke-dasharray="5 4"' : '';
    const rx = n.shape === 'stadium' ? nodeH / 2 : n.shape === 'rect' ? 6 : 10;

    nodeSvgs.push(
      `<g>` +
        `<rect x="${pos.x}" y="${pos.y}" width="${nodeW}" height="${nodeH}" rx="${rx}" fill="${fill}" stroke="${stroke}" stroke-width="${strokeW}"${dash} />` +
        `<text x="${pos.x + nodeW / 2}" y="${pos.y + (n.subtitle ? 25 : 35)}" text-anchor="middle" font-size="13.5" font-weight="500" fill="${titleFill}" font-family="-apple-system,BlinkMacSystemFont,sans-serif">${escapeXml(n.label)}</text>` +
        (n.subtitle
          ? `<text x="${pos.x + nodeW / 2}" y="${pos.y + 45}" text-anchor="middle" font-size="11.5" fill="${pal.textSecondary}" font-family="ui-monospace,SFMono-Regular,Menlo,monospace">${escapeXml(n.subtitle)}</text>`
          : '') +
        `</g>`,
    );
  }

  return [
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${Math.max(360, totalW)} ${Math.max(120, totalH)}" width="100%" style="display:block;max-width:100%;height:auto;">`,
    `<defs><marker id="pipi-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M 0 1.5 L 10 5 L 0 8.5 z" fill="${pal.borderStrong}" /></marker></defs>`,
    ...edgeSvgs,
    ...nodeSvgs,
    `</svg>`,
  ].join('\n');
}

function renderSequenceSvg(source: string, theme: DiagramThemeMode): string {
  const pal = DIAGRAM_PALETTES[theme];
  const lines = source
    .replace(/\r\n/g, '\n')
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith('%%') && !/^sequenceDiagram/i.test(l));

  const participants: string[] = [];
  const messages: Array<{ from: string; to: string; label: string; dashed: boolean }> = [];
  const ensureParticipant = (name: string) => {
    const clean = name.trim();
    if (clean && !participants.includes(clean)) participants.push(clean);
  };

  for (const line of lines) {
    const pMatch = line.match(/^participant\s+(.+?)(?:\s+as\s+(.+))?$/i);
    if (pMatch?.[1]) {
      ensureParticipant(pMatch[2] ?? pMatch[1]);
      continue;
    }
    const mMatch = line.match(/^([^:-]+?)\s*(-->>|->>|-->|->)\s*([^:]+?)\s*:\s*(.*)$/);
    if (mMatch?.[1] && mMatch[2] && mMatch[3]) {
      ensureParticipant(mMatch[1]);
      ensureParticipant(mMatch[3]);
      messages.push({
        from: mMatch[1].trim(),
        to: mMatch[3].trim(),
        label: (mMatch[4] ?? '').trim(),
        dashed: mMatch[2].startsWith('--'),
      });
    }
  }

  const colW = 160;
  const padX = 48;
  const topY = 24;
  const boxH = 38;
  const stepY = 48;
  const totalW = Math.max(360, padX * 2 + Math.max(1, participants.length) * colW);
  const totalH = topY + boxH + Math.max(1, messages.length) * stepY + 46;

  const colCenter = (name: string) => padX + participants.indexOf(name) * colW + colW / 2;

  const parts: string[] = [
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${totalW} ${totalH}" width="100%" style="display:block;max-width:100%;height:auto;">`,
    `<defs><marker id="seq-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M 0 1.5 L 10 5 L 0 8.5 z" fill="${pal.accent}" /></marker></defs>`,
  ];

  for (const p of participants) {
    const cx = colCenter(p);
    parts.push(
      `<line x1="${cx}" y1="${topY + boxH}" x2="${cx}" y2="${totalH - 20}" stroke="${pal.borderSubtle}" stroke-dasharray="4 4" stroke-width="1.2" />`,
      `<rect x="${cx - 64}" y="${topY}" width="128" height="${boxH}" rx="8" fill="${pal.bgSurface}" stroke="${pal.borderStrong}" stroke-width="1.2" />`,
      `<text x="${cx}" y="${topY + 23}" text-anchor="middle" font-size="13" font-weight="500" fill="${pal.textPrimary}" font-family="-apple-system,BlinkMacSystemFont,sans-serif">${escapeXml(p)}</text>`,
    );
  }

  messages.forEach((m, idx) => {
    const y = topY + boxH + 34 + idx * stepY;
    const x1 = colCenter(m.from);
    const x2 = colCenter(m.to);
    const dash = m.dashed ? ' stroke-dasharray="5 4"' : '';
    parts.push(
      `<line x1="${x1}" y1="${y}" x2="${x2}" y2="${y}" stroke="${pal.accent}" stroke-width="1.5"${dash} marker-end="url(#seq-arrow)" />`,
      `<text x="${(x1 + x2) / 2}" y="${y - 8}" text-anchor="middle" font-size="11.5" fill="${pal.textSecondary}" font-family="-apple-system,BlinkMacSystemFont,sans-serif">${escapeXml(m.label)}</text>`,
    );
  });

  parts.push(`</svg>`);
  return parts.join('\n');
}

function renderXyChartSvg(source: string, theme: DiagramThemeMode): string {
  const pal = DIAGRAM_PALETTES[theme];
  const lines = source
    .replace(/\r\n/g, '\n')
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean);

  let title = '';
  const series: Array<{ kind: 'line' | 'bar'; values: number[]; color: string }> = [];
  const paletteCycle = [pal.accent, pal.textSecondary, pal.warn, pal.ok];

  for (const line of lines) {
    const t = line.match(/^title\s+"([^"]+)"/i);
    if (t?.[1]) {
      title = t[1];
      continue;
    }
    const s = line.match(/^(line|bar)\s+\[([^\]]+)\]/i);
    if (s?.[1] && s[2]) {
      const values = s[2]
        .split(',')
        .map((v) => Number(v.trim()))
        .filter((n) => Number.isFinite(n));
      if (values.length > 0) {
        series.push({
          kind: s[1].toLowerCase() === 'bar' ? 'bar' : 'line',
          values,
          color: paletteCycle[series.length % paletteCycle.length]!,
        });
      }
    }
  }

  const W = 680;
  const H = 220;
  const padL = 44;
  const padR = 24;
  const padT = title ? 36 : 20;
  const padB = 28;
  const plotW = W - padL - padR;
  const plotH = H - padT - padB;

  const allVals = series.flatMap((s) => s.values);
  const minV = allVals.length ? Math.min(...allVals) : 0;
  const maxV = allVals.length ? Math.max(...allVals) : 1;
  const spanV = maxV - minV || 1;
  const maxLen = Math.max(2, ...series.map((s) => s.values.length));

  const xOf = (i: number, len: number) => padL + (len <= 1 ? plotW / 2 : (i / (len - 1)) * plotW);
  const yOf = (v: number) => padT + plotH - ((v - minV) / spanV) * plotH;

  const parts: string[] = [
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="100%" style="display:block;max-width:100%;height:auto;">`,
    `<line x1="${padL}" y1="${padT + plotH}" x2="${W - padR}" y2="${padT + plotH}" stroke="${pal.borderSubtle}" stroke-width="1" />`,
  ];
  if (title) {
    parts.push(
      `<text x="${padL}" y="22" font-size="13" font-weight="500" fill="${pal.textPrimary}" font-family="-apple-system,BlinkMacSystemFont,sans-serif">${escapeXml(title)}</text>`,
    );
  }

  for (const s of series) {
    if (s.kind === 'bar') {
      const barW = Math.max(8, (plotW / maxLen) * 0.55);
      s.values.forEach((v, i) => {
        const cx = xOf(i, s.values.length);
        const y = yOf(v);
        parts.push(
          `<rect x="${cx - barW / 2}" y="${y}" width="${barW}" height="${Math.max(2, padT + plotH - y)}" rx="3" fill="${s.color}" opacity="0.82" />`,
        );
      });
    } else {
      const pts = s.values.map((v, i) => `${xOf(i, s.values.length).toFixed(1)},${yOf(v).toFixed(1)}`).join(' ');
      parts.push(`<polyline fill="none" stroke="${s.color}" stroke-width="2" stroke-linejoin="round" points="${pts}" />`);
    }
  }

  parts.push(`</svg>`);
  return parts.join('\n');
}

export function renderMermaidToSvg(source: string, theme: DiagramThemeMode = 'dark'): string {
  const trimmed = source.trim();
  if (/^sequenceDiagram\b/i.test(trimmed)) {
    return renderSequenceSvg(trimmed, theme);
  }
  if (/^xychart(?:-beta)?\b/i.test(trimmed)) {
    return renderXyChartSvg(trimmed, theme);
  }
  return renderFlowchartSvg(trimmed, theme);
}

// ---------------------------------------------------------------------------
// 4. OMP-Style Terminal Unicode ASCII Diagram Renderer
// ---------------------------------------------------------------------------

export function renderMermaidToAscii(source: string): string {
  const trimmed = source.trim();
  if (/^sequenceDiagram\b/i.test(trimmed)) {
    const lines = trimmed
      .split(/\r?\n/)
      .map((l) => l.trim())
      .filter((l) => l && !/^sequenceDiagram/i.test(l) && !l.startsWith('%%'));
    return lines
      .map((l) => {
        const m = l.match(/^([^:-]+?)\s*(-->>|->>|-->|->)\s*([^:]+?)\s*:\s*(.*)$/);
        if (!m) return `  ${l}`;
        const arrow = m[2]?.startsWith('--') ? '╌╌▶' : '──▶';
        return `  [${m[1]!.trim()}] ${arrow} [${m[3]!.trim()}]  ${(m[4] ?? '').trim()}`;
      })
      .join('\n');
  }

  const parsed = parseMermaidFlowchart(trimmed);
  if (parsed.nodes.length === 0) return trimmed;

  const byId = new Map(parsed.nodes.map((n) => [n.id, n]));
  const boxOf = (n: FlowchartNode) => {
    const text = n.subtitle ? `${n.label} (${n.subtitle})` : n.label;
    return n.shape === 'dashed' ? `┆ ${text} ┆` : `[ ${text} ]`;
  };

  const out: string[] = [];
  if (parsed.edges.length === 0) {
    for (const n of parsed.nodes) out.push(`  ${boxOf(n)}`);
    return out.join('\n');
  }

  for (const e of parsed.edges) {
    const from = byId.get(e.from);
    const to = byId.get(e.to);
    if (!from || !to) continue;
    const arrow = e.dashed ? '╌╌▶' : '──▶';
    const lbl = e.label ? `(${e.label}) ` : '';
    out.push(`  ${boxOf(from)} ${lbl}${arrow} ${boxOf(to)}`);
  }
  return out.join('\n');
}

// ---------------------------------------------------------------------------
// 5. Standalone Theme-Adaptive HTML Canvas Document Builder
// ---------------------------------------------------------------------------

export function renderDiagramToStandaloneHtml(input: {
  kind: DiagramKind;
  source: string;
  title?: string;
  theme?: DiagramThemeMode;
}): string {
  const theme = input.theme ?? 'dark';
  const pal = DIAGRAM_PALETTES[theme];
  const bodyContent =
    input.kind === 'svg'
      ? sanitizeSvg(input.source)
      : input.kind === 'mermaid' || input.kind === 'chart'
        ? renderMermaidToSvg(input.source, theme)
        : sanitizeSvg(input.source);

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${escapeXml(input.title ?? 'PiPiBot Diagram Canvas')}</title>
  <style>
    :root {
      --bg: ${pal.bgCanvas};
      --surface: ${pal.bgSurface};
      --inset: ${pal.bgInset};
      --border: ${pal.borderSubtle};
      --border-strong: ${pal.borderStrong};
      --text: ${pal.textPrimary};
      --text-secondary: ${pal.textSecondary};
      --text-muted: ${pal.textMuted};
      --accent: ${pal.accent};
      --warn: ${pal.warn};
      --ok: ${pal.ok};
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      padding: 20px;
      background: var(--bg);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
    }
    .canvas-stage {
      max-width: 1040px;
      margin: 0 auto;
      padding: 20px;
      border-radius: 12px;
      background: var(--inset);
      border: 1px solid var(--border);
    }
    .canvas-title {
      font-size: 14px;
      font-weight: 500;
      color: var(--text-secondary);
      margin: 0 0 14px;
    }
    svg { max-width: 100%; height: auto; display: block; margin: 0 auto; }
  </style>
</head>
<body>
  <main class="canvas-stage">
    ${input.title ? `<h1 class="canvas-title">${escapeXml(input.title)}</h1>` : ''}
    ${bodyContent}
  </main>
</body>
</html>`;
}
