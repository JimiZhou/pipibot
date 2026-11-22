/**
 * PiPiBot — Clean-room MIT implementation.
 * Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
 *
 * @pipibot/relay - e2e.ts
 * Zero-dependency, four-platform interoperable E2EE primitives:
 *   P-256 ECDH (65-byte uncompressed x963 public key)
 *   + HKDF-SHA256 (salt="pipibot-e2ee-v1:<hostId>", info="pipibot-aes256gcm-session:<sid>")
 *   + AES-256-GCM (12-byte random nonce, AAD="v1|<sid>|<dir>|<seq>", ciphertext||16-byte tag)
 *
 * Identical wire format across:
 *   - Swift CryptoKit (macOS & iOS)
 *   - Node.js node:crypto (Daemon & Relay tests)
 *   - Browser WebCrypto API (iPhone Safari / Chrome PWA)
 */

import { createCipheriv, createDecipheriv, createECDH, createHash, hkdfSync, randomBytes } from 'node:crypto';

export type E2EEDirection = 'c2h' | 'h2c';

export interface E2EEIdentity {
  hostId: string;
  publicKeyB64Url: string;
  privateKeyHex: string;
}

export interface E2EEEncryptedEnvelope {
  type: 'envelope';
  v: 1;
  hostId: string;
  clientId: string;
  sid: string;
  clientPubKey?: string;
  dir: E2EEDirection;
  seq: number;
  nonce: string;
  ct: string;
}

export interface UniversalPairingLink {
  relayOrigin: string;
  hostId: string;
  hostPublicKeyB64Url: string;
  oneTimeToken: string;
  lanHintURL?: string;
}

