#!/usr/bin/env node
// XAG Trust monitor. Node 18+, no dependencies. Not deployed (see .vercelignore).
//   node trust/check.mjs                      -> checks the productionUrl in trust-config.json
//   node trust/check.mjs https://example.com  -> checks another deployment
//   node trust/check.mjs --json               -> machine-readable output (App Manager / CI)
// Exit code 1 if anything FAILs. WARN = needs attention soon (expiring certificate or verification).
// Suggested schedule (TRUST_RUNBOOK.md): daily run; weekly review of WARNs; monthly provider re-verification.
import { readFileSync } from 'node:fs';
import tls from 'node:tls';

const args = process.argv.slice(2);
const asJson = args.includes('--json');
const cfg = JSON.parse(readFileSync(new URL('./trust-config.json', import.meta.url), 'utf8'));
const base = (args.find(a => /^https?:\/\//.test(a)) || cfg.productionUrl).replace(/\/$/, '');
const results = [];
const add = (level, check, detail) => results.push({ level, check, detail });
const DAY = 86400000;

// Bodies are always read (json/text), so sockets close cleanly on every server.
async function get(path, opts = {}) {
    const r = await fetch(base + path, { redirect: 'manual', ...opts, signal: AbortSignal.timeout(15000) });
    const body = await r.text();
    return { status: r.status, headers: r.headers, json: async () => JSON.parse(body) };
}

// 1. Availability
try {
    const t0 = Date.now();
    const r = await get('/');
    add(r.status === 200 ? 'PASS' : 'FAIL', 'Availability', `HTTP ${r.status} in ${Date.now() - t0} ms`);
    const h = n => r.headers.get(n);
    // 2. Security headers
    const want = {
        'strict-transport-security': v => /max-age=\d{7,}/.test(v),
        'content-security-policy': v => /default-src/.test(v) && /frame-ancestors/.test(v),
        'x-content-type-options': v => v.toLowerCase() === 'nosniff',
        'x-frame-options': v => /deny|sameorigin/i.test(v),
        'referrer-policy': v => !!v,
        'permissions-policy': v => !!v
    };
    for (const [k, ok] of Object.entries(want)) {
        const v = h(k);
        add(v && ok(v) ? 'PASS' : 'FAIL', `Header ${k}`, v ? v.slice(0, 80) : 'missing');
    }
} catch (e) { add('FAIL', 'Availability', e.message); }

// 3. HTTP -> HTTPS redirect
if (base.startsWith('https://')) {
    try {
        const r = await fetch(base.replace('https://', 'http://') + '/', { redirect: 'manual', signal: AbortSignal.timeout(15000) });
        await r.text();
        const loc = r.headers.get('location') || '';
        add(r.status >= 300 && r.status < 400 && loc.startsWith('https://') ? 'PASS' : 'FAIL', 'HTTP redirects to HTTPS', `HTTP ${r.status} -> ${loc || 'none'}`);
    } catch (e) { add('WARN', 'HTTP redirects to HTTPS', e.message); }

    // 4. TLS certificate expiry
    await new Promise(res => {
        const host = new URL(base).hostname;
        const s = tls.connect({ host, port: 443, servername: host, timeout: 15000 }, () => {
            const c = s.getPeerCertificate();
            const days = Math.floor((new Date(c.valid_to) - Date.now()) / DAY);
            add(!s.authorized ? 'FAIL' : days < 14 ? 'WARN' : 'PASS', 'TLS certificate',
                `${s.authorized ? 'valid' : 'NOT trusted: ' + s.authorizationError}, issuer ${c.issuer && c.issuer.O}, expires in ${days} days`);
            s.end(); res();
        });
        s.on('error', e => { add('FAIL', 'TLS certificate', e.message); res(); });
        s.on('timeout', () => { add('FAIL', 'TLS certificate', 'timeout'); s.destroy(); res(); });
    });
}

// 5. Internal files must not be public
for (const p of ['/CLAUDE.md', '/LAUNCH_SETUP.md', '/TRUST_RUNBOOK.md', '/map_live_schema_snapshot.sql', '/trust/check.mjs', '/.env', '/.git/HEAD']) {
    try {
        const r = await get(p);
        add(r.status === 404 || r.status === 403 ? 'PASS' : 'FAIL', `Not public: ${p}`, `HTTP ${r.status}`);
    } catch (e) { add('WARN', `Not public: ${p}`, e.message); }
}

// 6. Trust page and config are published and match the local config
try {
    const r = await get('/trust/');
    add(r.status === 200 ? 'PASS' : 'FAIL', 'Trust page /trust/', `HTTP ${r.status}`);
    const rc = await get('/trust/trust-config.json');
    if (rc.status !== 200) add('FAIL', 'Trust config published', `HTTP ${rc.status}`);
    else {
        const live = await rc.json();
        const same = JSON.stringify(live) === JSON.stringify(cfg);
        add(same ? 'PASS' : 'WARN', 'Trust config published', same ? 'live copy matches local' : 'live copy differs from local (deploy pending?)');
    }
} catch (e) { add('FAIL', 'Trust page /trust/', e.message); }

// 7. Verification expiry (same rules as XAGTrustStatus)
const EARNED = s => s && s !== 'not_yet_verified';
for (const p of cfg.providers || []) {
    if (!EARNED(p.status) || !p.checkedDate) { add('INFO', `Provider ${p.name}`, 'Not yet verified'); continue; }
    const age = Math.floor((Date.now() - new Date(p.checkedDate + 'T00:00:00')) / DAY);
    const valid = p.validityDays || 30;
    add(age > valid ? 'FAIL' : age > valid - 7 ? 'WARN' : 'PASS', `Provider ${p.name}`,
        `${p.status}, checked ${p.checkedDate} (${age} days ago, valid ${valid})` + (age > valid ? ': EXPIRED, re-verify' : ''));
}
// 8. Honesty guards on the config itself
for (const p of cfg.providers || []) {
    if (!EARNED(p.status) && (p.score != null || p.grade || p.certificateId || (p.badge && p.badge.src) || p.checkedDate))
        add('FAIL', `Config honesty: ${p.name}`, 'unverified provider has a score/grade/ID/badge/date');
    if (EARNED(p.status) && !p.verificationUrl)
        add('WARN', `Config honesty: ${p.name}`, 'verified status without a public verification URL');
}
const a = cfg.accessibility || {};
if (['A', 'AA', 'AAA'].includes(a.status) && (a.evaluation || {}).humanReview !== 'done')
    add('FAIL', 'Config honesty: accessibility', `WCAG ${a.status} declared without human review`);

const fails = results.filter(r => r.level === 'FAIL').length;
const warns = results.filter(r => r.level === 'WARN').length;
if (asJson) {
    console.log(JSON.stringify({ app: cfg.appId, url: base, checkedAt: new Date().toISOString(), fails, warns, results }, null, 2));
} else {
    console.log(`XAG Trust monitor: ${cfg.appName} @ ${base}\n`);
    for (const r of results) console.log(`${r.level.padEnd(4)}  ${r.check}: ${r.detail}`);
    console.log(`\n${fails} fail, ${warns} warn`);
}
process.exitCode = fails ? 1 : 0;
