#!/usr/bin/env node
/**
 * PipiBot Design System Automated Audit (`scripts/audit-design-system.mjs`)
 * Enforces OpenPencil 5-Rule Governance across:
 *   1. design-system/pipibot.pen
 *   2. design-system/design-system.md
 *   3. design-system/tokens.css & tokens.dtcg.json
 *   4. apps/ios-web/styles.css, index.html, app.js
 *   5. apps/apple/Sources/ (when present)
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, '..');

const errors = [];
const passes = [];

function pass(msg) {
  passes.push(msg);
}

function fail(msg) {
  errors.push(msg);
}

function readUtf8(relPath) {
  const full = path.join(REPO_ROOT, relPath);
  if (!fs.existsSync(full)) {
    fail(`Missing required file: ${relPath}`);
    return null;
  }
  return fs.readFileSync(full, 'utf8');
}

function relativeLuminance(hex) {
  const clean = hex.replace('#', '').slice(0, 6);
  const num = parseInt(clean, 16);
  const channels = [(num >> 16) & 255, (num >> 8) & 255, num & 255].map((c) => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
}

function wcagContrast(hexA, hexB) {
  const l1 = relativeLuminance(hexA);
  const l2 = relativeLuminance(hexB);
  return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
}

/* --------------------------------------------------------------------------
 * 1. Audit OpenPencil Document (`design-system/pipibot.pen`)
 * ------------------------------------------------------------------------ */
