/**
 * @pipibot/core - builtin-skills.ts
 *
 * PiPiBot — Clean-room MIT implementation.
 * Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
 * Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.
 *
 * Wave 3 (#11): Versioned Builtin Office & Daily Skill Packs with SHA-256 Verification
 * and Read-Only Projection (`0o444`) into Agent Context Views.
 */

import { createHash } from 'node:crypto';
import { chmod, mkdir, readFile, unlink, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

export interface BuiltinSkillPack {
  slug: string;
  version: string;
  titleZh: string;
  titleEn: string;
  category: 'office' | 'personal' | 'automation';
  description: string;
  markdownBody: string;
  sha256: string;
}

export interface ProjectedSkillReceipt {
  slug: string;
  version: string;
  sha256: string;
  filePath: string;
  status: 'projected' | 'verified' | 'repaired';
}

function sha256Hex(content: string): string {
  return createHash('sha256').update(content, 'utf8').digest('hex');
}

function buildSkillPack(input: Omit<BuiltinSkillPack, 'sha256'>): BuiltinSkillPack {
  const fullMarkdown = [
    '---',
    `slug: "${input.slug}"`,
    `version: "${input.version}"`,
    `category: "${input.category}"`,
    'readonly: true',
    '---',
    '',
    input.markdownBody.trim(),
    '',
  ].join('\n');
  return {
    ...input,
    markdownBody: fullMarkdown,
    sha256: sha256Hex(fullMarkdown),
  };
}

export const BUILTIN_SKILL_PACKS: readonly BuiltinSkillPack[] = [
  buildSkillPack({
    slug: 'docx',
    version: '1.0.0',
    titleZh: 'Word 文档生成与修订',
    titleEn: 'DOCX Document Authoring',
    category: 'office',
    description: 'Create, inspect, and refine structured Word (.docx) documents with clean headings and tables.',
    markdownBody: `# DOCX Skill\n\n- Produce clean outline hierarchy (H1/H2/H3), consistent tables, and UTF-8 CJK typography.\n- Never overwrite user files in place without an explicit backup or new revision filename.\n- Summarize key changes and output file path at completion.`,
  }),
  buildSkillPack({
    slug: 'pdf',
    version: '1.0.0',
    titleZh: 'PDF 审阅与版式输出',
    titleEn: 'PDF Inspection & Export',
    category: 'office',
    description: 'Extract structured sections/tables from PDFs and generate crisp print-ready PDF deliverables.',
    markdownBody: `# PDF Skill\n\n- Verify page count, margins, and embedded CJK fonts before finalizing exported PDFs.\n- When summarizing source PDFs, cite exact page numbers for every key claim.`,
  }),
  buildSkillPack({
    slug: 'pptx',
    version: '1.0.0',
    titleZh: '演示文稿制作 (PPTX)',
    titleEn: 'PPTX Presentation Builder',
    category: 'office',
    description: 'Author clear executive and technical slide decks with restrained visual hierarchy.',
    markdownBody: `# PPTX Skill\n\n- Keep one core message per slide, generous whitespace, and legible body sizing (>=14pt).\n- Separate speaker notes from slide bullet points.`,
  }),
  buildSkillPack({
    slug: 'xlsx',
    version: '1.0.0',
    titleZh: '电子表格与公式建模',
    titleEn: 'Spreadsheet & Formula Modeling',
    category: 'office',
    description: 'Analyze CSV/XLSX tables, validate formulas, and construct auditable personal budget or tracking sheets.',
    markdownBody: `# XLSX Skill\n\n- Prefer explicit formulas over hardcoded totals and keep raw input sheets separated from summary views.\n- Validate numeric rounding and currency/date formatting.`,
  }),
  buildSkillPack({
    slug: 'slide-deck',
    version: '1.0.0',
    titleZh: '结构化演讲故事线',
    titleEn: 'Structured Slide Storyboarding',
    category: 'office',
    description: 'Plan narrative arcs, section transitions, and visual pacing before generating slides.',
    markdownBody: `# Slide Deck Storyboarding\n\n- Open with the conclusion (Pyramid Principle), back each claim with concrete evidence, and close with clear decisions.`,
  }),
  buildSkillPack({
    slug: 'humanlike-browse',
    version: '1.0.0',
    titleZh: '克制浏览器信息检索',
    titleEn: 'Human-Paced Web Research',
    category: 'automation',
    description: 'Navigate pages calmly, verify primary sources, and pause immediately for authentication or CAPTCHAs.',
    markdownBody: `# Human-Paced Browse Skill\n\n- Read primary documentation directly, cite URLs, and never attempt to bypass logins, paywalls, or anti-bot gates.\n- Any form submission or external post requires explicit user approval.`,
  }),
  buildSkillPack({
    slug: 'personal-profile',
    version: '1.0.0',
    titleZh: '个人画像与 Wiki 整理',
    titleEn: 'Personal Profile & Wiki Curation',
    category: 'personal',
    description: 'Distill durable personal preferences, projects, and life notes into clean Personal Wiki entries.',
    markdownBody: `# Personal Profile & Wiki Skill\n\n- Organize personal knowledge into People, Projects, Topics, Life, and Repos.\n- Strip credentials or tokens before writing any Wiki page or memory summary.`,
  }),
  buildSkillPack({
    slug: 'proactive-response',
    version: '1.0.0',
    titleZh: '克制主动响应与备料',
    titleEn: 'Restrained Proactive Prepare',
    category: 'personal',
    description: 'Prepare read-only context briefings ahead of events while respecting quiet hours and user feedback.',
    markdownBody: `# Proactive Response Skill\n\n- Favor silent read-only Prepare briefings over disruptive pings.\n- Never execute external side effects autonomously during proactive runs.`,
  }),
];

export function getBuiltinSkill(slug: string): BuiltinSkillPack | undefined {
  return BUILTIN_SKILL_PACKS.find((s) => s.slug === slug);
}

/**
 * Projects all (or selected) versioned builtin skills as read-only (`0o444`) SKILL.md files
 * and verifies SHA-256 digests, auto-repairing tampered or outdated copies.
 */
export async function projectBuiltinSkillsReadOnly(
  targetRootDir: string,
  slugs?: string[],
): Promise<ProjectedSkillReceipt[]> {
  const selected = slugs
    ? BUILTIN_SKILL_PACKS.filter((s) => slugs.includes(s.slug))
    : [...BUILTIN_SKILL_PACKS];
  const receipts: ProjectedSkillReceipt[] = [];

  for (const skill of selected) {
    const skillDir = join(targetRootDir, 'skills', 'builtin', skill.slug);
    const filePath = join(skillDir, 'SKILL.md');
    await mkdir(skillDir, { recursive: true });

    let existingDigest: string | null = null;
    try {
      const existing = await readFile(filePath, 'utf8');
      existingDigest = sha256Hex(existing);
    } catch {
      existingDigest = null;
    }

    if (existingDigest === skill.sha256) {
      await chmod(filePath, 0o444).catch(() => {});
      receipts.push({
        slug: skill.slug,
        version: skill.version,
        sha256: skill.sha256,
        filePath,
        status: 'verified',
      });
      continue;
    }

    const wasTamperedOrOutdated = existingDigest !== null;
    if (wasTamperedOrOutdated) {
      await chmod(filePath, 0o644).catch(() => {});
      await unlink(filePath).catch(() => {});
    }
    await writeFile(filePath, skill.markdownBody, 'utf8');
    await chmod(filePath, 0o444);

    receipts.push({
      slug: skill.slug,
      version: skill.version,
      sha256: skill.sha256,
      filePath,
      status: wasTamperedOrOutdated ? 'repaired' : 'projected',
    });
  }

  return receipts;
}

export async function verifyProjectedSkillsIntegrity(
  targetRootDir: string,
  slugs?: string[],
): Promise<{ valid: boolean; mismatches: Array<{ slug: string; expected: string; actual: string | null }> }> {
  const selected = slugs
    ? BUILTIN_SKILL_PACKS.filter((s) => slugs.includes(s.slug))
    : [...BUILTIN_SKILL_PACKS];
  const mismatches: Array<{ slug: string; expected: string; actual: string | null }> = [];

  for (const skill of selected) {
    const filePath = join(targetRootDir, 'skills', 'builtin', skill.slug, 'SKILL.md');
    try {
      const raw = await readFile(filePath, 'utf8');
      const actual = sha256Hex(raw);
      if (actual !== skill.sha256) {
        mismatches.push({ slug: skill.slug, expected: skill.sha256, actual });
      }
    } catch {
      mismatches.push({ slug: skill.slug, expected: skill.sha256, actual: null });
    }
  }

  return { valid: mismatches.length === 0, mismatches };
}
