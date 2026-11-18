-- PipiBot Cloudflare D1 Schema (SQLite-compatible)
-- Stores PipiFleet node registry, offline webhook queue, Needs-You escalation inbox,
-- R2 artifact index, Evolution Diff digests, APNs tokens, and Access audit logs.

PRAGMA foreign_keys = ON;

-- 1. Unified Multi-Node Fleet Registry (Mac, iOS, VPS, Windows, Embedded)
CREATE TABLE IF NOT EXISTS fleet_nodes (
  node_id               TEXT PRIMARY KEY,
  display_name          TEXT NOT NULL,
  kind                  TEXT NOT NULL CHECK (kind IN ('mac', 'ios', 'vps', 'windows', 'embedded')),
  os_version            TEXT NOT NULL,
  arch                  TEXT NOT NULL,
  vitality              TEXT NOT NULL CHECK (vitality IN ('alive', 'busy', 'degraded', 'sleeping', 'offline')),
  tunnel_url            TEXT,
  cpu_load_pct          REAL NOT NULL DEFAULT 0,
  memory_used_pct       REAL NOT NULL DEFAULT 0,
  battery_pct           REAL,
  tunnel_rtt_ms         REAL,
  active_sessions_count INTEGER NOT NULL DEFAULT 0,
  capabilities_json     TEXT NOT NULL DEFAULT '{}',
  tags_json             TEXT NOT NULL DEFAULT '[]',
  last_seen_at          TEXT NOT NULL,
  created_at            TEXT NOT NULL,
  updated_at            TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_fleet_nodes_kind_vitality
  ON fleet_nodes(kind, vitality, last_seen_at DESC);

-- 2. Mac <-> iOS Relay Sessions
CREATE TABLE IF NOT EXISTS relay_sessions (
  session_id      TEXT PRIMARY KEY,
  host_node_id    TEXT NOT NULL,
  client_node_id  TEXT NOT NULL,
  status          TEXT NOT NULL CHECK (status IN ('active', 'sleeping_host', 'closed')),
  created_at      TEXT NOT NULL,
  last_active_at  TEXT NOT NULL
);

-- 3. Durable Offline Webhook & Command Queue (queued while Mac is asleep)
CREATE TABLE IF NOT EXISTS offline_webhook_queue (
  id               TEXT PRIMARY KEY,
  idempotency_key  TEXT NOT NULL UNIQUE,
  target_node_id   TEXT NOT NULL,
  source           TEXT NOT NULL CHECK (source IN (
                     'ios_client', 'github_webhook', 'linear_webhook', 'cron_trigger', 'iot_mqtt'
                   )),
  event_type       TEXT NOT NULL,
  payload_json     TEXT NOT NULL,
  status           TEXT NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending', 'delivered', 'acked', 'expired')),
  retry_count      INTEGER NOT NULL DEFAULT 0,
  created_at       TEXT NOT NULL,
  delivered_at     TEXT,
  acked_at         TEXT,
  expires_at       TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_queue_target_pending
  ON offline_webhook_queue(target_node_id, status, created_at ASC);

CREATE INDEX IF NOT EXISTS idx_queue_expires
  ON offline_webhook_queue(expires_at)
  WHERE status IN ('pending', 'delivered');

-- 4. Devin-style "Needs You" Decision Inbox
CREATE TABLE IF NOT EXISTS needs_you_decisions (
  id                     TEXT PRIMARY KEY,
  outcome_id             TEXT,
  session_id             TEXT NOT NULL,
  source_node_id         TEXT NOT NULL,
  severity               TEXT NOT NULL CHECK (severity IN ('info', 'warning', 'critical')),
  category               TEXT NOT NULL,
  title                  TEXT NOT NULL,
  summary                TEXT NOT NULL,
  recommended_option_id  TEXT NOT NULL,
  options_json           TEXT NOT NULL,
  evidence_json          TEXT NOT NULL DEFAULT '[]',
  status                 TEXT NOT NULL DEFAULT 'pending'
                         CHECK (status IN ('pending', 'resolved', 'expired')),
  chosen_option_id       TEXT,
  user_note              TEXT,
  resolved_by            TEXT,
  created_at             TEXT NOT NULL,
  resolved_at            TEXT
);

CREATE INDEX IF NOT EXISTS idx_decisions_status_created
  ON needs_you_decisions(status, created_at DESC);

-- 5. Zero-Egress R2 Artifact Metadata Index (enforces 10GB Free Tier Cap)
CREATE TABLE IF NOT EXISTS artifacts_index (
  artifact_id   TEXT PRIMARY KEY,
  r2_key        TEXT NOT NULL UNIQUE,
  node_id       TEXT NOT NULL,
  session_id    TEXT,
  kind          TEXT NOT NULL CHECK (kind IN (
                  'screenshot', 'video', 'encrypted_memory_backup', 'html_preview', 'log'
                )),
  content_type  TEXT NOT NULL,
  size_bytes    INTEGER NOT NULL CHECK (size_bytes >= 0),
  sha256_hex    TEXT NOT NULL,
  created_at    TEXT NOT NULL,
  expires_at    TEXT
);

CREATE INDEX IF NOT EXISTS idx_artifacts_expires
  ON artifacts_index(expires_at)
  WHERE expires_at IS NOT NULL;

-- 6. Nightly & Weekly Evolution Diff Digests (Synced between Mac and iOS)
CREATE TABLE IF NOT EXISTS evolution_digests (
  digest_id             TEXT PRIMARY KEY,
  node_id               TEXT NOT NULL,
  cycle                 TEXT NOT NULL CHECK (cycle IN ('micro_reflection', 'nightly_dreaming', 'weekly_meta')),
  understanding_score   REAL NOT NULL,
  pending_review_count  INTEGER NOT NULL DEFAULT 0,
  summary_json          TEXT NOT NULL,
  created_at            TEXT NOT NULL,
  updated_at            TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_evolution_created
  ON evolution_digests(created_at DESC);

-- 7. Apple Push Notification Service (APNs) Device & Live Activity Tokens
CREATE TABLE IF NOT EXISTS apns_device_tokens (
  token_id             TEXT PRIMARY KEY,
  node_id              TEXT NOT NULL,
  apns_token           TEXT NOT NULL UNIQUE,
  environment          TEXT NOT NULL DEFAULT 'production' CHECK (environment IN ('production', 'sandbox')),
  live_activity_token  TEXT,
  updated_at           TEXT NOT NULL
);

-- 8. Zero Trust Audit Trail
CREATE TABLE IF NOT EXISTS audit_log (
  id           TEXT PRIMARY KEY,
  actor_email  TEXT,
  auth_kind    TEXT NOT NULL,
  action       TEXT NOT NULL,
  resource_id  TEXT,
  detail_json  TEXT NOT NULL DEFAULT '{}',
  created_at   TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_audit_created
  ON audit_log(created_at DESC);
