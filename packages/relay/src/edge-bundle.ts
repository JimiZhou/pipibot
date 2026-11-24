/**
 * PiPiBot — Clean-room MIT implementation.
 * Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
 *
 * @pipibot/relay - edge-bundle.ts
 * 3-Tier Adaptive Node Enrollment & Resource-Constrained Embedded Device Agents:
 *   - Tier 1 (`node`): Full Herdr Agent Harness + E2EE + CDP Browser (x86_64/arm64, RAM >= 512MB, Node >= 22.6)
 *   - Tier 2 (`lite`): Zero-dependency Python 3 Edge Agent (~12MB RAM, stdlib only, ARMv7/MIPS/RISC-V/low-RAM)
 *   - Tier 3 (`edge`): Ultra-Lite POSIX `sh` Edge Agent (<2MB RAM, OpenWrt/BusyBox/routers/IoT, curl/wget only)
 */

export const PIPIBOT_EDGE_CLI_VERSION = '0.13.3';

export function renderAdaptiveInstallScript(origin: string): string {
  return `#!/bin/sh
set -eu

ORIGIN="\${PIPIBOT_RELAY_ORIGIN:-${origin}}"
FORCED_MODE="\${PIPIBOT_MODE:-auto}"
INSTALL_DIR="\${HOME}/.pipibot/bin"

echo "==> 正在探测设备架构与系统资源..."

OS_NAME="\$(uname -s 2>/dev/null || echo Linux)"
ARCH_NAME="\$(uname -m 2>/dev/null || echo unknown)"

# Detect Total RAM in MB (Linux /proc/meminfo, macOS sysctl, fallback 0)
RAM_MB=0
if [ -r /proc/meminfo ]; then
  MEM_KB="\$(awk '/^MemTotal:/ {print \$2; exit}' /proc/meminfo 2>/dev/null || echo 0)"
  if [ -n "\${MEM_KB}" ] && [ "\${MEM_KB}" -gt 0 ] 2>/dev/null; then
    RAM_MB="\$((MEM_KB / 1024))"
  fi
elif command -v sysctl >/dev/null 2>&1; then
  MEM_BYTES="\$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
  if [ -n "\${MEM_BYTES}" ] && [ "\${MEM_BYTES}" -gt 0 ] 2>/dev/null; then
    RAM_MB="\$((MEM_BYTES / 1048576))"
  fi
fi

# Detect Init System
INIT_SYS="nohup"
if [ "\${OS_NAME}" = "Darwin" ]; then
  INIT_SYS="launchd"
elif [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
  INIT_SYS="systemd"
elif [ -f /etc/openwrt_release ] || [ -x /sbin/procd ]; then
  INIT_SYS="procd"
elif command -v rc-service >/dev/null 2>&1; then
  INIT_SYS="openrc"
fi

# Detect HTTP Downloader
FETCH_TOOL=""
if command -v curl >/dev/null 2>&1; then
  FETCH_TOOL="curl"
elif command -v wget >/dev/null 2>&1; then
  FETCH_TOOL="wget"
else
  echo "❌ 未检测到 curl 或 wget，无法下载纳管程序。" >&2
  exit 1
fi

download_file() {
  _url="\$1"
  _out="\$2"
  if [ "\${FETCH_TOOL}" = "curl" ]; then
    curl -fsSL "\${_url}" -o "\${_out}"
  else
    wget -qO "\${_out}" "\${_url}"
  fi
}

# Detect Node.js version
NODE_MAJOR=0
if command -v node >/dev/null 2>&1; then
  NODE_MAJOR="\$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
fi

# Detect Python 3
HAS_PY3=0
if command -v python3 >/dev/null 2>&1; then
  HAS_PY3=1
fi

# Determine whether architecture is 64-bit full-featured
IS_64BIT=0
case "\${ARCH_NAME}" in
  x86_64|amd64|aarch64|arm64) IS_64BIT=1 ;;
esac

echo "    系统: \${OS_NAME} (\${ARCH_NAME}) · 内存: \${RAM_MB}MB · Init: \${INIT_SYS} · Node: v\${NODE_MAJOR} · Python3: \${HAS_PY3}"

# Adaptive Mode Selection (can override via PIPIBOT_MODE=node|lite|edge)
SELECTED_MODE="\${FORCED_MODE}"
if [ "\${SELECTED_MODE}" = "auto" ]; then
  if [ "\${IS_64BIT}" -eq 1 ] && [ "\${NODE_MAJOR}" -ge 22 ] && { [ "\${RAM_MB}" -eq 0 ] || [ "\${RAM_MB}" -ge 512 ]; }; then
    SELECTED_MODE="node"
  elif [ "\${HAS_PY3}" -eq 1 ] && { [ "\${RAM_MB}" -eq 0 ] || [ "\${RAM_MB}" -ge 64 ]; }; then
    SELECTED_MODE="lite"
  else
    SELECTED_MODE="edge"
  fi
fi

mkdir -p "\${INSTALL_DIR}"

# Pick writable bin path
if [ -w "/usr/local/bin" ]; then
  BIN_PATH="/usr/local/bin/pipibot"
elif [ -w "/usr/bin" ] && [ "\${INIT_SYS}" = "procd" ]; then
  BIN_PATH="/usr/bin/pipibot"
else
  mkdir -p "\${HOME}/.local/bin"
  BIN_PATH="\${HOME}/.local/bin/pipibot"
fi

if [ "\${SELECTED_MODE}" = "node" ]; then
  echo "==> 模式选择: [完整模式 Node.js]（支持 E2EE P-256 + Herdr 流式 PTY + 远端无头浏览器）"
  TARGET_TS="\${INSTALL_DIR}/pipibot.ts"
  download_file "\${ORIGIN}/cli/pipibot.ts" "\${TARGET_TS}"
  cat > "\${BIN_PATH}" <<EOF
#!/usr/bin/env sh
export NODE_USE_ENV_PROXY=1
exec node --dns-result-order=ipv4first --experimental-strip-types --no-warnings "\${TARGET_TS}" "\\\$@"
EOF
  chmod +x "\${BIN_PATH}"

elif [ "\${SELECTED_MODE}" = "lite" ]; then
  echo "==> 模式选择: [轻量嵌入式模式 Python 3]（零依赖 ~12MB 内存，适配低内存/ARMv7/RISC-V/NAS/无 Node 22 设备）"
  TARGET_PY="\${INSTALL_DIR}/pipibot-lite.py"
  download_file "\${ORIGIN}/cli/pipibot-lite.py" "\${TARGET_PY}"
  chmod +x "\${TARGET_PY}"
  cat > "\${BIN_PATH}" <<EOF
#!/usr/bin/env sh
export PIPIBOT_RELAY_ORIGIN="\${ORIGIN}"
exec python3 "\${TARGET_PY}" "\\\$@"
EOF
  chmod +x "\${BIN_PATH}"

else
  echo "==> 模式选择: [极简嵌入式模式 POSIX Shell]（<2MB 内存，仅需 sh + curl/wget，适配 OpenWrt/BusyBox/路由器/IoT）"
  TARGET_SH="\${INSTALL_DIR}/pipibot-edge.sh"
  download_file "\${ORIGIN}/cli/pipibot-edge.sh" "\${TARGET_SH}"
  chmod +x "\${TARGET_SH}"
  cat > "\${BIN_PATH}" <<EOF
#!/usr/bin/env sh
export PIPIBOT_RELAY_ORIGIN="\${ORIGIN}"
exec sh "\${TARGET_SH}" "\\\$@"
EOF
  chmod +x "\${BIN_PATH}"
fi

# Ensure ~/.local/bin in PATH if used
case "\${BIN_PATH}" in
  */.local/bin/*)
    for rc in "\${HOME}/.bashrc" "\${HOME}/.zshrc" "\${HOME}/.profile"; do
      if [ -f "\${rc}" ] && ! grep -q '\\.local/bin' "\${rc}" 2>/dev/null; then
        echo 'export PATH="\$HOME/.local/bin:\$PATH"' >> "\${rc}"
      fi
    done
    ;;
esac

echo ""
echo "✅ PiPiBot 纳管客户端已安装到 \${BIN_PATH} (模式: \${SELECTED_MODE})"
if ! command -v pipibot >/dev/null 2>&1; then
  echo "💡 请先执行：export PATH=\\"\${HOME}/.local/bin:\\\$PATH\\""
fi
echo ""
echo "下一步：运行以下命令完成账号授权并后台常驻纳管："
echo "  pipibot login && pipibot up -d"
echo ""
`;
}

