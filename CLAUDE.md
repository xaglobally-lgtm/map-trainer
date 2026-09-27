# MAP Trainer — Claude Code Handover

## What this is
NWEA MAP-style adaptive reading assessment PWA. Single-file HTML app (`index.html`) + Supabase backend. Currently deployed and live.

## Live infrastructure
- **Production URL:** https://map-trainer-six.vercel.app/
- **GitHub:** `xaglobally-lgtm/map-trainer`, `main` branch — Vercel auto-deploys on push
- **Supabase project:** "API Verifier LIVE", ref `iwpfhalextbzbvcajtxu` (shared with other apps — see namespacing below)
- **Local working folder (yours):** `C:\Users\user\Downloads\BUILDS\MAP\map-trainer`

## Repo structure
- `index.html` — the entire app (HTML/CSS/JS in one file, ~715KB). Contains procedural question generation (`FRAMES` object, A1–C2 CEFR bands), adaptive scoring, gamification, monetization, MAP Connect live-session code.
- `manifest.json`, `sw.js` (service worker — **network-first for index.html**, cache-fallback for icons only, `CACHE_NAME` currently v2), `icon-192.png`, `icon-512.png`, `icon-maskable-512.png`.
- `*.sql` files — migrations, already applied to production in this order (do not re-run; keep as history):
  `map_backend_schema.sql` → `map_leaderboard_migration.sql` → `map_by_type_migration.sql` → `map_schema_rename_migration.sql` → `map_connect_schema.sql` → `map_architecture_fixes.sql` → `map_connect_v1_migration.sql`

