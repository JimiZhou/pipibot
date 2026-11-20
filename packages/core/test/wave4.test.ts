/**
 * packages/core/test/wave4.test.ts
 *
 * Deterministic offline verification suite for Wave 4 (#07 Local Model Stack,
 * PolyStrata MIT integration, Loopback LLM Gateway + Isolated CLI Reverse-Injection;
 * #10 Personal Daily Voice Engine with Echo-Gated VAD Barge-In & On-Device-First Privacy).
 */

import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, stat } from 'node:fs/promises';
import { createServer, type Server } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import {
  LOCAL_MODEL_CATALOG,
  buildLocalEngineLaunchSpec,
  detectLocalHardwareProfile,
  getPolyStrataMoECatalog,
  planLocalModelSetup,
  verifyLocalModelWithQA,
} from '../src/model-autopilot.ts';
import {
  PipiLocalLLMGateway,
  prepareIsolatedCliOverlay,
} from '../src/local-llm-gateway.ts';
import { PipiModelScheduler } from '../src/model-scheduler.ts';
import { runPipiBotCli } from '../src/pipibot-cli.ts';
import {
  PipiDailyVoiceEngine,
  PipiEchoGatedVad,
  createCloudSttHttpAdapter,
  type VoiceSttProviderAdapter,
} from '../src/voice-engine.ts';

function sineWaveFrame(amplitude: number, freqHz = 280, sampleRate = 16_000, samples = 320): Float32Array {
  const buf = new Float32Array(samples);
  for (let i = 0; i < samples; i += 1) {
    buf[i] = amplitude * Math.sin((2 * Math.PI * freqHz * i) / sampleRate);
  }
  return buf;
}

async function startMockOpenAIServer(): Promise<{ server: Server; baseUrl: string }> {
  const server = createServer((req, res) => {
    const chunks: Buffer[] = [];
    req.on('data', (c) => chunks.push(Buffer.from(c)));
    req.on('end', () => {
      const bodyRaw = Buffer.concat(chunks).toString('utf8');
      const parsed = bodyRaw ? (JSON.parse(bodyRaw) as Record<string, unknown>) : {};
      const urlPath = (req.url ?? '/').split('?')[0];

      if (urlPath.endsWith('/chat/completions')) {
        const msgs = (parsed.messages as Array<{ content?: string }>) ?? [];
        const lastUser = msgs[msgs.length - 1]?.content ?? '';
        const reply = lastUser.includes('PIPI_QA_42')
          ? 'PIPI_QA_42 — sum is 42.'
          : `MockLocalReply:${lastUser}`;
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(
          JSON.stringify({
            id: 'mock_cmpl_1',
            object: 'chat.completion',
            model: parsed.model ?? 'qwen3.8-27b-ud-q4_k_m',
            choices: [
              {
                index: 0,
                message: { role: 'assistant', content: reply },
                finish_reason: 'stop',
              },
            ],
            usage: { prompt_tokens: 18, completion_tokens: 12, total_tokens: 30 },
          }),
        );
        return;
      }

      if (urlPath.endsWith('/audio/transcriptions')) {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ text: 'Cloud BYOK transcription ok' }));
        return;
      }

      res.writeHead(404);
      res.end();
    });
  });

  await new Promise<void>((resolveListen) => {
    server.listen(0, '127.0.0.1', () => resolveListen());
  });
  const addr = server.address();
  assert.ok(addr && typeof addr !== 'string');
  return { server, baseUrl: `http://127.0.0.1:${addr.port}/v1` };
}

