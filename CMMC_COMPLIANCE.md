# KnonixAI — CMMC, DFARS, NIST & Federal Compliance Guide

**Audience:** federal contractors, ISSOs, capture/compliance leads, and integrators evaluating KnonixAI for CMMC Level 1–2 programs and NIST SP 800-171–aligned environments.

**Status:** Product design and capability guide. KnonixAI is a **sovereign AI platform** that supports compliant *architectures* and *readiness workflows*. It is **not** a C3PAO assessment, SPRS filing tool, or substitute for legal counsel.

---

## Executive summary

| Question | Answer |
|----------|--------|
| **Does KnonixAI “make you CMMC certified”?** | No. Certification requires organizational controls + assessment. KnonixAI **helps implement and operate** an AI workload *inside* a boundary you control. |
| **Does it help with CMMC readiness?** | **Yes.** Built-in compliance expert mode, enclave evidence sweeps (knowledge, vault, SharePoint), domain matrices (AC–SI), POA&M-style planning, and Studio playbooks. |
| **Where does inference run?** | **Local by default** (Ollama open-weight models). Frontier APIs are **off by default** and admin-gated. |
| **Where do prompts / documents go?** | Stay on your install (Postgres, local embeddings, optional in-stack SearXNG) unless you explicitly enable frontier models or external search APIs. |
| **Who is it for?** | DIB suppliers, primes/subs under **DFARS 252.204-7012 / 7021**, GCC High tenants, and any org that needs **data + intelligence sovereignty**. |

---

## How KnonixAI maps to CMMC & related frameworks

### Framework coverage matrix

| Framework / clause | How KnonixAI supports programs | Product surfaces |
|--------------------|--------------------------------|------------------|
| **CMMC Level 1** | Foundational safeguarding posture; local AI so CUI-adjacent workflows need not leave the enclave; human approvals for durable writes | Chat, Spaces (CUI classification), Approvals |
| **CMMC Level 2** | Enclave RAG + vault + M365 evidence search; **14-domain readiness matrix** aligned to NIST SP 800-171 families; interactive coaching | Compliance intent, CMMC skill/plugin, readiness pipeline, Studio playbook |
| **CMMC Level 3** | Same platform with stricter classification, minimized external web, and enhanced program memory — *org still owns 800-172 technical controls* | Space instructions, CUI mode, connectors policy |
| **NIST SP 800-171** | Domain language (AC, AU, CM, IA, …); evidence-first guidance; gap / POA&M style deliverables | Regulation expert prompts, Studio “CMMC Readiness Sweep” |
| **NIST SP 800-172** | Crosswalk language for enhanced practices when asked; not an automated 800-172 scorer | Expert mode + knowledge corpus you upload |
| **NIST SP 800-53** | Definitions and control-family orientation via tools + your policy library | Web (official sources) + knowledge |
| **DFARS 252.204-7012** | Guidance on safeguarding CDI, IR reporting themes, pairing with 800-171; **verify clauses on your contract** | Compliance expert prompt, enclave search for your SSP/IR plan |
| **DFARS 252.204-7019 / 7020** | Assessment methodology / SPRS *narrative support* — not automated SPRS submission | Readiness reports |
| **DFARS 252.204-7021** | CMMC contract requirement awareness in coaching flows | Compliance expert mode |
| **FAR 52.204-21** | Basic safeguarding themes (Level 1–aligned) | Expert orientation |
| **CUI** | Classification flags, vault isolation, “minimize external web” for CUI spaces; no Purview bypass claims | Space classification, connectors ACL |

### CMMC Level 2 domain readiness (product support)

KnonixAI’s compliance expert produces evidence-based status across NIST 800-171–aligned domains:

