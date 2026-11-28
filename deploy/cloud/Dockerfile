# PiPiBot 24/7 Cloud Brigade Host
# Runs your AI Teammate team continuously with:
# - Stacked Claude Code & ChatGPT Codex subscription sessions (CLAUDE_CONFIG_DIR / CODEX_HOME)
# - Per-teammate persistent isolated Chromium browsers (LinkedIn, X, Reddit, GitHub)
# - Shared Cognitive Memory, Board coordination, and E2EE relay connectivity

FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    chromium \
    ca-certificates \
    curl \
    git \
    bubblewrap \
    fonts-noto-cjk \
    fonts-liberation \
    && rm -rf /var/lib/apt/lists/*

# Install official Claude Code & OpenAI Codex CLIs so users can reuse paid Claude / ChatGPT plans
RUN npm install -g @anthropic-ai/claude-code @openai/codex || true

WORKDIR /app
COPY package.json tsconfig.base.json ./
COPY packages ./packages
COPY design-system ./design-system
COPY apps/ios-web ./apps/ios-web

ENV HOME=/data
ENV PIPIBOT_HOST=0.0.0.0
ENV PIPIBOT_PORT=4242
ENV PIPIBOT_CHROME_PATH=/usr/bin/chromium

VOLUME ["/data"]
EXPOSE 4242

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -fsS http://127.0.0.1:4242/api/v1/status >/dev/null || exit 1

CMD ["node", "--experimental-strip-types", "packages/daemon/src/cli.ts", "cloud", "up", "--host", "0.0.0.0", "--port", "4242"]
