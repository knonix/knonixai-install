# KnonixAI — Terms of Use

**Effective date:** July 12, 2026  
**Last updated:** July 12, 2026  

**Provider:** Knonix (“**Knonix**,” “**we**,” “**us**,” or “**our**”)  
**Contact:** sales@knonix.com  

These Terms of Use (“**Terms**”) govern your access to and use of **KnonixAI** software, container images, documentation, websites (including without limitation `ai.knonix.com` and related properties), licensing/fleet services, and any related support or materials (collectively, the “**Software**” or “**Services**”).

**By downloading, installing, configuring, accessing, or using the Software, you accept these Terms on behalf of yourself and the organization you represent.** If you do not agree, do not install or use the Software.

> **Not legal advice.** These Terms are a commercial agreement template. They do not create attorney–client advice. Have your counsel review them for your jurisdiction and contracts.

---

## 1. Definitions

- **“You” / “Customer”** means the individual and the company, agency, or other legal entity that installs or uses the Software.
- **“Install” / “Deployment”** means any self-hosted, on-premises, cloud-tenant, air-gapped, edge, or other instance of the Software that you operate.
- **“Customer Data”** means all data, content, prompts, documents, credentials, logs, models you load, CUI, regulated data, and other information processed by or stored in your Deployment, including data in databases, volumes, connectors, and backups you control.
- **“Platform Services”** means optional Knonix-operated services (e.g., license validation, fleet heartbeats, billing, documentation sites), as distinct from your self-hosted Deployment.

---

## 2. Nature of the product — self-hosted, use at your own risk

2.1 **You operate the stack.** KnonixAI is primarily **self-hosted software**. You (or your IT provider) install, configure, network, patch, back up, secure, and operate the Deployment on infrastructure **you** control or contract for.

2.2 **Use at your own risk.** The Software is provided for use **entirely at your own risk**. You assume **all** risk of installation, configuration, operation, integration, model behavior, third-party dependencies (including open-source models and containers), and outcomes of use.

2.3 **Not a managed security or compliance service.** Knonix does **not** act as your system owner, ISSO, C3PAO, cloud provider of record for your Deployments, or guarantor of CMMC, DFARS, FedRAMP, HIPAA, GDPR, or any other framework. Compliance and accreditation remain **your** sole responsibility.

2.4 **AI output is not advice.** Model outputs may be incorrect, incomplete, biased, or fabricated. They are **not** legal, security, engineering, medical, or professional advice. You must independently verify all outputs before reliance.

---

## 3. License grant and restrictions

3.1 **License.** Subject to these Terms and any separate license, order form, or commercial agreement, Knonix grants you a limited, non-exclusive, non-transferable (except as permitted in writing), revocable license to install and use the Software for your internal business purposes in accordance with documentation and seat/licensing limits.

3.2 **Seat and license compliance.** You must comply with free-tier limits, paid seats, offline licenses, and fleet enrollment terms. Circumventing seat metering, reverse engineering license checks for evasion, or redistributing keys is prohibited.

3.3 **Restrictions.** You will not (and will not allow others to):

- Use the Software in violation of law or the rights of others;
- Attempt unauthorized access to Knonix systems or other customers’ data;
- Remove proprietary notices;
- Resell, sublicense, or provide the Software as a competing hosted service except as Knonix expressly permits in writing;
- Use Platform Services to attack, probe, or overload Knonix infrastructure beyond normal use.

3.4 **Open-source and third-party components.** The Software may include third-party and open-source components under their own licenses. Those licenses govern those components; Knonix provides them **as incorporated**, without separate warranty from Knonix beyond these Terms.

3.5 **Model weights and providers.** Local models (e.g., via Ollama) and optional frontier APIs are third-party technologies. Their licenses, acceptable-use policies, pricing, and privacy practices apply. Enabling frontier/cloud APIs may send prompts **outside** your boundary—you alone decide when that is appropriate.

---

## 4. Accounts, access, and your responsibilities

4.1 **Your environment.** You are solely responsible for:

- Hardware, OS, Docker, networking, DNS, TLS, firewalls, and identity providers;
- Access control, roster management, MFA, secrets, encryption keys, and admin hygiene;
- Patching, upgrades, migrations, and configuration of `.env` and related settings;
- Backups, disaster recovery, business continuity, and tested restores;
- Monitoring, logging, SIEM, and incident response for **your** Deployment;
- All Customer Data classification, retention, deletion, and legal holds.

4.2 **Security.** You must implement security controls appropriate to your data sensitivity (including CUI and other regulated data). **Knonix is not liable for security breaches, ransomware, insider threat, misconfiguration, weak passwords, exposed ports, leaked API keys, supply-chain issues in your environment, or failure to patch.**

4.3 **Data loss.** You must maintain backups. **Knonix is not liable for any data loss, corruption, deletion, failed migration, volume loss, disk failure, or inability to restore Customer Data**, whether or not related to the Software.

4.4 **Credentials.** You are responsible for all activity under your accounts and Deployments. Notify us promptly of unauthorized use of Platform Services credentials we issue (e.g., fleet tokens), without implying any duty on us to remediate your Deployment.