| Domain | Name | Product support for readiness work |
|--------|------|-------------------------------------|
| **AC** | Access Control | Search policies/SSO docs in knowledge, SharePoint; coach least-privilege |
| **AT** | Awareness & Training | Find training records / curricula in enclave |
| **AU** | Audit & Accountability | Locate logging/retention policies; gap if missing |
| **CM** | Configuration Management | Baseline & change-control docs in vault/library |
| **IA** | Identification & Authentication | MFA / identity policy evidence via tenant + knowledge |
| **IR** | Incident Response | IR plan search; structure POA&M-style improvements |
| **MA** | Maintenance | Maintenance procedures in knowledge corpus |
| **MP** | Media Protection | CUI media handling policies |
| **PS** | Personnel Security | Screening/onboarding policy artifacts |
| **PE** | Physical Protection | Facility/physical access procedures |
| **RA** | Risk Assessment | Risk register / scan reports if uploaded |
| **CA** | Security Assessment | SSP, POA&M, continuous monitoring evidence |
| **SC** | System & Communications Protection | Boundary / encryption policy docs |
| **SI** | System & Information Integrity | Patch / malware / monitoring procedures |

**Status values used in assessments:** Implemented · Partial · Planned · Not started · N/A · **Unknown (needs evidence)**.

---

## Architecture that supports a compliant AI enclave

```
┌─────────────────────────────────────────────────────────────┐
│  Your boundary (customer VPC / SCIF-adjacent / IL environment) │
│                                                               │
│  ┌──────────┐  ┌─────────┐  ┌──────────┐  ┌──────────────┐  │
│  │ KnonixAI │  │ Ollama  │  │ Postgres │  │ SearXNG      │  │
│  │ App      │──│ Local   │  │ +pgvector│  │ In-stack     │  │
│  │          │  │ LLMs    │  │ RAG/chat │  │ search       │  │
│  └────┬─────┘  └─────────┘  └──────────┘  └──────────────┘  │
│       │                                                       │
│       ├── Knowledge library (embeddings stay local)           │
│       ├── Space vault + MEMORY.md + SKILL.md                  │
│       ├── Approvals (human-in-the-loop durable writes)        │
│       └── Optional M365 / Google connectors (delegated ACL)   │
│                                                               │
│  Optional (OFF by default): Frontier APIs → leaves boundary  │
└─────────────────────────────────────────────────────────────┘
```

### Control-aligned product properties

| Property | Implementation | Typical control themes |
|----------|----------------|------------------------|
| **Data residency** | Self-hosted Docker; no required cloud LLM | SC, MP |
| **Least privilege AI actions** | Connector *read/search* by default; writes via Approvals | AC, CA |
| **Auditability** | Chat history, tool trails, activity UI, optional Langfuse | AU |
| **Identity** | Local GoTrue + optional Entra (incl. GCC High) / Google SSO | IA |
| **Separation of duties** | Org admin, seats, space roles (owner/editor/viewer) | AC, PS |
| **Media / document control** | Space vault isolation; CUI classification steering | MP, SC |
| **Integrity of configuration** | Admin models/connectors; install identity; env-based config | CM |
| **Incident-aware design** | License heartbeat **never** sends CUI/PII/prompt content | IR, SC |
| **Training & guidance** | In-product CMMC expert + Studio playbooks | AT, CA |

---

## Competitive & product mapping matrix (marketing)

How KnonixAI positions against common alternatives for **regulated / DIB** buyers:

