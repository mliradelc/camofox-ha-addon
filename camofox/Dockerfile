FROM node:22-slim

LABEL \
    io.hass.version="1.0.0" \
    io.hass.type="addon" \
    io.hass.arch="amd64|aarch64"

RUN apt-get update && apt-get install -y --no-install-recommends \
    # Firefox runtime dependencies (required by Camoufox)
    libgtk-3-0 \
    libdbus-glib-1-2 \
    libxt6 \
    libasound2 \
    libx11-xcb1 \
    libxcomposite1 \
    libxcursor1 \
    libxdamage1 \
    libxfixes3 \
    libxi6 \
    libxrandr2 \
    libxrender1 \
    libxss1 \
    libxtst6 \
    # Mesa/EGL for WebGL — missing these is a bot-detection signal
    libegl1-mesa \
    libgl1-mesa-dri \
    libgbm1 \
    # Xvfb virtual display — headless Firefox needs a display server
    xvfb \
    # Fonts — affects fingerprint consistency
    fonts-liberation \
    fonts-noto-color-emoji \
    fontconfig \
    # yt-dlp Python runtime
    python3-minimal \
    # nginx for HA ingress proxy
    nginx \
    # Utilities
    ca-certificates \
    curl \
    git \
    jq \
    unzip \
    && rm -rf /var/lib/apt/lists/*

COPY run.sh /
RUN chmod a+x /run.sh
CMD ["/run.sh"]
