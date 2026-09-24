-- MAP Trainer — adds per-skill-type breakdown storage to session sync,
-- needed so gamification (XP, badges, personal best, weakest-skill
-- recommendation) can be fully derived from server data for a signed-in
-- user, instead of depending on anything stored only in that device's
-- localStorage.
--
-- Run this in the Supabase SQL editor (same place as the other migrations).

alter table map_test_sessions
    add column if not exists by_type jsonb;

comment on column map_test_sessions.by_type is
    'Per-skill-type {correct,total} breakdown for this session, e.g. {"Vocabulary":{"correct":8,"total":10}} — mirrors computeByTypeAccuracy() in the app.';