test('Wave 4 (#07a): 5-layer Model Autopilot, 12-model PolyStrata catalog & Real-QA self-test gate', async () => {
  // Catalog must include >= 12 PolyStrata MoE models for Mac beta & PipiFleet Linux/Win
  const polyCatalog = getPolyStrataMoECatalog();
  assert.ok(polyCatalog.length >= 12, `Expected >= 12 PolyStrata models, got ${polyCatalog.length}`);
  assert.ok(LOCAL_MODEL_CATALOG.length >= 15);

  // 1. Apple Silicon 16 GB -> fits 64K Spark-X2.6-4B without blowing unified memory
  const mac16 = await detectLocalHardwareProfile({
    platformClass: 'macos_apple_silicon',
    osPlatform: 'darwin',
    cpuArch: 'arm64',
    cpuModel: 'Apple M4',
    totalRamGb: 16,
    availableRamGb: 11,
    unifiedMemory: true,
    isAppleSilicon: true,
    freeDiskGb: 120,
  });
  const plan16 = planLocalModelSetup(mac16);
  assert.equal(plan16.primaryModel.id, 'spark-x2.6-4b-q4_k_m');
  assert.ok(plan16.plannedContextWindow >= 65_536);
  assert.equal(plan16.companionBudget.canRunOnDeviceVoiceModel, true);

  // 2. Apple Silicon 32 GB -> high-quality 27B 128K context
  const mac32 = await detectLocalHardwareProfile({
    platformClass: 'macos_apple_silicon',
    osPlatform: 'darwin',
    cpuArch: 'arm64',
    cpuModel: 'Apple M4 Pro',
    totalRamGb: 32,
    availableRamGb: 24,
    unifiedMemory: true,
    isAppleSilicon: true,
    freeDiskGb: 240,
  });
  const plan32 = planLocalModelSetup(mac32);
  assert.equal(plan32.primaryModel.id, 'qwen3.8-27b-ud-q4_k_m');
  assert.equal(plan32.plannedContextWindow, 131_072);

  // 3. Apple Silicon 64 GB -> unlocks PolyStrata Metal+SSD prefetch beta MoE
  const mac64 = await detectLocalHardwareProfile({
    platformClass: 'macos_apple_silicon',
    osPlatform: 'darwin',
    cpuArch: 'arm64',
    cpuModel: 'Apple M4 Max',
    totalRamGb: 64,
    availableRamGb: 52,
    unifiedMemory: true,
    isAppleSilicon: true,
    freeDiskGb: 400,
  });
  const plan64 = planLocalModelSetup(mac64, { enableMacPolyStrataBeta: true });
  assert.equal(plan64.selectedEngine, 'polystrata');
  assert.equal(plan64.polyStrataMode, 'apple_metal_ssd_beta');
  const launchSpec = buildLocalEngineLaunchSpec(plan64, '/models/model.gguf');
  assert.ok(launchSpec.commandLine.includes('--metal-ssd-prefetch'));

  // 4. PipiFleet Linux NVIDIA 12 GB VRAM + 32 GB RAM -> selects PolyStrata Flash-Next MoE with CUDA+RAM/SSD paging
  const fleet12 = await detectLocalHardwareProfile({
    platformClass: 'linux_nvidia',
    osPlatform: 'linux',
    cpuArch: 'x64',
    cpuModel: 'AMD Ryzen 9',
    totalRamGb: 32,
    availableRamGb: 26,
    gpuVramGb: 12,
    unifiedMemory: false,
    isAppleSilicon: false,
    isFleetNode: true,
    freeDiskGb: 300,
  });
  const planFleet = planLocalModelSetup(fleet12);
  assert.equal(planFleet.selectedEngine, 'polystrata');
  assert.equal(planFleet.primaryModel.id, 'qwen3.8-flash-next-polystrata');
  assert.ok(
    planFleet.polyStrataMode === 'cuda_ssd_paging' || planFleet.polyStrataMode === 'cuda_ram_expert_offload',
  );

  // 5. Real QA Self-Test Verification Gate
  const mock = await startMockOpenAIServer();
  try {
    const qaPass = await verifyLocalModelWithQA({
      endpointUrl: mock.baseUrl,
      modelId: plan32.primaryModel.id,
    });
    assert.equal(qaPass.verified, true);
    assert.equal(qaPass.status, 'verified');
    assert.ok(qaPass.sampleOutput.includes('PIPI_QA_42'));
    assert.ok(qaPass.estimatedTokPerSec > 0);
  } finally {
    await new Promise<void>((r) => mock.server.close(() => r()));
  }
});