function auditPenDocument() {
  const raw = readUtf8('design-system/pipibot.pen');
  if (!raw) return;

  let doc;
  try {
    doc = JSON.parse(raw);
  } catch (err) {
    fail(`design-system/pipibot.pen invalid JSON: ${err.message}`);
    return;
  }

  if (!doc.schemaVersion) fail('pipibot.pen missing schemaVersion');
  if (!doc.variableCollections?.foundations || !doc.variableCollections?.theme || !doc.variableCollections?.tokens) {
    fail('pipibot.pen must define foundations, theme, and tokens variableCollections');
    return;
  }

  // Build flat variable table across collections
  const varDefs = new Map();
  for (const col of Object.values(doc.variableCollections)) {
    for (const [varId, def] of Object.entries(col.variables || {})) {
      varDefs.set(varId, def);
    }
  }

  function resolveVar(varId, mode, depth = 0) {
    if (depth > 8) return null;
    const def = varDefs.get(varId);
    if (!def) return null;
    const val = def.values?.[mode] ?? def.values?.default ?? Object.values(def.values || {})[0];
    if (typeof val === 'string') return val;
    if (val && typeof val === 'object' && val.alias) {
      return resolveVar(val.alias, mode, depth + 1);
    }
    return null;
  }

  const defaultMode = doc.meta?.defaultMode || 'Obsidian Dark';
  const textStyleIds = new Set(Object.keys(doc.textStyles || {}));
  if (textStyleIds.size === 0) fail('pipibot.pen must define textStyles');

  // Check 6 Canonical Components & 12 Screens
  const components = Array.isArray(doc.components) ? doc.components : [];
  const screens = Array.isArray(doc.screens) ? doc.screens : [];
  const compNames = new Set(components.map((c) => c.name));
  for (const requiredBlock of ['list-card', 'sheet', 'form-sheet', 'dock', 'bottom-bar', 'empty-state']) {
    if (!compNames.has(requiredBlock)) {
      fail(`pipibot.pen missing canonical component block: ${requiredBlock}`);
    }
  }
  if (screens.length < 12) {
    fail(`pipibot.pen must contain at least 12 screens, found ${screens.length}`);
  }

  let bindingCount = 0;
  let textCount = 0;
  let iconCount = 0;
  let clipCount = 0;
  let buttonCount = 0;
  let sheetCount = 0;

  const hexPattern = /#(?:[0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})\b/;

  function walkObj(obj, loc) {
    if (!obj || typeof obj !== 'object') return;
    if (Array.isArray(obj)) {
      obj.forEach((item, idx) => walkObj(item, `${loc}[${idx}]`));
      return;
    }

    // (a) Variable binding fallbackColor === resolvedTokenValue
    if ('variableId' in obj) {
      bindingCount++;
      const resolved = resolveVar(obj.variableId, defaultMode);
      if (!resolved) {
        fail(`pipibot.pen ${loc}: unresolved variableId "${obj.variableId}"`);
      } else if (!obj.fallbackColor || typeof obj.fallbackColor !== 'string') {
        fail(`pipibot.pen ${loc}: variable "${obj.variableId}" missing fallbackColor`);
      } else if (obj.fallbackColor.toUpperCase() !== resolved.toUpperCase()) {
        fail(`pipibot.pen ${loc}: fallbackColor ${obj.fallbackColor} !== resolved ${resolved} for ${obj.variableId}`);
      }
    }

    // (b) Zero raw hex literals outside fallbackColor on variable bindings
    for (const [k, v] of Object.entries(obj)) {
      if (typeof v === 'string' && hexPattern.test(v)) {
        if (!(k === 'fallbackColor' && 'variableId' in obj)) {
          fail(`pipibot.pen ${loc}.${k}: forbidden raw hex literal "${v}"`);
        }
      }
    }

    // (c) TEXT node must bind valid textStyleId
    if (obj.type === 'TEXT') {
      textCount++;
      if (!obj.textStyleId || !textStyleIds.has(obj.textStyleId)) {
        fail(`pipibot.pen ${loc} (${obj.id}): TEXT node invalid/missing textStyleId "${obj.textStyleId}"`);
      }
    }

    // (d) ICON node strokeWeight 1.5 (16-18px) or 1.75 (20-24px)
    if (obj.type === 'ICON') {
      iconCount++;
      const sz = obj.size;
      const sw = obj.strokeWeight;
      const validSmall = sz >= 16 && sz <= 18 && sw === 1.5;
      const validMed = sz >= 20 && sz <= 24 && sw === 1.75;
      if (!validSmall && !validMed) {
        fail(`pipibot.pen ${loc} (${obj.id}): ICON size=${sz} strokeWeight=${sw} violates 1.5(16-18)/1.75(20-24)`);
      }
    }

    // (e) clip: true ONLY when effects.length > 0 or overflowDirection !== 'NONE'
    if (obj.clip === true) {
      clipCount++;
      const hasEffects = Array.isArray(obj.effects) && obj.effects.length > 0;
      const hasScroll = typeof obj.overflowDirection === 'string' && obj.overflowDirection !== 'NONE';
      if (!hasEffects && !hasScroll) {
        fail(`pipibot.pen ${loc} (${obj.id}): clip:true without effects or scrollable overflowDirection`);
      }
    }

    // (f1) Button geometry rules
    if (obj.role === 'button') {
      buttonCount++;
      if (obj.platform === 'mobile') {
        if (obj.height !== 44 || obj.iconSize !== 18 || obj.gap !== 8) {
          fail(`pipibot.pen ${loc} (${obj.id}): mobile button geometry must be 44px / 18px icon / 8px gap`);
        }
      } else if (obj.platform === 'desktop') {
        if (obj.height !== 32 || obj.iconSize !== 16 || obj.gap !== 6) {
          fail(`pipibot.pen ${loc} (${obj.id}): desktop button geometry must be 32px / 16px icon / 6px gap`);
        }
      } else {
        fail(`pipibot.pen ${loc} (${obj.id}): button missing platform ("mobile" | "desktop")`);
      }
    }

    // (f2) Sheet topEdge 54 or 102
    if (obj.role === 'sheet' || obj.name === 'sheet' || obj.name === 'form-sheet') {
      sheetCount++;
      if (obj.topEdge !== 54 && obj.topEdge !== 102) {
        fail(`pipibot.pen ${loc} (${obj.id}): sheet topEdge=${obj.topEdge} must be 54 or 102`);
      }
    }

    for (const [k, v] of Object.entries(obj)) {
      if (v && typeof v === 'object') {
        walkObj(v, `${loc}.${k}`);
      }
    }
  }

  walkObj(components, 'components');
  walkObj(screens, 'screens');

  // Verify Vellum Light brand/foreground tokens >= 4.5:1 contrast against Vellum canvas
  const lightCanvas = resolveVar('tokens.bgCanvas', 'Vellum Light');
  const lightFgTokens = [
    'tokens.textPrimary',
    'tokens.textSecondary',
    'tokens.soulPrimary',
    'tokens.soulBtnBg',
    'tokens.soulSecondary',
    'tokens.statusOk',
    'tokens.statusWarn',
    'tokens.statusDanger',
    'tokens.harnessPi',
    'tokens.harnessClaude',
    'tokens.harnessCodex',
    'tokens.harnessOpencode',
    'tokens.harnessByok',
  ];
  for (const tid of lightFgTokens) {
    const fgHex = resolveVar(tid, 'Vellum Light');
    if (!fgHex || !lightCanvas) {
      fail(`pipibot.pen missing Vellum Light resolution for ${tid}`);
      continue;
    }
    const ratio = wcagContrast(fgHex, lightCanvas);
    if (ratio < 4.5) {
      fail(`pipibot.pen Vellum Light ${tid} (${fgHex}) vs ${lightCanvas} contrast ${ratio.toFixed(2)} < 4.5:1`);
    }
  }

  pass(
    `pipibot.pen passed: ${components.length} components, ${screens.length} screens, ${bindingCount} variable bindings (exact fallbackColor), ${textCount} text nodes, ${iconCount} icons, ${clipCount} clip frames, ${buttonCount} buttons, ${sheetCount} sheets, 13 Vellum Light contrast checks (>=4.5:1).`
  );
}

