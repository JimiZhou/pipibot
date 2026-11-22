/**
 * PiPiBot — Clean-room MIT implementation.
 * Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
 *
 * @pipibot/daemon - portable-template.ts
 * Portable Redacted Bot / Team Template Parser & Exporter (`bot.md` / `team.md` / `team.yaml`).
 * Bidirectional compatibility with community Markdown+YAML frontmatter templates AND PiPiBot Blueprints.
 */

export interface PortableBotSpec {
  slug: string;
  name: string;
  role: string;
  isolation: 'sandbox_box' | 'host_direct';
  goal?: string;
  instructions: string;
}

export interface PortableRoutineSpec {
  title: string;
  bot: string;
  trigger: string;
  cron?: string;
  enabled: false;
}

export interface PortableTemplate {
  format: string;
  scope: 'bot' | 'team';
  name: string;
  tagline: string;
  channel?: string;
  bots: PortableBotSpec[];
  routines: PortableRoutineSpec[];
  redactedCount: number;
}

const REDACT_RULES: Array<[RegExp, string]> = [
  [/sk-[A-Za-z0-9_-]{16,}/g, '<REDACTED_API_KEY>'],
  [/sk-ant-[A-Za-z0-9_-]{16,}/g, '<REDACTED_ANTHROPIC_KEY>'],
  [/AIza[0-9A-Za-z_-]{25,}/g, '<REDACTED_GOOGLE_KEY>'],
  [/gh[pousr]_[A-Za-z0-9]{20,}/g, '<REDACTED_GITHUB_TOKEN>'],
  [/Bearer\s+[A-Za-z0-9._-]{20,}/g, 'Bearer <REDACTED_TOKEN>'],
  [/pipi_(?:dev|brk)_[A-Za-z0-9_-]{12,}/g, '<REDACTED_PIPIBOT_TOKEN>'],
  [/-----BEGIN [A-Z ]+PRIVATE KEY-----[\s\S]*?-----END [A-Z ]+PRIVATE KEY-----/g, '<REDACTED_PRIVATE_KEY>'],
  [/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, '<REDACTED_EMAIL>'],
  [/\/(?:Users|home)\/[A-Za-z0-9._-]+/g, '<HOME>'],
];

export function redactPortableText(input: string): { cleaned: string; count: number } {
  let out = input;
  let count = 0;
  for (const [re, repl] of REDACT_RULES) {
    const matches = out.match(re);
    if (matches) count += matches.length;
    out = out.replace(re, repl);
  }
  return { cleaned: out, count };
}

function unquote(v: string): string {
  const s = v.trim();
  if ((s.startsWith('"') && s.endsWith('"')) || (s.startsWith("'") && s.endsWith("'"))) {
    return s.slice(1, -1);
  }
  return s;
}

function slugify(raw: string): string {
  return raw
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '') || 'bot';
}

