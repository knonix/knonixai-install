# KnonixAI — Privacy Policy

**Effective date:** July 12, 2026  
**Last updated:** July 12, 2026  

**Provider:** Knonix (“**Knonix**,” “**we**,” “**us**,” or “**our**”)  
**Contact:** sales@knonix.com  

This Privacy Policy describes how Knonix handles information in connection with **KnonixAI** software, documentation, websites, licensing, and related services (the “**Services**”).

> **Important for self-hosted installs:** When you run KnonixAI on **your** servers, **you** (your organization) determine how Customer Data is collected, stored, and processed **inside your Deployment**. Knonix does **not** operate your enclave and does **not** automatically receive your prompts, documents, or chat contents from a properly configured sovereign install. **You** are responsible for your own privacy notices to your users and for lawful processing of data you put into the system.

This Policy is provided for transparency. It is **not** legal advice. Your counsel should review compliance with GDPR, CCPA/CPRA, sector rules, and government privacy requirements.

---

## 1. Roles: who is responsible for what

| Scenario | Who controls Customer Data in the product? | Knonix’s typical role |
| -------- | ------------------------------------------ | --------------------- |
| **Self-hosted Deployment** (Docker on your infrastructure) | **You** (data controller / system owner for that environment) | Software vendor; may receive only limited operational metadata if you enable fleet/license features |
| **Knonix-operated site** (e.g., marketing site, docs, optional cloud features you use) | Knonix for data you submit to those sites | Controller for that site data |
| **Optional frontier AI APIs** you enable in your Deployment | You choose to send data to third parties (OpenAI, Anthropic, etc.) | Not the recipient; those providers’ policies apply |

**Knonix is not liable for how you configure privacy, retention, access, or cross-border transfers inside your Deployment.** See [Terms of Use](./TERMS_OF_USE.md).

---

## 2. Information we may collect

### 2.1 Information you provide directly

- Business contact details (name, work email, company) when you request licenses, support, or sales;
- Account information if you use a Knonix-operated service that requires accounts;
- Communications with sales or support;
- Billing details if you purchase seats (often processed by our payment processor, e.g. Stripe).

### 2.2 Self-hosted Deployments — data that stays with you

By design, a sovereign install is intended so that:

- Chat prompts, uploaded files, Space vault content, knowledge indexes, connector results, and local model inference run **in your environment**;
- Database volumes (e.g., Postgres), object storage you configure, and Ollama models live on **your** disks/volumes.

**Knonix does not receive that Customer Data unless you intentionally send it** (for example by enabling outbound webhooks, frontier APIs, support tickets that include exports, or misconfigured networking).

**You** must:

- Publish any privacy notice required for your employees/users;
- Honor data subject rights for data in **your** systems;
- Configure retention, encryption, and access control;
- Not rely on Knonix as your backup or DLP provider.

### 2.3 Operational / licensing metadata (if you use connected mode)

If you enable **connected** licensing / fleet enrollment, your install may periodically send **privacy-preserving operational signals** to Knonix Platform Services (e.g., `ai.knonix.com`), such as:

- Opaque install / instance identifiers or hashes;
- License key identifiers;
- Seat counts and billing-related quantities;
- Software version strings;
- Timestamps of heartbeats;
- Similar non-content telemetry needed to meter seats and support the product.

**Heartbeats are designed not to include chat prompts, document contents, or CUI.** You control whether connected mode is enabled (`free` / `offline` options may be available per documentation).

### 2.4 Website and documentation telemetry

When you visit Knonix websites or docs, we or our processors may collect:

- IP address, browser type, device///approximate location derived from IP;
- Pages viewed, referrers, and diagnostic logs;
- Cookies or local storage as needed for session, security, or analytics (if enabled).

### 2.5 Logs and security

We may process IP addresses, authentication events, and security logs for Platform Services to protect systems, debug outages, and prevent abuse.

### 2.6 AI model providers (your choice)

If **you** set `KNONIX_ALLOW_FRONTIER=true` (or equivalent) and provide API keys for third-party models, **your Deployment** sends prompts and context to those providers under **their** terms and privacy policies. That is outside Knonix’s hosting of your data. **Do not enable frontier APIs for data that must not leave your boundary.**

---

## 3. How we use information

We use information we control to:

- Provide and improve Platform Services (licensing, fleet, billing, docs);
- Authenticate and secure our systems;
- Communicate about licenses, security issues, and product changes;
- Comply with law and enforce Terms;
- Analyze aggregated usage of our websites and license telemetry (not your private chat content from sovereign installs).

