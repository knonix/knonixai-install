# Push installer + publish image (reconnect GitHub)

Use this after reboots or when credentials expire. You need a **GitHub account**
with access to `knonix/knonixai-install` and (for images) `ghcr.io/knonix/knonixai`.

---

## 1) Reconnect GitHub on this machine

### Option A — GitHub CLI (recommended)

```bash
# Install if missing (Debian/Ubuntu)
sudo apt-get update && sudo apt-get install -y gh

# Login (browser or token)
gh auth login
# Choose: GitHub.com → HTTPS → Login with a web browser
# OR: Paste an authentication token

# Confirm
gh auth status
```

### Option B — Personal Access Token (PAT)

1. GitHub → **Settings → Developer settings → Personal access tokens**
2. Create a token with scopes:
   - **Installer only:** `repo`
   - **Also publish images:** `repo` + `write:packages` + `read:packages`
3. On the VM:

```bash
export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
# optional: also use for git
echo "https://x-access-token:${GITHUB_TOKEN}@github.com" > ~/.git-credentials
git config --global credential.helper store
```

---

## 2) Push the **installer repo** (compose, entrypoint, docs)

```bash
cd ~/knonixai-install
git status
git pull --rebase origin main   # if others may have pushed

# If you have uncommitted UI fixes:
git add -A
git status   # never commit .env or secrets/
git commit -m "UI: resources rail + single thinking dots; reboot-safe restarts"

# Push
git push origin main
# or with token:
git push "https://x-access-token:${GITHUB_TOKEN}@github.com/knonix/knonixai-install.git" main
```

Customers then:

```bash
git clone https://github.com/knonix/knonixai-install.git
cd knonixai-install && ./install.sh
```

---

## 3) Publish a **new app image** to GHCR (optional)

Runtime patches in `scripts/knonix-entrypoint.sh` apply on every start for
`:latest`. Baking them into the image is optional but cleaner for customers.

```bash
# Login to GHCR
echo "$GITHUB_TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin

cd ~/knonixai-install/image-build

# Builds on top of current :latest and pushes fixed-health + latest
export IMAGE=ghcr.io/knonix/knonixai
export BASE_IMAGE=ghcr.io/knonix/knonixai:latest
export PUSH=true
./publish-fixed-image.sh
```

Or manually:

```bash
docker pull ghcr.io/knonix/knonixai:latest
docker build \
  --build-arg BASE_IMAGE=ghcr.io/knonix/knonixai:latest \
  -f Dockerfile.fix-public-image \
  -t ghcr.io/knonix/knonixai:latest \
  -t ghcr.io/knonix/knonixai:fixed-$(date -u +%Y%m%d) \
  .
docker push ghcr.io/knonix/knonixai:latest
docker push ghcr.io/knonix/knonixai:fixed-$(date -u +%Y%m%d)
```

Then on any install:

```bash
cd ~/knonixai-install
docker compose pull knonixai
docker compose -f docker-compose.yml -f docker-compose.proxy.yml up -d knonixai
```

---

## 4) Platform host (this server) after publish

```bash
cd ~/knonixai-install
docker compose \
  -f docker-compose.yml \
  -f docker-compose.proxy.yml \
  -f docker-compose.platform.yml \
  --profile auth \
  pull knonixai
docker compose \
  -f docker-compose.yml \
  -f docker-compose.proxy.yml \
  -f docker-compose.platform.yml \
  --profile auth \
  up -d knonixai
```

---

## Notes

| Item | Detail |
|------|--------|
| Never push | `.env`, `secrets/`, `platform/license-service/data/` |
| Runtime patches | `scripts/knonix-entrypoint.sh` always re-applies on container start |
| SSH | Unrelated to GitHub — use `ssh knonix@192.168.0.2` |
| Token expiry | Re-run `gh auth login` or create a new PAT |
