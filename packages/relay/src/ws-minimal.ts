/**
 * PiPiBot — Clean-room MIT implementation.
 * Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
 *
 * @pipibot/relay - ws-minimal.ts
 * Zero-dependency RFC 6455 WebSocket Server upgrade helper + Lightweight Client
 * built strictly on Node.js stdlib (`node:crypto`, `node:http`, `node:https`, `node:net`, `node:tls`).
 * Enables instant deployment on Oracle VPS with zero `npm install` packages.
 */

import { createHash, randomBytes } from 'node:crypto';
import type { IncomingMessage } from 'node:http';
import { request as httpRequest } from 'node:http';
import { request as httpsRequest } from 'node:https';
import type { Duplex } from 'node:stream';

const WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

export interface MinimalWebSocket {
  readonly id: string;
  readonly remoteIp: string;
  readonly readyState: 'open' | 'closed';
  sendText(text: string): boolean;
  ping(): void;
  close(code?: number, reason?: string): void;
  onMessage(handler: (text: string) => void): void;
  onClose(handler: () => void): void;
  onError(handler: (err: Error) => void): void;
}

function encodeServerFrame(opcode: number, payload: Buffer, masked: boolean): Buffer {
  const len = payload.length;
  let headerLen = 2;
  if (len >= 126 && len < 65536) headerLen += 2;
  else if (len >= 65536) headerLen += 8;
  const maskLen = masked ? 4 : 0;

  const out = Buffer.allocUnsafe(headerLen + maskLen + len);
  out[0] = 0x80 | (opcode & 0x0f);
  const maskBit = masked ? 0x80 : 0x00;

  let offset = 2;
  if (len < 126) {
    out[1] = maskBit | len;
  } else if (len < 65536) {
    out[1] = maskBit | 126;
    out.writeUInt16BE(len, 2);
    offset = 4;
  } else {
    out[1] = maskBit | 127;
    out.writeBigUInt64BE(BigInt(len), 2);
    offset = 10;
  }

  if (masked) {
    const maskKey = randomBytes(4);
    maskKey.copy(out, offset);
    offset += 4;
    for (let i = 0; i < len; i += 1) {
      out[offset + i] = payload[i]! ^ maskKey[i & 3]!;
    }
  } else {
    payload.copy(out, offset);
  }
  return out;
}

class SocketWebSocket implements MinimalWebSocket {
  readonly id: string;
  readonly remoteIp: string;
  private socket: Duplex;
  private isClient: boolean;
  private maxFrameBytes: number;
  private state: 'open' | 'closed' = 'open';
  private recvBuf: Buffer = Buffer.alloc(0);
  private msgHandlers: Array<(text: string) => void> = [];
  private closeHandlers: Array<() => void> = [];
  private errHandlers: Array<(err: Error) => void> = [];
  private fragmentChunks: Buffer[] = [];
  private fragmentOpcode = 0;

  constructor(socket: Duplex, remoteIp: string, isClient: boolean, maxFrameBytes: number, initialHead?: Buffer) {
    this.id = `ws_${randomBytes(6).toString('hex')}`;
    this.socket = socket;
    this.remoteIp = remoteIp;
    this.isClient = isClient;
    this.maxFrameBytes = maxFrameBytes;

    socket.on('data', (chunk: Buffer) => {
      this.onRawData(chunk);
    });
    socket.on('close', () => {
      this.finishClose();
    });
    socket.on('error', (err: Error) => {
      for (const h of this.errHandlers) h(err);
      this.finishClose();
    });

    if (initialHead && initialHead.length > 0) {
      this.onRawData(initialHead);
    }
  }

  get readyState(): 'open' | 'closed' {
    return this.state;
  }

  sendText(text: string): boolean {
    if (this.state !== 'open' || this.socket.destroyed) return false;
    const payload = Buffer.from(text, 'utf8');
    if (payload.length > this.maxFrameBytes) return false;
    try {
      this.socket.write(encodeServerFrame(0x1, payload, this.isClient));
      return true;
    } catch {
      this.finishClose();
      return false;
    }
  }

  ping(): void {
    if (this.state !== 'open' || this.socket.destroyed) return;
    try {
      this.socket.write(encodeServerFrame(0x9, Buffer.alloc(0), this.isClient));
    } catch {
      this.finishClose();
    }
  }

  close(code = 1000, reason = ''): void {
    if (this.state === 'closed') return;
    const reasonBuf = Buffer.from(reason, 'utf8');
    const payload = Buffer.allocUnsafe(2 + reasonBuf.length);
    payload.writeUInt16BE(code, 0);
    reasonBuf.copy(payload, 2);
    try {
      if (!this.socket.destroyed) {
        this.socket.write(encodeServerFrame(0x8, payload, this.isClient));
      }
      this.socket.end();
    } catch {
      // ignore
    }
    this.finishClose();
  }

  onMessage(handler: (text: string) => void): void {
    this.msgHandlers.push(handler);
  }

  onClose(handler: () => void): void {
    this.closeHandlers.push(handler);
  }

  onError(handler: (err: Error) => void): void {
    this.errHandlers.push(handler);
  }

  private finishClose(): void {
    if (this.state === 'closed') return;
    this.state = 'closed';
    for (const h of this.closeHandlers) {
      try {
        h();
      } catch {
        // ignore
      }
    }
  }

