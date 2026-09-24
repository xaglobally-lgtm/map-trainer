# MAP Trainer — State File

Paste this at the top of a new chat, or just say "follow the next step in the state file."

## What this is
Adaptive reading assessment simulator styled after NWEA MAP — now a live PWA with real accounts, and actively growing into a full "adaptive academic assessment and growth platform" (student gamification + school control room), per the product direction agreed this session.

## 🟢 LIVE
- **Production URL: https://map-trainer-six.vercel.app/**
- GitHub: `xaglobally-lgtm/map-trainer` (main branch) — Vercel auto-deploys from it
- Supabase: `map_*` tables in the shared **API Verifier LIVE** project (`iwpfhalextbzbvcajtxu`)
- Confirmed working end-to-end: PWA install, entitlement gate (grades 1–2 free / 3–8 need `plan='full'`), real magic-link sign-in via Supabase Auth

## Completed this session
- **Simulation vs. Training Mode split** (real, built): two dashboard tabs. Simulation = only the adaptive tests (renamed "Adaptive: 40 Questions" / "Adaptive: 40 Questions — more passage-based sets" [rate bumped 55%→75%] / "Adaptive: 100 Questions"), forces off hints + word-help + feedback popups regardless of Settings, has an adjustable time limit (default 80 min, counts down, auto-submits at zero). Training = everything else (skill practice, Bloom's, CEFR checks, sequential progress), feedback stays on.
- **Gamification layer v1** (real, built, local-device only for now): XP (+10/question regardless of correctness — deliberately not tied to academic performance — +50 test-completion bonus), Levels (500 XP/level), a "Difficulty ↑" toast when a correct answer pushes the student into a higher CEFR band mid-test, and a **Player Card** on the dashboard showing name/level/XP bar/personal best/improvement streak/delta-from-last-test/badges. Badges implemented: 10 Tests Completed, 30-Test Veteran, 5-Test Streak, Perfect Score, Beat Your Best. All computed from the existing local test-history log (`xag_hist_v2`), aggregated across all modes per student name.
- Prior sessions: full single-file build (question content, illustrations, accessibility, CCSS accuracy), Tier 1 PWA conversion, Tier 2 Phase A (accounts/entitlement/session-sync), all deployed live.

## The big picture (agreed this session)
Position: **"An adaptive academic assessment and growth platform built around MAP-style preparation"** — not "a MAP practice test." Three buyers, three pitches: student ("beat my personal best"), parent ("is my child improving"), school ("assess, train, monitor, manage"). MAP Connect (live class sessions) is what turns the individual PWA into a *school* product, not just "add a teacher dashboard."

Decided: no "flaming red" combat framing for competitive features (kept as a real design option, chosen against). No live image-generation API for now; if pursued later, the lower-risk path is a curated art bank pre-generated once, offline, not live per-request.

- **Enhanced results screen** (real, built): "Your Strengths" section with per-skill-type star ratings (★★★★☆), computed from the actual questions answered in that attempt. "Your Next Target" (current RIT + 10, explicitly labeled as a reasonable goal, not an official NWEA growth projection — deliberate per the discussion about not overstating what the app's numbers represent). "Recommended Training" — the 1-2 weakest skill types (under 70% accuracy, min. 2 questions) each get a one-click "Practice this →" button that jumps straight into the matching Training Mode skill-practice mode. Note: the practice-mode mapping uses the 3 skill filters that already exist (Vocabulary / informational-text / literary-text) — there's no dedicated filter yet for finer-grained types like "Inference" specifically; that's a small follow-up (a new `SKILL_FILTERS` entry per type), not done in this pass. The existing growth-delta-from-last-test and history graph were already built from a prior session — confirmed still there, not duplicated.

- **Gamification layer completed** (real, built, all local-device for now):
  - **Rank tiers**: Bronze/Silver/Gold/Platinum, derived from Level (thresholds at Level 1/5/10/20), shown on the player card next to the level.
  - **Weekly Mission**: "Complete 2 tests this week," tracked by bucketing history entries into calendar weeks (Monday start), shown as X/2 with a checkmark when done.
  - **"What should I do today?"** smart recommendation on the dashboard: aggregates per-skill-type accuracy across a student's ENTIRE history (not just their last test — required a real data change, see below), finds their single weakest skill type with at least 5 questions attempted (so one unlucky question can't get flagged as "your weakness"), and shows a one-click START button into the matching Training Mode practice.
  - **"Your Growth Path"** on the results screen: a simple horizontal milestone track (current RIT ±20, in steps of 10) with the student's position marked — explicitly not framed as the real NWEA scale.
  - **Data model change this required**: test-history entries now also store a `byType` breakdown (per-skill-type correct/total) alongside the existing rit/lexile/accuracy fields, computed via a new shared `computeByTypeAccuracy()` helper (also used by the results-screen strengths section, so both features stay consistent). Older history entries made before this change won't have `byType` and are silently skipped by the aggregation — not a bug, just means the recommendation needs a little fresh history to kick in.

- **Async leaderboards** (real, built — needs one SQL migration run before it works): the RLS gap flagged in the original schema comments turned out to matter immediately — a student's `map_test_sessions` rows are only readable by that student, so a client-side leaderboard query would have been silently blocked. Fixed properly with `map_leaderboard_migration.sql`: a `SECURITY DEFINER` Postgres function (`get_class_leaderboard`) that returns only aggregated, name-level data, and only to someone who is actually a member of (or the teacher of) that specific class — not a blanket RLS loosening. Frontend: class creation (generates a short join code like `FOX-482`), joining by code, a "Classes & Leaderboards" section in the Account modal, and a leaderboard modal with three tabs (Highest RIT, Most Improved, Best Accuracy). Also added the profile-creation step that was missing until now — `ensureProfile()` upserts a `map_profiles` row (display name + role) the first time someone touches a class feature, since the leaderboard needs a name to show and nothing before this created that row.

- **Certificates** (real, built): canvas-rendered, downloadable PNG certificates for each earned badge (10-Test Certificate, Reading Champion, Problem Solver, Personal Best Award, Improvement Award), accessed via "🏆 View Certificates" on the player card. **Real constraint surfaced and handled honestly, not glossed over**: the existing "Send Report" feature uses a `mailto:` link, and browsers cannot attach files to a mailto link automatically for security reasons — so "auto-email the certificate with the report" isn't achievable client-side as literally requested. Added a clear note in the Send Report modal instead (download the certificate, attach it yourself). A real automated version would need a backend email service (Supabase Edge Function + an email API like Resend) — scoped but not built, since it's new paid infrastructure that needs the user's sign-off first, not something to add silently.

- **Gamification moved to the cloud for signed-in users** (real architectural fix, not a patch). XP, levels, badges, streaks, and personal best are no longer stored counters at all — they're computed fresh every time from test history, which now comes from `map_test_sessions` (via Supabase) when signed in, or the local device log when not. Concretely: XP = 10/question + 50/test, derived from history length and question counts, not incremented and stored. Badges are a pure function of history, not a saved array. This means a signed-in student's level, badges, and personal best now genuinely follow them across devices — the exact problem flagged and fixed. Required one new migration (`map_by_type_migration.sql` — adds a `by_type jsonb` column to `map_test_sessions`, since the weakest-skill recommendation and "Perfect Score" badge need the per-skill-type breakdown that used to only exist in local history). Anonymous/no-account use is unchanged — still fully local, still fully functional.
- **`ensureProfile()` role bug fixed**: now takes an inferred role (`'teacher'` from `createClass()`, `'student'` from `joinClass()`), and — more importantly — never overwrites an existing role on a repeat call, since one person can plausibly be a teacher for one class and a member of another.

## Backlog (in priority order)

## Roadmap — organized from everything discussed, not yet all built
**A. Gamification, remaining pieces** (no new infra needed, same pattern as what's built)
- Rank tiers (Bronze→Platinum) layered on top of existing XP/level data
- Weekly missions ("Complete 2 tests this week") — needs a week-bucketing function over existing history
- Certificates (printable/downloadable, "Reading Champion," "10-Test Certificate," etc.) — genuinely cheap given badge data already exists
- "What should I do today?" smart recommendation — needs per-skill-type accuracy aggregation over `state.results`/history (weakest area → one-click start)
- "Your MAP Journey" visual progress path (180→190→...→230) — pure UI over existing RIT history

**B. Enhanced results screen** (no new infra) — strengths-by-skill-type breakdown (★ rating per type), "your next target," recommended practice links straight into Training Mode skill-focus modes. High commercial value per the test→diagnosis→training→retest loop discussed.

**C. Async leaderboards** (schema already exists, no realtime needed) — class/weekly/monthly/improvement/accuracy/streak leaderboards are just periodic queries against `map_test_sessions` + `map_class_members`, which already exist from Phase A. Only the *live, watch-it-update-during-a-test* leaderboard needs real-time infrastructure — this is a smaller lift than it first appeared.

**D. Live group sessions ("MAP Connect")** — the Kahoot-like piece. Needs new tables (`map_group_sessions`, `map_group_participants`) and Supabase Realtime. Teacher starts a session, students join, live leaderboard updates as they progress.

**E. Teacher control room** — pause/resume/end a live session, per-student live status (🟢/🟡/🔴), lock/unlock, assign practice, reset an attempt, extend time, class analytics ("average improvement: +6," "most common difficulty: Inference"), automatic intervention suggestions ("Assign Vocabulary Level 3 → 15 questions → ASSIGN"). This is the actual higher-tier school product — depends on D.

**F. Doubling question-variant counts for all frames, all bands** — explicitly requested, genuinely large in scope (~53+ frames across A1–C2; the v2.9–v3.4 repetitiveness work already brought every frame to an 8–10+ variant floor, this asks for roughly double that across the board). Not started — this is many sessions of content-authoring work, not a single build step. Should be tackled incrementally, same verified-via-harness approach as before, likely band-by-band.

## Notable technical learnings (for next time)
- Browser automation this session was unreliable in bursts (roughly 1-in-3 to 1-in-4 actions completing) but fully capable when it worked — the entire live deploy (GitHub repo, Vercel import, Supabase verification, live sign-in test) was done via browser automation successfully once the connection stabilized. When it's misbehaving, switching to copy-paste git/SQL commands is faster than repeated retries.
- `file_upload` (browser tool) no longer accepts host filesystem paths in this environment.
- Player/gamification data is intentionally local-only (device-scoped) for now, same tier as the old history log — syncing it into Supabase (a `map_player_stats` table) is a natural fast-follow, not a blocker, once the mechanic is validated.

## Next step
Two independent threads:
1. **User**: push the latest `index.html` (adds the enhanced results screen) — same push pattern, confirmed working (last push succeeded; the "I don't see it" report turned out to be browser caching, resolved with a hard refresh).
2. **User**: run `map_leaderboard_migration.sql` in the Supabase SQL editor (same pattern as the original schema) — the leaderboard UI is built but calls a function that doesn't exist until this runs.
3. **User**: run `map_by_type_migration.sql` in the Supabase SQL editor — required before the cloud-derived gamification above actually works for signed-in users (it queries a column that doesn't exist until this runs).
4. **Gap-check against the user's full wishlist (done this session)** — confirmed NOT yet built: dedicated Student Profile page (progress graph/history/strengths/weaknesses/time-spent all in one place — pieces exist scattered across results screen and player card, not unified), weekly/monthly/streak/team leaderboards (only class/improvement/accuracy exist), leaderboard seasons (4-week resets), daily and skill-specific missions (only one generic weekly mission exists), challenge-level progress bar, automated email-with-attachment (see certificates note above), doubling question-variant counts across all bands (large content task, not started), curated art bank (deferred, "no image changes yet").
5. **Build**: D (live group sessions / "MAP Connect") and E (teacher control room) are the remaining BIG pieces — new schema (`map_group_sessions`, `map_group_participants`) + Supabase Realtime. Smaller remaining items (student profile page, more leaderboard types, more mission types) can go before or after D/E — ask the user which they'd rather see next.