export function parsePortableTemplate(raw: string): PortableTemplate {
  const { cleaned, count } = redactPortableText(raw);
  const trimmed = cleaned.trim();
  let fm = '';
  let body = trimmed;

  if (trimmed.startsWith('---')) {
    const endIdx = trimmed.indexOf('\n---', 3);
    if (endIdx > 0) {
      fm = trimmed.slice(3, endIdx);
      body = trimmed.slice(endIdx + 4).trim();
    }
  } else if (!trimmed.includes('# ')) {
    // Pure YAML (e.g. `team.yaml`)
    fm = trimmed;
    body = '';
  }

  let scope: 'bot' | 'team' = 'bot';
  let name = 'Imported Team';
  let tagline = '';
  let channel: string | undefined;
  const bots: PortableBotSpec[] = [];
  const routines: PortableRoutineSpec[] = [];

  let section: 'root' | 'bots' | 'routines' = 'root';
  let curBot: Record<string, string> = {};
  let curRoutine: Record<string, string> = {};

  const flushBot = () => {
    if (curBot.name) {
      bots.push({
        slug: curBot.slug || slugify(curBot.name),
        name: curBot.name,
        role: curBot.role || 'Specialist',
        isolation: 'sandbox_box',
        goal: curBot.goal,
        instructions: curBot.instructions || '',
      });
    }
    curBot = {};
  };
  const flushRoutine = () => {
    if (curRoutine.title) {
      routines.push({
        title: curRoutine.title,
        bot: curRoutine.bot || bots[0]?.slug || 'lead',
        trigger: curRoutine.trigger || 'schedule',
        cron: curRoutine.cron,
        enabled: false,
      });
    }
    curRoutine = {};
  };

  for (const line of fm.split(/\r?\n/)) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const isIndented = line.startsWith(' ') || line.startsWith('\t');
    if (!isIndented) {
      flushBot();
      flushRoutine();
      section = 'root';
      const colon = t.indexOf(':');
      if (colon < 0) continue;
      const k = t.slice(0, colon).trim().toLowerCase();
      const v = unquote(t.slice(colon + 1));
      if (k === 'scope' && (v === 'team' || v === 'bot')) scope = v;
      else if ((k === 'name' || k === 'title') && v) name = v;
      else if (k === 'tagline' || k === 'description') tagline = v;
      else if (k === 'channel' || k === 'department') channel = v || undefined;
      else if (k === 'bots' || k === 'agents' || k === 'members') section = 'bots';
      else if (k === 'routines' || k === 'triggers') section = 'routines';
    } else if (section === 'bots') {
      const rest = t.startsWith('- ') ? (flushBot(), t.slice(2)) : t;
      const colon = rest.indexOf(':');
      if (colon > 0) curBot[rest.slice(0, colon).trim().toLowerCase()] = unquote(rest.slice(colon + 1));
    } else if (section === 'routines') {
      const rest = t.startsWith('- ') ? (flushRoutine(), t.slice(2)) : t;
      const colon = rest.indexOf(':');
      if (colon > 0) curRoutine[rest.slice(0, colon).trim().toLowerCase()] = unquote(rest.slice(colon + 1));
    }
  }
  flushBot();
  flushRoutine();

  if (bots.length === 0) {
    bots.push({
      slug: slugify(name),
      name,
      role: tagline || 'Imported Agent',
      isolation: 'sandbox_box',
      instructions: body,
    });
  } else if (bots.length > 1) {
    scope = 'team';
  }

  return {
    format: 'pipibot-portable-v1',
    scope,
    name,
    tagline,
    channel,
    bots,
    routines,
    redactedCount: count,
  };
}

export function exportPortableTemplateMarkdown(tpl: Omit<PortableTemplate, 'format' | 'redactedCount'>): {
  markdown: string;
  redactedCount: number;
} {
  let totalRedacted = 0;
  const clean = (s: string) => {
    const r = redactPortableText(s);
    totalRedacted += r.count;
    return r.cleaned;
  };
  const lines = [
    '---',
    'format: pipibot-portable-v1',
    `scope: ${tpl.bots.length > 1 ? 'team' : tpl.scope}`,
    `name: "${clean(tpl.name).replace(/"/g, "'")}"`,
    `tagline: "${clean(tpl.tagline).replace(/"/g, "'")}"`,
    'bots:',
  ];
  for (const b of tpl.bots) {
    lines.push(`  - slug: ${b.slug}`);
    lines.push(`    name: "${clean(b.name).replace(/"/g, "'")}"`);
    lines.push(`    role: "${clean(b.role).replace(/"/g, "'")}"`);
    lines.push(`    isolation: sandbox_box`);
    if (b.goal) lines.push(`    goal: "${clean(b.goal).replace(/"/g, "'")}"`);
  }
  if (tpl.routines.length > 0) {
    lines.push('routines:');
    for (const r of tpl.routines) {
      lines.push(`  - title: "${clean(r.title).replace(/"/g, "'")}"`);
      lines.push(`    bot: ${r.bot}`);
      lines.push(`    trigger: ${r.trigger}`);
      if (r.cron) lines.push(`    cron: "${r.cron}"`);
      lines.push('    enabled: false');
    }
  }
  lines.push('---', '', `# ${clean(tpl.name)}`, '');
  for (const b of tpl.bots) {
    lines.push(`## Bot: ${clean(b.name)}`, '', clean(b.instructions || b.role), '');
  }
  return { markdown: lines.join('\n'), redactedCount: totalRedacted };
}