We do **not** sell Customer Data from sovereign installs as a product feature, and we do not use your private chat contents for advertising.

---

## 4. Legal bases (EEA/UK where applicable)

Where GDPR-style rules apply to data Knonix processes as a controller, we rely on:

- **Contract** — to provide licenses and Platform Services you request;
- **Legitimate interests** — security, fraud prevention, product improvement of our platform (balanced against your rights);
- **Consent** — where required (e.g., certain cookies or marketing);
- **Legal obligation** — where we must retain or disclose information.

For self-hosted Customer Data, **you** determine legal bases for your processing.

---

## 5. Sharing of information

We may share information we control with:

- **Service providers** (hosting, email, payments, analytics, error monitoring) under contractual confidentiality and use limits;
- **Professional advisors** (lawyers, accountants) under confidentiality;
- **Authorities** when required by law or to protect rights and safety;
- **Business transfers** (merger, acquisition, asset sale) subject to appropriate safeguards.

We do **not** sell personal information as defined by the CCPA “sale” concept for monetary consideration as a core business practice. We do not share your Deployment’s chat content with third parties unless you configure your system to do so.

---

## 6. International transfers

Platform Services may be hosted in the United States or other countries. Where required, we use appropriate transfer mechanisms for data we control. For self-hosted Deployments, **you** control where data resides.

---

## 7. Retention

- **License and billing records:** retained as needed for contract, tax, and dispute purposes;
- **Security logs:** retained for a limited operational period unless needed longer for investigations;
- **Website analytics:** per tool configuration;
- **Your Deployment data:** retained solely under **your** policies—Knonix cannot delete data on servers we do not operate.

---

## 8. Security

We implement administrative and technical measures designed to protect Platform Services we operate. **No method of transmission or storage is 100% secure.**  

**You are solely responsible for securing your Deployments** (patching, secrets, network exposure, backups, access control).  

**To the maximum extent permitted by law, Knonix disclaims liability for security incidents, unauthorized access, or data loss in your environment or resulting from your configuration**, as further set out in the [Terms of Use](./TERMS_OF_USE.md).

---

## 9. Your privacy rights

### 9.1 Data held by Knonix (Platform Services / sales)

Depending on your location, you may have rights to access, correct, delete, or export personal data, or to object to certain processing. Contact **sales@knonix.com**. We may verify identity before acting.

### 9.2 Data held only in your Deployment

Requests about chat history, uploaded files, or user accounts **inside your install** must be directed to **your organization’s administrator**. Knonix generally **cannot** access or delete that data.

### 9.3 California (CCPA/CPRA) summary

For personal information Knonix collects as a business about California residents (e.g., website or sales leads): categories may include identifiers and internet activity; sources include you and your devices; purposes are as in Section 3; sharing is as in Section 5. We do not sell personal information for money. To exercise rights, contact sales@knonix.com.

---

## 10. Children’s privacy

The Services are not directed to children under 16 (or higher age if required). We do not knowingly collect personal information from children for Platform Services. Enterprise Deployments are for organizational use under your policies.

---

## 11. Third-party links and integrations

Documentation and the product may link to third parties (model providers, Microsoft, Google, Docker, GitHub). Their privacy practices govern their services. Enabling connectors in **your** Deployment connects **your** tenant data under **your** OAuth consents and policies.

---

## 12. Government and sensitive data

If you process CUI or other sensitive government-related information:

- Keep it in **your** authorized boundary;
- Do **not** enable non-sovereign frontier APIs for that data unless your policy and contract allow;
- Do **not** paste CUI into support emails or public tickets;
- Heartbeats should remain non-content operational metadata only.

Knonix does not assume responsibility for your boundary architecture or marking failures.

---

## 13. Changes to this Policy

We may update this Policy by posting a new version with a revised “Last updated” date. Material changes may be highlighted in documentation or product notices. Continued use of Platform Services after the effective date constitutes acceptance where permitted by law.

---

## 14. Contact

**Knonix**  
Email: **sales@knonix.com**  

For privacy requests related to data Knonix holds, include “Privacy Request” in the subject line and sufficient detail to locate your information.

---

## 15. Relationship to Terms of Use

Use of the Software is also governed by the [Terms of Use](./TERMS_OF_USE.md), including **disclaimers of warranties**, **limitations of liability**, and **customer responsibility** for data loss and security. If there is a conflict about liability, the Terms of Use control.

---

**Related:** [Terms of Use](./TERMS_OF_USE.md) · [README](./README.md) · [CMMC_COMPLIANCE.md](./CMMC_COMPLIANCE.md)
