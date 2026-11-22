/**
 * PiPiBot — Clean-room MIT implementation.
 * Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
 *
 * @pipibot/daemon - mcp-server.ts
 * Strictly Bounded stdio MCP Server (`pipibot-daemon mcp`) allowing external IDEs/Agents
 * (Claude Code, Cursor, Antigravity) to inspect and coordinate PiPiBot teams safely.
 *
 * Security Boundary (Hard Enforced):
 * - ALLOWED: list nodes/bots/worktrees, read proof/diff summaries, dispatch tasks, preview team templates, run sentinel scan.
 * - HARD BLOCKED (403 FORBIDDEN_BOUNDED_MCP): approve/deny decisions, approve/send draft gates, merge worktrees, delete data, read/write secrets.
 */

import { createInterface } from 'node:readline';

export interface BoundedMCPRequest {
  jsonrpc?: string;
  id?: string | number | null;
  method: string;
  params?: Record<string, unknown>;
}

export interface BoundedMCPResponse {
  jsonrpc: '2.0';
  id: string | number | null;
  result?: unknown;
  error?: { code: number; message: string };
}

export const FORBIDDEN_MCP_TOOLS = new Set([
  'pipibot_approve_decision',
  'pipibot_deny_decision',
  'pipibot_merge_worktree',
  'pipibot_approve_draft',
  'pipibot_delete_bot',
  'pipibot_read_secrets',
  'pipibot_set_credentials',
]);

export const BOUNDED_MCP_TOOLS = [
  {
    name: 'pipibot_list_nodes',
    description: 'List all online/offline machines and CLI agents in the PiPiBot Mesh cluster.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'pipibot_list_worktrees',
    description: 'List active isolated Git worktree review sessions and their Review Proof scores (read-only).',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'pipibot_dispatch_task',
    description: 'Dispatch a task to a target PiPiBot node or agent and return the task ID/status.',
    inputSchema: {
      type: 'object',
      properties: {
        nodeId: { type: 'string', description: 'Optional target node ID or name' },
        prompt: { type: 'string', description: 'Task prompt to execute' },
      },
      required: ['prompt'],
    },
  },
  {
    name: 'pipibot_sentinel_health',
    description: 'Run zero-LLM read-only Sentinel health inspection on the workspace.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'pipibot_list_knowledge_gaps',
    description: 'List recorded Knowledge Gaps and unresolved operational loop questions (read-only).',
    inputSchema: { type: 'object', properties: {} },
  },
];

export async function handleBoundedMCPRequest(
  req: BoundedMCPRequest,
  hubBaseUrl: string,
  authToken?: string,
  fetchFn: typeof fetch = fetch,
): Promise<BoundedMCPResponse> {
  const id = req.id ?? null;

  if (req.method === 'initialize') {
    return {
      jsonrpc: '2.0',
      id,
      result: {
        protocolVersion: '2024-11-05',
        serverInfo: { name: 'pipibot-bounded-mcp', version: '0.15.0' },
        capabilities: { tools: {} },
      },
    };
  }

  if (req.method === 'tools/list') {
    return {
      jsonrpc: '2.0',
      id,
      result: { tools: BOUNDED_MCP_TOOLS },
    };
  }

  if (req.method === 'tools/call') {
    const toolName = String(req.params?.name ?? '');
    const args = (req.params?.arguments as Record<string, unknown> | undefined) ?? {};

    if (FORBIDDEN_MCP_TOOLS.has(toolName) || /approve|merge|delete|secret|credential/i.test(toolName)) {
      return {
        jsonrpc: '2.0',
        id,
        error: {
          code: -32003,
          message: `FORBIDDEN_BOUNDED_MCP: '${toolName}' is blocked on external MCP; human approvals, merges, deletions, and secrets stay in Mac/PWA/WeChat.`,
        },
      };
    }

    const base = hubBaseUrl.replace(/\/+$/, '');
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'X-PiPiBot-Scope': 'mcp_bounded',
    };
    if (authToken) headers.Authorization = `Bearer ${authToken}`;

    try {
      if (toolName === 'pipibot_list_nodes') {
        const r = await fetchFn(`${base}/api/v1/mesh/nodes`, { headers });
        const data = await r.json();
        return { jsonrpc: '2.0', id, result: { content: [{ type: 'text', text: JSON.stringify(data, null, 2) }] } };
      }
      if (toolName === 'pipibot_list_worktrees') {
        const r = await fetchFn(`${base}/api/v1/worktrees`, { headers });
        const data = await r.json();
        return { jsonrpc: '2.0', id, result: { content: [{ type: 'text', text: JSON.stringify(data, null, 2) }] } };
      }
      if (toolName === 'pipibot_sentinel_health') {
        const r = await fetchFn(`${base}/api/v1/sentinel/health`, { headers });
        const data = await r.json();
        return { jsonrpc: '2.0', id, result: { content: [{ type: 'text', text: JSON.stringify(data, null, 2) }] } };
      }
      if (toolName === 'pipibot_list_knowledge_gaps') {
        const r = await fetchFn(`${base}/api/v1/gaps`, { headers });
        const data = await r.json();
        return { jsonrpc: '2.0', id, result: { content: [{ type: 'text', text: JSON.stringify(data, null, 2) }] } };
      }
      if (toolName === 'pipibot_dispatch_task') {
        const prompt = String(args.prompt ?? '').trim();
        if (!prompt) {
          return { jsonrpc: '2.0', id, error: { code: -32602, message: 'prompt is required' } };
        }
        const r = await fetchFn(`${base}/api/v1/mesh/tasks`, {
          method: 'POST',
          headers,
          body: JSON.stringify({
            targetNodeId: args.nodeId ? String(args.nodeId) : undefined,
            prompt,
          }),
        });
        const data = await r.json();
        return { jsonrpc: '2.0', id, result: { content: [{ type: 'text', text: JSON.stringify(data, null, 2) }] } };
      }
      return { jsonrpc: '2.0', id, error: { code: -32601, message: `Unknown MCP tool: ${toolName}` } };
    } catch (err) {
      return { jsonrpc: '2.0', id, error: { code: -32000, message: String(err) } };
    }
  }

  return { jsonrpc: '2.0', id, error: { code: -32601, message: `Method not found: ${req.method}` } };
}

export function runBoundedMCPStdioLoop(hubBaseUrl: string, authToken?: string): void {
  const rl = createInterface({ input: process.stdin, crlfDelay: Infinity });
  rl.on('line', async (line) => {
    const trimmed = line.trim();
    if (!trimmed) return;
    try {
      const req = JSON.parse(trimmed) as BoundedMCPRequest;
      if (req.method === 'notifications/initialized') return;
      const resp = await handleBoundedMCPRequest(req, hubBaseUrl, authToken);
      process.stdout.write(`${JSON.stringify(resp)}\n`);
    } catch (err) {
      process.stdout.write(
        `${JSON.stringify({ jsonrpc: '2.0', id: null, error: { code: -32700, message: String(err) } })}\n`,
      );
    }
  });
}
