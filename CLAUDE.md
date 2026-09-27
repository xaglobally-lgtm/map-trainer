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
  - participants also have teacher-only `teacher_paused`, `extra_seconds`, `reset_count` (column privileges: clients may UPDATE only `status, current_question_index, current_rit, last_seen_at`; teacher changes go through `teacher_control_participant()`)
- `edu_assignments` — assigned practice (class-wide, or one student via `student_id`); completion = a finished `map_test_sessions` row in that mode after `created_at`
- Practice (Training) completions are synced to `map_test_sessions` with `practice_only = true` (since 2026-09-27); gamification/`fetchCloudHistory` and leaderboards exclude them
- Key SECURITY DEFINER functions (execute: `authenticated` only, not `anon`): `current_plan()`, `is_class_member/teacher()`, `is_session_participant/teacher()`, `my_class_count()`, `join_class_by_code()`, `join_group_session()`, `get_class_leaderboard()`, `get_live_leaderboard()`, `teacher_control_participant()`, `get_assignment_progress()`, `get_class_analytics()`
- **Important constraint:** this Supabase project is shared with other apps. Never touch tables without the `map_`/`edu_` prefix. Auth → URL Configuration → Redirect URLs must keep `https://map-trainer-six.vercel.app/**` — do not touch Site URL (it belongs to another app on the same project).
- Get the anon key from Supabase dashboard → Settings → API (already wired into `index.html` — don't need to repaste unless rotating). Never expose the service role key client-side.

## Verified content count (2026-09-27, via Node vm harness — not estimated)
- Main bank (`FRAMES`, A1–C2, 59 frames): 68,553 variants; Bloom's (`BLOOM_FRAMES`): 88; **total 68,641** (as of the content-depth PR). Passage sets: 11 templates (A1 and C2 now have 3 each).
- Down from 85,169 on 2026-09-26 **on purpose**: the content audit removed incoherent slot combinations (vocab words paired with contradicting contexts, verb × topic Bloom nonsense like "Implement the weather"). Every remaining variant should make sense.
- **Content rule:** slots that must agree (word ↔ context sentence, weather ↔ action, place ↔ animal, verb ↔ prompt) are stored together as one bundle, never as independent slots.
- **Label rule:** skill modes filter on `type === 'Vocabulary'` and on `ccss` starting with `RI` (Informational) or `RL` (Literary). Label by the *text type* (story vs nonfiction), not the question type — a story tagged `RI` leaks into Informational mode.

## Progress (approximate — judgement estimates, not measured)
- **Core app (content/modes/gamification/monetization): ~86%**. Remaining: F (double coherent variants), backlog.
- **MAP Connect: ~85%**
  - D — live session core: **~92%** (only the real two-device test remains).
  - E — teacher control room: **~80%** built 2026-09-27 (per-student pause / +5 min / reset, class dashboard with analytics + intervention suggestions, assigned practice with completion tracking, student "Assigned by your teacher" card). UI verified in-browser with mocked data; **not yet exercised with real teacher + student accounts**.
- **Overall product: ~82%**

## What's built (don't rebuild)
Simulation/Training mode split, adaptive RIT/Lexile/CEFR engine, 4-tier plans (free/pro/educator/connect) with server-enforced caps (2 classes/educator, 40 students/class), one-time `trial_20` mode, cloud+local gamification (XP/levels/ranks/badges/certificates/weekly mission/smart recommendation — all derived live from history, nothing stored as counters), async leaderboards, enhanced results screen (strengths/next-target/recommended practice), MAP Connect v1 (host + join + realtime board + heartbeat + pause/resume/end), question progress track, skill-mode nearest-level fallback (`nearestSkillLevel`).

## What's next (pick up here, in order)
1. **Real two-device test (user)** — now covers D *and* E. Teacher (`plan='connect'`, one exists) + student on another device/email:
   - Live: join shows ≤1s; Start auto-starts student; answers update board; session Pause/Resume; per-student ⏸/▶, +5m (student sees notice, timer grows), ↺ reset (two clicks; student restarts at Q1); student reload rejoins; closed tab 🔴 ~1s; End.
   - Class dashboard (Account → class → 📊 Dashboard): student appears after joining the class; suggestions; assign practice → student sees "📌 Assigned by your teacher" → completes it → teacher sees x/y done.
   - While it runs, query `edu_group_participants` / `edu_assignments` to separate realtime problems from write/RLS problems.
2. **F — double *coherent* variants** band by band by adding bundles; re-verify with the harness. Thinnest: C2 (5 frames), C1 vocab (1 frame), B2/C1/C2 vocab banks (8–10 words).
3. Backlog: dedicated Student Profile page; more leaderboard types/seasons; daily/skill-specific missions; finer `SKILL_FILTERS` (e.g. Inference) so suggestions/“Practice this” can target a single skill; real SMTP (Resend) before school launch; curated offline image art bank.

Done 2026-09-27 (for history): PRs #1–#3 merged; migrations `map_connect_faster_disconnect`, `map_teacher_controls`, `map_class_analytics_ccss`, `map_revoke_anon_function_execute` applied via `apply_migration`; content-depth items from the audit; E built.

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
Three migrations listed above were run in the SQL editor and never committed (`map_backend_schema.sql`, `map_schema_rename_migration.sql`, `map_connect_v1_migration.sql`). They are not in Supabase's migration history either, so they can't be recovered verbatim. `map_live_schema_snapshot.sql` (reconstructed from the live catalog 2026-09-26, pglast-checked) records every `map_`/`edu_` object as it existed then; **`map_teacher_controls.sql` (2026-09-27) applies on top of it**. Treat it as authoritative over the individual migration files. Going forward, apply new migrations via the Supabase MCP `apply_migration` (so they land in migration history) **and** commit the `.sql` file.
- Extra tables not in the schema list above: `map_history_points`, `map_flagged_questions` (owner-only RLS).
- `edu_class_members` / `edu_group_participants` have no INSERT policy on purpose: rows are created only via the `join_class_by_code` / `join_group_session` RPCs.
