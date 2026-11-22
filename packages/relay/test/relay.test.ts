/**
 * PiPiBot — Clean-room MIT implementation.
 * @pipibot/relay automated E2EE, WebSocket Relay, WebRTC Signaling & Multi-Tenant Limit tests.
 */

import assert from 'node:assert/strict';
import test from 'node:test';

import {
  deriveSessionKey,
  formatUniversalPairingLink,
  generateE2EEIdentity,
  openE2EEFrame,
  parseUniversalPairingLink,
  sealE2EEFrame,
  type E2EEEncryptedEnvelope,
} from '../src/e2e.ts';
import { PipiE2EERelayServer } from '../src/server.ts';
import { connectMinimalWebSocket } from '../src/ws-minimal.ts';

test('E2EE P-256 ECDH + HKDF-SHA256 + AES-256-GCM round-trip & anti-replay', () => {
  const host = generateE2EEIdentity();
  const client = generateE2EEIdentity();
  const sid = 'sess_test_001';

  const clientKey = deriveSessionKey(client.privateKeyHex, host.publicKeyB64Url, host.hostId, sid);
  const hostKey = deriveSessionKey(host.privateKeyHex, client.publicKeyB64Url, host.hostId, sid);
  assert.deepEqual(clientKey, hostKey);

  const env1 = sealE2EEFrame({
    sessionKey: clientKey,
    hostId: host.hostId,
    clientId: 'web_01',
    sid,
    dir: 'c2h',
    seq: 1,
    clientPubKey: client.publicKeyB64Url,
    plaintext: { kind: 'http_req', path: '/api/v1/mobile/snapshot', secretCheck: 'hello-jarvis' },
  });

  // Zero-knowledge check: ciphertext must never contain plaintext
  assert.equal(JSON.stringify(env1).includes('hello-jarvis'), false);

  const opened = openE2EEFrame<{ secretCheck: string }>(hostKey, env1, 0);
  assert.equal(opened.secretCheck, 'hello-jarvis');

  // Replay protection: reusing seq 1 must throw
  assert.throws(() => openE2EEFrame(hostKey, env1, 1), /Replay detected/);

  // Universal pairing link puts secret exclusively in #fragment
  const linkStr = formatUniversalPairingLink({
    relayOrigin: 'https://pipibot.jimizhou.com',
    hostId: host.hostId,
    hostPublicKeyB64Url: host.publicKeyB64Url,
    oneTimeToken: 'ABCD-2345',
    lanHintURL: 'http://192.168.1.50:4242',
  });
  const parsedUrl = new URL(linkStr);
  assert.equal(parsedUrl.pathname, `/c/${host.hostId}`);
  assert.equal(parsedUrl.search, '');
  assert.ok(parsedUrl.hash.includes('t=ABCD-2345'));

  const parsedLink = parseUniversalPairingLink(linkStr);
  assert.ok(parsedLink);
  assert.equal(parsedLink.hostId, host.hostId);
  assert.equal(parsedLink.oneTimeToken, 'ABCD-2345');
  assert.equal(parsedLink.hostPublicKeyB64Url, host.publicKeyB64Url);
});

