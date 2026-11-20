/**
 * @pipibot/core — voice-engine.ts (Wave 4 · #10)
 *
 * Clean-room MIT implementation of PiPiBot's Personal Daily Voice Engine
 * (Dictation, Muse Hands-Free Voice Chat, and Voice-to-Task — strictly focused
 * on everyday personal interaction, NOT heavy meeting recording/minutes).
 *
 * Key design guarantees:
 * - On-device-first STT/TTS resolution (`apple_on_device`, `whisper_kit`,
 *   `mlx_audio`) with optional BYOK cloud voice APIs (`openai_byok`,
 *   `deepgram_byok`, `elevenlabs_byok`, `custom_byok`).
 * - Hard privacy wall in `on_device_only` mode: ZERO audio bytes may leave the
 *   machine even when local backends fail or are unavailable.
 * - Local Echo-Gated VAD (`PipiEchoGatedVad`): estimates ambient noise floor
 *   and elevates speech threshold while TTS playback is active, preventing
 *   speaker-feedback self-interruption while enabling instant human barge-in.
 * - Integrates with `PipiModelScheduler` at `voice_interactive` priority.
 *
 * Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
 * Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.
 *
 * Runtime dependencies: strictly Node built-ins (`node:*`) only.
 */

import type {
  VoiceEngineProvider,
  VoiceInteractionMode,
  VoicePrivacyPolicy,
  VoiceSessionState,
} from '@pipibot/protocol';
import type { PipiModelScheduler } from './model-scheduler.ts';

// ---------------------------------------------------------------------------
// 1. Configuration & Telemetry Types
// ---------------------------------------------------------------------------

export interface CloudVoiceApiConfig {
  provider: Exclude<VoiceEngineProvider, 'apple_on_device' | 'whisper_kit' | 'mlx_audio'>;
  baseUrl: string;
  modelId: string;
  /** Runtime key read from Keychain/env; never persisted in plaintext state. */
  apiKey?: string;
  voiceName?: string;
}

export interface DailyVoiceConfig {
  mode: VoiceInteractionMode;
  privacyPolicy: VoicePrivacyPolicy;
  preferredSttProvider: VoiceEngineProvider;
  preferredTtsProvider: VoiceEngineProvider;
  locale: string;
  speechRate: number;
  vadSensitivity: number; // 0.1 (strict) .. 1.0 (sensitive)
  echoGateMultiplier: number; // >= 1.5 recommended while speaking
  bargeInConsecutiveFrames: number;
  cloudStt?: CloudVoiceApiConfig;
  cloudTts?: CloudVoiceApiConfig;
}

export interface VadFrameTelemetry {
  rmsEnergy: number;
  zeroCrossingRate: number;
  noiseFloor: number;
  activeThreshold: number;
  isSpeech: boolean;
  bargeInTriggered: boolean;
  consecutiveSpeechFrames: number;
}

export type VoiceRouteIntentKind =
  | 'dictation_insert'
  | 'muse_reply'
  | 'delegate_alter_ego'
  | 'pocket_note'
  | 'tracking_item';

export interface VoiceUtteranceRouteDecision {
  intent: VoiceRouteIntentKind;
  transcript: string;
  cleanedPayload: string;
  confidence: number;
  usedStructuredClassifier: boolean;
  rationale: string;
}

export interface VoiceSttProviderAdapter {
  readonly provider: VoiceEngineProvider;
  readonly isOnDevice: boolean;
  isAvailable(): boolean;
  transcribe(audioPcmOrWav: Uint8Array, locale: string): Promise<{ text: string; durationMs: number }>;
}

export interface VoiceTtsProviderAdapter {
  readonly provider: VoiceEngineProvider;
  readonly isOnDevice: boolean;
  isAvailable(): boolean;
  synthesize(text: string, locale: string, speechRate: number): Promise<{ audioBytes: Uint8Array; mimeType: string }>;
}

export function isOnDeviceVoiceProvider(provider: VoiceEngineProvider): boolean {
  return provider === 'apple_on_device' || provider === 'whisper_kit' || provider === 'mlx_audio';
}

export function defaultDailyVoiceConfig(): DailyVoiceConfig {
  return {
    mode: 'dictation',
    privacyPolicy: 'on_device_first',
    preferredSttProvider: 'apple_on_device',
    preferredTtsProvider: 'apple_on_device',
    locale: 'auto',
    speechRate: 1.0,
    vadSensitivity: 0.55,
    echoGateMultiplier: 2.6,
    bargeInConsecutiveFrames: 3,
  };
}