export function toBase64Url(buf: Buffer | Uint8Array): string {
  return Buffer.from(buf)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

export function fromBase64Url(input: string): Buffer {
  const normalized = input.replace(/-/g, '+').replace(/_/g, '/');
  const padLen = (4 - (normalized.length % 4)) % 4;
  return Buffer.from(normalized + '='.repeat(padLen), 'base64');
}

export function deriveHostId(publicKeyRaw65: Buffer): string {
  return createHash('sha256').update(publicKeyRaw65).digest('hex').slice(0, 16);
}

export function generateE2EEIdentity(): E2EEIdentity {
  const ecdh = createECDH('prime256v1');
  ecdh.generateKeys();
  const pub = ecdh.getPublicKey();
  const priv = ecdh.getPrivateKey();
  return {
    hostId: deriveHostId(pub),
    publicKeyB64Url: toBase64Url(pub),
    privateKeyHex: priv.toString('hex'),
  };
}

export function deriveSessionKey(
  ownPrivateKeyHex: string,
  peerPublicKeyB64Url: string,
  hostId: string,
  sessionId: string,
): Buffer {
  const ecdh = createECDH('prime256v1');
  ecdh.setPrivateKey(Buffer.from(ownPrivateKeyHex, 'hex'));
  const peerRaw = fromBase64Url(peerPublicKeyB64Url);
  if (peerRaw.length !== 65 || peerRaw[0] !== 0x04) {
    throw new Error('Invalid P-256 uncompressed public key (expected 65 bytes starting with 0x04)');
  }
  const sharedSecret = ecdh.computeSecret(peerRaw);
  const salt = Buffer.from(`pipibot-e2ee-v1:${hostId}`, 'utf8');
  const info = Buffer.from(`pipibot-aes256gcm-session:${sessionId}`, 'utf8');
  return Buffer.from(hkdfSync('sha256', sharedSecret, salt, info, 32));
}

export function sealE2EEFrame(params: {
  sessionKey: Buffer;
  hostId: string;
  clientId: string;
  sid: string;
  dir: E2EEDirection;
  seq: number;
  plaintext: unknown;
  clientPubKey?: string;
}): E2EEEncryptedEnvelope {
  const nonce = randomBytes(12);
  const aad = Buffer.from(`v1|${params.sid}|${params.dir}|${params.seq}`, 'utf8');
  const plainBuf = Buffer.from(
    typeof params.plaintext === 'string' ? params.plaintext : JSON.stringify(params.plaintext),
    'utf8',
  );
  const cipher = createCipheriv('aes-256-gcm', params.sessionKey, nonce);
  cipher.setAAD(aad);
  const encrypted = Buffer.concat([cipher.update(plainBuf), cipher.final()]);
  const tag = cipher.getAuthTag();
  const combined = Buffer.concat([encrypted, tag]);

  const env: E2EEEncryptedEnvelope = {
    type: 'envelope',
    v: 1,
    hostId: params.hostId,
    clientId: params.clientId,
    sid: params.sid,
    dir: params.dir,
    seq: params.seq,
    nonce: toBase64Url(nonce),
    ct: toBase64Url(combined),
  };
  if (params.clientPubKey) env.clientPubKey = params.clientPubKey;
  return env;
}

export function openE2EEFrame<T = unknown>(
  sessionKey: Buffer,
  envelope: E2EEEncryptedEnvelope,
  lastAcceptedSeq?: number,
): T {
  if (envelope.v !== 1) {
    throw new Error(`Unsupported E2EE envelope version: ${String(envelope.v)}`);
  }
  if (!Number.isInteger(envelope.seq) || envelope.seq <= 0) {
    throw new Error('Invalid E2EE sequence number');
  }
  if (lastAcceptedSeq !== undefined && envelope.seq <= lastAcceptedSeq) {
    throw new Error(`Replay detected: seq ${envelope.seq} <= ${lastAcceptedSeq}`);
  }
  const nonce = fromBase64Url(envelope.nonce);
  const combined = fromBase64Url(envelope.ct);
  if (nonce.length !== 12 || combined.length < 16) {
    throw new Error('Malformed E2EE ciphertext or nonce');
  }
  const ciphertext = combined.subarray(0, combined.length - 16);
  const tag = combined.subarray(combined.length - 16);
  const aad = Buffer.from(`v1|${envelope.sid}|${envelope.dir}|${envelope.seq}`, 'utf8');

  const decipher = createDecipheriv('aes-256-gcm', sessionKey, nonce);
  decipher.setAAD(aad);
  decipher.setAuthTag(tag);
  const plain = Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString('utf8');
  return JSON.parse(plain) as T;
}

export function formatUniversalPairingLink(link: UniversalPairingLink): string {
  const origin = link.relayOrigin.replace(/\/+$/, '');
  const parts = [
    `t=${encodeURIComponent(link.oneTimeToken)}`,
    `k=${encodeURIComponent(link.hostPublicKeyB64Url)}`,
  ];
  if (link.lanHintURL && link.lanHintURL.trim()) {
    parts.push(`lan=${encodeURIComponent(link.lanHintURL.trim())}`);
  }
  return `${origin}/c/${encodeURIComponent(link.hostId)}#${parts.join('&')}`;
}

export function parseUniversalPairingLink(rawUrl: string): UniversalPairingLink | null {
  try {
    const parsed = new URL(rawUrl.trim());
    const segs = parsed.pathname.split('/').filter(Boolean);
    if (segs.length < 2 || segs[0] !== 'c' || !segs[1]) return null;
    const hostId = decodeURIComponent(segs[1]);
    const frag = parsed.hash.replace(/^#/, '');
    const params = new URLSearchParams(frag);
    const token = params.get('t') ?? '';
    const pubKey = params.get('k') ?? '';
    if (!token || !pubKey) return null;
    const lan = params.get('lan') ?? undefined;
    return {
      relayOrigin: `${parsed.protocol}//${parsed.host}`,
      hostId,
      hostPublicKeyB64Url: pubKey,
      oneTimeToken: token,
      lanHintURL: lan || undefined,
    };
  } catch {
    return null;
  }
}