| Capability | **KnonixAI** | Microsoft 365 Copilot | ChatGPT Enterprise / Team | Claude for Work / API | Glean | Perplexity Enterprise | Cursor / coding IDEs |
|------------|--------------|------------------------|---------------------------|------------------------|-------|----------------------|----------------------|
| **Default inference location** | **Your enclave (Ollama)** | Microsoft cloud | OpenAI cloud | Anthropic cloud | Vendor cloud | Vendor cloud | Cloud or local IDE |
| **Sovereign-by-default** | **Yes** | No (tenant cloud) | No | No | No | No | Partial (local models optional) |
| **Self-host full stack** | **Yes (Docker)** | No | No | No | No | No | Desktop only |
| **Air-gapped / offline license** | **Supported** | No | No | No | Limited | No | Limited |
| **GCC High / Azure Gov Graph** | **Yes (`.us` routing)** | Native M365 | N/A | N/A | Varies | N/A | N/A |
| **CMMC-oriented coaching** | **Yes (built-in expert + readiness pipeline)** | Generic | Generic | Generic | Search-centric | Research-centric | Code-centric |
| **Enclave evidence sweep** (vault + RAG + SharePoint) | **Yes** | M365 grounding | Uploads | Projects/uploads | Enterprise index | Web + uploads | Repo only |
| **Human approve-to-write** | **Yes** | Policy-dependent | N/A | N/A | Varies | N/A | Git commits local |
| **Local RAG (pgvector)** | **Yes** | Graph/SharePoint | Vendor storage | Vendor | Vendor | Vendor | Code index |
| **Open-weight model choice** | **Full Ollama catalog** | No | No | No | No | No | Some local |
| **Frontier models** | Opt-in, labeled non-sovereign | Always cloud | Always cloud | Always cloud | Cloud | Cloud | Cloud |
| **Per-seat fleet licensing** | **Yes (2 free seats + metered)** | M365 SKU | Per seat | Per seat | Enterprise | Per seat | Per seat |
| **Federal Studio playbooks** | **Yes (CMMC sweep, CUI redact, gov memo)** | Copilot Studio (cloud) | GPTs | Projects | Workflows | Collections | Rules/skills |
| **Best fit** | **DIB / CMMC programs needing AI *inside* the boundary** | M365-native productivity | General enterprise chat | High-quality cloud assistants | Intranet search | Web research | Software engineering |

### One-line positioning

> **KnonixAI is the sovereign AI enclave for federal contractors** — Copilot-class productivity *without* defaulting your prompts and documents to a public LLM cloud, with **CMMC/NIST readiness workflows** built into Spaces, Studio, and chat.

---

## Using KnonixAI for CMMC readiness (operator runbook)

1. **Install** on hardware that meets [SYSTEM_REQUIREMENTS.md](../install/SYSTEM_REQUIREMENTS.md) (production tier recommended for teams).
2. Create a **Space** (e.g. “CMMC Program”) — set classification to **CUI** when appropriate.
3. Install plugin **CMMC & Regulation Expert** (or apply skill pack **CMMC & DFARS Expert**).
4. Ingest **SSP, policies, IR plan, training records, inventory** into Knowledge and/or Space Vault.
5. Link **Microsoft 365** (commercial or GCC High) if evidence lives in SharePoint/OneDrive/email.
6. Ask:  
   *“Assess our CMMC Level 2 readiness using this space’s vault, knowledge, and SharePoint. Produce a domain matrix and 90-day plan.”*
7. Review the matrix; **approve** MEMORY.md updates so the program gets smarter over time.
8. Optionally run Studio playbook **CMMC Readiness Sweep**.

### What good looks like

- Statuses marked **Unknown** when evidence is missing (not invented “Implemented”).
- Citations to enclave documents and/or official sources.
- POA&M-style gaps with owners and urgency.
- Clear disclaimer: decision support, not certification.

---

## What KnonixAI does *not* claim

| Claim | Reality |
|-------|---------|
| “CMMC certified software” | Organizations are assessed; software is a **component** of your architecture |
| Automatic SPRS score filing | Not provided — narrative and gap support only |
| Replacement for C3PAO / DIBCAC | Coaching and evidence organization only |
| Automatic Purview / MIP labeling | Respects user ACL on connectors; does not bypass Microsoft sensitivity labels |
| Legal advice | Always verify DFARS/FAR clauses on the **actual contract** |

---

## Related documentation

| Doc | Purpose |
|-----|---------|
| [SYSTEM_REQUIREMENTS.md](./SYSTEM_REQUIREMENTS.md) | Hardware for smooth, production inference |
| [FEATURES.md](./FEATURES.md) | Full product feature reference |
| [INSTALL_SETTINGS.md](./INSTALL_SETTINGS.md) | Environment variables |
| [EASY_SETUP.md](./EASY_SETUP.md) | Non-technical install walkthrough |

---

## Document control

| Item | Value |
|------|--------|
| Product | KnonixAI |
| Topic | CMMC / DFARS / NIST compliance positioning |
| Maintainer | Knonix |
| Review | Update when control catalogs or product compliance features change |
