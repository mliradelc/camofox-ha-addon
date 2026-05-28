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
