#!/usr/bin/env bash
# Push public installer commits to GitHub (run where you have gh auth or a PAT).
set -euo pipefail
WT="${1:-/home/knonix/.grok/worktrees/knonix-knonixai-install/knonixai}"
cd "$WT"
git status -sb
git log --oneline origin/main..HEAD
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  git push origin main
elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
  git push "https://x-access-token:${GITHUB_TOKEN}@github.com/knonix/knonixai-install.git" main
else
  echo "Set GITHUB_TOKEN or run: gh auth login"
  echo "Then: git push origin main"
  exit 1
fi
echo "Pushed. Customers can: git clone https://github.com/knonix/knonixai-install.git && cd knonixai-install && ./install.sh"