/* --------------------------------------------------------------------------
 * 2. Audit Persistent Design Memory (`design-system/design-system.md`)
 * ------------------------------------------------------------------------ */
function auditDesignMemoryMd() {
  const md = readUtf8('design-system/design-system.md');
  if (!md) return;

  const ruleLines = md.split('\n').filter((line) => line.trim().startsWith('- **Rule**:'));
  if (ruleLines.length < 15) {
    fail(`design-system.md expected >= 15 structured rules, found ${ruleLines.length}`);
  }

  for (const [idx, line] of ruleLines.entries()) {
    const hasReason = line.includes('**Reason**:');
    const hasDate = /\(\d{4}-\d{2}-\d{2}\)\*?\s*$/.test(line.trim());
    if (!hasReason || !hasDate) {
      fail(`design-system.md rule #${idx + 1} violates "sentence + **Reason**: + (YYYY-MM-DD)" format`);
    }
  }

  for (const keyword of ['list-card', 'sheet', 'form-sheet', 'dock', 'bottom-bar', 'empty-state', 'device-pair', 'dynamic-island', '2026-11-19']) {
    if (!md.includes(keyword)) {
      fail(`design-system.md missing required governance concept: ${keyword}`);
    }
  }

  pass(`design-system.md passed: ${ruleLines.length} rules strictly formatted (rule + reason + date).`);
}

/* --------------------------------------------------------------------------
 * 3. Audit Web Companion CSS & HTML (`apps/ios-web/` & `design-system/`)
 * ------------------------------------------------------------------------ */
