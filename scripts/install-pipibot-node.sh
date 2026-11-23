#!/usr/bin/env bash
# PiPiBot — One-command Linux/macOS Headless Mesh Hub & Node Installer
# Usage:
#   Join a machine as a Mesh Node:
#     bash scripts/install-pipibot-node.sh --hub http://<hub-ip>:4242 --name linux-4090 [--token <tok>] [--install-systemd]
#   Start a standalone 24h Hub on Linux VPS:
#     bash scripts/install-pipibot-node.sh --role hub --port 4242 [--token <tok>] [--install-systemd]

set -euo pipefail

ROLE="node"
HUB_URL=""
NODE_NAME="$(hostname)"
TOKEN=""
PORT="4242"
WORKSPACE="${PWD}"
INSTALL_SYSTEMD="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) ROLE="$2"; shift 2 ;;
    --hub) HUB_URL="$2"; shift 2 ;;
    --name) NODE_NAME="$2"; shift 2 ;;
    --token) TOKEN="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --workspace) WORKSPACE="$2"; shift 2 ;;
    --install-systemd) INSTALL_SYSTEMD="true"; shift ;;
    *) shift ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI_PATH="$REPO_ROOT/packages/daemon/src/cli.ts"

if ! command -v node >/dev/null 2>&1; then
  echo "Error: Node.js >= 22.6 is required on this machine." >&2
  exit 1
fi

if [[ "$INSTALL_SYSTEMD" == "true" ]]; then
  UNIT_NAME="pipibot-${ROLE}.service"
  ARGS=(daemon install --role "$ROLE" --systemd --port "$PORT" --name "$NODE_NAME" --workspace "$WORKSPACE")
  [[ -n "$HUB_URL" ]] && ARGS+=(--hub "$HUB_URL")
  [[ -n "$TOKEN" ]] && ARGS+=(--token "$TOKEN")
  echo "==> Generating systemd unit: /etc/systemd/system/${UNIT_NAME}"
  node --experimental-strip-types "$CLI_PATH" "${ARGS[@]}"
  echo "==> Save the output above to /etc/systemd/system/${UNIT_NAME} and run:"
  echo "    sudo systemctl daemon-reload && sudo systemctl enable --now ${UNIT_NAME}"
  exit 0
fi

if [[ "$ROLE" == "hub" ]]; then
  ARGS=(hub start --host 0.0.0.0 --port "$PORT" --workspace "$WORKSPACE")
  [[ -n "$TOKEN" ]] && ARGS+=(--token "$TOKEN")
  exec node --experimental-strip-types "$CLI_PATH" "${ARGS[@]}"
elif [[ -n "$HUB_URL" ]]; then
  ARGS=(node join --hub "$HUB_URL" --name "$NODE_NAME" --workspace "$WORKSPACE")
  [[ -n "$TOKEN" ]] && ARGS+=(--token "$TOKEN")
  exec node --experimental-strip-types "$CLI_PATH" "${ARGS[@]}"
else
  # Default Unified Account CLI installer (no --hub required)
  ORIGIN="${PIPIBOT_RELAY_ORIGIN:-https://pipibot.jimizhou.com}"
  INSTALL_DIR="${HOME}/.pipibot/bin"
  TARGET_TS="${INSTALL_DIR}/pipibot.ts"
  mkdir -p "${INSTALL_DIR}"
  if [[ -f "$REPO_ROOT/packages/daemon/src/relay-agent-host.ts" ]]; then
    cp "$REPO_ROOT/packages/daemon/src/relay-agent-host.ts" "${TARGET_TS}"
  else
    curl -fsSL "${ORIGIN}/cli/pipibot.ts" -o "${TARGET_TS}"
  fi
  if [[ -w "/usr/local/bin" ]]; then
    BIN_PATH="/usr/local/bin/pipibot"
  else
    mkdir -p "${HOME}/.local/bin"
    BIN_PATH="${HOME}/.local/bin/pipibot"
  fi
  cat > "${BIN_PATH}" <<EOF
#!/usr/bin/env bash
exec node --experimental-strip-types --no-warnings "${TARGET_TS}" "\$@"
EOF
  chmod +x "${BIN_PATH}"
  echo "✅ PiPiBot CLI 已安装到 ${BIN_PATH}"
  echo "下一步：运行 pipibot login && pipibot up"
fi