## Supabase schema (current)
- `map_profiles` (id, display_name, role, use_nickname, nickname)
- `map_subscriptions` (plan: `free`/`pro`/`educator`/`connect`, read via `current_plan()`)
- `map_test_sessions` (+ `by_type jsonb`, `app_id` default `'map-reading'`)
- `edu_classes`, `edu_class_members` — cross-subject naming (shared with future non-Reading MAP apps)
- `edu_group_sessions`, `edu_group_participants` — MAP Connect live sessions, both in the `supabase_realtime` publication
- Key SECURITY DEFINER functions: `current_plan()`, `is_class_member/teacher()`, `is_session_participant/teacher()`, `my_class_count()`, `join_class_by_code()`, `join_group_session()`, `get_class_leaderboard()`, `get_live_leaderboard()`
- **Important constraint:** this Supabase project is shared with other apps. Never touch tables without the `map_`/`edu_` prefix. Auth → URL Configuration → Redirect URLs must keep `https://map-trainer-six.vercel.app/**` — do not touch Site URL (it belongs to another app on the same project).
- Get the anon key from Supabase dashboard → Settings → API (already wired into `index.html` — don't need to repaste unless rotating). Never expose the service role key client-side.

## Verified content count (2026-09-27, via Node vm harness — not estimated)
- Main bank (`FRAMES`, A1–C2, 59 frames): 68,553 variants; Bloom's (`BLOOM_FRAMES`): 88; **total 68,641** (as of the content-depth PR). Passage sets: 11 templates (A1 and C2 now have 3 each).
- Down from 85,169 on 2026-09-26 **on purpose**: the content audit removed incoherent slot combinations (vocab words paired with contradicting contexts, verb × topic Bloom nonsense like "Implement the weather"). Every remaining variant should make sense.
- **Content rule:** slots that must agree (word ↔ context sentence, weather ↔ action, place ↔ animal, verb ↔ prompt) are stored together as one bundle, never as independent slots.
- **Label rule:** skill modes filter on `type === 'Vocabulary'` and on `ccss` starting with `RI` (Informational) or `RL` (Literary). Label by the *text type* (story vs nonfiction), not the question type — a story tagged `RI` leaks into Informational mode.

## Progress (approximate — judgement estimates, not measured)
- **Core app (content/modes/gamification/monetization): ~86%**
  - 2026-09-27 PR #2 (merged): skill-mode routing fix, full content audit, Grade 1 vocabulary, progress track, phone layout.
  - 2026-09-27 content-depth PR: A1/A2 nonfiction frames (A1 Informational went 0 → 3 native frames), 2 new A1 sets + 2 new C2 sets, C1_structure now 5 structures, fair distractors for rhetoric / C2_eval / main idea / tone / C1–C2 vocab, set CCSS labelled by serving band.
  - Remaining: F (double coherent variants), backlog.
- **MAP Connect: ~45%**
  - D — live session core: **~92%**. 20s disconnect migration applied 2026-09-27. Only the real two-device test remains.
  - E — teacher control room extras: **0%**.
- **Overall product: ~70%**

## What's built (don't rebuild)
Simulation/Training mode split, adaptive RIT/Lexile/CEFR engine, 4-tier plans (free/pro/educator/connect) with server-enforced caps (2 classes/educator, 40 students/class), one-time `trial_20` mode, cloud+local gamification (XP/levels/ranks/badges/certificates/weekly mission/smart recommendation — all derived live from history, nothing stored as counters), async leaderboards, enhanced results screen (strengths/next-target/recommended practice), MAP Connect v1 (host + join + realtime board + heartbeat + pause/resume/end), question progress track, skill-mode nearest-level fallback (`nearestSkillLevel`).

## What's next (pick up here, in order)
1. **Real two-device MAP Connect test** — needs the user on two devices (can't be automated here). Teacher account needs `plan='connect'` (one exists); student on a second device with a different email. Checklist: join shows on teacher board ≤1s; Start auto-starts student; answers update teacher board; Pause/Resume; student reload rejoins; closed tab shows 🔴 in ~1s; End ends student test. While it runs, query `edu_group_participants` to separate realtime problems from write/RLS problems.
2. **E — teacher control room extras:** per-student pause/extend-time/reset-attempt, assign practice, class analytics, intervention suggestions. RLS lets a student update their own `edu_group_participants.status`, so per-student pause needs a teacher-only column (e.g. `teacher_paused`) or an RPC.
3. **F — double *coherent* variants** band by band by adding bundles (not independent slot values); re-verify with the harness after each pass. Thinnest areas: C2 (5 frames), C1 vocab (1 frame), B2/C1/C2 vocab banks (8–10 words each).
4. Deferred/backlog (not scheduled): dedicated Student Profile page, more leaderboard types/seasons, daily/skill-specific missions, curated offline image art bank, real SMTP (e.g. Resend) before school launch, a `SKILL_FILTERS` entry per finer skill (e.g. Inference) for the results screen's "Practice this" links.

Done 2026-09-27 (for history): PRs #1 and #2 merged; `map_connect_faster_disconnect` applied via `apply_migration` after deploy; content-depth items from the audit.

## Decisions already made (don't re-litigate)
- No live image-generation API. Illustrations are procedural SVG; a real "art bank" would need a defined photo-need list first and is its own project — deferred, not scheduled.
- Grade/RIT starting buttons (1–8) are never gated by plan — they only set adaptive test starting point, not access.
- Gamification is fully derived from test history (no stored XP/badge counters) so local and cloud users stay architecturally consistent.
- MAP Connect hub scope: build it Reading-specific for now; keep the schema (`edu_*` + `app_id`) ready for a future shared multi-subject hub, but don't build that hub yet.

## Known limitations (accepted, not bugs)
- Simulation paywall is client-side only (question generation runs in-browser, can't be server-enforced without a backend generation service).
- `map_test_sessions` inserts are self-reported — leaderboard scores are spoofable by a technical user.
- Supabase's built-in email is dev-only/rate-limited — needs real SMTP (e.g. Resend) before school launch.

## Verification method to keep using
Node `vm`-based sandbox: extract the `<script>` content from `index.html`, stub DOM/localStorage/etc. (an auto-mocking Proxy works well for anything not directly relevant), run it, then inspect exported objects (`FRAMES`, plan/paywall functions) directly rather than estimating. Also: `pglast` (Python) to parse-check every SQL migration before shipping it.

## Schema source of truth: `map_live_schema_snapshot.sql`
Three migrations listed above were run in the SQL editor and never committed (`map_backend_schema.sql`, `map_schema_rename_migration.sql`, `map_connect_v1_migration.sql`). They are not in Supabase's migration history either, so they can't be recovered verbatim. `map_live_schema_snapshot.sql` (reconstructed from the live catalog 2026-09-26, pglast-checked) records every `map_`/`edu_` object as it actually exists. Treat it as authoritative over the individual migration files. Going forward, apply new migrations via the Supabase MCP `apply_migration` (so they land in migration history) **and** commit the `.sql` file.
- Extra tables not in the schema list above: `map_history_points`, `map_flagged_questions` (owner-only RLS).
- `edu_class_members` / `edu_group_participants` have no INSERT policy on purpose: rows are created only via the `join_class_by_code` / `join_group_session` RPCs.