4.5 **Acceptable use.** You will not use the Software to develop malware, violate export controls, engage in unlawful surveillance, or process data you are not authorized to process.

---

## 5. Platform Services (licensing, fleet, website)

5.1 **Optional connectivity.** Some features (license heartbeats, fleet enrollment, billing status) may send **limited operational metadata** to Knonix (see Privacy Policy). Self-hosted inference and Customer Data in your Deployment are intended to stay in **your** boundary unless **you** enable outbound tools or frontier APIs.

5.2 **No uptime guarantee for free or best-effort services.** Platform Services may be interrupted, changed, or discontinued. Knonix does not guarantee continuous availability of license servers, documentation sites, or container registries.

5.3 **Fleet and admin.** Fleet dashboards and cross-customer visibility are limited to Knonix’s platform environment and authorized personnel as described in product documentation—not to ordinary customer Deployments.

---

## 6. Intellectual property

6.1 **Knonix IP.** Knonix and its licensors retain all right, title, and interest in the Software, branding, and documentation, excluding Customer Data and third-party components.

6.2 **Customer Data.** As between you and Knonix, you retain rights in Customer Data. You grant Knonix only the rights needed to provide Platform Services you enable (e.g., process license heartbeats).

6.3 **Feedback.** If you provide feedback or suggestions, you grant Knonix a perpetual, royalty-free license to use them without obligation to you.

---

## 7. Disclaimers — no warranties

**TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW:**

7.1 **THE SOFTWARE AND SERVICES ARE PROVIDED “AS IS” AND “AS AVAILABLE,” WITH ALL FAULTS, AND WITHOUT WARRANTY OF ANY KIND.**

7.2 **KNONIX DISCLAIMS ALL WARRANTIES, WHETHER EXPRESS, IMPLIED, STATUTORY, OR OTHERWISE**, including but not limited to warranties of **merchantability**, **fitness for a particular purpose**, **title**, **non-infringement**, **quiet enjoyment**, **accuracy**, **completeness**, **reliability**, **security**, **uninterrupted or error-free operation**, and **compatibility** with your systems or requirements (including any government authorization to operate).

7.3 **KNONIX DOES NOT WARRANT** that the Software will:

- Detect, prevent, or withstand any cyber attack or breach;
- Meet CMMC, NIST, DFARS, FAR, FedRAMP, or any assessment objective;
- Produce correct SSP, POA&M, policy, or other compliance documents;
- Preserve data integrity or availability;
- Interoperate with Microsoft 365, Google, Ollama, Docker, or any third party without failure.

7.4 **No warranty from demos, marketing, or documentation.** Product pages, comparisons, GitHub docs, and sales materials are informational only and do not create warranties or service levels unless stated in a signed order form that expressly overrides these Terms.

---

## 8. Limitation of liability — no liability for listed harms

**TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW:**

8.1 **Exclusion of damages.** **KNONIX AND ITS OFFICERS, DIRECTORS, EMPLOYEES, AGENTS, SUPPLIERS, AND LICENSORS WILL NOT BE LIABLE FOR ANY:**

- **Indirect, incidental, special, consequential, exemplary, or punitive damages**;
- **Lost profits, revenue, goodwill, or business opportunity**;
- **Data loss, data corruption, or cost of reprocurement of data**;
- **Security breaches, unauthorized access, ransomware, malware, or disclosure of Customer Data** (including CUI or personal data);
- **Regulatory fines, failed assessments, contract loss, or suspension from government programs**;
- **Personal injury or property damage** arising from use of the Software;
- **Cost of substitute software or services**;
- **Downtime, delay, or failed backups/migrations**;
- **Model hallucinations, incorrect outputs, or decisions made in reliance on outputs**;
- **Third-party claims** arising from your use or your Customer Data;

**WHETHER BASED IN CONTRACT, TORT (INCLUDING NEGLIGENCE), STRICT LIABILITY, OR ANY OTHER THEORY, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGES, AND EVEN IF A REMEDY FAILS OF ITS ESSENTIAL PURPOSE.**

8.2 **Liability cap.** **TO THE MAXIMUM EXTENT PERMITTED BY LAW, KNONIX’S TOTAL AGGREGATE LIABILITY ARISING OUT OF OR RELATED TO THE SOFTWARE OR THESE TERMS WILL NOT EXCEED THE GREATER OF: (A) THE AMOUNTS YOU PAID TO KNONIX FOR THE SOFTWARE OR RELATED LICENSES IN THE TWELVE (12) MONTHS BEFORE THE CLAIM; OR (B) ONE HUNDRED U.S. DOLLARS (US $100).** If you use only free tiers and paid nothing, Knonix’s aggregate liability shall not exceed **US $100**.

8.3 **Allocation of risk.** These limitations allocate risk between you and Knonix and are a fundamental basis of the bargain. The Software would not be offered on the same terms without them.

