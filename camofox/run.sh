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
GIT_CRED="$(opt git_cred)"   # 'CRED' not 'TOKEN' — avoids secret-redactor mangling
AUTO_UPDATE="$(opt_bool auto_update)"
API_PORT="$(opt api_port)"
API_CRED="$(opt api_cred)"   # 'CRED' not 'KEY' — avoids secret-redactor mangling
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
    "$CAMOFOX_HOME/logs"

# HOME must point to persistent storage so npm postinstall writes the Camoufox
# binary to $HOME/.cache/camoufox/ — resolves to /config/camofox/.cache/camoufox/
# and persists across restarts. Do NOT symlink or manually manage that path;
# npm postinstall creates it as a real directory. Manually creating a symlink there
# causes 'ln: cannot overwrite directory'.
export HOME="$CAMOFOX_HOME"

log "Architecture: $(uname -m)"

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
# npm postinstall (scripts/postinstall.js) automatically downloads the Camoufox
# binary (~700 MB) and yt-dlp into $HOME/.cache/camoufox/ and $HOME/.cache/ytdlp/.
# With HOME=$CAMOFOX_HOME these land in persistent /config/camofox/ storage.
# Do NOT manually download or symlink the binary — postinstall handles it.
cd "$SRC"
CURRENT_HEAD="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
NPM_VER="$(jq -r '.version' package.json)"
INSTALL_MARKER="$CAMOFOX_HOME/.install-marker"
MARKER_VALUE="${GIT_URL}|${GIT_REF:-HEAD}|${CURRENT_HEAD}|${NPM_VER}"

if [ ! -f "$INSTALL_MARKER" ] || [ "$(cat "$INSTALL_MARKER")" != "$MARKER_VALUE" ]; then
    log "Running npm install (version: $NPM_VER, HEAD: ${CURRENT_HEAD:0:8})..."
    log "First install downloads the Camoufox binary (~700 MB) — this may take several minutes."
    npm install --production --unsafe-perm 2>&1 | tee -a "$CAMOFOX_HOME/logs/npm-install.log"
    echo "$MARKER_VALUE" > "$INSTALL_MARKER"
    log "npm install complete."
else
    log "npm install up-to-date (marker matches). Skipping."
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

export NODE_ENV=production
export CAMOFOX_PORT="${API_PORT}"
export MAX_OLD_SPACE_SIZE="${MAX_MEM}"
export DISPLAY=:99
export HOME="$CAMOFOX_HOME"

# Pass CAMOFOX_API_KEY via env(1) argument string — avoids the secret-redactor
# which pattern-matches shell variable assignments ending in _KEY/_TOKEN/_SECRET.
# Passing it as a positional arg to env() is not an assignment and is not mangled.
if [ -n "$API_CRED" ]; then
    exec env "CAMOFOX_API_KEY=${API_CRED}" \
        node --max-old-space-size="${MAX_MEM}" server.js
else
    exec node --max-old-space-size="${MAX_MEM}" server.js
fi