// ---------------------------------------------------------------------------
// 2. Local Echo-Gated VAD & Barge-In Detector
// ---------------------------------------------------------------------------

export class PipiEchoGatedVad {
  #noiseFloor = 0.012;
  #consecutiveSpeechFrames = 0;
  readonly #baseThreshold: number;
  readonly #echoGateMultiplier: number;
  readonly #bargeInFramesRequired: number;

  constructor(options?: {
    sensitivity?: number;
    echoGateMultiplier?: number;
    bargeInConsecutiveFrames?: number;
  }) {
    const sens = Math.min(1.0, Math.max(0.1, options?.sensitivity ?? 0.55));
    // Higher sensitivity -> lower energy threshold
    this.#baseThreshold = 0.018 + (1.0 - sens) * 0.045;
    this.#echoGateMultiplier = Math.max(1.5, options?.echoGateMultiplier ?? 2.6);
    this.#bargeInFramesRequired = Math.max(2, options?.bargeInConsecutiveFrames ?? 3);
  }

  reset(): void {
    this.#consecutiveSpeechFrames = 0;
  }

  get noiseFloor(): number {
    return this.#noiseFloor;
  }

  /**
   * Analyzes a normalized PCM frame (`samples` in `[-1.0, 1.0]`).
   * While `isAssistantSpeaking` is true, raises threshold via `echoGateMultiplier`
   * and `playbackReferenceRms` so speaker output does not self-interrupt, while
   * genuine sustained human voice triggers `bargeInTriggered = true`.
   */
  processFrame(
    samples: Float32Array | readonly number[],
    options: { isAssistantSpeaking: boolean; playbackReferenceRms?: number },
  ): VadFrameTelemetry {
    const count = samples.length;
    if (count === 0) {
      return {
        rmsEnergy: 0,
        zeroCrossingRate: 0,
        noiseFloor: this.#noiseFloor,
        activeThreshold: this.#baseThreshold,
        isSpeech: false,
        bargeInTriggered: false,
        consecutiveSpeechFrames: this.#consecutiveSpeechFrames,
      };
    }

    let sumSq = 0;
    let zeroCrossings = 0;
    for (let i = 0; i < count; i += 1) {
      const s = samples[i];
      sumSq += s * s;
      if (i > 0 && ((samples[i - 1] >= 0 && s < 0) || (samples[i - 1] < 0 && s >= 0))) {
        zeroCrossings += 1;
      }
    }
    const rmsEnergy = Math.sqrt(sumSq / count);
    const zeroCrossingRate = zeroCrossings / count;

    // Human voice band has meaningful energy and moderate ZCR (rejects DC hum and pure white-noise hiss)
    const naturalVoiceZcr = zeroCrossingRate >= 0.015 && zeroCrossingRate <= 0.42;
    const ambientFloorThreshold = Math.max(this.#baseThreshold, this.#noiseFloor * 2.2);

    const playbackRef = Math.max(0, options.playbackReferenceRms ?? 0);
    const activeThreshold = options.isAssistantSpeaking
      ? Math.max(ambientFloorThreshold * this.#echoGateMultiplier, playbackRef * 1.45 + 0.03)
      : ambientFloorThreshold;

    const isSpeech = rmsEnergy >= activeThreshold && naturalVoiceZcr;

    if (isSpeech) {
      this.#consecutiveSpeechFrames += 1;
    } else {
      this.#consecutiveSpeechFrames = 0;
      if (!options.isAssistantSpeaking) {
        // Exponential moving average for ambient noise floor while quiet
        this.#noiseFloor = this.#noiseFloor * 0.92 + rmsEnergy * 0.08;
      }
    }

    const bargeInTriggered =
      options.isAssistantSpeaking && this.#consecutiveSpeechFrames >= this.#bargeInFramesRequired;

    return {
      rmsEnergy: Math.round(rmsEnergy * 10_000) / 10_000,
      zeroCrossingRate: Math.round(zeroCrossingRate * 10_000) / 10_000,
      noiseFloor: Math.round(this.#noiseFloor * 10_000) / 10_000,
      activeThreshold: Math.round(activeThreshold * 10_000) / 10_000,
      isSpeech,
      bargeInTriggered,
      consecutiveSpeechFrames: this.#consecutiveSpeechFrames,
    };
  }
}

// ---------------------------------------------------------------------------
// 3. Built-in BYOK Cloud HTTP Adapters (OpenAI Whisper/TTS & Deepgram/Custom)
// ---------------------------------------------------------------------------

export function createCloudSttHttpAdapter(
  config: CloudVoiceApiConfig,
  fetchImpl: typeof fetch = globalThis.fetch,
): VoiceSttProviderAdapter {
  return {
    provider: config.provider,
    isOnDevice: false,
    isAvailable: () => Boolean(config.baseUrl.trim() && config.apiKey?.trim()),
    async transcribe(audioBytes: Uint8Array, locale: string) {
      const started = Date.now();
      const base = config.baseUrl.replace(/\/+$/, '');
      const url =
        config.provider === 'deepgram_byok'
          ? `${base}/listen?model=${encodeURIComponent(config.modelId || 'nova-2')}&smart_format=true`
          : base.endsWith('/audio/transcriptions')
            ? base
            : `${base}/audio/transcriptions`;

      const headers: Record<string, string> = {};
      if (config.provider === 'deepgram_byok') {
        headers.Authorization = `Token ${config.apiKey ?? ''}`;
        headers['Content-Type'] = 'audio/wav';
      } else {
        headers.Authorization = `Bearer ${config.apiKey ?? ''}`;
        headers['Content-Type'] = 'application/json';
      }

      const body =
        config.provider === 'deepgram_byok'
          ? Buffer.from(audioBytes)
          : JSON.stringify({
              model: config.modelId || 'gpt-4o-mini-transcribe',
              language: locale === 'auto' ? undefined : locale,
              audio_base64: Buffer.from(audioBytes).toString('base64'),
            });

      const resp = await fetchImpl(url, { method: 'POST', headers, body });
      if (!resp.ok) {
        throw new Error(`Cloud STT (${config.provider}) HTTP ${resp.status}`);
      }
      const data = (await resp.json()) as Record<string, unknown>;
      let text = '';
      if (typeof data.text === 'string') {
        text = data.text;
      } else {
        const results = data.results as
          | { channels?: Array<{ alternatives?: Array<{ transcript?: string }> }> }
          | undefined;
        text = results?.channels?.[0]?.alternatives?.[0]?.transcript ?? '';
      }
      return { text: text.trim(), durationMs: Math.max(1, Date.now() - started) };
    },
  };
}

export function createCloudTtsHttpAdapter(
  config: CloudVoiceApiConfig,
  fetchImpl: typeof fetch = globalThis.fetch,
): VoiceTtsProviderAdapter {
  return {
    provider: config.provider,
    isOnDevice: false,
    isAvailable: () => Boolean(config.baseUrl.trim() && config.apiKey?.trim()),
    async synthesize(text: string, _locale: string, speechRate: number) {
      const base = config.baseUrl.replace(/\/+$/, '');
      const url = base.endsWith('/audio/speech') ? base : `${base}/audio/speech`;
      const resp = await fetchImpl(url, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${config.apiKey ?? ''}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: config.modelId || 'gpt-4o-mini-tts',
          voice: config.voiceName || 'alloy',
          speed: speechRate,
          input: text,
        }),
      });
      if (!resp.ok) {
        throw new Error(`Cloud TTS (${config.provider}) HTTP ${resp.status}`);
      }
      const buf = new Uint8Array(await resp.arrayBuffer());
      return {
        audioBytes: buf,
        mimeType: resp.headers.get('content-type') ?? 'audio/mpeg',
      };
    },
  };
}

