/* XAG Trust & Verification Layer — reusable, dependency-free.
 *
 * One central config (trust-config.json) drives:
 *   XAGTrust.status(entry)          -> XAGTrustStatus: current / expiring / expired / none
 *   XAGTrust.renderBadges(el, cfg)  -> XAGTrustBadges: only valid, official badges
 *   XAGTrust.renderFooter(el, cfg)  -> XAGTrustFooter: links + valid badges + Trust link
 *   XAGTrust.renderPassport(el,cfg) -> the /trust page (Trust Passport)
 *   XAGTrust.lastVerified(cfg)      -> most recent real check date (never hard-coded)
 *
 * Rules enforced here (see TRUST_RUNBOOK.md): nothing unverified is shown as
 * verified; expired verifications visibly expire; no overall "trust score";
 * scans are never called certifications; WCAG logo only when a level is
 * actually declared.
 */
(function () {
    'use strict';
    const SCRIPT_SRC = (document.currentScript && document.currentScript.src) || location.href;
    const CONFIG_URL = new URL('trust-config.json', SCRIPT_SRC).href;
    const DAY = 86400000;
    const EXPIRING_WINDOW_DAYS = 7;

    // Exact wording per earned status. Scans are never "certified".
    const STATUS_LABEL = {
        verified: 'Verified', scanned: 'Scanned', tested: 'Tested',
        security_verified: 'Security Verified', security_certificate: 'Security Certificate',
        domain_verified: 'Domain Verified', integrity_verified: 'Integrity Verified',
        sealed: 'Cryptographically Sealed', independently_checked: 'Independently Checked',
        not_yet_verified: 'Not yet verified'
    };
    const EARNED = new Set(Object.keys(STATUS_LABEL).filter(s => s !== 'not_yet_verified'));

    function esc(s) {
        return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    }
    function fmtDate(iso) {
        if (!iso) return '';
        const d = new Date(iso + (iso.length === 10 ? 'T00:00:00' : ''));
        return isNaN(d) ? '' : d.toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' });
    }
    function safeUrl(u) { return u && /^(https:\/\/|\/)/.test(u) ? u : null; }

    // XAGTrustStatus
    function status(entry, now) {
        now = now || Date.now();
        if (!entry || !EARNED.has(entry.status) || !entry.checkedDate) {
            return { state: 'none', label: 'Not yet verified', icon: '○' };
        }
        const age = Math.floor((now - new Date(entry.checkedDate + 'T00:00:00').getTime()) / DAY);
        const valid = entry.validityDays || 30;
        const base = STATUS_LABEL[entry.status];
        if (age > valid) return { state: 'expired', label: 'Verification expired', icon: '🔴', base, age };
        if (age > valid - EXPIRING_WINDOW_DAYS) return { state: 'expiring', label: 'Verification due', icon: '🟡', base, age };
        return { state: 'current', label: base, icon: '🟢', base, age };
    }

    // Latest independent-provider verification date (null if none).
    function lastIndependent(cfg) {
        return (cfg.providers || []).filter(p => status(p).state !== 'none').map(p => p.checkedDate).sort().pop() || null;
    }
    // Latest date of any real check (providers, internal checks, history).
    function lastVerified(cfg) {
        const dates = [];
        (cfg.providers || []).forEach(p => { if (status(p).state !== 'none') dates.push(p.checkedDate); });
        (cfg.internalChecks || []).forEach(c => c.date && dates.push(c.date));
        (cfg.history || []).forEach(h => h.date && dates.push(h.date));
        if (cfg.accessibility && cfg.accessibility.checkedDate) dates.push(cfg.accessibility.checkedDate);
        return dates.sort().pop() || null;
    }

    // XAGTrustBadges: official badge images only, only while current or due.
    function badgesHtml(cfg) {
        const out = [];
        (cfg.providers || []).forEach(p => {
            const st = status(p);
            if (!p.badge || !p.badge.src || (st.state !== 'current' && st.state !== 'expiring')) return;
            const href = safeUrl(p.verificationUrl);
            const img = `<img src="${esc(p.badge.src)}" alt="${esc(p.badge.alt || p.name + ' ' + st.base)}" height="${p.badge.height || 28}" loading="lazy">`;
            out.push(href ? `<a href="${esc(href)}" target="_blank" rel="noopener">${img}</a>` : img);
        });
        const a = cfg.accessibility || {};
        if (['A', 'AA', 'AAA'].includes(a.level) && a.status === a.level && a.logo) {
            out.push(`<a href="${esc(a.logoLink || 'https://www.w3.org/WAI/standards-guidelines/wcag/conformance-logos/')}" target="_blank" rel="noopener"><img src="${esc(a.logo)}" alt="WCAG 2.2 ${esc(a.level)} conformance logo" height="31"></a>`);
        }
        return out.join(' ');
    }
    function renderBadges(el, cfg) { if (el) el.innerHTML = badgesHtml(cfg); }

    // XAGTrustFooter
    function renderFooter(el, cfg) {
        if (!el) return;
        const L = cfg.links || {};
        const links = [
            L.privacy && `<a href="${esc(L.privacy)}">Privacy</a>`,
            L.terms && `<a href="${esc(L.terms)}">Terms</a>`,
            L.accessibilityStatement && `<a href="${esc(L.accessibilityStatement)}">Accessibility</a>`,
            `<a href="${esc(cfg.trustUrl || '/trust/')}"><b>Trust &amp; Verification →</b></a>`
        ].filter(Boolean);
        const badges = badgesHtml(cfg);
        el.innerHTML = `<div class="xag-trust-footer">
            <div>© XAG · ${links.join(' · ')}</div>
            ${badges ? `<div class="xag-trust-badges">${badges}</div>` : ''}
        </div>`;
    }

    // Live self-check, run in the visitor's browser each time (not stored).
    async function liveSelfCheck() {
        const rows = [];
        rows.push({ ok: location.protocol === 'https:', label: 'Connection uses HTTPS' });
        try {
            const r = await fetch('/', { cache: 'no-store' });
            const h = n => r.headers.get(n);
            rows.push({ ok: !!h('strict-transport-security'), label: 'HSTS (always use HTTPS)' });
            rows.push({ ok: !!h('content-security-policy'), label: 'Content Security Policy' });
            rows.push({ ok: (h('x-content-type-options') || '').toLowerCase() === 'nosniff', label: 'MIME-sniffing protection' });
            rows.push({ ok: !!h('x-frame-options') || /frame-ancestors/.test(h('content-security-policy') || ''), label: 'Clickjacking protection' });
            rows.push({ ok: !!h('referrer-policy'), label: 'Referrer policy' });
        } catch (e) { rows.push({ ok: false, label: 'Security headers (could not be read)' }); }
        try {
            const probes = ['/CLAUDE.md', '/map_live_schema_snapshot.sql', '/.env', '/.git/HEAD'];
            const res = await Promise.all(probes.map(p => fetch(p, { cache: 'no-store', method: 'HEAD' }).then(x => x.status).catch(() => 0)));
            rows.push({ ok: res.every(s => s === 404 || s === 403), label: 'Internal project files not publicly downloadable' });
        } catch (e) { /* ignore */ }
        return rows;
    }

    function section(icon, title, bodyHtml, statusHtml) {
        return `<section class="xt-sec"><h2><span aria-hidden="true">${icon}</span> ${esc(title)}</h2>${statusHtml || ''}${bodyHtml}</section>`;
    }
    function pill(st) {
        const cls = { current: 'ok', expiring: 'due', expired: 'bad', none: 'none' }[st.state];
        const text = st.state === 'expired' || st.state === 'expiring' ? `${st.label} (${st.base})` : st.label;
        return `<span class="xt-pill xt-${cls}">${st.icon} ${esc(text)}</span>`;
    }
    function providerRow(p) {
        const st = status(p);
        const href = safeUrl(p.verificationUrl);
        const extra = [
            p.score != null && `Score: ${esc(p.score)}`,
            p.grade && `Grade: ${esc(p.grade)}`,
            p.certificateId && `Certificate ID: ${esc(p.certificateId)}`,
            st.state !== 'none' && `Last checked: ${fmtDate(p.checkedDate)}`
        ].filter(Boolean).join(' · ');
        return `<li><b>${esc(p.name)}</b> ${pill(st)}${p.kind ? `<div class="xt-meta">${esc(p.kind)}</div>` : ''}
            ${extra ? `<div class="xt-meta">${extra}</div>` : ''}
            ${href && st.state !== 'none' ? `<a href="${esc(href)}" target="_blank" rel="noopener">View verification →</a>` : ''}</li>`;
    }

    // Trust Passport (/trust)
    async function renderPassport(el, cfg) {
        if (!el) return;
        const last = lastVerified(cfg);
        const sec = (cfg.providers || []).filter(p => p.category === 'security');
        const dom = (cfg.providers || []).filter(p => p.category === 'domain');
        const anySecCurrent = sec.some(p => status(p).state === 'current');
        const internalSec = (cfg.internalChecks || []).filter(c => c.area === 'security');
        const a = cfg.accessibility || {};
        const aLabel = ['A', 'AA', 'AAA'].includes(a.status) ? `WCAG 2.2 ${a.status} Conformance (declared by XAG)`
            : a.status === 'testing' ? 'Testing in progress (not yet established)' : 'Not yet tested';
        const ev = a.evaluation || {};
        const evLabel = v => ({ done: '✓ done', partial: '◐ partial', not_done: '○ not yet' }[v] || '○ not yet');
        const P = cfg.privacy || {}, PI = P.items || {};
        const tick = b => b ? '✓' : '○';
        const I = cfg.integrity || {};
        const history = [
            ...(cfg.internalChecks || []).map(c => ({ date: c.date, text: `${c.summary} (XAG internal check)` })),
            ...(cfg.providers || []).filter(p => status(p).state !== 'none').map(p => ({ date: p.checkedDate, text: `${p.name}: ${STATUS_LABEL[p.status]}` })),
            ...(cfg.history || [])
        ].filter(h => h.date).sort((x, y) => y.date.localeCompare(x.date));

        el.innerHTML = `
        <header class="xt-head">
            <div class="xt-kicker">XAG</div>
            <h1>${esc(cfg.appName)}</h1>
            <p class="xt-sub">Trust &amp; Verification: a transparent record of the security, accessibility, privacy, domain and integrity checks for this application.</p>
            <p class="xt-last">${lastIndependent(cfg)
                ? `Last verified: <b>${fmtDate(lastIndependent(cfg))}</b>`
                : `Last reviewed: <b>${last ? fmtDate(last) : 'Not yet reviewed'}</b> <small>(XAG internal checks; no independent verification yet)</small>`}</p>
        </header>

        <nav class="xt-summary" aria-label="Current status">
            <div><span aria-hidden="true">🛡</span> Security<br><b>${anySecCurrent ? 'Verified by an independent provider' : 'Tested by XAG · external verification pending'}</b></div>
            <div><span aria-hidden="true">♿</span> Accessibility<br><b>${esc(aLabel)}</b></div>
            <div><span aria-hidden="true">🔐</span> Privacy<br><b>${PI.privacyPolicy ? 'Privacy information available' : 'Privacy policy in preparation'}</b></div>
            <div><span aria-hidden="true">✓</span> Domain<br><b>${dom.some(p => status(p).state === 'current') ? 'Domain ownership verified' : 'Not yet verified'}</b></div>
            <div><span aria-hidden="true">🔏</span> Integrity<br><b>${(I.artifacts || []).length ? 'Selected artifacts sealed' : 'Not yet sealed'}</b></div>
        </nav>

        ${section('🛡', 'Security', `
            <h3>Live self-check <small>(run in your browser just now)</small></h3>
            <ul class="xt-list" id="xt-live"><li>Checking…</li></ul>
            <h3>Independent providers</h3>
            <ul class="xt-list">${sec.map(providerRow).join('')}</ul>
            <h3>XAG internal checks</h3>
            <ul class="xt-list">${internalSec.map(c => `<li>${fmtDate(c.date)}: ${esc(c.summary)}</li>`).join('') || '<li>None recorded</li>'}</ul>
            <p class="xt-note">Automated scans and badges are dated records of specific checks. They are not audits, penetration tests or guarantees that an application is secure.</p>`)}

        ${section('♿', 'Accessibility', `
            <p>Standard: <b>${esc(a.standard || 'WCAG 2.2')}</b> · Status: <b>${esc(aLabel)}</b></p>
            <ul class="xt-list">
                <li>Automated checks: ${evLabel(ev.automated)}</li>
                <li>Keyboard testing: ${evLabel(ev.keyboard)}</li>
                <li>Responsive testing: ${evLabel(ev.responsive)}</li>
                <li>Human review: ${evLabel(ev.humanReview)}</li>
            </ul>
            ${cfg.links && cfg.links.accessibilityStatement ? `<a href="${esc(cfg.links.accessibilityStatement)}">View accessibility statement →</a>` : ''}
            <p class="xt-note">${esc(a.note || '')}</p>`)}

        ${section('🔐', 'Privacy', `
            <ul class="xt-list">
                <li>${tick(PI.privacyPolicy)} Privacy policy</li>
                <li>${tick(PI.termsOfUse)} Terms of use</li>
                <li>${tick(PI.dataUseInformation)} Data-use information</li>
                <li>${tick(PI.thirdPartyServicesDisclosed)} Third-party services disclosed</li>
                <li>${tick(PI.accountDeletionProcess)} Account and data deletion process</li>
            </ul>
            ${(P.thirdPartyServices || []).length ? `<p>Third-party services used: ${P.thirdPartyServices.map(esc).join('; ')}.</p>` : ''}
            ${cfg.links && cfg.links.privacy ? `<a href="${esc(cfg.links.privacy)}">View Privacy Policy →</a>` : '<p class="xt-note">The full privacy policy is being prepared.</p>'}`)}

        ${section('✓', 'Domain ownership', `<ul class="xt-list">${dom.map(providerRow).join('')}</ul>`)}

        ${section('🔏', 'Content & software integrity', `
            ${(I.artifacts || []).length ? `<ul class="xt-list">${I.artifacts.map(x => `<li><b>${esc(x.name)}</b>: ${esc(x.status === 'sealed' ? 'Cryptographically Sealed' : x.status)}${x.provider ? ' by ' + esc(x.provider) : ''}${x.date ? ', ' + fmtDate(x.date) : ''} ${safeUrl(x.proofUrl) ? `<a href="${esc(x.proofUrl)}" target="_blank" rel="noopener">Verify integrity →</a>` : ''}</li>`).join('')}</ul>`
                : '<p>No artifacts have been sealed yet.</p>'}
            <p class="xt-note">${esc(I.note || '')}</p>`)}

        ${section('📋', 'Verification history', `<ol class="xt-hist">${history.map(h => `<li><b>${fmtDate(h.date)}</b>: ${esc(h.text)}</li>`).join('') || '<li>No entries yet</li>'}</ol>`)}

        <p class="xt-note xt-foot">This page shows individual evidence categories rather than a single score: a security scan does not establish accessibility, and a domain check does not establish security. Entries without evidence are shown as "Not yet verified".</p>`;

        const live = await liveSelfCheck();
        const ul = el.querySelector('#xt-live');
        if (ul) ul.innerHTML = live.map(r => `<li>${r.ok ? '✓' : '✗'} ${esc(r.label)}</li>`).join('');
    }

    async function load(url) {
        const r = await fetch(url || CONFIG_URL, { cache: 'no-store' });
        if (!r.ok) throw new Error('trust config not found');
        return r.json();
    }
    // Machine-readable summary for the XAG App Manager Trust Center.
    function summary(cfg) {
        const sec = (cfg.providers || []).filter(p => p.category === 'security');
        const dom = (cfg.providers || []).filter(p => p.category === 'domain');
        return {
            appName: cfg.appName, appId: cfg.appId, productionUrl: cfg.productionUrl, trustUrl: cfg.trustUrl,
            security: sec.some(p => status(p).state === 'current') ? 'verified' : 'tested_internal',
            accessibility: (cfg.accessibility || {}).status || 'not_tested',
            privacy: (cfg.privacy || {}).status || 'unknown',
            domain: dom.some(p => status(p).state === 'current') ? 'verified' : 'not_yet_verified',
            integrity: ((cfg.integrity || {}).artifacts || []).length ? 'sealed_artifacts' : 'not_yet_sealed',
            expired: (cfg.providers || []).filter(p => status(p).state === 'expired').map(p => p.id),
            lastIndependentVerification: lastIndependent(cfg),
            lastReviewed: lastVerified(cfg)
        };
    }

    window.XAGTrust = { load, status, lastVerified, lastIndependent, renderBadges, renderFooter, renderPassport, liveSelfCheck, summary, fmtDate };
})();