export function renderPythonLiteAgent(origin: string): string {
  return `#!/usr/bin/env python3
"""
PiPiBot Lite Edge Agent (Zero-Dependency Python 3 stdlib, ~12MB RAM).
Designed for embedded Linux, Raspberry Pi Zero, ARMv7, RISC-V, NAS, and low-RAM servers
where Node.js >= 22 is unavailable or too heavy.
Commands:
  pipibot login     Authorize device via Device Flow (PIPI-XXXX)
  pipibot up [-d]   Connect to PiPiBot Relay & serve remote shell / telemetry
  pipibot down      Stop background daemon
  pipibot status    Show device status
"""

import hashlib
import json
import os
import platform
import signal
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid

VERSION = "${PIPIBOT_EDGE_CLI_VERSION}"
ORIGIN = os.environ.get("PIPIBOT_RELAY_ORIGIN", "${origin}").rstrip("/")
AUTO_UPGRADE = os.environ.get("PIPIBOT_AUTO_UPGRADE", "1").lower() not in ("0", "false", "no", "off")
AUTO_UPGRADE_INTERVAL_SEC = max(300, int(os.environ.get("PIPIBOT_AUTO_UPGRADE_INTERVAL_SEC", "21600") or "21600"))
HOME = os.path.expanduser("~")
STATE_DIR = os.path.join(HOME, ".pipibot")
AUTH_FILE = os.path.join(STATE_DIR, "edge-auth.json")
PID_FILE = os.path.join(STATE_DIR, "edge.pid")
LOG_FILE = os.path.join(STATE_DIR, "edge.log")


def check_and_self_upgrade(force=False, quiet=False):
    script_path = os.path.abspath(__file__)
    try:
        with open(script_path, "rb") as f:
            local_sha = hashlib.sha256(f.read()).hexdigest()
    except Exception:
        local_sha = ""
    st, manifest = http_json("GET", "/cli/version.json", timeout=15)
    if st != 200 or not isinstance(manifest, dict):
        if not quiet:
            print(f"⚠️ 无法获取版本清单 ({ORIGIN}/cli/version.json)", flush=True)
        return False
    art = (manifest.get("artifacts") or {}).get("lite") or {}
    remote_sha = str(art.get("sha256") or "")
    remote_ver = str(manifest.get("version") or VERSION)
    if remote_sha and remote_sha == local_sha and not force:
        if not quiet:
            print(f"✅ PiPiBot Lite 已是最新版本 (v{VERSION} · {local_sha[:8]})", flush=True)
        return False
    dl_url = str(art.get("url") or (ORIGIN + "/cli/pipibot-lite.py"))
    try:
        req = urllib.request.Request(dl_url, headers={"User-Agent": f"PiPiBot-Lite/{VERSION}"})
        with urllib.request.urlopen(req, timeout=25) as resp:
            raw = resp.read()
        actual_sha = hashlib.sha256(raw).hexdigest()
        if remote_sha and actual_sha != remote_sha:
            if not quiet:
                print("❌ 升级包 SHA-256 校验失败，已取消升级", flush=True)
            return False
        if b"PiPiBot Lite Edge Agent" not in raw:
            return False
        tmp_path = script_path + ".tmp"
        with open(tmp_path, "wb") as f:
            f.write(raw)
        os.chmod(tmp_path, 0o755)
        os.replace(tmp_path, script_path)
        print(f"⬆️ PiPiBot Lite 已自动升级至 v{remote_ver} ({actual_sha[:8]})", flush=True)
        return True
    except Exception as e:
        if not quiet:
            print(f"⚠️ 升级失败: {e}", flush=True)
        return False


def http_json(method, path, body=None, token=None, timeout=35):
    url = ORIGIN + path
    data = json.dumps(body).encode("utf-8") if body is not None else None
    headers = {"Content-Type": "application/json", "User-Agent": "PiPiBot-Lite/1.0"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            return resp.status, json.loads(raw) if raw.strip() else {}
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"error": raw or str(e)}
    except Exception as e:
        return 0, {"error": str(e)}


def read_mem_mb():
    try:
        with open("/proc/meminfo", "r") as f:
            for line in f:
                if line.startswith("MemTotal:"):
                    return int(line.split()[1]) // 1024
    except Exception:
        pass
    return 0


def read_uptime_sec():
    try:
        with open("/proc/uptime", "r") as f:
            return int(float(f.read().split()[0]))
    except Exception:
        return 0


def load_auth():
    if not os.path.exists(AUTH_FILE):
        return None
    try:
        with open(AUTH_FILE, "r") as f:
            return json.load(f)
    except Exception:
        return None


def save_auth(data):
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(AUTH_FILE, "w") as f:
        json.dump(data, f, indent=2)
    try:
        os.chmod(AUTH_FILE, 0o600)
    except Exception:
        pass


def cmd_login():
    host_name = socket.gethostname()
    arch = platform.machine() or "unknown"
    status, flow = http_json("POST", "/api/auth/device/start", {
        "clientLabel": f"{host_name} ({arch} · Lite)",
    })
    if status != 200 or not flow.get("deviceCode"):
        print(f"❌ 无法发起设备登录 ({status}): {flow}", file=sys.stderr)
        sys.exit(1)

    print("")
    print("🔐 请在任意浏览器打开以下链接并确认授权：")
    print(f"   {flow.get('verificationUrl', ORIGIN + '/login')}")
    print(f"   一次性授权码：{flow['userCode']}")
    print("")
    print("⏳ 等待浏览器授权中...")

    deadline = time.time() + int(flow.get("expiresInSec", 600))
    interval = max(2, int(flow.get("intervalSec", 3)))
    while time.time() < deadline:
        time.sleep(interval)
        st, poll = http_json("POST", "/api/auth/device/poll", {"deviceCode": flow["deviceCode"]})
        if st == 200 and poll.get("status") == "approved" and poll.get("accessToken"):
            existing = load_auth() or {}
            host_id = existing.get("hostId") or ("edge_" + uuid.uuid4().hex[:12])
            auth = {
                "relayOrigin": ORIGIN,
                "accessToken": poll["accessToken"],
                "user": poll.get("user", {}),
                "hostId": host_id,
                "deviceName": host_name,
                "arch": arch,
                "workspacePath": os.getcwd(),
            }
            save_auth(auth)
            reg_st, _ = http_json("POST", "/api/devices/register", {
                "name": host_name,
                "platform": "linux",
                "hostId": host_id,
                "hostPubKey": "edge-https",
                "capabilities": ["Edge Lite", arch, f"{read_mem_mb()}MB RAM"],
                "workspacePath": os.getcwd(),
            }, token=auth["accessToken"])
            if reg_st == 200:
                print(f"✅ 登录并注册设备成功：{host_name} (hostId={host_id})")
            else:
                print(f"✅ 登录成功 (hostId={host_id})")
            print("下一步运行：pipibot up -d")
            return
        if poll.get("status") == "expired":
            print("❌ 授权码已过期，请重新运行 pipibot login", file=sys.stderr)
            sys.exit(1)
    print("❌ 授权超时", file=sys.stderr)
    sys.exit(1)


def run_shell(command, timeout_ms=20000, cwd=None):
    timeout_s = max(2, min(60, int(timeout_ms) / 1000.0))
    try:
        proc = subprocess.run(
            ["/bin/sh", "-c", command],
            cwd=cwd or os.getcwd(),
            capture_output=True,
            text=True,
            timeout=timeout_s,
        )
        return proc.returncode, proc.stdout[:32768], proc.stderr[:32768]
    except subprocess.TimeoutExpired:
        return 124, "", f"命令超时 (>{timeout_s}s)"
    except Exception as e:
        return 1, "", str(e)


def cmd_up(daemon=False):
    auth = load_auth()
    if not auth or not auth.get("accessToken"):
        print("❌ 尚未登录，请先执行：pipibot login", file=sys.stderr)
        sys.exit(1)

    if daemon:
        os.makedirs(STATE_DIR, exist_ok=True)
        with open(LOG_FILE, "a") as logf:
            proc = subprocess.Popen(
                [sys.executable, os.path.abspath(__file__), "up"],
                stdout=logf,
                stderr=logf,
                stdin=subprocess.DEVNULL,
                start_new_session=True,
            )
        with open(PID_FILE, "w") as pf:
            pf.write(str(proc.pid))
        print(f"✅ PiPiBot Lite 已后台启动 (PID={proc.pid}, log={LOG_FILE})")
        return

    host_id = auth["hostId"]
    token = auth["accessToken"]
    device_name = auth.get("deviceName") or socket.gethostname()
    arch = platform.machine() or "unknown"
    mem_mb = read_mem_mb()
    workspace = auth.get("workspacePath") or os.getcwd()

    # Re-register on startup
    http_json("POST", "/api/devices/register", {
        "name": device_name,
        "platform": "linux",
        "hostId": host_id,
        "hostPubKey": "edge-https",
        "capabilities": ["Edge Lite", arch, f"{mem_mb}MB RAM"],
        "workspacePath": workspace,
    }, token=token)

    print(f"🚀 PiPiBot Lite 嵌入式守护已上线：{device_name} ({arch}, {mem_mb}MB) -> {ORIGIN}", flush=True)

    running = True

    def _stop(_sig, _frame):
        nonlocal running
        running = False

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)

    last_upgrade_check = time.time()

    while running:
        if AUTO_UPGRADE and (time.time() - last_upgrade_check) >= AUTO_UPGRADE_INTERVAL_SEC:
            last_upgrade_check = time.time()
            if check_and_self_upgrade(force=False, quiet=True):
                print("🔄 正在无缝热重启至新版 PiPiBot Lite...", flush=True)
                os.execv(sys.executable, [sys.executable, os.path.abspath(__file__), "up"])

        st, data = http_json("POST", "/api/edge/heartbeat", {
            "hostId": host_id,
            "hostName": device_name,
            "arch": arch,
            "memMB": mem_mb,
            "uptimeSeconds": read_uptime_sec(),
            "workspacePath": workspace,
            "mode": "lite",
            "cliVersion": VERSION,
        }, token=token, timeout=35)

        if st == 200 and isinstance(data, dict) and data.get("task"):
            task = data["task"]
            code, out, err = run_shell(
                str(task.get("command", "")),
                timeout_ms=int(task.get("timeoutMs", 20000)),
                cwd=task.get("cwd") or workspace,
            )
            http_json("POST", "/api/edge/result", {
                "hostId": host_id,
                "taskId": task["id"],
                "exitCode": code,
                "stdout": out,
                "stderr": err,
            }, token=token, timeout=15)
        elif st != 200:
            time.sleep(4)


def cmd_down():
    if os.path.exists(PID_FILE):
        try:
            pid = int(open(PID_FILE).read().strip())
            os.kill(pid, signal.SIGTERM)
            print(f"✅ 已停止 PiPiBot Lite (PID={pid})")
        except Exception:
            print("ℹ️ 后台进程未在运行")
        try:
            os.remove(PID_FILE)
        except Exception:
            pass
    else:
        print("ℹ️ 未找到运行中的 PID 文件")


def cmd_status():
    auth = load_auth()
    pid = open(PID_FILE).read().strip() if os.path.exists(PID_FILE) else "未运行"
    print(f"PiPiBot Lite · mode=lite · arch={platform.machine()} · mem={read_mem_mb()}MB · pid={pid}")
    if auth:
        print(f"  hostId={auth.get('hostId')} · name={auth.get('deviceName')} · relay={ORIGIN}")
    else:
        print("  状态：未登录（请运行 pipibot login）")


if __name__ == "__main__":
    args = sys.argv[1:]
    cmd = args[0] if args else "status"
    if cmd == "login":
        cmd_login()
    elif cmd == "up":
        cmd_up(daemon=("-d" in args or "--daemon" in args))
    elif cmd == "down":
        cmd_down()
    elif cmd in ("upgrade", "update"):
        upgraded = check_and_self_upgrade(force=("--force" in args), quiet=False)
        if upgraded and os.path.exists(PID_FILE):
            cmd_down()
            os.execv(sys.executable, [sys.executable, os.path.abspath(__file__), "up", "-d"])
    elif cmd in ("version", "--version", "-v"):
        print(f"PiPiBot Lite CLI v{VERSION} (mode=lite)")
    else:
        cmd_status()
`;
}