  private onRawData(chunk: Buffer): void {
    if (this.state !== 'open') return;
    this.recvBuf = this.recvBuf.length === 0 ? chunk : Buffer.concat([this.recvBuf, chunk]);

    while (this.recvBuf.length >= 2) {
      const b0 = this.recvBuf[0]!;
      const b1 = this.recvBuf[1]!;
      const fin = (b0 & 0x80) !== 0;
      const opcode = b0 & 0x0f;
      const masked = (b1 & 0x80) !== 0;
      let payloadLen = b1 & 0x7f;
      let offset = 2;

      if (payloadLen === 126) {
        if (this.recvBuf.length < 4) return;
        payloadLen = this.recvBuf.readUInt16BE(2);
        offset = 4;
      } else if (payloadLen === 127) {
        if (this.recvBuf.length < 10) return;
        const bigLen = this.recvBuf.readBigUInt64BE(2);
        if (bigLen > BigInt(this.maxFrameBytes)) {
          this.close(1009, 'Frame too large');
          return;
        }
        payloadLen = Number(bigLen);
        offset = 10;
      }

      if (payloadLen > this.maxFrameBytes) {
        this.close(1009, 'Frame too large');
        return;
      }

      const maskLen = masked ? 4 : 0;
      const totalFrameLen = offset + maskLen + payloadLen;
      if (this.recvBuf.length < totalFrameLen) return;

      let payload = Buffer.from(this.recvBuf.subarray(offset + maskLen, totalFrameLen));
      if (masked) {
        const maskKey = this.recvBuf.subarray(offset, offset + 4);
        for (let i = 0; i < payload.length; i += 1) {
          payload[i] = payload[i]! ^ maskKey[i & 3]!;
        }
      }
      this.recvBuf = this.recvBuf.subarray(totalFrameLen);

      if (opcode === 0x8) {
        this.close(1000);
        return;
      }
      if (opcode === 0x9) {
        // Ping -> Pong
        if (!this.socket.destroyed) {
          this.socket.write(encodeServerFrame(0xa, payload, this.isClient));
        }
        continue;
      }
      if (opcode === 0xa) {
        // Pong
        continue;
      }
      if (opcode === 0x1 || opcode === 0x2) {
        if (fin) {
          const text = payload.toString('utf8');
          for (const h of this.msgHandlers) h(text);
        } else {
          this.fragmentOpcode = opcode;
          this.fragmentChunks = [payload];
        }
      } else if (opcode === 0x0 && this.fragmentOpcode !== 0) {
        this.fragmentChunks.push(payload);
        const totalSize = this.fragmentChunks.reduce((acc, b) => acc + b.length, 0);
        if (totalSize > this.maxFrameBytes) {
          this.close(1009, 'Fragmented message too large');
          return;
        }
        if (fin) {
          const full = Buffer.concat(this.fragmentChunks);
          this.fragmentChunks = [];
          this.fragmentOpcode = 0;
          const text = full.toString('utf8');
          for (const h of this.msgHandlers) h(text);
        }
      }
    }
  }
}

export function extractClientIp(req: IncomingMessage): string {
  const cfIp = req.headers['cf-connecting-ip'];
  if (typeof cfIp === 'string' && cfIp.trim()) return cfIp.trim();
  const xff = req.headers['x-forwarded-for'];
  if (typeof xff === 'string' && xff.trim()) {
    return xff.split(',')[0]?.trim() || '127.0.0.1';
  }
  return req.socket.remoteAddress ?? '127.0.0.1';
}

export function acceptWebSocketUpgrade(
  req: IncomingMessage,
  socket: Duplex,
  head: Buffer,
  maxFrameBytes = 512 * 1024,
): MinimalWebSocket | null {
  const key = req.headers['sec-websocket-key'];
  if (typeof key !== 'string' || !key) {
    socket.write('HTTP/1.1 400 Bad Request\r\n\r\n');
    socket.destroy();
    return null;
  }
  const accept = createHash('sha1').update(`${key}${WS_GUID}`).digest('base64');
  socket.write(
    [
      'HTTP/1.1 101 Switching Protocols',
      'Upgrade: websocket',
      'Connection: Upgrade',
      `Sec-WebSocket-Accept: ${accept}`,
      '',
      '',
    ].join('\r\n'),
  );
  return new SocketWebSocket(socket, extractClientIp(req), false, maxFrameBytes, head);
}

export function connectMinimalWebSocket(
  wsUrl: string,
  options?: { headers?: Record<string, string>; maxFrameBytes?: number; timeoutMs?: number },
): Promise<MinimalWebSocket> {
  return new Promise((resolve, reject) => {
    const parsed = new URL(wsUrl);
    const isSecure = parsed.protocol === 'wss:';
    const key = randomBytes(16).toString('base64');
    const expectedAccept = createHash('sha1').update(`${key}${WS_GUID}`).digest('base64');
    const reqFn = isSecure ? httpsRequest : httpRequest;

    const req = reqFn({
      hostname: parsed.hostname,
      port: parsed.port || (isSecure ? 443 : 80),
      path: `${parsed.pathname}${parsed.search}`,
      method: 'GET',
      timeout: options?.timeoutMs ?? 8000,
      headers: {
        Upgrade: 'websocket',
        Connection: 'Upgrade',
        'Sec-WebSocket-Key': key,
        'Sec-WebSocket-Version': '13',
        ...(options?.headers ?? {}),
      },
    });

    req.on('upgrade', (res, socket, head) => {
      const accept = res.headers['sec-websocket-accept'];
      if (accept !== expectedAccept) {
        socket.destroy();
        reject(new Error('WebSocket handshake Sec-WebSocket-Accept mismatch'));
        return;
      }
      resolve(new SocketWebSocket(socket, parsed.hostname, true, options?.maxFrameBytes ?? 512 * 1024, head));
    });

    req.on('response', (res) => {
      reject(new Error(`WebSocket upgrade rejected with HTTP ${res.statusCode ?? 0}`));
      res.resume();
    });
    req.on('timeout', () => {
      req.destroy(new Error('WebSocket connect timeout'));
    });
    req.on('error', (err) => {
      reject(err);
    });
    req.end();
  });
}
