-- MAP Connect — live group session schema (Roadmap item D).
-- Run this in the Supabase SQL editor, same place as the others.

-- ── Nickname / privacy choice (student decides, per the discussion) ──────
alter table map_profiles
    add column if not exists use_nickname boolean not null default false,
    add column if not exists nickname text;
comment on column map_profiles.use_nickname is
    'Student''s own choice — true shows nickname instead of real name on any leaderboard (class or live).';

-- ── Sessions ──────────────────────────────────────────────────────────────
-- class_id is nullable on purpose: a teacher can run an ad-hoc session with
-- no saved class/roster (per teacher_control option agreed), or a real
-- class-based one. Either way, join_code is the single mechanism students
-- use to get in — for a class-based session it can be pre-shared with the
-- roster, for an ad-hoc one it's the only way in.
create table edu_group_sessions (
    id uuid primary key default gen_random_uuid(),
    teacher_id uuid not null references auth.users(id) on delete cascade,
    class_id uuid references edu_classes(id) on delete set null,
    app_id text not null default 'map-reading',
    name text not null,
    join_code text not null unique,
    mode text not null default 'adaptive_40',
    status text not null default 'waiting' check (status in ('waiting','active','paused','ended')),
    started_at timestamptz,
    ended_at timestamptz,
    created_at timestamptz not null default now()
);

-- ── Participants ──────────────────────────────────────────────────────────
-- status here is the teacher/student-driven state (joined/active/paused).
-- "Disconnected" is deliberately NOT stored — it's derived at read time from
-- last_seen_at (see get_live_leaderboard below), so a student who stops
-- sending heartbeats is automatically shown as disconnected without any
-- explicit action, and just as automatically shown as reconnected the
-- moment a heartbeat resumes. No manual "reconnect" step needed.
create table edu_group_participants (
    id uuid primary key default gen_random_uuid(),
    session_id uuid not null references edu_group_sessions(id) on delete cascade,
    student_id uuid not null references auth.users(id) on delete cascade,
    status text not null default 'joined' check (status in ('joined','active','paused')),
    current_question_index integer not null default 0,
    current_rit integer,
    joined_at timestamptz not null default now(),
    last_seen_at timestamptz not null default now(),
    unique (session_id, student_id)
);

-- Heartbeat cadence: client pings every ~20s (and after each answered
-- question). 45s (a little over 2 missed pings) is the disconnect
-- threshold — long enough to absorb one slow network blip, short enough
-- that a teacher isn't staring at a stale "active" status for a student
-- who's actually gone.
-- (This constant lives in the app code, not the database — noted here for
-- anyone reading this migration later.)

alter table edu_group_sessions enable row level security;
alter table edu_group_participants enable row level security;

create policy "teacher owns their sessions" on edu_group_sessions
    for all using (auth.uid() = teacher_id);

create policy "student sees a session they've joined" on edu_group_sessions
    for select using (
        exists (select 1 from edu_group_participants p where p.session_id = id and p.student_id = auth.uid())
    );

create policy "student manages own participant row" on edu_group_participants
    for all using (auth.uid() = student_id);

create policy "teacher sees participants in their own sessions" on edu_group_participants
    for select using (
        exists (select 1 from edu_group_sessions s where s.id = session_id and s.teacher_id = auth.uid())
    );

-- ── Live leaderboard (same pattern as get_class_leaderboard: aggregated,
-- name-respecting data only, only to session members/teacher) ────────────
create or replace function get_live_leaderboard(p_session_id uuid)
returns table (
    student_id uuid,
    display_name text,
    status text,
    is_connected boolean,
    current_question_index integer,
    current_rit integer
)
language sql
security definer
set search_path = public
as $$
    select
        p.student_id,
        case when pr.use_nickname and pr.nickname is not null and pr.nickname != ''
             then pr.nickname
             else coalesce(pr.display_name, 'Student') end as display_name,
        p.status,
        (now() - p.last_seen_at) < interval '45 seconds' as is_connected,
        p.current_question_index,
        p.current_rit
    from edu_group_participants p
    left join map_profiles pr on pr.id = p.student_id
    where p.session_id = p_session_id
      and (
        exists (select 1 from edu_group_participants me where me.session_id = p_session_id and me.student_id = auth.uid())
        or exists (select 1 from edu_group_sessions s where s.id = p_session_id and s.teacher_id = auth.uid())
      );
$$;

grant execute on function get_live_leaderboard(uuid) to authenticated;

-- Also apply the same nickname preference to the existing class leaderboard,
-- for consistency — a student's privacy choice should hold everywhere their
-- name/score is shown to others, not just in live sessions.
create or replace function get_class_leaderboard(p_class_id uuid)
returns table (
    user_id uuid,
    display_name text,
    best_rit integer,
    first_rit integer,
    latest_rit integer,
    avg_accuracy numeric,
    tests_completed integer
)
language sql
security definer
set search_path = public
as $$
    select
        m.student_id as user_id,
        case when p.use_nickname and p.nickname is not null and p.nickname != ''
             then p.nickname
             else coalesce(p.display_name, 'Student') end as display_name,
        max(s.rit_end) as best_rit,
        (array_agg(s.rit_end order by s.completed_at asc))[1] as first_rit,
        (array_agg(s.rit_end order by s.completed_at desc))[1] as latest_rit,
        avg(s.correct_count::numeric / nullif(s.question_count, 0)) as avg_accuracy,
        count(s.id)::integer as tests_completed
    from edu_class_members m
    join map_test_sessions s
        on s.user_id = m.student_id and s.cancelled = false and s.completed_at is not null
    left join map_profiles p on p.id = m.student_id
    where m.class_id = p_class_id
      and (
        exists (select 1 from edu_class_members me where me.class_id = p_class_id and me.student_id = auth.uid())
        or exists (select 1 from edu_classes c where c.id = p_class_id and c.teacher_id = auth.uid())
      )
    group by m.student_id, p.display_name, p.use_nickname, p.nickname;
$$;

grant execute on function get_class_leaderboard(uuid) to authenticated;