8.4 **Jurisdictions that disallow some exclusions.** Some jurisdictions do not allow certain warranty disclaimers or liability limits. In those jurisdictions, Knonix’s liability is limited to the **minimum** extent required by law—but only for those non-waivable claims—and all waivable claims remain limited as above.

---

## 9. Indemnification by Customer

You will **defend, indemnify, and hold harmless** Knonix and its officers, directors, employees, agents, and licensors from and against any claims, damages, losses, liabilities, costs, and expenses (including reasonable attorneys’ fees) arising out of or related to:

- Your Deployment, configuration, or operation of the Software;
- Customer Data (including alleged infringement, privacy, or security claims);
- Your violation of law or these Terms;
- Your combination of the Software with other systems or data;
- Your failure to back up, secure, or authorize processing of data;
- Any claim by your employees, contractors, end users, or customers related to the Software or outputs;
- Export, sanctions, or government contracting obligations you fail to meet.

---

## 10. Government and regulated use

10.1 **Your compliance duties.** If you process CUI, classified-adjacent, ITAR, EAR, health, financial, or other regulated data, **you alone** must ensure lawful authority, marking, access control, continuous monitoring, and contractual flow-downs.

10.2 **No certification.** KnonixAI is **not** “CMMC certified software,” does not replace a C3PAO assessment, and does not guarantee SPRS scores, ATO, or authorization boundaries.

10.3 **Federal users.** If you are a U.S. government end user, the Software is commercial computer software under FAR/DFARS commercial item provisions as applicable; rights are only those customarily provided to the public under these Terms, except as mandatory federal law requires otherwise.

---

## 11. Export and sanctions

You will comply with U.S. and other applicable export control and sanctions laws. You will not permit use of the Software by prohibited parties or in prohibited jurisdictions.

---

## 12. Term and termination

12.1 These Terms apply while you possess or use the Software or Platform Services.

12.2 Knonix may suspend or terminate Platform Services or licenses for material breach, non-payment, legal risk, or abuse.

12.3 On termination, you must stop using Platform Services and paid features as required by your license. Sections that by nature should survive (including 2, 4, 6–11, 13–16) survive termination.

---

## 13. Governing law and disputes

13.1 **Governing law.** These Terms are governed by the laws of the **State of Delaware, USA**, excluding conflict-of-law rules, unless a signed order form specifies otherwise.

13.2 **Venue.** Exclusive venue for disputes shall be state or federal courts located in **Delaware**, unless mandatory law requires otherwise. Each party consents to personal jurisdiction there.

13.3 **Injunctions.** Nothing prevents either party from seeking injunctive relief for IP misuse or unauthorized access to systems.

13.4 **Informal resolution.** Before filing a claim, you agree to attempt good-faith resolution by contacting sales@knonix.com with a description of the dispute (without waiving limitation periods beyond what law allows).

---

## 14. Changes to Terms or Software

14.1 Knonix may update these Terms by posting a revised version (e.g., on GitHub installer docs or knonix.com). Continued use after the effective date constitutes acceptance, except where prohibited.

14.2 Knonix may modify, deprecate, or discontinue features. Self-hosted images you already run remain under your operational control subject to license validity.

---

## 15. Miscellaneous

15.1 **Entire agreement.** These Terms, plus any signed order form or enterprise agreement that expressly states it controls, are the entire agreement regarding the Software. If conflict exists, the signed enterprise agreement controls for that subject.

15.2 **Severability.** If any provision is unenforceable, the remainder stays in effect, and the provision will be modified to the minimum extent required.

15.3 **Waiver.** Failure to enforce a provision is not a waiver.

15.4 **Assignment.** You may not assign these Terms without Knonix’s consent, except to a successor in connection with a merger or sale of substantially all assets if the assignee agrees in writing. Knonix may assign to an affiliate or successor.

15.5 **Force majeure.** Knonix is not liable for delays or failures due to events beyond reasonable control (including cloud provider outages, war, natural disaster, internet failures, or labor disputes).

15.6 **No third-party beneficiaries.** Except for indemnified Knonix personnel under Section 9, there are no third-party beneficiaries.

15.7 **Notices.** Notices to Knonix: sales@knonix.com. Notices to you: email associated with your license or admin account, or posted documentation.

15.8 **Language.** English controls.

15.9 **Relationship.** Parties are independent contractors. These Terms do not create a partnership, joint venture, or employment relationship. Knonix is not your processor of Customer Data in self-hosted Deployments except as limited Platform Services you enable (see Privacy Policy).

---

## 16. Acknowledgment

**YOU ACKNOWLEDGE THAT YOU HAVE READ THESE TERMS, UNDERSTAND THEM, AND AGREE THAT:**

1. The Software is **use at your own risk**;  
2. **You** are solely responsible for security, backups, compliance, and Customer Data;  
3. **Knonix is not liable** for data loss, breaches, incorrect AI outputs, failed assessments, or consequential damages as limited herein; and  
4. The liability cap and disclaimers are material terms.

---

**Related:** [Privacy Policy](./PRIVACY_POLICY.md) · [README](./README.md) · [CMMC_COMPLIANCE.md](./CMMC_COMPLIANCE.md)