test('Wave 4 (#07b): Loopback LLM Gateway (OpenAI <-> Anthropic JSON & SSE) + Isolated CLI Reverse-Injection', async () => {
  const mock = await startMockOpenAIServer();
  const dataRoot = await mkdtemp(join(tmpdir(), 'pipibot-wave4-gw-'));
  let unloadedCalled = false;

  const gateway = new PipiLocalLLMGateway({
    host: '127.0.0.1',
    port: 0,
    upstream: {
      id: 'local_polystrata',
      label: 'PolyStrata Local',
      sourceMode: 'local_model',
      dialect: 'openai',
      baseUrl: mock.baseUrl,
      modelId: 'qwen3.8-27b-ud-q4_k_m',
      contextWindow: 131_072,
    },
    onUnloadLocalModel: () => {
      unloadedCalled = true;
    },
  });

  try {
    // Reject non-loopback host binding for security
    assert.throws(
      () =>
        new PipiLocalLLMGateway({
          host: '0.0.0.0',
          upstream: gateway.upstream,
        }),
      /non-loopback/,
    );

    const started = await gateway.start();
    assert.ok(started.origin.startsWith('http://127.0.0.1:'));
    assert.ok(started.port > 0);

    // 1. Unauthorized request must be rejected with 401
    const unauthResp = await fetch(`${started.origin}/v1/models`);
    assert.equal(unauthResp.status, 401);

    // 2. OpenAI /v1/chat/completions passthrough
    const oaiResp = await fetch(`${started.origin}/v1/chat/completions`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${started.token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'any',
        messages: [{ role: 'user', content: 'hello-oai' }],
      }),
    });
    assert.equal(oaiResp.status, 200);
    const oaiJson = (await oaiResp.json()) as { choices: Array<{ message: { content: string } }> };
    assert.equal(oaiJson.choices[0].message.content, 'MockLocalReply:hello-oai');

    // 3. Anthropic /anthropic/v1/messages (Claude Code CLI dialect) auto-translated to OpenAI local upstream
    const antResp = await fetch(`${started.origin}/anthropic/v1/messages`, {
      method: 'POST',
      headers: {
        'x-api-key': started.token,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'claude-sonnet-4',
        system: 'Be concise',
        messages: [{ role: 'user', content: 'hello-claude-cli' }],
      }),
    });
    assert.equal(antResp.status, 200);
    const antJson = (await antResp.json()) as { type: string; content: Array<{ text: string }> };
    assert.equal(antJson.type, 'message');
    assert.equal(antJson.content[0].text, 'MockLocalReply:hello-claude-cli');

    // 4. Anthropic SSE streaming translation
    const sseResp = await fetch(`${started.origin}/anthropic/v1/messages`, {
      method: 'POST',
      headers: {
        'x-api-key': started.token,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'claude-sonnet-4',
        stream: true,
        messages: [{ role: 'user', content: 'stream-check' }],
      }),
    });
    assert.equal(sseResp.status, 200);
    const sseText = await sseResp.text();
    assert.ok(sseText.includes('event: content_block_delta'));
    assert.ok(sseText.includes('MockLocalReply:stream-check'));
    assert.ok(sseText.includes('event: message_stop'));

    // 5. Isolated CLI Reverse-Injection overlays (Claude, Codex, Pi, OpenCode)
    const claudeOverlay = await gateway.prepareCliOverlay(dataRoot, 'claude-code', 'session_a');
    assert.ok(claudeOverlay.env.CLAUDE_CONFIG_DIR.startsWith(dataRoot));
    assert.equal(claudeOverlay.env.ANTHROPIC_BASE_URL, `${started.origin}/anthropic`);
    assert.equal(claudeOverlay.env.ANTHROPIC_AUTH_TOKEN, started.token);
    const claudeStat = await stat(claudeOverlay.configFilesWritten[0]);
    assert.equal(claudeStat.mode & 0o777, 0o600);

    const codexOverlay = await prepareIsolatedCliOverlay({
      dataRootDir: dataRoot,
      cli: 'codex',
      profileId: 'session_a',
      gatewayOrigin: started.origin,
      gatewayToken: started.token,
      modelId: 'qwen3.8-27b-ud-q4_k_m',
    });
    assert.ok(codexOverlay.env.CODEX_HOME.startsWith(dataRoot));
    const codexToml = await readFile(codexOverlay.configFilesWritten[0], 'utf8');
    assert.ok(codexToml.includes(`base_url = "${started.origin}/v1"`));

    const piOverlay = await gateway.prepareCliOverlay(dataRoot, 'pi', 'session_a');
    assert.ok(piOverlay.env.PI_CODING_AGENT_DIR.startsWith(dataRoot));

    // 6. Active-run switch guard + local model unload when leaving local_model
    const blockedSwitch = await gateway.requestModelSourceSwitch({
      targetMode: 'byok',
      activeRunsCount: 2,
      confirmedInterruptActiveRuns: false,
    });
    assert.equal(blockedSwitch.switched, false);
    assert.equal(blockedSwitch.requiresConfirmation, true);
    assert.equal(unloadedCalled, false);

    const confirmedSwitch = await gateway.requestModelSourceSwitch({
      targetMode: 'byok',
      activeRunsCount: 2,
      confirmedInterruptActiveRuns: true,
    });
    assert.equal(confirmedSwitch.switched, true);
    assert.equal(confirmedSwitch.unloadedLocalModel, true);
    assert.equal(unloadedCalled, true);

    // 7. Unified pipibot CLI exposes Wave 4 `model plan` & `voice status`
    const cliModelPlan = await runPipiBotCli(['model', 'plan', '--ram-gb', '32', '--data-dir', dataRoot]);
    assert.equal(cliModelPlan.exitCode, 0);
    assert.ok(cliModelPlan.stdout.includes('primaryModel'));

    const cliVoice = await runPipiBotCli(['voice', 'status', '--data-dir', dataRoot]);
    assert.equal(cliVoice.exitCode, 0);
    assert.ok(cliVoice.stdout.includes('muse_hands_free'));
  } finally {
    await gateway.stop();
    await new Promise<void>((r) => mock.server.close(() => r()));
    await rm(dataRoot, { recursive: true, force: true });
  }
});

