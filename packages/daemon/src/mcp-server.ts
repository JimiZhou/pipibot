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
  {
    name: 'pipibot_board_list',
    description: 'List Board channels and task threads (filterable by channelSlug and status).',
    inputSchema: {
      type: 'object',
      properties: {
        channelSlug: { type: 'string', description: 'Optional channel slug such as inbox, dev, ops' },
        status: { type: 'string', enum: ['open', 'blocked', 'claimed', 'needs_you', 'done', 'cancelled'] },
      },
    },
  },
  {
    name: 'pipibot_board_post',
    description: 'Create a new Board task thread or post a progress update reply to an existing threadId.',
    inputSchema: {
      type: 'object',
      properties: {
        threadId: { type: 'string', description: 'Existing thread ID to reply to; omit to create a new thread' },
        channelSlug: { type: 'string', description: 'Target channel slug when creating a new thread' },
        title: { type: 'string', description: 'Thread title when creating a new thread' },
        body: { type: 'string', description: 'Message or task body content' },
        actorId: { type: 'string', description: 'Calling agent identifier (e.g. claude-code, codex)' },
        actorName: { type: 'string', description: 'Human-readable agent name' },
        blockedBy: { type: 'array', items: { type: 'string' }, description: 'Optional prerequisite thread IDs' },
        artifactRef: { type: 'string', description: 'Optional diff, PR URL, or artifact reference' },
      },
      required: ['body'],
    },
  },
  {
    name: 'pipibot_board_claim',
    description: 'Atomically claim a specific Board task thread (or the next open task in a channel) with a TTL lease.',
    inputSchema: {
      type: 'object',
      properties: {
        threadId: { type: 'string', description: 'Optional thread ID; omit to claim next open task in queue' },
        channelSlug: { type: 'string', description: 'Optional channel filter when claiming next open task' },
        actorId: { type: 'string', description: 'Agent identifier claiming the lease' },
        actorName: { type: 'string', description: 'Display name of claiming agent' },
        leaseMs: { type: 'number', description: 'Lease TTL in milliseconds (default 900000 = 15m)' },
        note: { type: 'string', description: 'Optional claim note' },
      },
      required: ['actorId'],
    },
  },
  {
    name: 'pipibot_board_renew',
    description: 'Renew an active Board task lease heartbeat to prevent claim_lost expiry.',
    inputSchema: {
      type: 'object',
      properties: {
        threadId: { type: 'string' },
        actorId: { type: 'string' },
        leaseToken: { type: 'string' },
        leaseMs: { type: 'number' },
      },
      required: ['threadId', 'actorId', 'leaseToken'],
    },
  },
  {
    name: 'pipibot_board_complete',
    description: 'Mark a claimed Board task complete with deliverable summary and automatically unblock downstream tasks.',
    inputSchema: {
      type: 'object',
      properties: {
        threadId: { type: 'string' },
        actorId: { type: 'string' },
        actorName: { type: 'string' },
        leaseToken: { type: 'string' },
        summary: { type: 'string' },
        deliverableRef: { type: 'string' },
      },
      required: ['threadId', 'actorId'],
    },
  },
  {
    name: 'pipibot_board_inspect',
    description: 'Inspect live Board activity events, active leases, and pending follow-ups.',
    inputSchema: {
      type: 'object',
      properties: {
        channelSlug: { type: 'string' },
        limit: { type: 'number' },
      },
    },
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
      if (toolName === 'pipibot_board_list') {
        const qs = new URLSearchParams();
        if (args.channelSlug) qs.set('channel', String(args.channelSlug));
        if (args.status) qs.set('status', String(args.status));
        const suffix = qs.toString() ? `?${qs.toString()}` : '';
        const r = await fetchFn(`${base}/api/v1/board${suffix}`, { headers });
        const data = await r.json();
        return { jsonrpc: '2.0', id, result: { content: [{ type: 'text', text: JSON.stringify(data, null, 2) }] } };
      }
      if (toolName === 'pipibot_board_inspect') {
        const qs = new URLSearchParams();
        if (args.channelSlug) qs.set('channel', String(args.channelSlug));
        if (typeof args.limit === 'number') qs.set('limit', String(args.limit));
        const suffix = qs.toString() ? `?${qs.toString()}` : '';
        const r = await fetchFn(`${base}/api/v1/board/inspect${suffix}`, { headers });
        const data = await r.json();
        return { jsonrpc: '2.0', id, result: { content: [{ type: 'text', text: JSON.stringify(data, null, 2) }] } };
      }
      if (toolName === 'pipibot_board_post') {
        const bodyText = String(args.body ?? '').trim();
        if (!bodyText) {
          return { jsonrpc: '2.0', id, error: { code: -32602, message: 'body is required' } };
        }
        const actor = {
          id: String(args.actorId ?? 'mcp:agent'),
          name: String(args.actorName ?? args.actorId ?? 'MCP Agent'),
          kind: 'harness',
        };
        if (args.threadId) {
          const r = await fetchFn(`${base}/api/v1/board/threads/${encodeURIComponent(String(args.threadId))}/messages`, {
            method: 'POST',
            headers,
            body: JSON.stringify({
              author: actor,
              body: bodyText,
              artifactRef: args.artifactRef ? String(args.artifactRef) : undefined,
            }),
          });
          const data = await r.json();
          return { jsonrpc: '2.0', id, result: { content: [{ type: 'text', text: JSON.stringify(data, null, 2) }] } };
        }
        const title = String(args.title ?? bodyText.slice(0, 72)).trim();
        const r = await fetchFn(`${base}/api/v1/board/threads`, {
          method: 'POST',
          headers,
          body: JSON.stringify({
            channelSlug: args.channelSlug ? String(args.channelSlug) : 'inbox',
            title,
            body: bodyText,
            author: actor,
            blockedBy: Array.isArray(args.blockedBy) ? args.blockedBy.map(String) : undefined,
          }),
        });
        const data = await r.json();
        return { jsonrpc: '2.0', id, result: { content: [{ type: 'text', text: JSON.stringify(data, null, 2) }] } };
      }
      if (toolName === 'pipibot_board_claim') {
        const actorId = String(args.actorId ?? '').trim();
        if (!actorId) {
          return { jsonrpc: '2.0', id, error: { code: -32602, message: 'actorId is required' } };
        }
        const actor = { id: actorId, name: String(args.actorName ?? actorId), kind: 'harness' };
        const endpoint = args.threadId
          ? `${base}/api/v1/board/threads/${encodeURIComponent(String(args.threadId))}/claim`
          : `${base}/api/v1/board/claim-next`;
        const r = await fetchFn(endpoint, {
          method: 'POST',
          headers,
          body: JSON.stringify({
            actor,
            channelSlug: args.channelSlug ? String(args.channelSlug) : undefined,
            leaseMs: typeof args.leaseMs === 'number' ? args.leaseMs : undefined,
            note: args.note ? String(args.note) : undefined,
          }),
        });
        const data = await r.json();
        return { jsonrpc: '2.0', id, result: { content: [{ type: 'text', text: JSON.stringify(data, null, 2) }] } };
      }
      if (toolName === 'pipibot_board_renew') {
        const threadId = String(args.threadId ?? '').trim();
        const actorId = String(args.actorId ?? '').trim();
        const leaseToken = String(args.leaseToken ?? '').trim();
        if (!threadId || !actorId || !leaseToken) {
          return { jsonrpc: '2.0', id, error: { code: -32602, message: 'threadId, actorId, and leaseToken are required' } };
        }
        const r = await fetchFn(`${base}/api/v1/board/threads/${encodeURIComponent(threadId)}/renew`, {
          method: 'POST',
          headers,
          body: JSON.stringify({
            actorId,
            leaseToken,
            leaseMs: typeof args.leaseMs === 'number' ? args.leaseMs : undefined,
          }),
        });
        const data = await r.json();
        return { jsonrpc: '2.0', id, result: { content: [{ type: 'text', text: JSON.stringify(data, null, 2) }] } };
      }
      if (toolName === 'pipibot_board_complete') {
        const threadId = String(args.threadId ?? '').trim();
        const actorId = String(args.actorId ?? '').trim();
        if (!threadId || !actorId) {
          return { jsonrpc: '2.0', id, error: { code: -32602, message: 'threadId and actorId are required' } };
        }
        const r = await fetchFn(`${base}/api/v1/board/threads/${encodeURIComponent(threadId)}/complete`, {
          method: 'POST',
          headers,
          body: JSON.stringify({
            actor: { id: actorId, name: String(args.actorName ?? actorId), kind: 'harness' },
            leaseToken: args.leaseToken ? String(args.leaseToken) : undefined,
            summary: args.summary ? String(args.summary) : undefined,
            deliverableRef: args.deliverableRef ? String(args.deliverableRef) : undefined,
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
