# KnonixAI — Easy setup (non-technical)

You do **not** need to be a developer. If you can open a Terminal and paste commands, you can install KnonixAI.

**Related docs:** [README](./README.md) · [CHANGELOG.md](./CHANGELOG.md) · [FEATURES.md](./FEATURES.md) · [INSTALL_SETTINGS.md](./INSTALL_SETTINGS.md) · [SYSTEM_REQUIREMENTS.md](./SYSTEM_REQUIREMENTS.md)

## What you need

1. A computer or server (Linux is best)
   - **Works on low-end / no GPU:** 4 CPU cores · **8–16 GB RAM** (default model is small and fast)
   - **Smoother with more RAM or a GPU** — the installer auto-picks model size
2. **Docker Desktop** (Mac/Windows) or **Docker Engine** (Linux)  
   Download: https://docs.docker.com/get-docker/
3. About **40 GB** free disk on small machines (more if you install large models later)

## Install in 3 steps

### 1. Get the installer folder

Download the **knonixai-install** package from Knonix (or clone it) and open a terminal **in that folder**.

### 2. Run the installer

```bash
chmod +x install.sh
./install.sh
```

Answer the questions in plain English:

| Prompt | What to enter |
|--------|----------------|
| Postgres password | Press Enter to accept the secure random password (save it somewhere safe) |
| Public domain | Your website name (e.g. `ai.company.com`) or leave blank for `localhost` |
| HTTPS email | Your work email if you set a domain |
| Fleet token | Paste the token from your Knonix license email, or leave blank for free/local |

The script will:

- Start Docker if needed  
- Create a safe configuration file (`.env`)  
- **Detect CPU/RAM/GPU** and pick a model that stays interactive on your machine  
- Download the KnonixAI app  
- Start the database, AI model server, and website  
- Pull default local AI models (3B on small CPUs; larger only if you have the resources)  

**Speed tip:** use **Quick** mode for everyday chat. Deep research is heavier on small machines.

### 3. Open the app

- **Local only:** open http://localhost:3000  
- **With domain:** open `https://your-domain` (after DNS points to the server)

Sign up as the **first user** — that account becomes the organization owner.

## First-day checklist (in the product)

1. **Sign up / log in**  
2. **Admin → Members** — invite teammates (or stay solo)  
3. **Connectors** — link Microsoft 365 or Google (optional)  
4. **Chat research modes** (composer): **Quick · Pro · Adaptive · Deep**  
   - Pro asks clarifying questions; Deep builds multi-source reports  
   - Watch the agent work (tools), then **Sources** + **Related** follow-ups  
   - Download icon under answers exports a Markdown report  
5. **Spaces** — create a space for a team or project  
6. **Space → Settings → SKILL.md** — upload personality or use a skill pack  
7. **Space → Settings → Productivity**  
   - **Vault** — paste important documents  
   - **Memory** — list durable facts  
   - **Skill packs** — Apply “Compliance Reviewer” or others  
   - **Approvals** — approve agent write proposals  
8. Start a **space chat** and ask a real work question  

## Health check

```bash
./scripts/verify-install.sh
```

Or open: `https://your-domain/api/knonix/health`

## Common issues

| Problem | Fix |
|---------|-----|
| “Docker not found” | Install Docker Desktop and open it once |
| Site won’t load | Wait 2–3 minutes after install; models are still downloading |
| Chat is slow | Normal on CPU; first answer can take longer. Use **Quick** mode for snappy replies; **Deep** is slower by design |
| No Sources under answer | Use **Pro** or **Deep** and ask a research question so the agent runs web search |
| Mode toggle only shows Quick | Hard-refresh the browser (Ctrl/Cmd+Shift+R) after updating the image |
| “does not support tools” / phi4 missing | That model is chat-only. Use `qwen2.5:7b` (or any model with `tools` in `ollama show`). phi4:14b will not appear in the picker after refresh |
| Forgot password | Use Admin/GoTrue reset or re-set via your auth provider |
| Need help | Contact Knonix support with your install domain |

## What “Easy mode” means

- Defaults are safe for a single-company install  
- Local models stay **on your machine**  
- You can add domain + HTTPS later by editing `.env` and re-running `./install.sh`  

You never need to build the app from source for a normal customer install.

## Legal

By installing KnonixAI you agree to the **[Terms of Use](./TERMS_OF_USE.md)** (use at your own risk; you are responsible for security and backups).  
Privacy: **[Privacy Policy](./PRIVACY_POLICY.md)**.

## Keeping KnonixAI up to date

Knonix publishes new **installer** versions and **app images**. To see if you need an update:

```bash
cd knonixai-install
./scripts/check-updates.sh
```

If an update is available:

```bash
git pull origin main
cat CHANGELOG.md | head -60
docker compose pull
docker compose -f docker-compose.yml -f docker-compose.proxy.yml --profile auth up -d
```

Then refresh your browser (Ctrl+Shift+R / Cmd+Shift+R).

The **CHANGELOG.md** file lists what changed in each version.
