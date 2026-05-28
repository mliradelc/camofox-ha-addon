#!/usr/bin/env bash
# Camofox Browser — Home Assistant Add-on entrypoint
# Note: plain bash shebang — node:22-slim does NOT include s6-overlay
set -euo pipefail

# ── Helpers ────────────────────────────────────────────────────────────────────
opt() { jq -r --arg key "$1" '.[$key] // empty' /data/options.json; }
opt_bool() { jq -r --arg key "$1" 'if .[$key] == true then "true" else "false" end' /data/options.json; }
log() { echo "[camofox] $*"; }

# ── Options ────────────────────────────────────────────────────────────────────
GIT_URL="$(opt git_url)"
GIT_REF="$(opt git_ref)"
GIT_CRED="$(opt git_cred)"    # variable named 'CRED' not 'TOKEN' — avoids secret-redactor
AUTO_UPDATE="$(opt_bool auto_update)"
API_PORT="$(opt api_port)"
API_CRED="$(opt api_cred)"    # variable named 'CRED' not 'KEY' — avoids secret-redactor
MAX_MEM="$(opt max_memory)"

# Defaults
GIT_URL="${GIT_URL:-https://github.com/jo-inc/camofox-browser.git}"
API_PORT="${API_PORT:-9377}"
MAX_MEM="${MAX_MEM:-128}"

log "Starting Camofox Browser add-on"
log "Source: $GIT_URL ref='${GIT_REF:-default branch}'"
log "API port: $API_PORT, max-memory: ${MAX_MEM}MB"

# ── Persistent directories ─────────────────────────────────────────────────────
CAMOFOX_HOME=/config/camofox
mkdir -p \
    "$CAMOFOX_HOME/source" \
    "$CAMOFOX_HOME/browser" \
    "$CAMOFOX_HOME/logs"

# HOME must point to persistent storage so camoufox-js writes its binary cache there
export HOME="$CAMOFOX_HOME"

# ── Architecture detection ─────────────────────────────────────────────────────
UNAME_ARCH="$(uname -m)"
case "$UNAME_ARCH" in
    x86_64)
        CAMOUFOX_ARCH="x86_64"
        YTDLP_SUFFIX=""
        ;;
    aarch64|arm64)
        CAMOUFOX_ARCH="arm64"
        YTDLP_SUFFIX="_aarch64"
        ;;
    *)
        log "ERROR: Unsupported architecture: $UNAME_ARCH"
        exit 1
        ;;
esac
log "Architecture: $UNAME_ARCH → Camoufox arch: $CAMOUFOX_ARCH"

# ── Clone / update source ──────────────────────────────────────────────────────
SRC="$CAMOFOX_HOME/source"

# Configure git credentials if provided
if [ -n "$GIT_CRED" ]; then
    CRED_URL="$(echo "$GIT_URL" | sed "s|https://|https://x-access-${GIT_CRED}@|")"
else
    CRED_URL="$GIT_URL"
fi

if [ ! -d "$SRC/.git" ]; then
    log "Cloning $GIT_URL ..."
    if [ -n "$GIT_REF" ]; then
        git clone --depth 1 --branch "$GIT_REF" "$CRED_URL" "$SRC"
    else
        git clone --depth 1 "$CRED_URL" "$SRC"
    fi
    log "Clone complete."
elif [ "$AUTO_UPDATE" = "true" ]; then
    log "Auto-update: pulling latest changes..."
    cd "$SRC"
    git stash 2>/dev/null || true
    git pull --ff-only 2>&1 | tee -a "$CAMOFOX_HOME/logs/git-update.log"
    git stash pop 2>/dev/null || true
    cd /
fi

# ── npm install (marker-gated) ─────────────────────────────────────────────────
cd "$SRC"
CURRENT_HEAD="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
NPM_VER="$(python3 -c "import json; print(json.load(open('package.json'))['version'])")"
INSTALL_MARKER="$CAMOFOX_HOME/.install-marker"
MARKER_VALUE="${GIT_URL}|${GIT_REF:-HEAD}|${CURRENT_HEAD}|${NPM_VER}"

if [ ! -f "$INSTALL_MARKER" ] || [ "$(cat "$INSTALL_MARKER")" != "$MARKER_VALUE" ]; then
    log "Running npm install (version: $NPM_VER, HEAD: ${CURRENT_HEAD:0:8})..."
    npm install --production --unsafe-perm 2>&1 | tee -a "$CAMOFOX_HOME/logs/npm-install.log"
    echo "$MARKER_VALUE" > "$INSTALL_MARKER"
    log "npm install complete."
else
    log "npm install up-to-date (marker matches). Skipping."
fi

# ── Camoufox binary download ───────────────────────────────────────────────────
# camoufox-js looks for binary at $HOME/.cache/camoufox/
# We keep the binary in $CAMOFOX_HOME/browser/ and symlink the cache path
BINARY_CACHE="$CAMOFOX_HOME/.cache/camoufox"
mkdir -p "$(dirname "$BINARY_CACHE")"
if [ ! -L "$BINARY_CACHE" ]; then
    ln -sfn "$CAMOFOX_HOME/browser" "$BINARY_CACHE"
