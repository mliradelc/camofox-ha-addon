## 1.0.4 (2026-05-28)

- Fix: port mapping corrected from `9378/tcp: 9378` to `9377/tcp: 9378` — HA Supervisor maps the internal container port (9377, where Node.js actually listens) to external port 9378. The previous mapping targeted the wrong container port, causing connection resets on `homeassistant:9378`.

## 1.0.3 (2026-05-28)

- Fix: download yt-dlp binary to persistent storage at boot — upstream postinstall.js does not download it; the youtube plugin post-install.sh does (runs only during Docker build, not at runtime). Binary stored in /config/camofox/yt-dlp, symlinked to /usr/local/bin/ each boot.
- Improvement: remove HA ingress panel and "Open Web UI" button — Camofox has no web UI; the blank page it produced was confusing. REST API is now exposed directly on port 9378.
- Improvement: remove nginx proxy (was only serving the ingress endpoint which is now disabled).
- Improvement: add descriptive tooltips for all configuration options in the HA add-on UI.

## 1.0.2 (2026-05-28)

- Fix: remove manual Camoufox binary download block — npm postinstall already handles this (downloading ~700 MB binary + yt-dlp + GeoIP database to $HOME/.cache/camoufox/)
- Fix: remove `ln -sfn` that failed with "cannot overwrite directory" when HOME pointed to persistent storage and postinstall had already created the cache path as a real directory
- Fix: CAMOFOX_API_KEY passed via `env` positional argument to avoid secret-redactor mangling

## 1.0.1 (2026-05-28)

- Fix: replace `python3 -c 'import json'` with `jq` — `python3-minimal` in node:22-slim does not ship the json stdlib module


## 1.0.0 (2026-05-28)

### Initial release

- Packages [jo-inc/camofox-browser](https://github.com/jo-inc/camofox-browser) v1.11.2
- Camoufox binary v150.0.2-beta.25 (Firefox fork with C++-level fingerprint spoofing)
- Node.js 22 runtime, nginx ingress proxy, Xvfb virtual display
- REST API on port 9377 (configurable): `/tabs`, `/snapshot`, `/click`, `/type`, `/navigate`, `/screenshot` and more
- Auto-update mode: `git pull` on restart when `auto_update: true`
- Marker-gated npm install: skips reinstall when source unchanged
- Persistent binary cache: Camoufox binary downloaded once to `/config/camofox/browser/`
- amd64 and aarch64 support
- HA ingress panel at port 49171
