#!/usr/bin/env bash
# verify_build.sh — post-build verification for camofox-ha-addon
# Run from repo root before declaring build complete.
set -euo pipefail

ERRORS=0
PASS=0

ok()   { echo "  OK: $*"; ((PASS++)) || true; }
fail() { echo "FAIL: $*"; ((ERRORS++)) || true; }

echo "=== Camofox HA Add-on — Build Verification ==="
echo ""

# 1. Secret redactor artefacts
echo "--- Checking for secret-redactor artefacts (***) ---"
if grep -r '\*\*\*' camofox/ .github/ 2>/dev/null | grep -v '.upstream-versions.json' | grep -v 'CHANGELOG' | grep -v '#'; then
    fail "Secret-redactor artefacts found — check the files above"
else
    ok "No redaction artefacts"
fi

# 2. Shell syntax
echo "--- Shell syntax ---"
if bash -n camofox/run.sh 2>&1; then
    ok "run.sh syntax OK"
else
    fail "run.sh has syntax errors"
fi

# 3. YAML validity
echo "--- YAML validity ---"
for f in camofox/config.yaml camofox/translations/en.yaml repository.yaml .github/workflows/release.yml .github/workflows/upstream-watch.yml .github/workflows/validate.yml .github/workflows/integration-test.yml .github/dependabot.yml; do
    if [ -f "$f" ]; then
        if python3 -c "import yaml; yaml.safe_load(open('$f'))" 2>/dev/null; then
            ok "$f YAML valid"
        else
            fail "$f YAML invalid"
        fi
    else
        fail "$f not found"
    fi
done

# 4. JSON validity
echo "--- JSON validity ---"
for f in camofox/.upstream-versions.json; do
    if [ -f "$f" ]; then
        if python3 -c "import json; json.load(open('$f'))" 2>/dev/null; then
            ok "$f JSON valid"
        else
            fail "$f JSON invalid"
        fi
    else
        fail "$f not found"
    fi
done

# 5. Required files present
echo "--- Required files ---"
for f in \
    repository.yaml \
    README.md \
    LICENSE \
    CHANGELOG.md \
    .gitignore \
    camofox/config.yaml \
    camofox/Dockerfile \
    camofox/run.sh \
    camofox/CHANGELOG.md \
    camofox/DOCS.md \
    camofox/.upstream-versions.json \
    camofox/translations/en.yaml \
    .github/workflows/release.yml \
    .github/workflows/upstream-watch.yml \
    .github/workflows/validate.yml \
    .github/workflows/integration-test.yml \
    .github/dependabot.yml; do
    if [ -f "$f" ]; then
        ok "$f present"
    else
        fail "$f MISSING"
    fi
done

# Icon check (warn only — may be absent on a fresh build before copy)
if [ -f "camofox/icon.png" ]; then
    ok "camofox/icon.png present"
else
    echo "WARN: camofox/icon.png not found (add before release)"
fi

# 6. Dockerfile — check it is NOT a copy of hermes-ha-addon / honcho Dockerfile
echo "--- Dockerfile Camofox-specificity ---"
if grep -qi 'hermes_agent\|honcho\|fastapi\|pgvector\|postgresql\|redis-server\|chromium\|nodejs\|go 1\.' camofox/Dockerfile 2>/dev/null; then
    fail "Dockerfile contains references to other projects (hermes/honcho/pgvector/redis)"
else
    ok "Dockerfile looks Camofox-specific"
fi
# Must have node:22-slim base
if grep -q 'node:22-slim' camofox/Dockerfile 2>/dev/null; then
    ok "Dockerfile uses node:22-slim base"
else
    fail "Dockerfile does not use node:22-slim base"
fi

# 7. config.yaml — key fields
echo "--- config.yaml fields ---"
IMAGE=$(python3 -c "import yaml; d=yaml.safe_load(open('camofox/config.yaml')); print(d.get('image','MISSING'))")
if echo "$IMAGE" | grep -q '{arch}'; then
    fail "config.yaml image field contains /{arch} — HA Supervisor creates sub-package path. Remove /{arch}."
elif [ "$IMAGE" = "MISSING" ]; then
    fail "config.yaml missing image: field"
else
    ok "config.yaml image: $IMAGE (no /{arch})"
fi

# 8. Git status
echo "--- Git status ---"
if git -C . status --porcelain 2>/dev/null | grep -q .; then
    echo "WARN: Uncommitted changes:"
    git -C . status --porcelain
else
    ok "Git working tree clean"
fi

# 9. Remote sync check
echo "--- Remote sync ---"
if git -C . remote get-url origin 2>/dev/null | grep -q 'camofox-ha-addon'; then
    LOCAL_HEAD=$(git -C . rev-parse HEAD 2>/dev/null || echo "unknown")
    REMOTE_HEAD=$(git -C . ls-remote origin HEAD 2>/dev/null | cut -f1 || echo "unknown")
    if [ "$LOCAL_HEAD" = "$REMOTE_HEAD" ]; then
        ok "Remote is up to date (HEAD: ${LOCAL_HEAD:0:8})"
    else
        fail "Remote is behind local! Run: git push origin main"
    fi
else
    echo "WARN: Cannot verify remote sync (origin not set or wrong URL)"
fi

echo ""
echo "=== Results: $PASS checks passed, $ERRORS failures ==="
if [ "$ERRORS" -gt 0 ]; then
    echo "BUILD VERIFICATION FAILED — fix the issues above before declaring done."
    exit 1
else
    echo "BUILD VERIFICATION PASSED."
fi
