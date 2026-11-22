/**
 * PiPiBot — Clean-room MIT implementation.
 * Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
 *
 * @pipibot/daemon - ecosystem.ts
 * Native MCP Server (stdio + SSE/HTTP) & standard SKILL.md community ecosystem manager.
 * Runs identically on macOS and headless Linux servers, synced across Hub & Nodes.
 */

import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { basename, join, resolve } from 'node:path';
import { randomUUID } from 'node:crypto';

export interface InstalledSkillPack {
  id: string;
  name: string;
  description: string;
  source: string;
  scope: 'global' | 'host' | 'bot';
  targetId?: string;
  tags: string[];
  bodyMarkdown: string;
  installedAt: string;
  enabled: boolean;
}

export interface InstalledMCPServer {
  id: string;
  name: string;
  description: string;
  transport: 'stdio' | 'sse';
  command?: string;
  args?: string[];
  url?: string;
  env?: Record<string, string>;
  scope: 'global' | 'host' | 'bot';
  targetId?: string;
  enabled: boolean;
  installedAt: string;
}

export interface MCPToolSchema {
  name: string;
  description: string;
  inputSchema: Record<string, unknown>;
}

export interface CuratedCatalogEntry {
  id: string;
  kind: 'mcp' | 'skill';
  name: string;
  description: string;
  tags: string[];
  installSpec: string;
  mcpCommand?: string;
  mcpArgs?: string[];
  skillMarkdown?: string;
}

export const CURATED_ECOSYSTEM_CATALOG: readonly CuratedCatalogEntry[] = [
  {
    id: 'mcp-filesystem',
    kind: 'mcp',
    name: 'Filesystem MCP',
    description: 'Official community MCP server for structured directory & file operations on any Linux/Mac node.',
    tags: ['files', 'official', 'free'],
    installSpec: '@modelcontextprotocol/server-filesystem',
    mcpCommand: 'npx',
    mcpArgs: ['-y', '@modelcontextprotocol/server-filesystem', '.'],
  },
  {
    id: 'mcp-fetch',
    kind: 'mcp',
    name: 'Web Fetch MCP',
    description: 'Fetch and convert web pages/docs to clean Markdown via MCP.',
    tags: ['web', 'research', 'free'],
    installSpec: '@modelcontextprotocol/server-fetch',
    mcpCommand: 'npx',
    mcpArgs: ['-y', '@modelcontextprotocol/server-fetch'],
  },
  {
    id: 'mcp-memory',
    kind: 'mcp',
    name: 'Knowledge Graph Memory MCP',
    description: 'Persistent entity & relation graph memory shared across agents.',
    tags: ['memory', 'graph', 'free'],
    installSpec: '@modelcontextprotocol/server-memory',
    mcpCommand: 'npx',
    mcpArgs: ['-y', '@modelcontextprotocol/server-memory'],
  },
  {
    id: 'skill-linux-ops',
    kind: 'skill',
    name: 'Linux & GPU Ops Expert',
    description: 'Diagnoses systemd units, Docker containers, ports, disk usage, and NVIDIA GPU memory cleanly.',
    tags: ['linux', 'gpu', 'devops'],
    installSpec: 'builtin:skill-linux-ops',
    skillMarkdown: [
      '---',
      'name: Linux & GPU Ops Expert',
      'description: Diagnose systemd services, NVIDIA GPUs, ports, and disk pressure safely.',
      'tags: [linux, gpu, devops]',
      '---',
      '# Linux & GPU Ops Skill',
      '- Prefer read-only probes first (`nvidia-smi`, `df -h`, `ss -tulpn`, `systemctl status`).',
      '- Summarize bottlenecks in plain language before suggesting any restart or cleanup.',
    ].join('\n'),
  },
  {
    id: 'skill-code-reviewer',
    kind: 'skill',
    name: 'PR & Architecture Reviewer',
    description: 'Performs structured security, concurrency, and regression reviews on git diffs.',
    tags: ['code', 'review', 'git'],
    installSpec: 'builtin:skill-code-reviewer',
    skillMarkdown: [
      '---',
      'name: PR & Architecture Reviewer',
      'description: Structured security, concurrency, and regression checks on code changes.',
      'tags: [code, review, git]',
      '---',
      '# Code Review Skill',
      '- Check correctness, error handling, race conditions, and secret leaks first.',
      '- Cite exact file paths and concrete minimal fixes.',
    ].join('\n'),
  },
];