export function renderPosixEdgeAgent(origin: string): string {
  return `#!/bin/sh
# PiPiBot Ultra-Lite POSIX Shell Edge Agent (<2MB RAM)
# Works on OpenWrt, BusyBox, routers, and minimal IoT devices with only sh + curl/wget.
set -eu

VERSION="${PIPIBOT_EDGE_CLI_VERSION}"
ORIGIN="\${PIPIBOT_RELAY_ORIGIN:-${origin}}"
AUTO_UPGRADE="\${PIPIBOT_AUTO_UPGRADE:-1}"
STATE_DIR="\${HOME}/.pipibot"
AUTH_FILE="\${STATE_DIR}/edge-auth.env"
PID_FILE="\${STATE_DIR}/edge.pid"
LOG_FILE="\${STATE_DIR}/edge.log"

cmd_upgrade() {
  _self="\$0"
  _tmp="\${_self}.tmp"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "\${ORIGIN}/cli/pipibot-edge.sh" -o "\${_tmp}" 2>/dev/null || { rm -f "\${_tmp}"; return 1; }
  else
    wget -qO "\${_tmp}" "\${ORIGIN}/cli/pipibot-edge.sh" 2>/dev/null || { rm -f "\${_tmp}"; return 1; }
  fi
  if grep -q "PiPiBot Ultra-Lite POSIX Shell Edge Agent" "\${_tmp}" 2>/dev/null; then
    if cmp -s "\${_self}" "\${_tmp}" 2>/dev/null && [ "\${1:-}" != "--force" ]; then
      rm -f "\${_tmp}"
      [ "\${2:-}" != "quiet" ] && echo "✅ PiPiBot Edge 已是最新版本 (v\${VERSION})"
      return 2
    fi
    chmod +x "\${_tmp}"
    mv -f "\${_tmp}" "\${_self}"
    echo "⬆️ PiPiBot Edge 已升级至最新版本"
    return 0
  fi
  rm -f "\${_tmp}"
  return 1
}

mkdir -p "\${STATE_DIR}"

json_get() {
  # Minimal POSIX JSON string extractor: json_get '{"k":"v"}' k
  printf '%s' "\$1" | sed -n 's/.*"'"\$2"'"[[:space:]]*:[[:space:]]*"\\([^"]*\\)".*/\\1/p' | head -n 1
}

json_escape() {
  printf '%s' "\$1" | sed -e 's/\\\\/\\\\\\\\/g' -e 's/"/\\\\"/g' | awk 'BEGIN{ORS=""} {if(NR>1) printf "\\\\n"; printf "%s", $0}'
}

http_post() {
  _path="\$1"
  _body="\$2"
  _tok="\${3:-}"
  if command -v curl >/dev/null 2>&1; then
    if [ -n "\${_tok}" ]; then
      curl -fsS --max-time 35 -X POST -H "Content-Type: application/json" -H "Authorization: Bearer \${_tok}" -d "\${_body}" "\${ORIGIN}\${_path}" 2>/dev/null || true
    else
      curl -fsS --max-time 35 -X POST -H "Content-Type: application/json" -d "\${_body}" "\${ORIGIN}\${_path}" 2>/dev/null || true
    fi
  else
    if [ -n "\${_tok}" ]; then
      wget -qO- --timeout=35 --header="Content-Type: application/json" --header="Authorization: Bearer \${_tok}" --post-data="\${_body}" "\${ORIGIN}\${_path}" 2>/dev/null || true
    else
      wget -qO- --timeout=35 --header="Content-Type: application/json" --post-data="\${_body}" "\${ORIGIN}\${_path}" 2>/dev/null || true
    fi
  fi
}

cmd_login() {
  _host="\$(hostname 2>/dev/null || echo embedded)"
  _arch="\$(uname -m 2>/dev/null || echo unknown)"
  _resp="\$(http_post "/api/auth/device/start" "{\\"clientLabel\\":\\"\${_host} (\${_arch} · Edge)\\"}")"
  _dev_code="\$(json_get "\${_resp}" "deviceCode")"
  _user_code="\$(json_get "\${_resp}" "userCode")"
  _vurl="\$(json_get "\${_resp}" "verificationUrl")"
  if [ -z "\${_dev_code}" ]; then
    echo "❌ 无法发起设备授权，请检查网络连接：\${ORIGIN}" >&2
    exit 1
  fi
  echo ""
  echo "🔐 请在浏览器打开：\${_vurl:-\${ORIGIN}/login}"
  echo "   一次性授权码：\${_user_code}"
  echo "⏳ 等待确认授权..."
  _tries=0
  while [ "\${_tries}" -lt 180 ]; do
    sleep 3
    _tries="\$((_tries + 1))"
    _poll="\$(http_post "/api/auth/device/poll" "{\\"deviceCode\\":\\"\${_dev_code}\\"}")"
    _st="\$(json_get "\${_poll}" "status")"
    if [ "\${_st}" = "approved" ]; then
      _token="\$(json_get "\${_poll}" "accessToken")"
      _hid="edge_\$(date +%s | tail -c 9)"
      if [ -f "\${AUTH_FILE}" ]; then
        # shellcheck disable=SC1090
        . "\${AUTH_FILE}" || true
        [ -n "\${HOST_ID:-}" ] && _hid="\${HOST_ID}"
      fi
      cat > "\${AUTH_FILE}" <<EOF
ACCESS_TOKEN="\${_token}"
HOST_ID="\${_hid}"
DEVICE_NAME="\${_host}"
EOF
      chmod 600 "\${AUTH_FILE}" 2>/dev/null || true
      http_post "/api/devices/register" "{\\"name\\":\\"\${_host}\\",\\"platform\\":\\"linux\\",\\"hostId\\":\\"\${_hid}\\",\\"hostPubKey\\":\\"edge-https\\",\\"capabilities\\":[\\"Edge Shell\\",\\"\${_arch}\\"],\\"workspacePath\\":\\"\${PWD}\\"}" "\${_token}" >/dev/null
      echo "✅ 嵌入式设备授权并纳管成功：\${_host} (hostId=\${_hid})"
      echo "下一步运行：pipibot up -d"
      return 0
    fi
    if [ "\${_st}" = "expired" ]; then
      echo "❌ 授权码已过期" >&2
      exit 1
    fi
  done
  echo "❌ 授权超时" >&2
  exit 1
}

cmd_up() {
  if [ ! -f "\${AUTH_FILE}" ]; then
    echo "❌ 尚未登录，请先运行：pipibot login" >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  . "\${AUTH_FILE}"
  if [ "\${1:-}" = "-d" ] || [ "\${1:-}" = "--daemon" ]; then
    nohup sh "\$0" up >>"\${LOG_FILE}" 2>&1 &
    echo \$! > "\${PID_FILE}"
    echo "✅ PiPiBot Edge 已后台启动 (PID=\$!, log=\${LOG_FILE})"
    return 0
  fi
  _arch="\$(uname -m 2>/dev/null || echo unknown)"
  echo "🚀 PiPiBot Edge 极简守护已上线：\${DEVICE_NAME} (\${_arch}) -> \${ORIGIN}"
  _ticks=0
  while true; do
    _ticks="\$((_ticks + 1))"
    if [ "\${AUTO_UPGRADE}" != "0" ] && [ "\$((_ticks % 10800))" -eq 0 ]; then
      if cmd_upgrade "" "quiet"; then
        echo "🔄 正在无缝重启至新版 PiPiBot Edge..."
        exec sh "\$0" up
      fi
    fi
    _hb="\$(http_post "/api/edge/heartbeat" "{\\"hostId\\":\\"\${HOST_ID}\\",\\"hostName\\":\\"\${DEVICE_NAME}\\",\\"arch\\":\\"\${_arch}\\",\\"workspacePath\\":\\"\${PWD}\\",\\"mode\\":\\"edge\\",\\"cliVersion\\":\\"\${VERSION}\\"}" "\${ACCESS_TOKEN}")"
    _tid="\$(json_get "\${_hb}" "id")"
    _cmd="\$(json_get "\${_hb}" "command")"
    if [ -n "\${_tid}" ] && [ -n "\${_cmd}" ]; then
      _out="\$(sh -c "\${_cmd}" 2>&1 || true)"
      _code=\$?
      _esc="\$(json_escape "\$(printf '%s' "\${_out}" | head -c 16384)")"
      http_post "/api/edge/result" "{\\"hostId\\":\\"\${HOST_ID}\\",\\"taskId\\":\\"\${_tid}\\",\\"exitCode\\":\${_code},\\"stdout\\":\\"\${_esc}\\",\\"stderr\\":\\"\\"}" "\${ACCESS_TOKEN}" >/dev/null
    else
      sleep 2
    fi
  done
}

cmd_down() {
  if [ -f "\${PID_FILE}" ]; then
    kill "\$(cat "\${PID_FILE}")" 2>/dev/null || true
    rm -f "\${PID_FILE}"
    echo "✅ 已停止 PiPiBot Edge"
  else
    echo "ℹ️ 未在运行"
  fi
}

cmd_status() {
  _pid="未运行"
  [ -f "\${PID_FILE}" ] && _pid="\$(cat "\${PID_FILE}")"
  echo "PiPiBot Edge · mode=edge · arch=\$(uname -m 2>/dev/null) · pid=\${_pid}"
}

case "\${1:-status}" in
  login) cmd_login ;;
  up) shift; cmd_up "\${1:-}" ;;
  down) cmd_down ;;
  upgrade|update)
    if cmd_upgrade "\${2:-}" ""; then
      if [ -f "\${PID_FILE}" ]; then
        cmd_down
        cmd_up -d
      fi
    fi
    ;;
  version|--version|-v) echo "PiPiBot Edge CLI v\${VERSION} (mode=edge)" ;;
  *) cmd_status ;;
esac
`;
}
