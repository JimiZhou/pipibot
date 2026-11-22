#!/usr/bin/env node
/**
 * PiPiBot — Clean-room MIT implementation.
 * Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
 *
 * @pipibot/relay - cli.ts
 * Standalone Zero-Knowledge E2EE Relay Server CLI (`pipibot-relay`).
 */

import { realpathSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

import { PipiE2EERelayServer } from './server.ts';

function printHelp(): void {
  console.log(`PiPiBot Zero-Knowledge E2EE Relay Server

Usage:
  pipibot-relay [--host 127.0.0.1] [--port 9191] [--stun-port 0]

Environment Variables:
  PIPIBOT_RELAY_HOST                Bind host (default: 127.0.0.1)
  PIPIBOT_RELAY_PORT                Bind port (default: 9191)
  PIPIBOT_RELAY_STUN_PORT           Optional UDP STUN reflector port (default: 0 / off)
  PIPIBOT_RELAY_MAX_CONN_PER_IP     Per-IP max concurrent WS connections (default: 24)
  PIPIBOT_RELAY_MAX_CLIENTS_HOST    Max concurrent clients per hostId (default: 12)
  PIPIBOT_RELAY_INVITE_KEYS         Comma-separated invite keys (empty = open public mode)
`);
}

async function main(): Promise<void> {
  const argv = process.argv.slice(2);
  if (argv.includes('--help') || argv.includes('-h')) {
    printHelp();
    return;
  }

  let host = process.env.PIPIBOT_RELAY_HOST ?? '127.0.0.1';
  let port = Number(process.env.PIPIBOT_RELAY_PORT ?? '9191');
  let stunUdpPort = Number(process.env.PIPIBOT_RELAY_STUN_PORT ?? '0');

  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === '--host' && argv[i + 1]) {
      host = argv[i + 1]!;
      i += 1;
    } else if (argv[i] === '--port' && argv[i + 1]) {
      port = Number(argv[i + 1]!);
      i += 1;
    } else if (argv[i] === '--stun-port' && argv[i + 1]) {
      stunUdpPort = Number(argv[i + 1]!);
      i += 1;
    }
  }

  const inviteKeys = (process.env.PIPIBOT_RELAY_INVITE_KEYS ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);

  const server = new PipiE2EERelayServer({
    host,
    port,
    stunUdpPort,
    maxConnectionsPerIp: Number(process.env.PIPIBOT_RELAY_MAX_CONN_PER_IP ?? '24'),
    maxClientsPerHost: Number(process.env.PIPIBOT_RELAY_MAX_CLIENTS_HOST ?? '12'),
    inviteKeys,
  });

  const info = await server.start();
  console.log(
    `[pipibot-relay] listening on http://${info.host}:${info.port} (ws: /ws, health: /healthz, inviteOnly: ${inviteKeys.length > 0}${info.stunPort > 0 ? `, stun-udp: ${info.stunPort}` : ''})`,
  );

  const shutdown = async () => {
    await server.stop();
    process.exit(0);
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

const isEntrypoint = (() => {
  if (!process.argv[1]) return false;
  try {
    return import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href;
  } catch {
    return false;
  }
})();

if (isEntrypoint) {
  main().catch((err) => {
    console.error('[pipibot-relay] fatal:', err);
    process.exit(1);
  });
}