export function parseSkillMarkdown(rawMarkdown: string, fallbackName = 'Custom Skill'): {
  name: string;
  description: string;
  tags: string[];
  bodyMarkdown: string;
} {
  const trimmed = rawMarkdown.trim();
  let name = fallbackName;
  let description = 'Community SKILL.md pack';
  let tags: string[] = [];
  let body = trimmed;

  if (trimmed.startsWith('---')) {
    const endIdx = trimmed.indexOf('\n---', 3);
    if (endIdx !== -1) {
      const fm = trimmed.slice(3, endIdx).trim();
      body = trimmed.slice(endIdx + 4).trim();
      for (const line of fm.split(/\r?\n/)) {
        const colon = line.indexOf(':');
        if (colon === -1) continue;
        const key = line.slice(0, colon).trim().toLowerCase();
        const val = line.slice(colon + 1).trim().replace(/^["']|["']$/g, '');
        if (key === 'name' && val) name = val;
        if (key === 'description' && val) description = val;
        if (key === 'tags' && val) {
          tags = val
            .replace(/^\[|\]$/g, '')
            .split(/[,，]/)
            .map((t) => t.trim().replace(/^["']|["']$/g, ''))
            .filter(Boolean);
        }
      }
    }
  }

  return { name, description, tags, bodyMarkdown: body };
}

export class EcosystemRegistry {
  private readonly filePath: string;
  private skills: InstalledSkillPack[] = [];
  private mcpServers: InstalledMCPServer[] = [];

  constructor(storageDir: string) {
    mkdirSync(storageDir, { recursive: true });
    this.filePath = join(storageDir, 'ecosystem.json');
    this.load();
  }

  private load(): void {
    if (!existsSync(this.filePath)) return;
    try {
      const parsed = JSON.parse(readFileSync(this.filePath, 'utf8')) as {
        skills?: InstalledSkillPack[];
        mcpServers?: InstalledMCPServer[];
      };
      this.skills = Array.isArray(parsed.skills) ? parsed.skills : [];
      this.mcpServers = Array.isArray(parsed.mcpServers) ? parsed.mcpServers : [];
    } catch {
      this.skills = [];
      this.mcpServers = [];
    }
  }

  private save(): void {
    try {
      writeFileSync(
        this.filePath,
        JSON.stringify({ skills: this.skills, mcpServers: this.mcpServers }, null, 2),
        'utf8',
      );
    } catch {
      // Ignore transient write failures
    }
  }

  public getSnapshot(): {
    catalog: readonly CuratedCatalogEntry[];
    skills: InstalledSkillPack[];
    mcpServers: InstalledMCPServer[];
  } {
    return {
      catalog: CURATED_ECOSYSTEM_CATALOG,
      skills: [...this.skills],
      mcpServers: [...this.mcpServers],
    };
  }

  public upsertSkill(input: {
    id?: string;
    source: string;
    rawMarkdown?: string;
    name?: string;
    description?: string;
    scope?: 'global' | 'host' | 'bot';
    targetId?: string;
  }): InstalledSkillPack {
    let rawMd = input.rawMarkdown ?? '';
    const trimmedSource = input.source.trim();

    // Check curated builtin catalog
    const catalogHit = CURATED_ECOSYSTEM_CATALOG.find(
      (c) => c.kind === 'skill' && (c.id === trimmedSource || c.installSpec === trimmedSource),
    );
    if (!rawMd && catalogHit?.skillMarkdown) {
      rawMd = catalogHit.skillMarkdown;
    }

    // Check local directory or SKILL.md path
    if (!rawMd && trimmedSource && !trimmedSource.startsWith('http://') && !trimmedSource.startsWith('https://')) {
      const resolved = resolve(trimmedSource);
      if (existsSync(resolved)) {
        const directSkill = existsSync(join(resolved, 'SKILL.md')) ? join(resolved, 'SKILL.md') : resolved;
        if (existsSync(directSkill) && directSkill.endsWith('.md')) {
          rawMd = readFileSync(directSkill, 'utf8');
        } else if (existsSync(resolved)) {
          try {
            const firstMd = readdirSync(resolved).find((f) => f.toLowerCase() === 'skill.md');
            if (firstMd) rawMd = readFileSync(join(resolved, firstMd), 'utf8');
          } catch {
            // ignore
          }
        }
      }
    }

    const parsed = parseSkillMarkdown(
      rawMd || `# ${input.name ?? basename(trimmedSource)}\nInstalled from ${trimmedSource}`,
      input.name ?? catalogHit?.name ?? (basename(trimmedSource) || 'Custom Skill'),
    );

    const id = input.id ?? catalogHit?.id ?? `skill_${randomUUID().slice(0, 8)}`;
    const pack: InstalledSkillPack = {
      id,
      name: input.name ?? parsed.name,
      description: input.description ?? parsed.description,
      source: trimmedSource,
      scope: input.scope ?? 'global',
      targetId: input.targetId,
      tags: parsed.tags,
      bodyMarkdown: parsed.bodyMarkdown,
      installedAt: new Date().toISOString(),
      enabled: true,
    };

    const idx = this.skills.findIndex((s) => s.id === id);
    if (idx >= 0) this.skills[idx] = pack;
    else this.skills.push(pack);
    this.save();
    return pack;
  }

  public async installSkillFromGitHubOrSource(input: {
    source: string;
    scope?: 'global' | 'host' | 'bot';
    targetId?: string;
  }): Promise<InstalledSkillPack> {
    const src = input.source.trim();
    let rawMarkdown = '';
    let fallbackName: string | undefined;

    // Support GitHub repo URL or raw SKILL.md URL
    if (src.startsWith('https://github.com/')) {
      const clean = src.replace(/\/+$/, '').replace(/\.git$/, '');
      const parts = clean.replace('https://github.com/', '').split('/');
      if (parts.length >= 2) {
        const [owner, repo] = parts;
        fallbackName = repo;
        const candidates = [
          `https://raw.githubusercontent.com/${owner}/${repo}/main/SKILL.md`,
          `https://raw.githubusercontent.com/${owner}/${repo}/master/SKILL.md`,
          `https://raw.githubusercontent.com/${owner}/${repo}/main/README.md`,
        ];
        for (const url of candidates) {
          try {
            const resp = await fetch(url, { signal: AbortSignal.timeout(8000) });
            if (resp.ok) {
              rawMarkdown = await resp.text();
              break;
            }
          } catch {
            // try next candidate
          }
        }
      }
    } else if (src.startsWith('https://') || src.startsWith('http://')) {
      try {
        const resp = await fetch(src, { signal: AbortSignal.timeout(8000) });
        if (resp.ok) rawMarkdown = await resp.text();
      } catch {
        // fallback to stub
      }
    }

    return this.upsertSkill({
      source: src,
      rawMarkdown: rawMarkdown || undefined,
      name: fallbackName,
      scope: input.scope,
      targetId: input.targetId,
    });
  }

  public upsertMCPServer(input: {
    id?: string;
    name: string;
    description?: string;
    transport?: 'stdio' | 'sse';
    command?: string;
    args?: string[];
    url?: string;
    env?: Record<string, string>;
    scope?: 'global' | 'host' | 'bot';
    targetId?: string;
  }): InstalledMCPServer {
    const id = input.id ?? `mcp_${randomUUID().slice(0, 8)}`;
    const server: InstalledMCPServer = {
      id,
      name: input.name,
      description: input.description ?? 'Community MCP Server',
      transport: input.transport ?? (input.url ? 'sse' : 'stdio'),
      command: input.command,
      args: input.args,
      url: input.url,
      env: input.env,
      scope: input.scope ?? 'global',
      targetId: input.targetId,
      enabled: true,
      installedAt: new Date().toISOString(),
    };
    const idx = this.mcpServers.findIndex((m) => m.id === id);
    if (idx >= 0) this.mcpServers[idx] = server;
    else this.mcpServers.push(server);
    this.save();
    return server;
  }

  public removeSkill(id: string): boolean {
    const before = this.skills.length;
    this.skills = this.skills.filter((s) => s.id !== id);
    if (this.skills.length !== before) {
      this.save();
      return true;
    }
    return false;
  }

  public removeMCPServer(id: string): boolean {
    const before = this.mcpServers.length;
    this.mcpServers = this.mcpServers.filter((m) => m.id !== id);
    if (this.mcpServers.length !== before) {
      this.save();
      return true;
    }
    return false;
  }
}

/**
 * Lightweight JSON-RPC 2.0 MCP stdio tool discovery & invocation helper for Linux/macOS nodes.
 */
export async function probeStdioMCPTools(
  command: string,
  args: string[] = [],
  env: Record<string, string> = {},
  timeoutMs = 8000,
): Promise<MCPToolSchema[]> {
  return new Promise((resolveTools) => {
    const child = spawn(command, args, {
      env: { ...process.env, ...env },
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    let buffer = '';
    let settled = false;

    const finish = (tools: MCPToolSchema[]) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      try {
        child.kill('SIGTERM');
      } catch {
        // ignore
      }
      resolveTools(tools);
    };

    const timer = setTimeout(() => finish([]), timeoutMs);

    child.on('error', () => finish([]));
    child.stdout.on('data', (chunk: Buffer) => {
      buffer += chunk.toString('utf8');
      const lines = buffer.split('\n');
      buffer = lines.pop() ?? '';
      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed.startsWith('{')) continue;
        try {
          const msg = JSON.parse(trimmed) as { id?: number; result?: { tools?: MCPToolSchema[] } };
          if (msg.id === 1) {
            child.stdin.write(
              `${JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' })}\n`,
            );
            child.stdin.write(
              `${JSON.stringify({ jsonrpc: '2.0', id: 2, method: 'tools/list', params: {} })}\n`,
            );
          } else if (msg.id === 2) {
            finish(Array.isArray(msg.result?.tools) ? msg.result.tools : []);
          }
        } catch {
          // ignore malformed line
        }
      }
    });

    child.stdin.write(
      `${JSON.stringify({
        jsonrpc: '2.0',
        id: 1,
        method: 'initialize',
        params: {
          protocolVersion: '2024-11-05',
          capabilities: {},
          clientInfo: { name: 'pipibot-mesh-node', version: '0.12.0' },
        },
      })}\n`,
    );
  });
}
