# Camofox Browser

An anti-detect headless browser REST API server for AI agents, packaged as a Home Assistant add-on.

Powered by [Camoufox](https://github.com/daijro/camoufox) — a Firefox fork that spoofs browser fingerprints at the C++ level, bypassing Cloudflare, bot detection, and anti-scraping protections.

## Features

- **Anti-detection**: C++-level spoofing of Navigator, WebGL, AudioContext, WebRTC, screen geometry
- **REST API**: Full browser automation via simple HTTP endpoints
- **AI-agent ready**: Token-efficient accessibility snapshots with stable element refs (`e1`, `e2`, ...)
- **Session isolation**: Separate cookies and storage per user ID
- **YouTube transcripts**: Via yt-dlp, no API key needed
- **Auto-update**: Pull latest source on restart without rebuilding the Docker image
- **amd64 + aarch64**: Both architectures supported

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `git_url` | `https://github.com/jo-inc/camofox-browser.git` | Source repository URL |
| `git_ref` | _(blank)_ | Branch, tag, or commit. Blank = default branch |
| `git_cred` | _(blank)_ | Credential for private repositories |
| `auto_update` | `false` | Pull latest source on every add-on restart |
| `api_port` | `9377` | Internal Node.js server port |
| `api_cred` | _(blank)_ | API key for the `CAMOFOX_API_KEY` environment variable |
| `max_memory` | `128` | Node.js `--max-old-space-size` in MB (64–2048) |

## First Start

1. Install the add-on and click **Start**.
2. On first boot the add-on will:
   - Clone the camofox-browser source (~2 MB)
   - Run `npm install` (~30 s)
   - Download the Camoufox Firefox binary (~300 MB) — **this takes 2–5 minutes** depending on your connection
3. Once started, the API is available via the HA sidebar or directly on port 9378 (if mapped).

## API Quick Reference

```bash
# Create a tab
curl -X POST http://your-ha:9378/tabs \
  -H 'Content-Type: application/json' \
  -d '{"userId": "agent1", "url": "https://example.com"}'

# Get accessibility snapshot
curl "http://your-ha:9378/tabs/TAB_ID/snapshot?userId=agent1"

# Click by element ref
curl -X POST http://your-ha:9378/tabs/TAB_ID/click \
  -H 'Content-Type: application/json' \
  -d '{"userId": "agent1", "ref": "e1"}'

# Take a screenshot
curl "http://your-ha:9378/tabs/TAB_ID/screenshot?userId=agent1" \
  --output screenshot.png
```

Full API docs available at `http://your-ha:9378/docs` once the add-on is running.

## Persistent Storage

All data is stored under `/config/camofox/`:

| Path | Contents |
|------|----------|
| `source/` | Cloned camofox-browser source |
| `browser/` | Camoufox Firefox binary (~300 MB) |
| `.cache/camoufox/` | Symlink to `browser/` |
| `logs/` | npm install, git update, Xvfb logs |

## Support

- Add-on issues: [mliradelc/camofox-ha-addon](https://github.com/mliradelc/camofox-ha-addon/issues)
- Upstream server: [jo-inc/camofox-browser](https://github.com/jo-inc/camofox-browser)
- Camoufox browser: [daijro/camoufox](https://github.com/daijro/camoufox)
