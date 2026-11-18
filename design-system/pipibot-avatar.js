/**
 * PipiAvatar — Zero-Dependency Procedural SVG Character Engine
 * Inspired by ArvinYin1/grokbot-animation-anatomy & tailored for PipiBot.
 *
 * Pillars:
 *  1. 192-ray radial polar outline interpolation across 8 core shapes
 *  2. 6-track cubic-Bézier keyframe choreography (x, y, rot, squash, scale, lids)
 *  3. 120 Hz semi-implicit Euler spring trio (amount, swap, spin)
 *  4. Pseudo-3D Rodrigues sphere eye projection + orthographic projection + SVG glow
 *  5. Clip-embedded 0.26s blinks (closed at 45%) + imperative blink()
 *  6. 53-state machine across 5 lifecycle groups + 9 expressions + seeded PRNG
 */

export const RAY_COUNT = 192;
export const FIXED_HZ = 120;
export const FIXED_DT = 1 / FIXED_HZ;
export const BLINK_DURATION = 0.26;
export const BLINK_PEAK_RATIO = 0.45;

/* ============================================================================
 * 1. Seeded PRNG (Mulberry32) & Math Helpers
 * ========================================================================== */

export function createSeededRng(seed = 20261118) {
  let state = seed >>> 0;
  return function nextRandom() {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function clamp(val, min, max) {
  return Math.max(min, Math.min(max, val));
}

export function lerp(a, b, t) {
  return a + (b - a) * t;
}

export function normalizeVec(v) {
  const len = Math.hypot(v[0], v[1], v[2]);
  if (len < 1e-8) return [0, 0, 1];
  return [v[0] / len, v[1] / len, v[2] / len];
}

export function dotVec(a, b) {
  return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

export function crossVec(a, b) {
  return [
    a[1] * b[2] - a[2] * b[1],
    a[2] * b[0] - a[0] * b[2],
    a[0] * b[1] - a[1] * b[0],
  ];
}

/**
 * Rodrigues' Rotation Formula:
 * v_rot = v*cos(theta) + (k x v)*sin(theta) + k*(k . v)*(1 - cos(theta))
 */
export function rodriguesRotate(v, k, theta) {
  const axis = normalizeVec(k);
  const cosT = Math.cos(theta);
  const sinT = Math.sin(theta);
  const kCrossV = crossVec(axis, v);
  const kDotV = dotVec(axis, v);
  const factor = 1 - cosT;
  return [
    v[0] * cosT + kCrossV[0] * sinT + axis[0] * kDotV * factor,
    v[1] * cosT + kCrossV[1] * sinT + axis[1] * kDotV * factor,
    v[2] * cosT + kCrossV[2] * sinT + axis[2] * kDotV * factor,
  ];
}

/**
 * Evaluate cubic-bezier(p1x, p1y, p2x, p2y) at progress t in [0, 1].
 * Supports overshoot control points (p1y/p2y outside [0, 1]).
 */
export function cubicBezier(p1x, p1y, p2x, p2y, t) {
  const u = clamp(t, 0, 1);
  if (u <= 0) return 0;
  if (u >= 1) return 1;

  const sampleX = (s) => {
    const inv = 1 - s;
    return 3 * inv * inv * s * p1x + 3 * inv * s * s * p2x + s * s * s;
  };
  const sampleDX = (s) => {
    const inv = 1 - s;
    return 3 * inv * inv * p1x + 6 * inv * s * (p2x - p1x) + 3 * s * s * (1 - p2x);
  };
  const sampleY = (s) => {
    const inv = 1 - s;
    return 3 * inv * inv * s * p1y + 3 * inv * s * s * p2y + s * s * s;
  };

  let s = u;
  for (let i = 0; i < 6; i++) {
    const err = sampleX(s) - u;
    if (Math.abs(err) < 1e-5) return sampleY(s);
    const dx = sampleDX(s);
    if (Math.abs(dx) < 1e-5) break;
    s = clamp(s - err / dx, 0, 1);
  }

  let lo = 0;
  let hi = 1;
  s = u;
  for (let i = 0; i < 12; i++) {
    const x = sampleX(s);
    if (Math.abs(x - u) < 1e-5) break;
    if (u > x) lo = s;
    else hi = s;
    s = 0.5 * (lo + hi);
  }
  return sampleY(s);
}

/* ============================================================================
 * 2. 192-Ray Polar Shape Sampling & Smooth Contour Builder
 * ========================================================================== */

export const AVATAR_SHAPES = {
  orb: {
    id: 'orb',
    label: 'Orb',
    labelZh: '灵动圆球',
    polarFn: () => 0.98,
  },
  squircle: {
    id: 'squircle',
    label: 'Squircle',
    labelZh: '超椭圆胶囊',
    polarFn: (theta) => {
      const c = Math.abs(Math.cos(theta));
      const s = Math.abs(Math.sin(theta));
      return Math.pow(Math.pow(c, 4) + Math.pow(s, 4), -0.25) * 0.94;
    },
  },
  cloud: {
    id: 'cloud',
    label: 'Cloud',
    labelZh: '漫步云朵',
    polarFn: (theta) => {
      return 0.87 + 0.115 * Math.cos(5 * theta - Math.PI / 2) + 0.038 * Math.cos(10 * theta);
    },
  },
  spark: {
    id: 'spark',
    label: 'Spark',
    labelZh: '灵感星芒',
    polarFn: (theta) => {
      return 0.70 + 0.34 * Math.pow(Math.abs(Math.cos(2 * theta)), 1.65);
    },
  },
  bolt: {
    id: 'bolt',
    label: 'Bolt',
    labelZh: '高能脉冲',
    polarFn: (theta) => {
      return 0.85 + 0.13 * Math.cos(2 * theta - 0.65) + 0.10 * Math.cos(6 * theta + 0.25);
    },
  },
  shield: {
    id: 'shield',
    label: 'Shield',
    labelZh: '守护盾徽',
    polarFn: (theta) => {
      const s = Math.sin(theta);
      const c2 = Math.cos(theta) * Math.cos(theta);
      const base = Math.pow(Math.pow(Math.abs(Math.cos(theta)), 3.2) + Math.pow(Math.abs(s), 3.2), -1 / 3.2) * 0.94;
      if (s > 0) {
        return base * (1 - 0.28 * s * c2 + 0.11 * Math.pow(s, 4));
      }
      return base * (1 - 0.05 * Math.pow(-s, 3));
    },
  },
  dream: {
    id: 'dream',
    label: 'Dream',
    labelZh: '梦境弦月',
    polarFn: (theta) => {
      return 0.90 + 0.10 * Math.sin(2 * theta - 0.4) + 0.07 * Math.cos(3 * theta + 0.6) - 0.04 * Math.cos(theta);
    },
  },
  terminal: {
    id: 'terminal',
    label: 'Terminal',
    labelZh: '终端视窗',
    polarFn: (theta) => {
      const rx = Math.abs(Math.cos(theta)) / 1.07;
      const ry = Math.abs(Math.sin(theta)) / 0.89;
      return Math.pow(Math.pow(rx, 6) + Math.pow(ry, 6), -1 / 6);
    },
  },
};

const SHAPE_CACHE = new Map();

export function sampleShape192(shapeId) {
  const key = AVATAR_SHAPES[shapeId] ? shapeId : 'orb';
  if (SHAPE_CACHE.has(key)) {
    return SHAPE_CACHE.get(key);
  }
  const fn = AVATAR_SHAPES[key].polarFn;
  const radii = new Float32Array(RAY_COUNT);
  for (let i = 0; i < RAY_COUNT; i++) {
    const theta = (Math.PI * 2 * i) / RAY_COUNT;
    radii[i] = fn(theta);
  }
  SHAPE_CACHE.set(key, radii);
  return radii;
}

export function interpolateRays192(fromRadii, toRadii, t, outArray = null) {
  const out = outArray || new Float32Array(RAY_COUNT);
  for (let i = 0; i < RAY_COUNT; i++) {
    out[i] = fromRadii[i] + (toRadii[i] - fromRadii[i]) * t;
  }
  return out;
}

export function raysToSmoothSvgPath(radii, cx, cy, baseRadius, sx = 1, sy = 1, rotRad = 0) {
  const ptsX = new Float32Array(RAY_COUNT);
  const ptsY = new Float32Array(RAY_COUNT);
  const cosR = Math.cos(rotRad);
  const sinR = Math.sin(rotRad);

  for (let i = 0; i < RAY_COUNT; i++) {
    const theta = (Math.PI * 2 * i) / RAY_COUNT;
    const r = radii[i] * baseRadius;
    const lx = Math.cos(theta) * r * sx;
    const ly = Math.sin(theta) * r * sy;
    ptsX[i] = cx + lx * cosR - ly * sinR;
    ptsY[i] = cy + lx * sinR + ly * cosR;
  }

  // Quadratic midpoint spline across the 192 sampled polar coordinates
  const lastIdx = RAY_COUNT - 1;
  const startMidX = (ptsX[lastIdx] + ptsX[0]) * 0.5;
  const startMidY = (ptsY[lastIdx] + ptsY[0]) * 0.5;

  const parts = [`M${startMidX.toFixed(2)},${startMidY.toFixed(2)}`];
  for (let i = 0; i < RAY_COUNT; i++) {
    const next = (i + 1) % RAY_COUNT;
    const midX = (ptsX[i] + ptsX[next]) * 0.5;
    const midY = (ptsY[i] + ptsY[next]) * 0.5;
    parts.push(`Q${ptsX[i].toFixed(2)},${ptsY[i].toFixed(2)} ${midX.toFixed(2)},${midY.toFixed(2)}`);
  }
  parts.push('Z');
  return parts.join('');
}

/* ============================================================================
 * 3. 120 Hz Semi-Implicit Euler Spring Channel
 * ========================================================================== */

export class SpringChannel {
  constructor({ value = 0, target = 0, stiffness = 240, damping = 18 } = {}) {
    this.value = value;
    this.target = target;
    this.velocity = 0;
    this.stiffness = stiffness;
    this.damping = damping;
  }

  step(dt = FIXED_DT) {
    const acc = (this.target - this.value) * this.stiffness - this.velocity * this.damping;
    this.velocity += acc * dt;
    this.value += this.velocity * dt;
    return this.value;
  }

  impulse(vel) {
    this.velocity += vel;
  }

  setTarget(target, stiffness = this.stiffness, damping = this.damping) {
    this.target = target;
    this.stiffness = stiffness;
    this.damping = damping;
  }

  snap(val) {
    this.value = val;
    this.target = val;
    this.velocity = 0;
  }
}

/* ============================================================================
 * 4. 9 Core Expressions & 6-Track Keyframe Choreography
 * ========================================================================== */

export const CORE_EXPRESSIONS = {
  neutral: {
    id: 'neutral',
    label: 'Neutral',
    labelZh: '平静',
    eyeW: 5.2,
    eyeH: 6.4,
    eyeRadius: 5.0,
    tiltDeg: 0,
    squashBias: 0,
    lidTop: 0,
    lidBottom: 0,
    happyArc: 0,
    glowBoost: 1.0,
  },
  happy: {
    id: 'happy',
    label: 'Happy',
    labelZh: '愉悦',
    eyeW: 5.6,
    eyeH: 5.2,
    eyeRadius: 5.0,
    tiltDeg: 0,
    squashBias: 0.04,
    lidTop: 0,
    lidBottom: 0.42,
    happyArc: 1.0,
    glowBoost: 1.25,
  },
  focused: {
    id: 'focused',
    label: 'Focused',
    labelZh: '专注',
    eyeW: 5.8,
    eyeH: 4.3,
    eyeRadius: 2.2,
    tiltDeg: 4,
    squashBias: -0.02,
    lidTop: 0.24,
    lidBottom: 0.14,
    happyArc: 0,
    glowBoost: 1.3,
  },
  curious: {
    id: 'curious',
    label: 'Curious',
    labelZh: '好奇',
    eyeW: 5.6,
    eyeH: 7.2,
    eyeRadius: 5.4,
    tiltDeg: -7,
    squashBias: 0.02,
    lidTop: 0,
    lidBottom: 0,
    happyArc: 0,
    asymmetry: 0.18,
    glowBoost: 1.15,
  },
  alert: {
    id: 'alert',
    label: 'Alert',
    labelZh: '警觉',
    eyeW: 6.0,
    eyeH: 7.8,
    eyeRadius: 3.4,
    tiltDeg: 0,
    squashBias: -0.06,
    lidTop: 0,
    lidBottom: 0,
    happyArc: 0,
    glowBoost: 1.55,
  },
  proud: {
    id: 'proud',
    label: 'Proud',
    labelZh: '成就',
    eyeW: 5.8,
    eyeH: 4.6,
    eyeRadius: 4.2,
    tiltDeg: -3,
    squashBias: 0.05,
    lidTop: 0.08,
    lidBottom: 0.45,
    happyArc: 0.85,
    glowBoost: 1.4,
  },
  sleepy: {
    id: 'sleepy',
    label: 'Sleepy',
    labelZh: '安眠',
    eyeW: 5.4,
    eyeH: 2.8,
    eyeRadius: 2.4,
    tiltDeg: 0,
    squashBias: 0.07,
    lidTop: 0.68,
    lidBottom: 0.12,
    happyArc: 0,
    glowBoost: 0.65,
  },
  evolving: {
    id: 'evolving',
    label: 'Evolving',
    labelZh: '进化',
    eyeW: 5.8,
    eyeH: 6.8,
    eyeRadius: 5.4,
    tiltDeg: 0,
    squashBias: 0.02,
    lidTop: 0.05,
    lidBottom: 0.10,
    happyArc: 0.3,
    glowBoost: 1.65,
  },
  listening: {
    id: 'listening',
    label: 'Listening',
    labelZh: '聆听',
    eyeW: 5.9,
    eyeH: 7.0,
    eyeRadius: 5.8,
    tiltDeg: -4,
    squashBias: 0.03,
    lidTop: 0,
    lidBottom: 0,
    happyArc: 0,
    glowBoost: 1.35,
  },
};

function evalKeyframeTrack(keyframes, u) {
  if (!keyframes || keyframes.length === 0) return 0;
  if (keyframes.length === 1) return keyframes[0].v;
  const t = ((u % 1) + 1) % 1;
  for (let i = 0; i < keyframes.length - 1; i++) {
    const a = keyframes[i];
    const b = keyframes[i + 1];
    if (t >= a.t && t <= b.t) {
      const span = Math.max(1e-5, b.t - a.t);
      const localT = (t - a.t) / span;
      const ease = b.ease || [0.34, 1.56, 0.64, 1];
      const curved = cubicBezier(ease[0], ease[1], ease[2], ease[3], localT);
      return lerp(a.v, b.v, curved);
    }
  }
  return keyframes[keyframes.length - 1].v;
}

export const AVATAR_LIFECYCLE_PRESETS = {
  idle: {
    id: 'idle',
    group: 'Idle & Ambient',
    shape: 'orb',
    expression: 'neutral',
    color: '#7c6cf6',
    periodSec: 4.2,
    tracks: {
      x: [
        { t: 0, v: 0 },
        { t: 0.5, v: 1.4, ease: [0.42, 0, 0.58, 1] },
        { t: 1, v: 0, ease: [0.42, 0, 0.58, 1] },
      ],
      y: [
        { t: 0, v: 0 },
        { t: 0.5, v: -3.2, ease: [0.42, 0, 0.58, 1] },
        { t: 1, v: 0, ease: [0.42, 0, 0.58, 1] },
      ],
      rot: [
        { t: 0, v: -1.5 },
        { t: 0.5, v: 1.5, ease: [0.42, 0, 0.58, 1] },
        { t: 1, v: -1.5, ease: [0.42, 0, 0.58, 1] },
      ],
      squash: [
        { t: 0, v: 0 },
        { t: 0.5, v: -0.025, ease: [0.42, 0, 0.58, 1] },
        { t: 1, v: 0, ease: [0.42, 0, 0.58, 1] },
      ],
      scale: [
        { t: 0, v: 0.99 },
        { t: 0.5, v: 1.025, ease: [0.42, 0, 0.58, 1] },
        { t: 1, v: 0.99, ease: [0.42, 0, 0.58, 1] },
      ],
      lids: [{ t: 0, v: 0 }, { t: 1, v: 0 }],
    },
  },
  thinking: {
    id: 'thinking',
    group: 'Thinking & Reasoning',
    shape: 'cloud',
    expression: 'curious',
    color: '#38bdf8',
    periodSec: 2.6,
    tracks: {
      x: [
        { t: 0, v: -2.2 },
        { t: 0.5, v: 2.2, ease: [0.34, 1.56, 0.64, 1] },
        { t: 1, v: -2.2, ease: [0.34, 1.56, 0.64, 1] },
      ],
      y: [
        { t: 0, v: -1.5 },
        { t: 0.35, v: -5.2, ease: [0.34, 1.56, 0.64, 1] },
        { t: 0.7, v: 1.0, ease: [0.42, 0, 0.58, 1] },
        { t: 1, v: -1.5, ease: [0.42, 0, 0.58, 1] },
      ],
      rot: [
        { t: 0, v: -5 },
        { t: 0.5, v: 6, ease: [0.34, 1.56, 0.64, 1] },
        { t: 1, v: -5, ease: [0.34, 1.56, 0.64, 1] },
      ],
      squash: [
        { t: 0, v: 0.02 },
        { t: 0.5, v: -0.04, ease: [0.34, 1.56, 0.64, 1] },
        { t: 1, v: 0.02, ease: [0.42, 0, 0.58, 1] },
      ],
      scale: [
        { t: 0, v: 0.98 },
        { t: 0.5, v: 1.04, ease: [0.42, 0, 0.58, 1] },
        { t: 1, v: 0.98, ease: [0.42, 0, 0.58, 1] },
      ],
      lids: [
        { t: 0, v: 0.06 },
        { t: 0.5, v: 0.16, ease: [0.42, 0, 0.58, 1] },
        { t: 1, v: 0.06, ease: [0.42, 0, 0.58, 1] },
      ],
    },
  },
  'pi-coding': {
    id: 'pi-coding',
    group: 'Tool & Harness Execution',
    shape: 'terminal',
    expression: 'focused',
    color: '#10b981',
    periodSec: 1.5,
    tracks: {
      x: [
        { t: 0, v: -1.4 },
        { t: 0.25, v: 1.6, ease: [0.22, 1, 0.36, 1] },
        { t: 0.5, v: -1.2, ease: [0.22, 1, 0.36, 1] },
        { t: 0.75, v: 1.4, ease: [0.22, 1, 0.36, 1] },
        { t: 1, v: -1.4, ease: [0.22, 1, 0.36, 1] },
      ],
      y: [
        { t: 0, v: 0 },
        { t: 0.25, v: -2.4, ease: [0.34, 1.56, 0.64, 1] },
        { t: 0.5, v: 0.6, ease: [0.42, 0, 0.58, 1] },
        { t: 0.75, v: -2.0, ease: [0.34, 1.56, 0.64, 1] },
        { t: 1, v: 0, ease: [0.42, 0, 0.58, 1] },
      ],
      rot: [
        { t: 0, v: -1.5 },
        { t: 0.5, v: 1.5, ease: [0.22, 1, 0.36, 1] },
        { t: 1, v: -1.5, ease: [0.22, 1, 0.36, 1] },
      ],
      squash: [
        { t: 0, v: 0.03 },
        { t: 0.5, v: -0.03, ease: [0.34, 1.56, 0.64, 1] },
        { t: 1, v: 0.03, ease: [0.34, 1.56, 0.64, 1] },
      ],
      scale: [
        { t: 0, v: 1.0 },
        { t: 0.5, v: 1.03, ease: [0.22, 1, 0.36, 1] },
        { t: 1, v: 1.0, ease: [0.22, 1, 0.36, 1] },
      ],
      lids: [{ t: 0, v: 0.12 }, { t: 1, v: 0.12 }],
    },
  },
  'claude-routing': {
    id: 'claude-routing',
    group: 'Tool & Harness Execution',
    shape: 'squircle',
    expression: 'focused',
    color: '#d97757',
    periodSec: 2.1,
    tracks: {
      x: [{ t: 0, v: 0 }, { t: 0.5, v: 1.8 }, { t: 1, v: 0 }],
      y: [{ t: 0, v: 0 }, { t: 0.5, v: -3.5, ease: [0.34, 1.56, 0.64, 1] }, { t: 1, v: 0 }],
      rot: [{ t: 0, v: -2 }, { t: 0.5, v: 3 }, { t: 1, v: -2 }],
      squash: [{ t: 0, v: 0.01 }, { t: 0.5, v: -0.04 }, { t: 1, v: 0.01 }],
      scale: [{ t: 0, v: 0.99 }, { t: 0.5, v: 1.035 }, { t: 1, v: 0.99 }],
      lids: [{ t: 0, v: 0.08 }, { t: 1, v: 0.08 }],
    },
  },
  'codex-routing': {
    id: 'codex-routing',
    group: 'Tool & Harness Execution',
    shape: 'bolt',
    expression: 'focused',
    color: '#3b82f6',
    periodSec: 1.35,
    tracks: {
      x: [{ t: 0, v: -2 }, { t: 0.5, v: 2, ease: [0.22, 1, 0.36, 1] }, { t: 1, v: -2 }],
      y: [{ t: 0, v: 0 }, { t: 0.35, v: -4.2, ease: [0.34, 1.56, 0.64, 1] }, { t: 1, v: 0 }],
      rot: [{ t: 0, v: -4 }, { t: 0.5, v: 4 }, { t: 1, v: -4 }],
      squash: [{ t: 0, v: 0.04 }, { t: 0.5, v: -0.05 }, { t: 1, v: 0.04 }],
      scale: [{ t: 0, v: 0.98 }, { t: 0.5, v: 1.045 }, { t: 1, v: 0.98 }],
      lids: [{ t: 0, v: 0.14 }, { t: 1, v: 0.14 }],
    },
  },
  'opencode-routing': {
    id: 'opencode-routing',
    group: 'Tool & Harness Execution',
    shape: 'spark',
    expression: 'curious',
    color: '#a855f7',
    periodSec: 1.9,
    tracks: {
      x: [{ t: 0, v: 0 }, { t: 0.5, v: -1.8 }, { t: 1, v: 0 }],
      y: [{ t: 0, v: 0 }, { t: 0.5, v: -4.0, ease: [0.34, 1.56, 0.64, 1] }, { t: 1, v: 0 }],
      rot: [{ t: 0, v: -3 }, { t: 0.5, v: 5 }, { t: 1, v: -3 }],
      squash: [{ t: 0, v: 0 }, { t: 0.5, v: -0.04 }, { t: 1, v: 0 }],
      scale: [{ t: 0, v: 0.98 }, { t: 0.5, v: 1.04 }, { t: 1, v: 0.98 }],
      lids: [{ t: 0, v: 0 }, { t: 1, v: 0 }],
    },
  },
  'byok-streaming': {
    id: 'byok-streaming',
    group: 'Tool & Harness Execution',
    shape: 'orb',
    expression: 'listening',
    color: '#f59e0b',
    periodSec: 1.7,
    tracks: {
      x: [{ t: 0, v: -1 }, { t: 0.5, v: 1 }, { t: 1, v: -1 }],
      y: [{ t: 0, v: 0 }, { t: 0.5, v: -3.0 }, { t: 1, v: 0 }],
      rot: [{ t: 0, v: -2 }, { t: 0.5, v: 2 }, { t: 1, v: -2 }],
      squash: [{ t: 0, v: 0.02 }, { t: 0.5, v: -0.03 }, { t: 1, v: 0.02 }],
      scale: [{ t: 0, v: 0.99 }, { t: 0.5, v: 1.05 }, { t: 1, v: 0.99 }],
      lids: [{ t: 0, v: 0 }, { t: 1, v: 0 }],
    },
  },
  'manus-cue': {
    id: 'manus-cue',
    group: 'Cue & Needs-You Alert',
    shape: 'spark',
    expression: 'curious',
    color: '#f59e0b',
    periodSec: 2.0,
    tracks: {
      x: [{ t: 0, v: 0 }, { t: 0.3, v: 2.8, ease: [0.34, 1.56, 0.64, 1] }, { t: 1, v: 0 }],
      y: [{ t: 0, v: 0 }, { t: 0.4, v: -4.8, ease: [0.34, 1.56, 0.64, 1] }, { t: 1, v: 0 }],
      rot: [{ t: 0, v: -6 }, { t: 0.45, v: 4, ease: [0.34, 1.56, 0.64, 1] }, { t: 1, v: -6 }],
      squash: [{ t: 0, v: 0.04 }, { t: 0.4, v: -0.05 }, { t: 1, v: 0.04 }],
      scale: [{ t: 0, v: 0.98 }, { t: 0.4, v: 1.06 }, { t: 1, v: 0.98 }],
      lids: [{ t: 0, v: 0 }, { t: 1, v: 0 }],
    },
  },
  'needs-you': {
    id: 'needs-you',
    group: 'Cue & Needs-You Alert',
    shape: 'shield',
    expression: 'alert',
    color: '#ef4444',
    periodSec: 1.15,
    tracks: {
      x: [
        { t: 0, v: 0 },
        { t: 0.18, v: -2.4, ease: [0.34, 1.56, 0.64, 1] },
        { t: 0.36, v: 2.4, ease: [0.34, 1.56, 0.64, 1] },
        { t: 0.55, v: 0, ease: [0.22, 1, 0.36, 1] },
        { t: 1, v: 0 },
      ],
      y: [
        { t: 0, v: 0 },
        { t: 0.25, v: -5.6, ease: [0.34, 1.56, 0.64, 1] },
        { t: 0.6, v: 0.5, ease: [0.42, 0, 0.58, 1] },
        { t: 1, v: 0 },
      ],
      rot: [
        { t: 0, v: 0 },
        { t: 0.2, v: -5 },
        { t: 0.4, v: 5 },
        { t: 0.65, v: 0 },
        { t: 1, v: 0 },
      ],
      squash: [
        { t: 0, v: 0.06 },
        { t: 0.28, v: -0.07, ease: [0.34, 1.56, 0.64, 1] },
        { t: 0.65, v: 0.02 },
        { t: 1, v: 0.06 },
      ],
      scale: [
        { t: 0, v: 1.0 },
        { t: 0.28, v: 1.07, ease: [0.34, 1.56, 0.64, 1] },
        { t: 1, v: 1.0 },
      ],
      lids: [{ t: 0, v: 0 }, { t: 1, v: 0 }],
    },
  },
  evolving: {
    id: 'evolving',
    group: 'Self-Evolution & Dreaming',
    shape: 'spark',
    expression: 'evolving',
    color: '#c084fc',
    periodSec: 3.0,
    tracks: {
      x: [{ t: 0, v: 0 }, { t: 0.5, v: 1.6 }, { t: 1, v: 0 }],
      y: [{ t: 0, v: 0 }, { t: 0.5, v: -6.0, ease: [0.34, 1.56, 0.64, 1] }, { t: 1, v: 0 }],
      rot: [{ t: 0, v: -4 }, { t: 0.5, v: 4, ease: [0.42, 0, 0.58, 1] }, { t: 1, v: -4 }],
      squash: [{ t: 0, v: 0.02 }, { t: 0.5, v: -0.05 }, { t: 1, v: 0.02 }],
      scale: [{ t: 0, v: 0.97 }, { t: 0.5, v: 1.06, ease: [0.34, 1.56, 0.64, 1] }, { t: 1, v: 0.97 }],
      lids: [{ t: 0, v: 0 }, { t: 1, v: 0 }],
    },
  },
  sleeping: {
    id: 'sleeping',
    group: 'Self-Evolution & Dreaming',
    shape: 'dream',
    expression: 'sleepy',
    color: '#818cf8',
    periodSec: 5.2,
    tracks: {
      x: [{ t: 0, v: -0.8 }, { t: 0.5, v: 0.8 }, { t: 1, v: -0.8 }],
      y: [{ t: 0, v: 2.0 }, { t: 0.5, v: 4.5, ease: [0.42, 0, 0.58, 1] }, { t: 1, v: 2.0 }],
      rot: [{ t: 0, v: 4 }, { t: 0.5, v: 8, ease: [0.42, 0, 0.58, 1] }, { t: 1, v: 4 }],
      squash: [{ t: 0, v: 0.06 }, { t: 0.5, v: 0.10, ease: [0.42, 0, 0.58, 1] }, { t: 1, v: 0.06 }],
      scale: [{ t: 0, v: 0.97 }, { t: 0.5, v: 1.01, ease: [0.42, 0, 0.58, 1] }, { t: 1, v: 0.97 }],
      lids: [{ t: 0, v: 0.78 }, { t: 1, v: 0.78 }],
    },
  },
};

/* ============================================================================
 * 5. Complete 53-State Catalog Across 5 Lifecycle Groups
 * ========================================================================== */

export const AVATAR_STATES_53 = [
  // Group 1: Idle & Ambient (10)
  { id: 'idle', name: 'Idle Breathe', nameZh: '静息呼吸', group: 'Idle & Ambient', preset: 'idle', shape: 'orb', expression: 'neutral', color: '#7c6cf6', haptic: 'none' },
  { id: 'ambient-breathe', name: 'Ambient Pulse', nameZh: '环境轻搏', group: 'Idle & Ambient', preset: 'idle', shape: 'orb', expression: 'happy', color: '#7c6cf6', haptic: 'soft' },
  { id: 'ambient-wander', name: 'Gaze Wander', nameZh: '视线巡游', group: 'Idle & Ambient', preset: 'idle', shape: 'squircle', expression: 'curious', color: '#818cf8', haptic: 'none' },
  { id: 'ambient-curious-glance', name: 'Curious Glance', nameZh: '侧目倾听', group: 'Idle & Ambient', preset: 'idle', shape: 'squircle', expression: 'curious', color: '#38bdf8', haptic: 'soft' },
  { id: 'ambient-coffee-break', name: 'Coffee Break', nameZh: '午间小憩', group: 'Idle & Ambient', preset: 'idle', shape: 'cloud', expression: 'happy', color: '#f59e0b', haptic: 'none' },
  { id: 'ambient-night-watch', name: 'Night Watch', nameZh: '夜间守望', group: 'Idle & Ambient', preset: 'idle', shape: 'shield', expression: 'focused', color: '#6366f1', haptic: 'none' },
  { id: 'ambient-battery-saver', name: 'Eco Standby', nameZh: '低功耗待机', group: 'Idle & Ambient', preset: 'sleeping', shape: 'orb', expression: 'sleepy', color: '#6c7382', haptic: 'none' },
  { id: 'ambient-standby', name: 'MenuBar Docked', nameZh: '状态栏驻留', group: 'Idle & Ambient', preset: 'idle', shape: 'squircle', expression: 'neutral', color: '#7c6cf6', haptic: 'none' },
  { id: 'ambient-warm-welcome', name: 'Warm Welcome', nameZh: '晨间问候', group: 'Idle & Ambient', preset: 'evolving', shape: 'orb', expression: 'happy', color: '#10b981', haptic: 'success' },
  { id: 'ambient-zen', name: 'Zen Flow', nameZh: '心流伴随', group: 'Idle & Ambient', preset: 'idle', shape: 'dream', expression: 'proud', color: '#7c6cf6', haptic: 'none' },

  // Group 2: Thinking & Reasoning (11)
  { id: 'thinking', name: 'Deep Thinking', nameZh: '深度思考', group: 'Thinking & Reasoning', preset: 'thinking', shape: 'cloud', expression: 'curious', color: '#38bdf8', haptic: 'tick' },
  { id: 'deep-reasoning', name: 'Chain of Thought', nameZh: '长链推理', group: 'Thinking & Reasoning', preset: 'thinking', shape: 'cloud', expression: 'focused', color: '#38bdf8', haptic: 'tick' },
  { id: 'memory-recall', name: 'Memory Recall', nameZh: '四层记忆召回', group: 'Thinking & Reasoning', preset: 'thinking', shape: 'orb', expression: 'curious', color: '#c084fc', haptic: 'soft' },
  { id: 'context-scanning', name: 'Context Scanning', nameZh: '窗口语境扫描', group: 'Thinking & Reasoning', preset: 'thinking', shape: 'terminal', expression: 'focused', color: '#38bdf8', haptic: 'none' },
  { id: 'plan-structuring', name: 'Plan Structuring', nameZh: '任务拆解编排', group: 'Thinking & Reasoning', preset: 'thinking', shape: 'squircle', expression: 'focused', color: '#7c6cf6', haptic: 'tick' },
  { id: 'hypothesis-branching', name: 'Branch Exploring', nameZh: '多假设推演', group: 'Thinking & Reasoning', preset: 'thinking', shape: 'spark', expression: 'curious', color: '#a855f7', haptic: 'none' },
  { id: 'cross-checking', name: 'Cross Checking', nameZh: '证据交叉校验', group: 'Thinking & Reasoning', preset: 'thinking', shape: 'shield', expression: 'focused', color: '#10b981', haptic: 'none' },
  { id: 'cost-routing', name: 'Harness Cost Route', nameZh: '模型成本路由', group: 'Thinking & Reasoning', preset: 'thinking', shape: 'bolt', expression: 'focused', color: '#f59e0b', haptic: 'none' },
  { id: 'diff-analyzing', name: 'Diff Analyzing', nameZh: '代码差异审查', group: 'Thinking & Reasoning', preset: 'pi-coding', shape: 'terminal', expression: 'focused', color: '#3b82f6', haptic: 'none' },
  { id: 'voice-transcribing', name: 'Voice Listening', nameZh: '语音打断聆听', group: 'Thinking & Reasoning', preset: 'byok-streaming', shape: 'orb', expression: 'listening', color: '#38bdf8', haptic: 'soft' },
  { id: 'synthesizing', name: 'Outcome Synthesis', nameZh: '结果汇总提炼', group: 'Thinking & Reasoning', preset: 'evolving', shape: 'spark', expression: 'proud', color: '#10b981', haptic: 'success' },

  // Group 3: Tool & Harness Execution (14)
  { id: 'pi-coding', name: 'Pi Core Active', nameZh: 'Pi 原生执行', group: 'Tool & Harness Execution', preset: 'pi-coding', shape: 'terminal', expression: 'focused', color: '#10b981', haptic: 'tick' },
  { id: 'pi-bash-running', name: 'Pi Bash Shell', nameZh: '终端命令运行', group: 'Tool & Harness Execution', preset: 'pi-coding', shape: 'terminal', expression: 'focused', color: '#10b981', haptic: 'tick' },
  { id: 'pi-file-editing', name: 'Pi File Patching', nameZh: '精准文件修改', group: 'Tool & Harness Execution', preset: 'pi-coding', shape: 'squircle', expression: 'focused', color: '#10b981', haptic: 'soft' },
  { id: 'claude-routing', name: 'Claude Code CLI', nameZh: 'Claude 接管中', group: 'Tool & Harness Execution', preset: 'claude-routing', shape: 'squircle', expression: 'focused', color: '#d97757', haptic: 'tick' },
  { id: 'codex-routing', name: 'Codex Harness', nameZh: 'Codex 接管中', group: 'Tool & Harness Execution', preset: 'codex-routing', shape: 'bolt', expression: 'focused', color: '#3b82f6', haptic: 'tick' },
  { id: 'opencode-routing', name: 'OpenCode ACP', nameZh: 'OpenCode 接管', group: 'Tool & Harness Execution', preset: 'opencode-routing', shape: 'spark', expression: 'curious', color: '#a855f7', haptic: 'tick' },
  { id: 'byok-streaming', name: 'BYOK Streaming', nameZh: 'BYOK 直连流式', group: 'Tool & Harness Execution', preset: 'byok-streaming', shape: 'orb', expression: 'listening', color: '#f59e0b', haptic: 'none' },
  { id: 'mcp-bridging', name: 'Routed MCP Bridge', nameZh: 'MCP 工具桥接', group: 'Tool & Harness Execution', preset: 'pi-coding', shape: 'bolt', expression: 'focused', color: '#38bdf8', haptic: 'none' },
  { id: 'subsession-spawning', name: 'Child Bot Spawning', nameZh: '子会话并发派生', group: 'Tool & Harness Execution', preset: 'opencode-routing', shape: 'spark', expression: 'happy', color: '#7c6cf6', haptic: 'double-tick' },
  { id: 'browser-evaluating', name: 'Layout Evaluator', nameZh: '浏览器回归评测', group: 'Tool & Harness Execution', preset: 'thinking', shape: 'squircle', expression: 'curious', color: '#38bdf8', haptic: 'none' },
  { id: 'vps-deploying', name: 'VPS Deploying', nameZh: 'VPS 节点部署', group: 'Tool & Harness Execution', preset: 'codex-routing', shape: 'bolt', expression: 'focused', color: '#10b981', haptic: 'success' },
  { id: 'mac-automating', name: 'Mac UI Automating', nameZh: 'Mac 系统自动化', group: 'Tool & Harness Execution', preset: 'pi-coding', shape: 'squircle', expression: 'focused', color: '#38bdf8', haptic: 'soft' },
  { id: 'iot-signaling', name: 'IoT MQTT Signal', nameZh: '嵌入式设备联动', group: 'Tool & Harness Execution', preset: 'byok-streaming', shape: 'spark', expression: 'happy', color: '#f472b6', haptic: 'tick' },
  { id: 'git-committing', name: 'PR Shipping', nameZh: '代码提交与 PR', group: 'Tool & Harness Execution', preset: 'evolving', shape: 'shield', expression: 'proud', color: '#10b981', haptic: 'success' },

  // Group 4: Cue & Needs-You Alert (10)
  { id: 'manus-cue', name: 'Manus Cue Ready', nameZh: 'Cue 灵感轻提示', group: 'Cue & Needs-You Alert', preset: 'manus-cue', shape: 'spark', expression: 'curious', color: '#f59e0b', haptic: 'cue-whisper' },
  { id: 'cue-whispering', name: 'Cue Whispering', nameZh: '上下文低语', group: 'Cue & Needs-You Alert', preset: 'manus-cue', shape: 'cloud', expression: 'happy', color: '#f59e0b', haptic: 'soft' },
  { id: 'cue-window-matched', name: 'Window Context Lock', nameZh: '前台应用匹配', group: 'Cue & Needs-You Alert', preset: 'manus-cue', shape: 'squircle', expression: 'listening', color: '#38bdf8', haptic: 'tick' },
  { id: 'needs-you', name: 'Needs You Inbox', nameZh: '等待人类拍板', group: 'Cue & Needs-You Alert', preset: 'needs-you', shape: 'shield', expression: 'alert', color: '#ef4444', haptic: 'needs-you' },
  { id: 'needs-you-urgent', name: 'Urgent Escalation', nameZh: '高危操作确认', group: 'Cue & Needs-You Alert', preset: 'needs-you', shape: 'bolt', expression: 'alert', color: '#ef4444', haptic: 'urgent' },
  { id: 'needs-you-approval', name: 'Approve PR / Deploy', nameZh: '待批准上线', group: 'Cue & Needs-You Alert', preset: 'needs-you', shape: 'shield', expression: 'curious', color: '#f59e0b', haptic: 'needs-you' },
  { id: 'needs-you-diff-ready', name: 'R2 Evidence Ready', nameZh: '前后对比证据就绪', group: 'Cue & Needs-You Alert', preset: 'manus-cue', shape: 'terminal', expression: 'proud', color: '#38bdf8', haptic: 'soft' },
  { id: 'fleet-degraded', name: 'Fleet Node Degraded', nameZh: '节点健康告警', group: 'Cue & Needs-You Alert', preset: 'needs-you', shape: 'bolt', expression: 'alert', color: '#f59e0b', haptic: 'warning' },
  { id: 'tunnel-reconnecting', name: 'Cloudflare Reconnect', nameZh: '隧道重连中', group: 'Cue & Needs-You Alert', preset: 'thinking', shape: 'cloud', expression: 'curious', color: '#f59e0b', haptic: 'none' },
  { id: 'voice-interrupted', name: 'Voice Interrupt', nameZh: '语音打断接管', group: 'Cue & Needs-You Alert', preset: 'byok-streaming', shape: 'orb', expression: 'listening', color: '#7c6cf6', haptic: 'tick' },

  // Group 5: Self-Evolution & Dreaming (8)
  { id: 'evolving', name: 'Self-Evolving', nameZh: '认知自我进化', group: 'Self-Evolution & Dreaming', preset: 'evolving', shape: 'spark', expression: 'evolving', color: '#c084fc', haptic: 'dream-sync' },
  { id: 'sleeping', name: 'Nightly Sleep', nameZh: '夜间休眠待命', group: 'Self-Evolution & Dreaming', preset: 'sleeping', shape: 'dream', expression: 'sleepy', color: '#818cf8', haptic: 'none' },
  { id: 'dreaming-consolidating', name: 'Dream Consolidate', nameZh: '夜间记忆做梦整合', group: 'Self-Evolution & Dreaming', preset: 'sleeping', shape: 'dream', expression: 'sleepy', color: '#c084fc', haptic: 'none' },
  { id: 'skill-synthesizing', name: 'Skill Synthesis', nameZh: '自动蒸馏新技能', group: 'Self-Evolution & Dreaming', preset: 'evolving', shape: 'terminal', expression: 'evolving', color: '#a855f7', haptic: 'dream-sync' },
  { id: 'persona-updating', name: 'USER.md Refining', nameZh: '用户画像更新', group: 'Self-Evolution & Dreaming', preset: 'evolving', shape: 'orb', expression: 'happy', color: '#7c6cf6', haptic: 'soft' },
  { id: 'memory-pruning', name: 'Memory Superseding', nameZh: '过期事实淘汰', group: 'Self-Evolution & Dreaming', preset: 'thinking', shape: 'dream', expression: 'focused', color: '#818cf8', haptic: 'none' },
  { id: 'r2-backing-up', name: 'R2 Encrypted Sync', nameZh: 'R2 加密快照同步', group: 'Self-Evolution & Dreaming', preset: 'idle', shape: 'shield', expression: 'neutral', color: '#10b981', haptic: 'none' },
  { id: 'evolution-proud', name: 'Understanding +1%', nameZh: '默契度提升庆祝', group: 'Self-Evolution & Dreaming', preset: 'evolving', shape: 'spark', expression: 'proud', color: '#10b981', haptic: 'success' },
];

export const STATE_BY_ID = new Map(AVATAR_STATES_53.map((s) => [s.id, s]));

/* ============================================================================
 * 6. PipiAvatar Engine Class (DOM + Headless Safe)
 * ========================================================================== */

const LEFT_EYE_SPHERE_BASE = normalizeVec([-0.31, -0.04, 0.95]);
const RIGHT_EYE_SPHERE_BASE = normalizeVec([0.31, -0.04, 0.95]);

export class PipiAvatar {
  constructor(container, options = {}) {
    this.container = typeof container === 'string' && typeof document !== 'undefined'
      ? document.querySelector(container)
      : container;

    this.size = options.size || 200;
    this.interactive = options.interactive !== false;
    this.autoBlink = options.autoBlink !== false;
    this.cursorTrack = options.cursorTrack !== false;
    this.onTelemetry = typeof options.onTelemetry === 'function' ? options.onTelemetry : null;
    this.onPoke = typeof options.onPoke === 'function' ? options.onPoke : null;

    this.rng = createSeededRng(options.seed || 20261118);
    this.uid = `pipi-${Math.floor(this.rng() * 1e9)}`;

    // State & Morph buffers
    this.stateId = options.initialState || 'idle';
    this.preset = AVATAR_LIFECYCLE_PRESETS.idle;
    this.shapeId = 'orb';
    this.expressionId = 'neutral';
    this.accentColor = '#7c6cf6';

    this.fromRadii = sampleShape192('orb');
    this.toRadii = sampleShape192('orb');
    this.currentRadii = new Float32Array(this.fromRadii);

    // 120 Hz Euler spring trio
    this.springs = {
      amount: new SpringChannel({ value: 0, target: 0, stiffness: 360, damping: 18 }),
      swap: new SpringChannel({ value: 1, target: 1, stiffness: 210, damping: 19 }),
      spin: new SpringChannel({ value: 0, target: 0, stiffness: 240, damping: 17 }),
      gazeX: new SpringChannel({ value: 0, target: 0, stiffness: 150, damping: 16 }),
      gazeY: new SpringChannel({ value: 0, target: 0, stiffness: 150, damping: 16 }),
    };

    // Target gaze in [-1, 1]
    this.pointerGaze = { x: 0, y: 0 };
    this.autoGaze = { x: 0, y: 0 };
    this.lastPointerMoveTime = 0;

    // Blink scheduler (0.26s, closed at 45%)
    this.blinkActive = false;
    this.blinkElapsed = 0;
    this.nextAutoBlinkAt = 2.4 + this.rng() * 2.5;

    // Timing & accumulator
    this.elapsed = 0;
    this.accumulator = 0;
    this.lastFrameMs = null;
    this.rafId = null;
    this.running = false;
    this.telemetryAccum = 0;

    // Last evaluated 6-track values
    this.tracks = { x: 0, y: 0, rot: 0, squash: 0, scale: 1, lids: 0 };
    this.lastEyeTelemetry = {
      theta: 0,
      axis: [0, 1, 0],
      left3D: [...LEFT_EYE_SPHERE_BASE],
      right3D: [...RIGHT_EYE_SPHERE_BASE],
      blinkClosure: 0,
    };

    if (this.container && typeof document !== 'undefined') {
      this._buildDom();
      this._bindEvents();
    }

    this.setState(this.stateId, { immediate: true });

    if (this.container && typeof window !== 'undefined' && options.autoStart !== false) {
      this.start();
    }
  }

  _buildDom() {
    const ns = 'http://www.w3.org/2000/svg';
    const svg = document.createElementNS(ns, 'svg');
    svg.setAttribute('viewBox', '0 0 120 120');
    svg.setAttribute('width', String(this.size));
    svg.setAttribute('height', String(this.size));
    svg.setAttribute('class', 'pipi-avatar-svg');
    svg.setAttribute('role', 'img');
    svg.setAttribute('aria-label', 'PipiBot Procedural Living Avatar');
    svg.style.overflow = 'visible';
    svg.style.display = 'block';
    svg.style.userSelect = 'none';

    const defs = document.createElementNS(ns, 'defs');

    // Outer glow filter
    const filter = document.createElementNS(ns, 'filter');
    filter.setAttribute('id', `${this.uid}-glow`);
    filter.setAttribute('x', '-40%');
    filter.setAttribute('y', '-40%');
    filter.setAttribute('width', '180%');
    filter.setAttribute('height', '180%');
    const blur = document.createElementNS(ns, 'feGaussianBlur');
    blur.setAttribute('stdDeviation', '3.2');
    blur.setAttribute('result', 'coloredBlur');
    const merge = document.createElementNS(ns, 'feMerge');
    const m1 = document.createElementNS(ns, 'feMergeNode');
    m1.setAttribute('in', 'coloredBlur');
    const m2 = document.createElementNS(ns, 'feMergeNode');
    m2.setAttribute('in', 'SourceGraphic');
    merge.append(m1, m2);
    filter.append(blur, merge);

    // Ambient halo gradient
    const haloGrad = document.createElementNS(ns, 'radialGradient');
    haloGrad.setAttribute('id', `${this.uid}-halo`);
    const hs1 = document.createElementNS(ns, 'stop');
    hs1.setAttribute('offset', '0%');
    hs1.setAttribute('stop-color', this.accentColor);
    hs1.setAttribute('stop-opacity', '0.42');
    const hs2 = document.createElementNS(ns, 'stop');
    hs2.setAttribute('offset', '100%');
    hs2.setAttribute('stop-color', this.accentColor);
    hs2.setAttribute('stop-opacity', '0');
    haloGrad.append(hs1, hs2);

    // Body 3D gradient
    const bodyGrad = document.createElementNS(ns, 'radialGradient');
    bodyGrad.setAttribute('id', `${this.uid}-body`);
    bodyGrad.setAttribute('cx', '38%');
    bodyGrad.setAttribute('cy', '30%');
    bodyGrad.setAttribute('r', '72%');
    const bs1 = document.createElementNS(ns, 'stop');
    bs1.setAttribute('offset', '0%');
    bs1.setAttribute('stop-color', '#363c4f');
    const bs2 = document.createElementNS(ns, 'stop');
    bs2.setAttribute('offset', '62%');
    bs2.setAttribute('stop-color', '#1a1e28');
    const bs3 = document.createElementNS(ns, 'stop');
    bs3.setAttribute('offset', '100%');
    bs3.setAttribute('stop-color', '#0e1016');
    bodyGrad.append(bs1, bs2, bs3);

    // Rim highlight gradient
    const rimGrad = document.createElementNS(ns, 'linearGradient');
    rimGrad.setAttribute('id', `${this.uid}-rim`);
    rimGrad.setAttribute('x1', '0%');
    rimGrad.setAttribute('y1', '0%');
    rimGrad.setAttribute('x2', '100%');
    rimGrad.setAttribute('y2', '100%');
    const rs1 = document.createElementNS(ns, 'stop');
    rs1.setAttribute('offset', '0%');
    rs1.setAttribute('stop-color', this.accentColor);
    rs1.setAttribute('stop-opacity', '0.92');
    const rs2 = document.createElementNS(ns, 'stop');
    rs2.setAttribute('offset', '55%');
    rs2.setAttribute('stop-color', '#ffffff');
    rs2.setAttribute('stop-opacity', '0.18');
    const rs3 = document.createElementNS(ns, 'stop');
    rs3.setAttribute('offset', '100%');
    rs3.setAttribute('stop-color', this.accentColor);
    rs3.setAttribute('stop-opacity', '0.65');
    rimGrad.append(rs1, rs2, rs3);

    defs.append(filter, haloGrad, bodyGrad, rimGrad);

    const haloCircle = document.createElementNS(ns, 'circle');
    haloCircle.setAttribute('cx', '60');
    haloCircle.setAttribute('cy', '60');
    haloCircle.setAttribute('r', '52');
    haloCircle.setAttribute('fill', `url(#${this.uid}-halo)`);

    const rootGroup = document.createElementNS(ns, 'g');

    const bodyPath = document.createElementNS(ns, 'path');
    bodyPath.setAttribute('fill', `url(#${this.uid}-body)`);
    bodyPath.setAttribute('stroke', `url(#${this.uid}-rim)`);
    bodyPath.setAttribute('stroke-width', '2.1');

    // Subtle specular crown reflection
    const crownHighlight = document.createElementNS(ns, 'ellipse');
    crownHighlight.setAttribute('cx', '51');
    crownHighlight.setAttribute('cy', '37');
    crownHighlight.setAttribute('rx', '16');
    crownHighlight.setAttribute('ry', '7');
    crownHighlight.setAttribute('fill', 'rgba(255,255,255,0.08)');
    crownHighlight.setAttribute('transform', 'rotate(-16 51 37)');

    const eyesGroup = document.createElementNS(ns, 'g');
    eyesGroup.setAttribute('filter', `url(#${this.uid}-glow)`);

    const leftEye = this._createEyeElement(ns);
    const rightEye = this._createEyeElement(ns);
    eyesGroup.append(leftEye.group, rightEye.group);

    rootGroup.append(bodyPath, crownHighlight, eyesGroup);
    svg.append(defs, haloCircle, rootGroup);

    this.container.innerHTML = '';
    this.container.appendChild(svg);

    this.dom = {
      svg,
      haloStop: hs1,
      haloStopEnd: hs2,
      rimStop1: rs1,
      rimStop3: rs3,
      haloCircle,
      rootGroup,
      bodyPath,
      crownHighlight,
      eyesGroup,
      leftEye,
      rightEye,
    };
  }

  _createEyeElement(ns) {
    const group = document.createElementNS(ns, 'g');
    const shape = document.createElementNS(ns, 'path');
    shape.setAttribute('fill', this.accentColor);
    const glint = document.createElementNS(ns, 'circle');
    glint.setAttribute('r', '1.45');
    glint.setAttribute('fill', '#ffffff');
    glint.setAttribute('opacity', '0.88');
    group.append(shape, glint);
    return { group, shape, glint };
  }

  _bindEvents() {
    if (!this.interactive) return;
    this._onClick = () => this.poke();
    this.dom.svg.style.cursor = 'pointer';
    this.dom.svg.addEventListener('click', this._onClick);
  }

  setGazeTarget(nx, ny) {
    this.pointerGaze.x = clamp(nx, -1, 1);
    this.pointerGaze.y = clamp(ny, -1, 1);
    this.lastPointerMoveTime = this.elapsed;
  }

  setState(stateId, opts = {}) {
    const meta = STATE_BY_ID.get(stateId);
    const presetKey = meta ? meta.preset : (AVATAR_LIFECYCLE_PRESETS[stateId] ? stateId : 'idle');
    const preset = AVATAR_LIFECYCLE_PRESETS[presetKey] || AVATAR_LIFECYCLE_PRESETS.idle;

    this.stateId = meta ? meta.id : preset.id;
    this.preset = preset;
    const nextShape = opts.shape || (meta ? meta.shape : preset.shape);
    const nextExpr = opts.expression || (meta ? meta.expression : preset.expression);
    const nextColor = opts.color || (meta ? meta.color : preset.color);

    this.setExpression(nextExpr);
    this.setAccentColor(nextColor);
    this.setShape(nextShape, { immediate: opts.immediate });

    if (!opts.immediate) {
      this.springs.amount.impulse(2.8);
      this.springs.spin.impulse(stateId === 'needs-you' ? -140 : 110);
    }
  }

  setShape(shapeId, opts = {}) {
    const resolved = AVATAR_SHAPES[shapeId] ? shapeId : 'orb';
    if (resolved === this.shapeId && !opts.immediate) return;
    this.shapeId = resolved;
    this.fromRadii = new Float32Array(this.currentRadii);
    this.toRadii = sampleShape192(resolved);
    if (opts.immediate) {
      this.currentRadii.set(this.toRadii);
      this.springs.swap.snap(1);
    } else {
      this.springs.swap.snap(0);
      this.springs.swap.setTarget(1, 210, 19);
      this.springs.amount.impulse(1.9);
    }
  }

  setExpression(expressionId) {
    this.expressionId = CORE_EXPRESSIONS[expressionId] ? expressionId : 'neutral';
  }

  setAccentColor(hex) {
    this.accentColor = hex;
    if (!this.dom) return;
    this.dom.haloStop.setAttribute('stop-color', hex);
    this.dom.haloStopEnd.setAttribute('stop-color', hex);
    this.dom.rimStop1.setAttribute('stop-color', hex);
    this.dom.rimStop3.setAttribute('stop-color', hex);
    this.dom.leftEye.shape.setAttribute('fill', hex);
    this.dom.rightEye.shape.setAttribute('fill', hex);
  }

  blink() {
    this.blinkActive = true;
    this.blinkElapsed = 0;
  }

  poke() {
    this.blink();
    this.springs.amount.impulse(4.8);
    this.springs.spin.impulse((this.rng() > 0.5 ? 1 : -1) * 185);
    if (this.onPoke) this.onPoke(this.stateId);
  }

  start() {
    if (this.running || typeof requestAnimationFrame === 'undefined') return;
    this.running = true;
    this.lastFrameMs = null;
    const tick = (nowMs) => {
      if (!this.running) return;
      if (this.lastFrameMs === null) this.lastFrameMs = nowMs;
      const dt = Math.min(0.05, Math.max(0, (nowMs - this.lastFrameMs) / 1000));
      this.lastFrameMs = nowMs;
      this.step(dt);
      this.render();
      this.rafId = requestAnimationFrame(tick);
    };
    this.rafId = requestAnimationFrame(tick);
  }

  stop() {
    this.running = false;
    if (this.rafId !== null && typeof cancelAnimationFrame !== 'undefined') {
      cancelAnimationFrame(this.rafId);
      this.rafId = null;
    }
  }

  destroy() {
    this.stop();
    if (this.dom && this._onClick) {
      this.dom.svg.removeEventListener('click', this._onClick);
    }
  }

  /**
   * Advance physics at locked 120 Hz semi-implicit Euler intervals.
   * Safe to invoke headlessly in unit verification without a DOM!
   */
  step(deltaSec) {
    this.accumulator += deltaSec;
    while (this.accumulator >= FIXED_DT) {
      this._stepFixed(FIXED_DT);
      this.accumulator -= FIXED_DT;
    }
  }

  _stepFixed(dt) {
    this.elapsed += dt;

    // 1. Auto-blink scheduler
    if (this.autoBlink && !this.blinkActive && this.elapsed >= this.nextAutoBlinkAt) {
      this.blink();
      const isDouble = this.rng() < 0.14;
      this.nextAutoBlinkAt = this.elapsed + (isDouble ? 0.36 : 2.6 + this.rng() * 3.4);
    }

    let blinkClosure = 0;
    if (this.blinkActive) {
      this.blinkElapsed += dt;
      const u = this.blinkElapsed / BLINK_DURATION;
      if (u >= 1) {
        this.blinkActive = false;
        this.blinkElapsed = 0;
        blinkClosure = 0;
      } else if (u <= BLINK_PEAK_RATIO) {
        blinkClosure = Math.pow(u / BLINK_PEAK_RATIO, 1.55);
      } else {
        blinkClosure = Math.pow(1 - (u - BLINK_PEAK_RATIO) / (1 - BLINK_PEAK_RATIO), 2.2);
      }
    }

    // 2. Autonomous gaze idle drift when pointer has rested
    if (!this.cursorTrack || this.elapsed - this.lastPointerMoveTime > 2.4) {
      const lookPhase = this.elapsed * 0.72;
      this.autoGaze.x = Math.sin(lookPhase) * 0.34 + Math.sin(lookPhase * 2.1) * 0.14;
      this.autoGaze.y = Math.cos(lookPhase * 0.85) * 0.20;
      this.springs.gazeX.setTarget(this.autoGaze.x, 85, 13);
      this.springs.gazeY.setTarget(this.autoGaze.y, 85, 13);
    } else {
      this.springs.gazeX.setTarget(this.pointerGaze.x, 180, 18);
      this.springs.gazeY.setTarget(this.pointerGaze.y, 180, 18);
    }

    // 3. Step 120 Hz Euler springs
    this.springs.amount.step(dt);
    this.springs.swap.step(dt);
    this.springs.spin.step(dt);
    this.springs.gazeX.step(dt);
    this.springs.gazeY.step(dt);

    // 4. Evaluate 6-track choreography
    const period = Math.max(0.5, this.preset.periodSec || 3.0);
    const phase = (this.elapsed % period) / period;
    const tDef = this.preset.tracks;

    this.tracks.x = evalKeyframeTrack(tDef.x, phase);
    this.tracks.y = evalKeyframeTrack(tDef.y, phase);
    this.tracks.rot = evalKeyframeTrack(tDef.rot, phase);
    this.tracks.squash = evalKeyframeTrack(tDef.squash, phase);
    this.tracks.scale = evalKeyframeTrack(tDef.scale, phase);
    this.tracks.lids = clamp(Math.max(evalKeyframeTrack(tDef.lids, phase), blinkClosure), 0, 1);

    // 5. Update interpolated 192-ray silhouette
    interpolateRays192(this.fromRadii, this.toRadii, this.springs.swap.value, this.currentRadii);

    // 6. Compute Rodrigues 3D sphere eye rotations
    const gx = this.springs.gazeX.value;
    const gy = this.springs.gazeY.value;
    const gazeMag = clamp(Math.hypot(gx, gy), 0, 1);
    const axis = gazeMag > 1e-4 ? normalizeVec([-gy, gx, 0]) : [0, 1, 0];
    const theta = gazeMag * 0.46;

    const left3D = rodriguesRotate(LEFT_EYE_SPHERE_BASE, axis, theta);
    const right3D = rodriguesRotate(RIGHT_EYE_SPHERE_BASE, axis, theta);

    this.lastEyeTelemetry = {
      theta,
      axis,
      left3D,
      right3D,
      blinkClosure,
      blinkProgress: this.blinkActive ? clamp(this.blinkElapsed / BLINK_DURATION, 0, 1) : 0,
    };

    // 7. Throttled telemetry emission (~30 Hz for smooth UI gauges without DOM thrash)
    if (this.onTelemetry) {
      this.telemetryAccum += dt;
      if (this.telemetryAccum >= 1 / 30) {
        this.telemetryAccum = 0;
        this.onTelemetry(this.getTelemetry());
      }
    }
  }

  getTelemetry() {
    return {
      stateId: this.stateId,
      shapeId: this.shapeId,
      expressionId: this.expressionId,
      accentColor: this.accentColor,
      elapsed: this.elapsed,
      springs: {
        amount: this.springs.amount.value,
        swap: this.springs.swap.value,
        spin: this.springs.spin.value,
      },
      tracks: { ...this.tracks },
      gaze: {
        x: this.springs.gazeX.value,
        y: this.springs.gazeY.value,
        thetaRad: this.lastEyeTelemetry.theta,
        axis: [...this.lastEyeTelemetry.axis],
        left3D: [...this.lastEyeTelemetry.left3D],
        right3D: [...this.lastEyeTelemetry.right3D],
      },
      blink: {
        active: this.blinkActive,
        progress: this.lastEyeTelemetry.blinkProgress,
        closure: this.lastEyeTelemetry.blinkClosure,
      },
    };
  }

  render() {
    if (!this.dom) return;

    const expr = CORE_EXPRESSIONS[this.expressionId] || CORE_EXPRESSIONS.neutral;
    const squashTotal = clamp(this.tracks.squash + this.springs.amount.value * 0.14 + (expr.squashBias || 0), -0.32, 0.35);
    const sx = (1 + squashTotal) * this.tracks.scale;
    const sy = (1 / Math.max(0.68, 1 + squashTotal)) * this.tracks.scale;
    const totalRotDeg = this.tracks.rot + this.springs.spin.value + (expr.tiltDeg || 0);
    const totalRotRad = (totalRotDeg * Math.PI) / 180;

    const cx = 60 + this.tracks.x;
    const cy = 60 + this.tracks.y;
    const baseRadius = 36;

    // 1. Body path from 192 rays
    const d = raysToSmoothSvgPath(this.currentRadii, cx, cy, baseRadius, sx, sy, totalRotRad);
    this.dom.bodyPath.setAttribute('d', d);

    // 2. Specular crown + ambient halo follow body motion
    this.dom.haloCircle.setAttribute('cx', cx.toFixed(2));
    this.dom.haloCircle.setAttribute('cy', cy.toFixed(2));
    this.dom.haloCircle.setAttribute('r', (50 * this.tracks.scale).toFixed(2));

    this.dom.crownHighlight.setAttribute('cx', (cx - 9).toFixed(2));
    this.dom.crownHighlight.setAttribute('cy', (cy - 21).toFixed(2));

    // 3. Project 3D Rodrigues sphere coordinates onto 2D face plane
    const faceSphereRadius = 25 * this.tracks.scale;
    const lidTotal = clamp(Math.max(this.tracks.lids, expr.lidTop), 0, 1);

    this._renderSingleEye(this.dom.leftEye, this.lastEyeTelemetry.left3D, cx, cy, faceSphereRadius, expr, lidTotal, 1);
    this._renderSingleEye(this.dom.rightEye, this.lastEyeTelemetry.right3D, cx, cy, faceSphereRadius, expr, lidTotal, expr.asymmetry ? 1 + expr.asymmetry : 1);
  }

  _renderSingleEye(eyeDom, v3, cx, cy, sphereRadius, expr, lidTop, scaleBonus = 1) {
    // Orthographic projection from unit sphere
    const ex = cx + v3[0] * sphereRadius;
    const ey = cy + v3[1] * sphereRadius;
    const foreshortenX = Math.max(0.36, v3[2]);

    const w = expr.eyeW * foreshortenX * scaleBonus;
    const rawH = expr.eyeH * scaleBonus;
    const openFactor = clamp(1 - lidTop * 0.92 - expr.lidBottom * 0.25, 0.08, 1);
    const h = Math.max(1.2, rawH * openFactor);

    // Happy / proud upward crescent arc vs rounded pill eye
    if ((expr.happyArc > 0.5 && lidTop < 0.35) || (this.expressionId === 'happy' && lidTop < 0.35)) {
      const arcW = w * 1.15;
      const arch = Math.max(2.6, rawH * 0.65);
      const pathD = [
        `M ${(ex - arcW).toFixed(2)} ${(ey + 1.5).toFixed(2)}`,
        `Q ${ex.toFixed(2)} ${(ey - arch * 1.65).toFixed(2)} ${(ex + arcW).toFixed(2)} ${(ey + 1.5).toFixed(2)}`,
        `Q ${ex.toFixed(2)} ${(ey - arch * 0.6).toFixed(2)} ${(ex - arcW).toFixed(2)} ${(ey + 1.5).toFixed(2)}`,
        'Z',
      ].join(' ');
      eyeDom.shape.setAttribute('d', pathD);
      eyeDom.glint.setAttribute('opacity', '0');
      return;
    }

    // Closed blink line or sleepy arc
    if (h <= 1.75) {
      const lineW = w * 1.12;
      const bend = this.expressionId === 'sleepy' ? 2.2 : 1.0;
      const pathD = [
        `M ${(ex - lineW).toFixed(2)} ${ey.toFixed(2)}`,
        `Q ${ex.toFixed(2)} ${(ey + bend).toFixed(2)} ${(ex + lineW).toFixed(2)} ${ey.toFixed(2)}`,
        `Q ${ex.toFixed(2)} ${(ey + bend + 1.4).toFixed(2)} ${(ex - lineW).toFixed(2)} ${ey.toFixed(2)}`,
        'Z',
      ].join(' ');
      eyeDom.shape.setAttribute('d', pathD);
      eyeDom.glint.setAttribute('opacity', '0');
      return;
    }

    // Rounded capsule/squircle eye path
    const rx = w;
    const ry = h;
    const k = 0.5522847498;
    const ox = rx * k;
    const oy = ry * k;
    const pathD = [
      `M ${ex.toFixed(2)} ${(ey - ry).toFixed(2)}`,
      `C ${(ex + ox).toFixed(2)} ${(ey - ry).toFixed(2)} ${(ex + rx).toFixed(2)} ${(ey - oy).toFixed(2)} ${(ex + rx).toFixed(2)} ${ey.toFixed(2)}`,
      `C ${(ex + rx).toFixed(2)} ${(ey + oy).toFixed(2)} ${(ex + ox).toFixed(2)} ${(ey + ry).toFixed(2)} ${ex.toFixed(2)} ${(ey + ry).toFixed(2)}`,
      `C ${(ex - ox).toFixed(2)} ${(ey + ry).toFixed(2)} ${(ex - rx).toFixed(2)} ${(ey + oy).toFixed(2)} ${(ex - rx).toFixed(2)} ${ey.toFixed(2)}`,
      `C ${(ex - rx).toFixed(2)} ${(ey - oy).toFixed(2)} ${(ex - ox).toFixed(2)} ${(ey - ry).toFixed(2)} ${ex.toFixed(2)} ${(ey - ry).toFixed(2)}`,
      'Z',
    ].join(' ');
    eyeDom.shape.setAttribute('d', pathD);

    // Specular eye glint
    eyeDom.glint.setAttribute('cx', (ex - rx * 0.34).toFixed(2));
    eyeDom.glint.setAttribute('cy', (ey - ry * 0.36).toFixed(2));
    eyeDom.glint.setAttribute('opacity', openFactor > 0.45 ? '0.88' : '0');
  }
}