function auditWebApp() {
  const tokensCss = readUtf8('design-system/tokens.css');
  const dtcgJson = readUtf8('design-system/tokens.dtcg.json');
  const iosCss = readUtf8('apps/ios-web/styles.css');
  const iosHtml = readUtf8('apps/ios-web/index.html');
  const iosJs = readUtf8('apps/ios-web/app.js');

  if (dtcgJson) {
    try {
      const parsed = JSON.parse(dtcgJson);
      if (!parsed.foundations || !parsed.theme || !parsed.tokens) {
        fail('design-system/tokens.dtcg.json must contain foundations, theme, and tokens tiers');
      } else {
        pass('design-system/tokens.dtcg.json valid 3-tier DTCG JSON.');
      }
    } catch (e) {
      fail(`tokens.dtcg.json invalid JSON: ${e.message}`);
    }
  }

  if (tokensCss) {
    for (const tierMarker of ['TIER 1: FOUNDATIONS', 'TIER 2 & TIER 3: OBSIDIAN DARK', 'TIER 2 & TIER 3: WARM VELLUM']) {
      if (!tokensCss.includes(tierMarker)) {
        fail(`design-system/tokens.css missing 3-tier section marker: ${tierMarker}`);
      }
    }
  }

  if (iosCss) {
    const strippedCss = iosCss.replace(/\/\*[\s\S]*?\*\//g, '');
    const hexHits = strippedCss.match(/#(?:[0-9A-Fa-f]{3,8})\b/g) || [];
    const rgbHits = strippedCss.match(/\brgba?\s*\(/gi) || [];
    if (hexHits.length > 0) {
      fail(`apps/ios-web/styles.css contains raw hex colors: ${hexHits.join(', ')}`);
    }
    if (rgbHits.length > 0) {
      fail(`apps/ios-web/styles.css contains raw rgb/rgba literals: ${rgbHits.length} occurrences`);
    }
    for (const blockCls of ['.pipi-list-card', '.pipi-sheet', '.pipi-form-sheet', '.pipi-dock', '.pipi-bottom-bar', '.pipi-empty-state']) {
      if (!iosCss.includes(blockCls)) {
        fail(`apps/ios-web/styles.css missing canonical block class: ${blockCls}`);
      }
    }
    if (hexHits.length === 0 && rgbHits.length === 0) {
      pass('apps/ios-web/styles.css passed: 0 raw hex/rgb literals, all 6 canonical named blocks present.');
    }
  }

  if (iosHtml && iosJs) {
    for (const cls of ['pipi-dock', 'pipi-bottom-bar', 'di-pill-shape', 'di-content-layer']) {
      if (!iosHtml.includes(cls)) {
        fail(`apps/ios-web/index.html missing required structure class: ${cls}`);
      }
    }
    for (const block of ['pipi-list-card', 'pipi-form-sheet', 'pipi-empty-state']) {
      if (!iosHtml.includes(block) && !iosJs.includes(block)) {
        fail(`apps/ios-web missing rendered canonical block: ${block}`);
      }
    }
    pass('apps/ios-web/index.html & app.js verified.');
  }
}

/* --------------------------------------------------------------------------
 * 4. Audit Native Apple SwiftUI Views (`apps/apple/Sources/`) if present
 * ------------------------------------------------------------------------ */
function auditAppleSources() {
  const appleSourcesDir = path.join(REPO_ROOT, 'apps/apple/Sources');
  if (!fs.existsSync(appleSourcesDir)) {
    pass('apps/apple/Sources not present yet (skipped Swift view raw-hex audit).');
    return;
  }

  const swiftFiles = [];
  function walkDir(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walkDir(full);
      else if (entry.isFile() && entry.name.endsWith('.swift')) swiftFiles.push(full);
    }
  }
  walkDir(appleSourcesDir);

  let hasDesignTokens = false;
  let hasCanonicalBlocks = false;
  let auditedViewCount = 0;

  for (const file of swiftFiles) {
    const rel = path.relative(REPO_ROOT, file);
    const content = fs.readFileSync(file, 'utf8');

    if (file.endsWith('DesignTokens.swift')) {
      hasDesignTokens = true;
      continue;
    }
    if (file.endsWith('CanonicalBlocks.swift')) {
      hasCanonicalBlocks = true;
      for (const sym of ['PipiListCard', 'PipiSheet', 'PipiFormSheet', 'PipiDock', 'PipiBottomBar', 'PipiEmptyState']) {
        if (!content.includes(sym)) {
          fail(`${rel} missing canonical SwiftUI block: ${sym}`);
        }
      }
    }

    auditedViewCount++;
    // Strip line & block comments before checking raw color hex literals
    const codeLines = content
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .split('\n')
      .map((l) => l.replace(/\/\/.*$/, ''));

    codeLines.forEach((line, idx) => {
      // Check for "#RRGGBB" / "#RRGGBBAA" color strings
      const colorHexStrings = line.match(/["']#(?:[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8}|[0-9A-Fa-f]{3})["']/g);
      if (colorHexStrings) {
        fail(`${rel}:${idx + 1}: raw hex color string ${colorHexStrings.join(', ')} outside DesignTokens.swift`);
      }
      // Check for Color/UIColor/NSColor/hex 0x... literals (allows PRNG constants like 0x6D2B79F5)
      if (/(?:Color|UIColor|NSColor|hex)\s*[:(][^)]*0x[0-9A-Fa-f]{6,8}/.test(line)) {
        fail(`${rel}:${idx + 1}: raw 0x hex color literal outside DesignTokens.swift`);
      }
    });
  }

  if (!hasDesignTokens) fail('apps/apple/Sources missing DesignTokens.swift');
  if (!hasCanonicalBlocks) fail('apps/apple/Sources missing CanonicalBlocks.swift');

  pass(`apps/apple/Sources passed: audited ${auditedViewCount} Swift files outside DesignTokens.swift (0 raw color hexes, 6 canonical SwiftUI blocks verified).`);
}

/* --------------------------------------------------------------------------
 * Run All Checks
 * ------------------------------------------------------------------------ */
auditPenDocument();
auditDesignMemoryMd();
auditWebApp();
auditAppleSources();

console.log('=== PipiBot Design System Audit ===');
for (const p of passes) console.log(`PASS: ${p}`);
if (errors.length > 0) {
  console.error('\nFAILURES:');
  for (const e of errors) console.error(`  - ${e}`);
  process.exit(1);
}
console.log('\nALL DESIGN SYSTEM GOVERNANCE CHECKS PASSED.');