test('Wave 4 (#10): Echo-Gated VAD barge-in, on_device_only privacy wall, BYOK cloud fallback & Voice-to-Task priority', async () => {
  const mock = await startMockOpenAIServer();
  try {
    // 1. Echo-Gated VAD ignores speaker playback echo, then immediately fires barge-in on sustained user voice
    const vad = new PipiEchoGatedVad({
      sensitivity: 0.6,
      echoGateMultiplier: 2.5,
      bargeInConsecutiveFrames: 3,
    });

    // Speaker echo frame (RMS ~0.07) with playback reference 0.08 -> MUST NOT trigger barge-in
    const echoFrame = sineWaveFrame(0.09, 260);
    for (let i = 0; i < 4; i += 1) {
      const t = vad.processFrame(echoFrame, { isAssistantSpeaking: true, playbackReferenceRms: 0.08 });
      assert.equal(t.bargeInTriggered, false);
    }

    // Real loud user voice (amplitude 0.45 -> RMS ~0.32 > threshold) for 3 consecutive frames -> MUST trigger barge-in!
    const userVoiceFrame = sineWaveFrame(0.45, 300);
    const t1 = vad.processFrame(userVoiceFrame, { isAssistantSpeaking: true, playbackReferenceRms: 0.08 });
    assert.equal(t1.isSpeech, true);
    assert.equal(t1.bargeInTriggered, false);
    const t2 = vad.processFrame(userVoiceFrame, { isAssistantSpeaking: true, playbackReferenceRms: 0.08 });
    assert.equal(t2.bargeInTriggered, false);
    const t3 = vad.processFrame(userVoiceFrame, { isAssistantSpeaking: true, playbackReferenceRms: 0.08 });
    assert.equal(t3.bargeInTriggered, true);

    // 2. Privacy Wall: on_device_only MUST refuse cloud fallback when on-device is unavailable
    const cloudStt = createCloudSttHttpAdapter({
      provider: 'openai_byok',
      baseUrl: mock.baseUrl,
      modelId: 'gpt-4o-mini-transcribe',
      apiKey: 'sk-test-local-mock',
    });

    const unavailableLocal: VoiceSttProviderAdapter = {
      provider: 'apple_on_device',
      isOnDevice: true,
      isAvailable: () => false,
      transcribe: async () => ({ text: 'never', durationMs: 1 }),
    };

    const scheduler = new PipiModelScheduler({ hardConcurrency: 2, softConcurrency: 1 });
    const voice = new PipiDailyVoiceEngine({
      config: {
        mode: 'muse_hands_free',
        privacyPolicy: 'on_device_only',
        preferredSttProvider: 'apple_on_device',
      },
      sttAdapters: [unavailableLocal, cloudStt],
      scheduler,
    });

    await assert.rejects(
      () => voice.transcribe(new Uint8Array([1, 2, 3, 4])),
      /privacy policy 'on_device_only'/,
    );

    // 3. Switching to on_device_first allows graceful fallback to BYOK cloud STT
    voice.updateConfig({ privacyPolicy: 'on_device_first' });
    const cloudResult = await voice.transcribe(new Uint8Array([1, 2, 3, 4]));
    assert.equal(cloudResult.usedOnDevice, false);
    assert.equal(cloudResult.providerUsed, 'openai_byok');
    assert.equal(cloudResult.text, 'Cloud BYOK transcription ok');

    // 4. When on-device adapter is available, on_device_first always prefers local zero-egress execution
    voice.registerSttAdapter({
      provider: 'apple_on_device',
      isOnDevice: true,
      isAvailable: () => true,
      transcribe: async () => ({ text: 'On-device Apple Speech transcript', durationMs: 18 }),
    });
    const localResult = await voice.transcribe(new Uint8Array([5, 6, 7, 8]));
    assert.equal(localResult.usedOnDevice, true);
    assert.equal(localResult.providerUsed, 'apple_on_device');

    // 5. Barge-in state transition during speaking
    voice.setState('speaking');
    for (let i = 0; i < 3; i += 1) {
      voice.ingestAudioFrame(userVoiceFrame, 0.06);
    }
    assert.equal(voice.state, 'interrupted');

    // 6. Voice-to-Task structured routing runs on scheduler at `voice_interactive` priority
    const route = await voice.routeUtterance('Draft my weekend trip checklist', 'voice_to_task');
    assert.equal(route.intent, 'delegate_alter_ego');
    assert.equal(route.cleanedPayload, 'Draft my weekend trip checklist');
  } finally {
    await new Promise<void>((r) => mock.server.close(() => r()));
  }
});
