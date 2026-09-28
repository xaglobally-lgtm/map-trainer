# XAG Trust & Verification Runbook

The framework is built and live-ready. Every external provider shows **"Not yet verified"** until you complete its steps below and record the real result. Nothing is ever faked: no scores, IDs, dates or badges that a provider did not issue.

## How the pieces fit

| Piece | File | What it does |
|---|---|---|
| Central config | `trust/trust-config.json` | The single source of truth. Edit only with real evidence. |
| Library | `trust/xag-trust.js` | `XAGTrust.status` (XAGTrustStatus), `renderBadges` (XAGTrustBadges), `renderFooter` (XAGTrustFooter), `renderPassport`, `summary` |
| Trust Passport | `trust/index.html` → `/trust/` | Public page: Security, Accessibility, Privacy, Domain, Integrity, History, plus a live self-check in the visitor's browser |
| App footer | `index.html` | "Trust & Verification →" link (Settings and results screen) and a badge slot that shows only current, official badges |
| Monitor | `trust/check.mjs` (not deployed) | `node trust/check.mjs` or `--json`; exit 1 on any FAIL |
| App Manager feed | `https://<app>/trust/trust-config.json` | The Trust Center reads this file; `XAGTrust.summary(cfg)` gives a one-line status per app |

**Status rules (automatic):** a provider entry counts only with an earned status *and* a `checkedDate`.
- 🟢 **Current**: within `validityDays` (default 30).
- 🟡 **Verification due**: in the last 7 days of validity.
- 🔴 **Verification expired**: past validity. Its badge is removed from the app automatically.

"Last verified" on the page uses only independent-provider dates. Until there are any, the page says "Last reviewed … (XAG internal checks)". There is no overall trust score, by design.

## Recording a real result (every provider)

1. Run the provider's check (steps below).
2. In `trust/trust-config.json`, find the provider and set:
   - `status`, using exact wording keys only:

     | Key | Shown as |
     |---|---|
     | `verified` | Verified |
     | `scanned` | Scanned |
     | `tested` | Tested |
     | `security_verified` | Security Verified |
     | `security_certificate` | Security Certificate |
     | `domain_verified` | Domain Verified |
     | `integrity_verified` | Integrity Verified |
     | `sealed` | Cryptographically Sealed |
     | `independently_checked` | Independently Checked |

   - `checkedDate` (YYYY-MM-DD, the date on the provider's report);
   - `verificationUrl` (the provider's public verification page);
   - `score`, `grade` and `certificateId` only if the provider actually issued them;
   - `badge`: `{ "src": "<official badge image URL or /trust/badges/file.svg>", "alt": "…" }`. Only an official badge the provider supplied.
3. Add a line to `history`: `{ "date": "YYYY-MM-DD", "text": "LaunchGuard: Verified certificate issued (score 86)" }`.
4. **CSP:** if the badge image or script loads from the provider's domain, add that domain to `img-src` (or `script-src`) in `vercel.json`. Otherwise the browser blocks it. Prefer downloading the official image into `trust/badges/` when the provider's terms allow.
5. Run `node trust/check.mjs`. The "Config honesty" checks must pass.
6. Commit, push, merge. Vercel deploys.

Never write "certified", "fully secure", "guaranteed", "hack-proof" or "compliant" unless a provider issued exactly that. An automated scan is "Scanned", never "Certified".

## Provider procedures

Order: security first (steps 1–4), then domain, accessibility, privacy, integrity.

1. **LaunchGuard** (security scan and Verified certificate): scan the production URL. A certificate needs a score of 80+ and no open critical or high findings. Fix the findings, rescan, then record `status: security_certificate` with the real `score`, `grade`, `certificateId` and verification link.
2. **Veriify** (HTTPS/TLS/headers/email): run it on the domain and fix what it flags. Email checks (SPF/DKIM/DMARC) need the custom domain and email. Record as `scanned` or `verified`, per what the report says.
3. **ClearAudit** and **Trusted Origin** (technical, SSL, DNS, reputation): run them, fix issues, record the results. Show a badge only if one was issued.
4. **Sentrio** (security/privacy/accessibility scan): record the security result here. Accessibility findings go into `accessibility.evaluation.automated`; they are *not* a WCAG claim.
5. **AcuityScan** (pre-release testing): run it before each major release. Keep it as an internal record (`tested`) unless it provides an official public badge.
6. **xlogs** (scan and domain verification badge): **needs the custom domain.** Verify ownership as xlogs instructs (DNS record or file), install its badge snippet, then add its domain to the CSP. Record xlogs, and also set the `domain` entry to `domain_verified` with the same date.
7. **W3C / WCAG 2.2** (accessibility): the W3C does not certify. We may *declare* a level only after a full evaluation:
   - automated checks (WAVE/axe or Sentrio);
   - keyboard-only walkthrough of every screen;
   - screen-reader check;
   - zoom to 200% and 400% (reflow);
   - colour contrast;
   - a human review.

   Then set `accessibility.status` to `"AA"` (for example), `level` to `"AA"`, `evaluation.humanReview` to `"done"`, and add `logo` (the official W3C conformance logo file) and `accessibilityStatement` in `links`. The monitor fails if a level is declared without human review.
8. **Let's Seal** (integrity): seal individual artifacts, not "the app". Good candidates are the Language Usage question bank JSON, the reading templates, and certificate PDFs. Add each to `integrity.artifacts`: `{ "name": "Language Usage bank v1", "status": "sealed", "provider": "Let's Seal", "date": "YYYY-MM-DD", "proofUrl": "https://…" }`.
9. **Privacy** (no provider): when the privacy policy, terms and deletion process exist, set the `privacy.items` flags to true, add the URLs in `links`, and change `privacy.status` to `"published"`. The footer shows the links automatically once they are set.

## Monitoring schedule

- **Daily:** `node trust/check.mjs`. It covers availability, HTTPS redirect, certificate expiry (WARN under 14 days), security headers, exposed internal files, the trust page, config honesty and verification expiry. It can be scheduled (Task Scheduler, a Claude scheduled task, or CI) and any FAIL raised as an alert.
- **Weekly:** review WARNs; any provider in 🟡 "Verification due" gets re-run that week.
- **Monthly (every 30 days):** re-run each provider you use and update `checkedDate`. Rerun the database access-control test. Add a `history` line.
- **On every release:** AcuityScan, plus `node trust/check.mjs` after the deploy.

## Adding another XAG app

Copy the `trust/` folder and the headers in `vercel.json` (adjust `connect-src` for that app's backend), plus `.vercelignore`. Edit `appName`, `appId`, `productionUrl` and `thirdPartyServices`, reset `internalChecks` and `history`, and add the footer link. PlanetOS and FamilyOS are excluded from this layer.

## Hard rules

- No fake or placeholder badges, scores, IDs or dates. Unverified means "Not yet verified".
- Expired stays visibly expired until re-verified; never silently bump dates.
- Categories stay separate: a security scan does not establish accessibility, and a domain check does not establish security.
- No combined trust score.
- Internal files (`*.md`, `*.sql`, `trust/check.mjs`) never deploy (`.vercelignore`); the monitor verifies it.
