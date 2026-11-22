import { createHmac, randomUUID, timingSafeEqual } from 'node:crypto';

export type DaemonTriggerKind =
  | 'schedule'
  | 'webhook'
  | 'file_or_git_watch'
  | 'channel_message'
  | 'host_health';

export interface DaemonEventRoutine {
  id: string;
  botId: string;
  title: string;
  prompt: string;
  triggerKind: DaemonTriggerKind;
  cronExpression?: string;
  webhookSecret?: string;
  watchPath?: string;
  messageKeyword?: string;
  healthMetric?: 'cpu_percent' | 'memory_percent' | 'disk_free_gb' | 'node_offline';
  healthThreshold?: number;
  cooldownSeconds: number;
  enabled: boolean;
  lastRunAt?: string;
}

export interface DaemonTriggerLog {
  id: string;
  routineId: string;
  title: string;
  triggerKind: DaemonTriggerKind;
  summary: string;
  payloadPreview?: string;
  triggeredAt: string;
}

export function computeWebhookHmac(secret: string, body: Buffer | string): string {
  const mac = createHmac('sha256', secret).update(body).digest('hex');
  return `sha256=${mac}`;
}

export function verifyWebhookSecret(opts: {
  secret?: string;
  authorizationHeader?: string;
  signatureHeader?: string;
  body: Buffer | string;
}): boolean {
  if (!opts.secret || !opts.secret.trim()) return true;
  const trimmed = opts.secret.trim();
  const auth = (opts.authorizationHeader || '').trim();
  if (auth === `Bearer ${trimmed}` || auth === trimmed) return true;
  const sig = (opts.signatureHeader || '').trim().toLowerCase();
  if (!sig) return false;
  const expected = computeWebhookHmac(trimmed, opts.body).toLowerCase();
  const a = Buffer.from(sig, 'utf8');
  const b = Buffer.from(expected, 'utf8');
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

function matchCronField(field: string, value: number, min: number, max: number, isDow = false): boolean {
  for (const part of field.split(',')) {
    const [rangeSpec, stepRaw] = part.split('/');
    const step = stepRaw ? Number.parseInt(stepRaw, 10) : 1;
    if (!Number.isFinite(step) || step <= 0) continue;
    if (rangeSpec === '*') {
      if ((value - min) % step === 0) return true;
      continue;
    }
    if (rangeSpec.includes('-')) {
      const [loRaw, hiRaw] = rangeSpec.split('-');
      let lo = Number.parseInt(loRaw, 10);
      let hi = Number.parseInt(hiRaw, 10);
      if (!Number.isFinite(lo) || !Number.isFinite(hi)) continue;
      if (isDow) {
        if (lo === 7) lo = 0;
        if (hi === 7) hi = 0;
      }
      if (lo <= hi && value >= lo && value <= hi && (value - lo) % step === 0) return true;
    } else {
      let exact = Number.parseInt(rangeSpec, 10);
      if (!Number.isFinite(exact)) continue;
      if (isDow && exact === 7) exact = 0;
      if (exact >= min && exact <= max && value === exact) return true;
    }
  }
  return false;
}

export function matchesCronExpression(expr: string, date: Date = new Date()): boolean {
  const fields = expr.trim().split(/\s+/);
  if (fields.length !== 5) return false;
  return (
    matchCronField(fields[0], date.getMinutes(), 0, 59) &&
    matchCronField(fields[1], date.getHours(), 0, 23) &&
    matchCronField(fields[2], date.getDate(), 1, 31) &&
    matchCronField(fields[3], date.getMonth() + 1, 1, 12) &&
    matchCronField(fields[4], date.getDay(), 0, 7, true)
  );
}

export class DaemonEventTriggerRegistry {
  private readonly routines = new Map<string, DaemonEventRoutine>();
  private readonly logs: DaemonTriggerLog[] = [];

  listRoutines(): DaemonEventRoutine[] {
    return Array.from(this.routines.values());
  }

  listLogs(): DaemonTriggerLog[] {
    return [...this.logs];
  }

  registerRoutine(input: Omit<DaemonEventRoutine, 'id' | 'cooldownSeconds' | 'enabled'> & {
    id?: string;
    cooldownSeconds?: number;
    enabled?: boolean;
  }): DaemonEventRoutine {
    const routine: DaemonEventRoutine = {
      id: input.id || `rt_${randomUUID().slice(0, 8)}`,
      botId: input.botId,
      title: input.title,
      prompt: input.prompt,
      triggerKind: input.triggerKind,
      cronExpression: input.cronExpression,
      webhookSecret: input.webhookSecret,
      watchPath: input.watchPath,
      messageKeyword: input.messageKeyword,
      healthMetric: input.healthMetric,
      healthThreshold: input.healthThreshold,
      cooldownSeconds: Math.max(5, input.cooldownSeconds ?? 60),
      enabled: input.enabled ?? true,
    };
    this.routines.set(routine.id, routine);
    return routine;
  }

  fireWebhook(opts: {
    routineId: string;
    authorizationHeader?: string;
    signatureHeader?: string;
    body: Buffer;
    now?: Date;
  }): { status: number; message: string; log?: DaemonTriggerLog } {
    const routine = this.routines.get(opts.routineId);
    if (!routine) return { status: 404, message: `Routine not found: ${opts.routineId}` };
    if (!routine.enabled || routine.triggerKind !== 'webhook') {
      return { status: 409, message: 'Routine is disabled or not a webhook trigger' };
    }
    if (
      !verifyWebhookSecret({
        secret: routine.webhookSecret,
        authorizationHeader: opts.authorizationHeader,
        signatureHeader: opts.signatureHeader,
        body: opts.body,
      })
    ) {
      return { status: 401, message: 'Invalid webhook signature or Bearer token' };
    }
    const now = opts.now ?? new Date();
    if (routine.lastRunAt) {
      const elapsedSec = (now.getTime() - new Date(routine.lastRunAt).getTime()) / 1000;
      if (elapsedSec < routine.cooldownSeconds) {
        return { status: 429, message: `Cooldown active for ${routine.id}` };
      }
    }
    routine.lastRunAt = now.toISOString();
    const log: DaemonTriggerLog = {
      id: `rtlog_${randomUUID().slice(0, 8)}`,
      routineId: routine.id,
      title: routine.title,
      triggerKind: 'webhook',
      summary: `HTTP Webhook POST /api/v1/webhooks/${routine.id}`,
      payloadPreview: opts.body.toString('utf8').trim().slice(0, 400) || undefined,
      triggeredAt: now.toISOString(),
    };
    this.logs.unshift(log);
    if (this.logs.length > 80) this.logs.length = 80;
    return { status: 202, message: `Triggered ${routine.title}`, log };
  }
}
