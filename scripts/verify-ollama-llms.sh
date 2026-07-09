#!/usr/bin/env bash
#
# verify-ollama-llms.sh — Debug Ollama models for KnonixAI readiness.
#
# Checks installed tags (and optionally catalog tags) for Ollama **tools**
# capability required by research chat (search, connectors, Pro/Deep modes).
#
# Usage:
#   ./scripts/verify-ollama-llms.sh
#   OLLAMA_HOST=http://localhost:11434 ./scripts/verify-ollama-llms.sh
#   ./scripts/verify-ollama-llms.sh --catalog   # also print catalog expectations
#
set -euo pipefail

OLLAMA_HOST="${OLLAMA_HOST:-http://127.0.0.1:11434}"
# Inside docker compose from install dir:
if [[ -z "${OLLAMA_HOST}" ]] || ! curl -sf "${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; then
  if command -v docker >/dev/null 2>&1; then
    # Try common container names
    for c in knonixai-ollama-1 ollama; do
      if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$c"; then
        OLLAMA_HOST="http://$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$c"):11434"
        break
      fi
    done
  fi
fi

SHOW_CATALOG=0
[[ "${1:-}" == "--catalog" ]] && SHOW_CATALOG=1

echo "==> KnonixAI Ollama LLM verification"
echo "    OLLAMA_HOST=${OLLAMA_HOST}"
echo

if ! curl -sf "${OLLAMA_HOST}/api/tags" >/dev/null; then
  echo "ERROR: cannot reach Ollama at ${OLLAMA_HOST}" >&2
  echo "       Start the stack (docker compose up -d) and retry." >&2
  exit 1
fi

python3 - <<'PY' "${OLLAMA_HOST}" "${SHOW_CATALOG}"
import json, sys, urllib.request

base = sys.argv[1]
show_catalog = sys.argv[2] == "1"

# Catalog expectations (mirrors lib/knonix/models.ts toolsSupported)
CATALOG = {
  "llama3.1:8b": True,
  "llama3.3:70b": True,
  "nemotron-mini:4b": True,
  "nemotron:70b": True,
  "mistral:7b": True,
  "mistral-nemo:12b": True,
  "qwen2.5:7b": True,
  "qwen2.5:32b": True,
  "qwen2.5-coder:7b": True,
  "gemma2:9b": False,
  "phi4:14b": False,
  "deepseek-r1:7b": True,
  "deepseek-r1:32b": True,
  "granite3.1-dense:8b": True,
  "olmo2:13b": False,
  "nomic-embed-text": False,  # embed only
}

def get(url, data=None):
  req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"} if data else {})
  with urllib.request.urlopen(req, timeout=30) as r:
    return json.load(r)

tags = get(f"{base}/api/tags").get("models") or []
print(f"{'TAG':32} {'ROLE':12} {'TOOLS':8} {'STATUS'}")
print("-" * 72)

chat_ok = []
chat_bad = []
embed_ok = []

for m in sorted(tags, key=lambda x: x.get("name", "")):
  name = m.get("name") or ""
  caps = m.get("capabilities")
  if not caps:
    try:
      body = get(f"{base}/api/show", json.dumps({"name": name}).encode())
      caps = body.get("capabilities") or []
    except Exception:
      caps = []
  tools = "tools" in caps
  embed = "embedding" in caps and "completion" not in caps
  if embed:
    role = "embed"
    embed_ok.append(name)
    status = "OK (embeddings)"
  elif tools:
    role = "chat+tools"
    chat_ok.append(name)
    status = "OK for research"
  else:
    role = "completion"
    chat_bad.append(name)
    status = "BLOCK research"
  print(f"{name:32} {role:12} {('YES' if tools else 'NO'):8} {status}  caps={caps}")

print()
print("=== Summary ===")
print(f"  Research-ready (tools): {len(chat_ok)}")
for n in chat_ok:
  print(f"    ✓ {n}")
print(f"  Completion-only (blocked for chat research): {len(chat_bad)}")
for n in chat_bad:
  print(f"    ✗ {n}")
print(f"  Embedding: {len(embed_ok)}")
for n in embed_ok:
  print(f"    · {n}")

if not chat_ok:
  print()
  print("ERROR: No tools-capable chat model installed.")
  print("  Fix:  ollama pull qwen2.5:7b")
  sys.exit(2)

if show_catalog:
  print()
  print("=== Catalog expectations (if you pull these) ===")
  print(f"{'TAG':32} {'EXPECT_TOOLS':14} {'NOTES'}")
  for tag, expect in CATALOG.items():
    note = "safe for research chat" if expect else "NOT for research — completion/embed only"
    print(f"{tag:32} {str(expect):14} {note}")

print()
print("Tip: after any pull, re-run this script. Knonix chat only uses tools-capable models.")
if chat_bad:
  print("You can free disk from blocked models, e.g.: ollama rm phi4:14b")
sys.exit(0)
PY