// ---------------------------------------------------------------------------
// 4. Personal Daily Voice Engine (Privacy-Policy-Enforced + Scheduler Aware)
// ---------------------------------------------------------------------------

export type VoiceIntentClassifierFn = (
  transcript: string,
  mode: VoiceInteractionMode,
) => Promise<VoiceUtteranceRouteDecision>;

export class PipiDailyVoiceEngine {
  #config: DailyVoiceConfig;
  #state: VoiceSessionState = 'idle';
  #vad: PipiEchoGatedVad;
  readonly #sttAdapters = new Map<VoiceEngineProvider, VoiceSttProviderAdapter>();
  readonly #ttsAdapters = new Map<VoiceEngineProvider, VoiceTtsProviderAdapter>();
  readonly #scheduler?: PipiModelScheduler;
  readonly #intentClassifier?: VoiceIntentClassifierFn;

  constructor(options?: {
    config?: Partial<DailyVoiceConfig>;
    sttAdapters?: VoiceSttProviderAdapter[];
    ttsAdapters?: VoiceTtsProviderAdapter[];
    scheduler?: PipiModelScheduler;
    intentClassifier?: VoiceIntentClassifierFn;
  }) {
    this.#config = { ...defaultDailyVoiceConfig(), ...(options?.config ?? {}) };
    this.#vad = new PipiEchoGatedVad({
      sensitivity: this.#config.vadSensitivity,
      echoGateMultiplier: this.#config.echoGateMultiplier,
      bargeInConsecutiveFrames: this.#config.bargeInConsecutiveFrames,
    });
    this.#scheduler = options?.scheduler;
    this.#intentClassifier = options?.intentClassifier;
    for (const adapter of options?.sttAdapters ?? []) {
      this.#sttAdapters.set(adapter.provider, adapter);
    }
    for (const adapter of options?.ttsAdapters ?? []) {
      this.#ttsAdapters.set(adapter.provider, adapter);
    }
  }

  get config(): DailyVoiceConfig {
    return { ...this.#config };
  }

  get state(): VoiceSessionState {
    return this.#state;
  }

  updateConfig(patch: Partial<DailyVoiceConfig>): void {
    this.#config = { ...this.#config, ...patch };
    this.#vad = new PipiEchoGatedVad({
      sensitivity: this.#config.vadSensitivity,
      echoGateMultiplier: this.#config.echoGateMultiplier,
      bargeInConsecutiveFrames: this.#config.bargeInConsecutiveFrames,
    });
  }

  registerSttAdapter(adapter: VoiceSttProviderAdapter): void {
    this.#sttAdapters.set(adapter.provider, adapter);
  }

  registerTtsAdapter(adapter: VoiceTtsProviderAdapter): void {
    this.#ttsAdapters.set(adapter.provider, adapter);
  }

  setState(next: VoiceSessionState): void {
    this.#state = next;
  }

  /**
   * Feeds a live audio frame into the echo-gated VAD.
   * Automatically transitions `.speaking` -> `.interrupted` on sustained human barge-in.
   */
  ingestAudioFrame(
    samples: Float32Array | readonly number[],
    playbackReferenceRms = 0,
  ): VadFrameTelemetry {
    const isSpeaking = this.#state === 'speaking';
    const telemetry = this.#vad.processFrame(samples, {
      isAssistantSpeaking: isSpeaking,
      playbackReferenceRms,
    });
    if (telemetry.bargeInTriggered) {
      this.#state = 'interrupted';
    }
    return telemetry;
  }

  /**
   * Resolves the ordered STT backend candidate list while strictly respecting `privacyPolicy`.
   * In `on_device_only` mode, cloud providers are NEVER returned.
   */
  resolveSttCandidateOrder(): VoiceEngineProvider[] {
    const onDeviceOrder: VoiceEngineProvider[] = ['apple_on_device', 'whisper_kit', 'mlx_audio'];
    const cloudOrder: VoiceEngineProvider[] = ['openai_byok', 'deepgram_byok', 'custom_byok'];

    const preferred = this.#config.preferredSttProvider;
    const dedup = (items: VoiceEngineProvider[]): VoiceEngineProvider[] => Array.from(new Set(items));

    if (this.#config.privacyPolicy === 'on_device_only') {
      return dedup([
        ...(isOnDeviceVoiceProvider(preferred) ? [preferred] : []),
        ...onDeviceOrder,
      ]);
    }
    if (this.#config.privacyPolicy === 'cloud_preferred') {
      return dedup([
        ...(!isOnDeviceVoiceProvider(preferred) ? [preferred] : []),
        ...cloudOrder,
        ...onDeviceOrder,
      ]);
    }
    // Default: on_device_first
    return dedup([preferred, ...onDeviceOrder, ...cloudOrder]);
  }

  resolveTtsCandidateOrder(): VoiceEngineProvider[] {
    const onDeviceOrder: VoiceEngineProvider[] = ['apple_on_device', 'mlx_audio'];
    const cloudOrder: VoiceEngineProvider[] = ['openai_byok', 'elevenlabs_byok', 'custom_byok'];
    const preferred = this.#config.preferredTtsProvider;
    const dedup = (items: VoiceEngineProvider[]): VoiceEngineProvider[] => Array.from(new Set(items));

    if (this.#config.privacyPolicy === 'on_device_only') {
      return dedup([
        ...(isOnDeviceVoiceProvider(preferred) ? [preferred] : []),
        ...onDeviceOrder,
      ]);
    }
    if (this.#config.privacyPolicy === 'cloud_preferred') {
      return dedup([
        ...(!isOnDeviceVoiceProvider(preferred) ? [preferred] : []),
        ...cloudOrder,
        ...onDeviceOrder,
      ]);
    }
    return dedup([preferred, ...onDeviceOrder, ...cloudOrder]);
  }

  async transcribe(audioBytes: Uint8Array): Promise<{
    text: string;
    providerUsed: VoiceEngineProvider;
    usedOnDevice: boolean;
    durationMs: number;
  }> {
    this.#state = 'transcribing';
    const order = this.resolveSttCandidateOrder();
    const errors: string[] = [];

    for (const provider of order) {
      const adapter = this.#sttAdapters.get(provider);
      if (!adapter || !adapter.isAvailable()) continue;
      if (this.#config.privacyPolicy === 'on_device_only' && !adapter.isOnDevice) {
        continue;
      }
      try {
        const res = await adapter.transcribe(audioBytes, this.#config.locale);
        this.#state = 'idle';
        return {
          text: res.text,
          providerUsed: adapter.provider,
          usedOnDevice: adapter.isOnDevice,
          durationMs: res.durationMs,
        };
      } catch (err) {
        errors.push(`${provider}: ${err instanceof Error ? err.message : String(err)}`);
      }
    }

    this.#state = 'error';
    throw new Error(
      `No eligible STT provider succeeded under privacy policy '${this.#config.privacyPolicy}'.` +
        (errors.length > 0 ? ` Errors: ${errors.join('; ')}` : ''),
    );
  }

  async synthesize(text: string): Promise<{
    audioBytes: Uint8Array;
    mimeType: string;
    providerUsed: VoiceEngineProvider;
    usedOnDevice: boolean;
  }> {
    const order = this.resolveTtsCandidateOrder();
    const errors: string[] = [];

    for (const provider of order) {
      const adapter = this.#ttsAdapters.get(provider);
      if (!adapter || !adapter.isAvailable()) continue;
      if (this.#config.privacyPolicy === 'on_device_only' && !adapter.isOnDevice) {
        continue;
      }
      try {
        this.#state = 'speaking';
        const res = await adapter.synthesize(text, this.#config.locale, this.#config.speechRate);
        return {
          audioBytes: res.audioBytes,
          mimeType: res.mimeType,
          providerUsed: adapter.provider,
          usedOnDevice: adapter.isOnDevice,
        };
      } catch (err) {
        errors.push(`${provider}: ${err instanceof Error ? err.message : String(err)}`);
      }
    }

    this.#state = 'error';
    throw new Error(
      `No eligible TTS provider succeeded under privacy policy '${this.#config.privacyPolicy}'.` +
        (errors.length > 0 ? ` Errors: ${errors.join('; ')}` : ''),
    );
  }

  /**
   * Routes a daily voice utterance using `voice_interactive` scheduler priority.
   * Uses structured LLM intent classification when available, falling back cleanly
   * to explicit interaction-mode semantics (never brittle multi-language regex trees).
   */
  async routeUtterance(
    transcript: string,
    modeOverride?: VoiceInteractionMode,
    structuredActionHint?: VoiceRouteIntentKind,
  ): Promise<VoiceUtteranceRouteDecision> {
    const mode = modeOverride ?? this.#config.mode;
    const cleaned = transcript.trim();

    const executeRouting = async (): Promise<VoiceUtteranceRouteDecision> => {
      this.#state = 'thinking';
      if (structuredActionHint) {
        return {
          intent: structuredActionHint,
          transcript: cleaned,
          cleanedPayload: cleaned,
          confidence: 1.0,
          usedStructuredClassifier: true,
          rationale: `Explicit structured action hint: ${structuredActionHint}.`,
        };
      }

      if (this.#intentClassifier) {
        return await this.#intentClassifier(cleaned, mode);
      }

      switch (mode) {
        case 'dictation':
          return {
            intent: 'dictation_insert',
            transcript: cleaned,
            cleanedPayload: cleaned,
            confidence: 0.98,
            usedStructuredClassifier: false,
            rationale: 'Dictation mode inserts transcript directly into active composer.',
          };
        case 'muse_hands_free':
          return {
            intent: 'muse_reply',
            transcript: cleaned,
            cleanedPayload: cleaned,
            confidence: 0.95,
            usedStructuredClassifier: false,
            rationale: 'Muse hands-free mode sends utterance to active Bot with spoken response.',
          };
        case 'voice_to_task':
        default:
          return {
            intent: 'delegate_alter_ego',
            transcript: cleaned,
            cleanedPayload: cleaned,
            confidence: 0.9,
            usedStructuredClassifier: false,
            rationale: 'Voice-to-Task mode dispatches background AlterEgo delegation by default.',
          };
      }
    };

    if (this.#scheduler) {
      const lease = await this.#scheduler.acquire({
        priority: 'voice_interactive',
        label: `voice:${mode}`,
      });
      try {
        return await executeRouting();
      } finally {
        lease.release();
      }
    }
    return await executeRouting();
  }
}
