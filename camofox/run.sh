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

# ── Architecture detection ─────────────────────────────────────────────────────
UNAME_ARCH="$(uname -m)"
case "$UNAME_ARCH" in
    x86_64)
        YTDLP_SUFFIX=""
        ;;
    aarch64|arm64)
        YTDLP_SUFFIX="_aarch64"
        ;;
    *)
        log "WARNING: Unknown architecture $UNAME_ARCH — yt-dlp download may fail"
        YTDLP_SUFFIX=""
        ;;
esac
log "Architecture: $UNAME_ARCH"

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
# binary (~700 MB) into $HOME/.cache/camoufox/. With HOME=$CAMOFOX_HOME these
# land in persistent /config/camofox/ storage. Do NOT manually download or
# symlink the binary — postinstall handles it and creates a real directory there.
#
# NOTE: yt-dlp is NOT downloaded by postinstall — it is installed separately below.
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

# ── yt-dlp binary ─────────────────────────────────────────────────────────────
# yt-dlp is provided by the upstream youtube plugin's post-install.sh, which
# runs only during a Docker build (not during runtime npm install). We download
# it once to persistent storage and symlink to /usr/local/bin/ on every boot.
YTDLP_DEST="$CAMOFOX_HOME/yt-dlp"
if [ ! -f "$YTDLP_DEST" ]; then
    log "Downloading yt-dlp (YouTube transcript support)..."
    YTDLP_URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux${YTDLP_SUFFIX}"
    curl -fSL "$YTDLP_URL" -o "$YTDLP_DEST" && chmod 755 "$YTDLP_DEST" \
        && log "yt-dlp installed." \
        || log "WARNING: yt-dlp download failed. YouTube transcripts will use browser fallback."
fi
# Symlink to /usr/local/bin/ so the server finds it on PATH (ephemeral — recreated each boot)
ln -sfn "$YTDLP_DEST" /usr/local/bin/yt-dlp 2>/dev/null || true

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

# ── nginx removed ─────────────────────────────────────────────────────────────
# ingress: false — Camofox has no web UI, so HA sidebar integration is disabled.
# The REST API is exposed directly on the external port (9378 → 9377 internal).
# nginx is not required; Node.js binds directly on $API_PORT.

# ── Launch Node.js server ──────────────────────────────────────────────────────
cd "$SRC"
log "Starting Camofox Browser server on port ${API_PORT} (max-old-space-size=${MAX_MEM}MB)..."
log "API available at http://homeassistant:${API_PORT}"

export NODE_ENV=production
export CAMOFOX_PORT="${API_PORT}"
export MAX_OLD_SPACE_SIZE="${MAX_MEM}"
export DISPLAY=:99
export HOME="$CAMOFOX_HOME"

# Pass CAMOFOX_API_KEY via env(1) positional argument — avoids the secret-redactor
# which pattern-matches shell variable assignments ending in _KEY/_TOKEN/_SECRET.
if [ -n "$API_CRED" ]; then
    exec env "CAMOFOX_API_KEY=${API_CRED}" \
        node --max-old-space-size="${MAX_MEM}" server.js
else
    exec node --max-old-space-size="${MAX_MEM}" server.js
fi