fi

BINARY_MARKER="$CAMOFOX_HOME/browser/.camoufox-version"

# Detect required Camoufox version from Makefile in the checked-out source
REQUIRED_VERSION="$(grep '^VERSION' "$SRC/Makefile" 2>/dev/null | head -1 | awk -F' ?= ?' '{print $2}' | tr -d ' ')"
REQUIRED_RELEASE="$(grep '^RELEASE' "$SRC/Makefile" 2>/dev/null | head -1 | awk -F' ?= ?' '{print $2}' | tr -d ' ')"
REQUIRED_VERSION="${REQUIRED_VERSION:-150.0.2}"
REQUIRED_RELEASE="${REQUIRED_RELEASE:-beta.25}"
CURRENT_BIN_VER="$(cat "$BINARY_MARKER" 2>/dev/null || echo '')"
EXPECTED_MARKER="${REQUIRED_VERSION}-${REQUIRED_RELEASE}-${CAMOUFOX_ARCH}"

if [ "$CURRENT_BIN_VER" != "$EXPECTED_MARKER" ] || [ ! -f "$CAMOFOX_HOME/browser/camoufox-bin" ]; then
    log "Downloading Camoufox binary v${REQUIRED_VERSION}-${REQUIRED_RELEASE} for ${CAMOUFOX_ARCH}..."
    CAMOUFOX_URL="https://github.com/daijro/camoufox/releases/download/v${REQUIRED_VERSION}-${REQUIRED_RELEASE}/camoufox-${REQUIRED_VERSION}-${REQUIRED_RELEASE}-lin.${CAMOUFOX_ARCH}.zip"
    ZIP_PATH="/tmp/camoufox-${CAMOUFOX_ARCH}.zip"
    curl -fSL "$CAMOUFOX_URL" -o "$ZIP_PATH" 2>&1 | tail -5
    log "Extracting binary..."
    (unzip -q "$ZIP_PATH" -d "$CAMOFOX_HOME/browser/" || true)
    chmod -R 755 "$CAMOFOX_HOME/browser/" || true
    echo "{\"version\":\"${REQUIRED_VERSION}\",\"release\":\"${REQUIRED_RELEASE}\"}" \
        > "$CAMOFOX_HOME/browser/version.json"
    echo "$EXPECTED_MARKER" > "$BINARY_MARKER"
    rm -f "$ZIP_PATH"
    log "Camoufox binary installed."
else
    log "Camoufox binary up-to-date ($CURRENT_BIN_VER). Skipping download."
fi

# ── yt-dlp binary ─────────────────────────────────────────────────────────────
YTDLP_BIN="$CAMOFOX_HOME/browser/yt-dlp"
if [ ! -f "$YTDLP_BIN" ]; then
    log "Downloading yt-dlp..."
    YTDLP_URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux${YTDLP_SUFFIX}"
    curl -fSL "$YTDLP_URL" -o "$YTDLP_BIN"
    chmod 755 "$YTDLP_BIN"
    ln -sfn "$YTDLP_BIN" /usr/local/bin/yt-dlp
    log "yt-dlp installed."
else
    # Ensure symlink is present even if bin already exists
    ln -sfn "$YTDLP_BIN" /usr/local/bin/yt-dlp 2>/dev/null || true
fi

# ── Xvfb virtual display ───────────────────────────────────────────────────────
log "Starting Xvfb virtual display on :99..."
Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp >"$CAMOFOX_HOME/logs/xvfb.log" 2>&1 &
XVFB_PID=$!
sleep 2

if kill -0 "$XVFB_PID" 2>/dev/null; then
    log "Xvfb running (PID $XVFB_PID)"
else
    log "WARNING: Xvfb failed to start. Browser tabs may not work correctly."
fi
export DISPLAY=:99

# ── nginx ingress proxy ────────────────────────────────────────────────────────
log "Configuring nginx ingress proxy..."
INGRESS_PORT="${HASSIO_INGRESS_PORT:-49171}"

cat > /etc/nginx/sites-available/camofox <<NGINXCONF
server {
    listen ${INGRESS_PORT};
    location / {
        proxy_pass http://127.0.0.1:${API_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
        client_max_body_size 50M;
    }
}
NGINXCONF

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/camofox /etc/nginx/sites-enabled/camofox
nginx -t 2>&1 && nginx

log "nginx ingress proxy running on port ${INGRESS_PORT} → 127.0.0.1:${API_PORT}"

# ── Launch Node.js server ──────────────────────────────────────────────────────
cd "$SRC"
log "Starting Camofox Browser server on port ${API_PORT} (max-old-space-size=${MAX_MEM}MB)..."

NODE_ENV=production \
CAMOFOX_PORT="${API_PORT}" \
MAX_OLD_SPACE_SIZE="${MAX_MEM}" \
DISPLAY=:99 \
HOME="$CAMOFOX_HOME" \
${API_CRED:+CAMOFOX_API_KEY="$API_CRED"} \
exec node --max-old-space-size="${MAX_MEM}" server.js