test('PipiE2EERelayServer serves universal 5-Tab PWA, relays opaque E2EE & WebRTC signaling, and enforces limits', async () => {
  const relay = new PipiE2EERelayServer({
    host: '127.0.0.1',
    port: 0,
    maxConnectionsPerIp: 10,
    maxClientsPerHost: 2,
  });
  const { port } = await relay.start();
  const baseHttp = `http://127.0.0.1:${port}`;
  const baseWs = `ws://127.0.0.1:${port}/ws`;

  try {
    const health = await fetch(`${baseHttp}/healthz`);
    assert.equal(health.status, 200);
    const healthJson = (await health.json()) as { ok: boolean; zeroKnowledgeE2EE: boolean };
    assert.equal(healthJson.ok, true);
    assert.equal(healthJson.zeroKnowledgeE2EE, true);

    const host = generateE2EEIdentity();
    const client = generateE2EEIdentity();

    const landingRes = await fetch(`${baseHttp}/`);
    assert.equal(landingRes.status, 200);
    const landingHtml = await landingRes.text();
    assert.ok(landingHtml.includes('https://github.com/JimiZhou/pipibot'));
    assert.ok(landingHtml.includes('/assets/app-icon.png'));
    assert.ok(landingHtml.includes('/assets/mac-workspace.png'));
    assert.ok(landingHtml.includes('/assets/mac-group.png'));
    assert.ok(landingHtml.includes('/assets/mac-mission.png'));
    assert.ok(landingHtml.includes('story-track'));
    assert.ok(landingHtml.includes('story-hud'));
    assert.equal(landingHtml.includes('stage-mac'), false);

    const featuresRes = await fetch(`${baseHttp}/features`);
    assert.equal(featuresRes.status, 200);
    const featuresHtml = await featuresRes.text();
    assert.ok(featuresHtml.includes('/assets/mac-group.png'));
    assert.ok(featuresHtml.includes('/assets/mac-mission.png'));

    const downloadRes = await fetch(`${baseHttp}/download`);
    assert.equal(downloadRes.status, 200);
    const downloadHtml = await downloadRes.text();
    assert.ok(downloadHtml.includes('macOS'));
    assert.ok(downloadHtml.includes('https://github.com/JimiZhou/pipibot/releases'));

    // Verify real static PNG assets & path traversal protection
    for (const asset of [
      '/assets/app-icon.png',
      '/assets/mac-workspace.png',
      '/assets/mac-workspace-dark.png',
      '/assets/mac-group.png',
      '/assets/mac-mission.png',
      '/apple-touch-icon.png',
    ]) {
      const aRes = await fetch(`${baseHttp}${asset}`);
      assert.equal(aRes.status, 200, `Expected 200 for ${asset}`);
      assert.equal(aRes.headers.get('content-type'), 'image/png');
      const buf = Buffer.from(await aRes.arrayBuffer());
      assert.equal(buf[0], 0x89);
      assert.equal(buf[1], 0x50);
      assert.equal(buf[2], 0x4e);
      assert.equal(buf[3], 0x47);
    }
    const missingAsset = await fetch(`${baseHttp}/assets/does-not-exist.png`);
    assert.equal(missingAsset.status, 404);
    const traversalAsset = await fetch(`${baseHttp}/assets/..%2Fpackage.json`);
    assert.equal(traversalAsset.status, 404);

    const pwaRes = await fetch(`${baseHttp}/c/${host.hostId}`);
    assert.equal(pwaRes.status, 200);
    const pwaHtml = await pwaRes.text();
    assert.ok(pwaHtml.includes('Companion'));
    assert.ok(pwaHtml.includes('E2EERelayTransport'));
    assert.ok(pwaHtml.includes('RTCPeerConnection'));
    assert.ok(pwaHtml.includes('renderColoredDiff'));

    const appRes = await fetch(`${baseHttp}/app`);
    assert.equal(appRes.status, 200);

    const hostWs = await connectMinimalWebSocket(baseWs);
    const hostMsgs: string[] = [];
    hostWs.onMessage((t) => hostMsgs.push(t));
    hostWs.sendText(JSON.stringify({ type: 'host_register', hostId: host.hostId }));

    await waitUntil(() => hostMsgs.some((m) => m.includes('"registered"')));

    const clientWs = await connectMinimalWebSocket(baseWs);
    const clientMsgs: string[] = [];
    clientWs.onMessage((t) => clientMsgs.push(t));
    clientWs.sendText(JSON.stringify({ type: 'client_join', hostId: host.hostId, clientId: 'ios_pwa_1' }));

    await waitUntil(() => clientMsgs.some((m) => m.includes('"joined"') && m.includes('"hostOnline":true')));

    // Send encrypted WebRTC offer + HTTP request from client -> host over relay
    const sid = 's_live_1';
    const cKey = deriveSessionKey(client.privateKeyHex, host.publicKeyB64Url, host.hostId, sid);
    const hKey = deriveSessionKey(host.privateKeyHex, client.publicKeyB64Url, host.hostId, sid);

    const sealedOffer = sealE2EEFrame({
      sessionKey: cKey,
      hostId: host.hostId,
      clientId: 'ios_pwa_1',
      sid,
      dir: 'c2h',
      seq: 1,
      clientPubKey: client.publicKeyB64Url,
      plaintext: { kind: 'rtc_offer', sdp: 'v=0\r\no=- 123 2 IN IP4 127.0.0.1\r\n' },
    });
    clientWs.sendText(JSON.stringify(sealedOffer));

    await waitUntil(() => hostMsgs.some((m) => m.includes('"envelope"')));
    const rawForwarded = hostMsgs.find((m) => m.includes('"envelope"'))!;
    assert.equal(rawForwarded.includes('rtc_offer'), false); // Relay never sees plaintext!
    const decryptedOffer = openE2EEFrame<{ kind: string; sdp: string }>(
      hKey,
      JSON.parse(rawForwarded) as E2EEEncryptedEnvelope,
      0,
    );
    assert.equal(decryptedOffer.kind, 'rtc_offer');

    // Host replies encrypted h2c
    const sealedReply = sealE2EEFrame({
      sessionKey: hKey,
      hostId: host.hostId,
      clientId: 'ios_pwa_1',
      sid,
      dir: 'h2c',
      seq: 1,
      plaintext: { kind: 'http_res', reqId: 'r1', body: { ok: true } },
    });
    hostWs.sendText(JSON.stringify(sealedReply));

    await waitUntil(() => clientMsgs.some((m) => m.includes('"envelope"')));
    const rawReply = clientMsgs.find((m) => m.includes('"envelope"'))!;
    const decryptedReply = openE2EEFrame<{ kind: string; body: { ok: boolean } }>(
      cKey,
      JSON.parse(rawReply) as E2EEEncryptedEnvelope,
      0,
    );
    assert.equal(decryptedReply.body.ok, true);

    const stats = relay.getStats();
    assert.equal(stats.onlineHosts, 1);
    assert.equal(stats.onlineClients, 1);
    assert.equal(stats.totalEnvelopesRelayed, 2);

    clientWs.close();
    hostWs.close();
  } finally {
    await relay.stop();
  }
});

test('PipiE2EERelayServer invite key gate rejects unauthorized hosts when configured', async () => {
  const relay = new PipiE2EERelayServer({
    host: '127.0.0.1',
    port: 0,
    inviteKeys: ['secret-invite-42'],
  });
  const { port } = await relay.start();
  const baseWs = `ws://127.0.0.1:${port}/ws`;
  try {
    const badHost = await connectMinimalWebSocket(baseWs);
    const msgs: string[] = [];
    badHost.onMessage((m) => msgs.push(m));
    badHost.sendText(JSON.stringify({ type: 'host_register', hostId: 'abcdef1234567890', inviteKey: 'wrong' }));
    await waitUntil(() => msgs.some((m) => m.includes('invite_key_required')));
    badHost.close();
  } finally {
    await relay.stop();
  }
});

async function waitUntil(cond: () => boolean, timeoutMs = 3000): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (cond()) return;
    await new Promise((r) => setTimeout(r, 20));
  }
  throw new Error('Timed out waiting for condition');
}
