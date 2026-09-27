-- =====================================================================
-- MAP Connect E — teacher control room (2026-09-27)
-- Applied via Supabase MCP apply_migration as: map_teacher_controls,
-- map_class_analytics_ccss (adds ccss to by_type), map_revoke_anon_function_execute.
-- Additive and backward compatible with the client deployed before it:
-- the old client only writes the four student columns granted below.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Per-student live controls
-- ---------------------------------------------------------------------
alter table public.edu_group_participants
    add column if not exists teacher_paused boolean not null default false,
    add column if not exists extra_seconds  integer not null default 0,
    add column if not exists reset_count    integer not null default 0;

-- RLS can't restrict columns, and "participant update: self" lets a student
-- update their own row. Column privileges close the gap: clients may write
-- only the progress/heartbeat columns; teacher controls go through
-- teacher_control_participant() (SECURITY DEFINER, bypasses these grants).
revoke update on public.edu_group_participants from anon, authenticated;
grant update (status, current_question_index, current_rit, last_seen_at)
    on public.edu_group_participants to authenticated;

create or replace function public.teacher_control_participant(
    p_session_id uuid, p_student_id uuid, p_action text, p_seconds integer default 300)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
    if not is_session_teacher(p_session_id) then
        raise exception 'Only the teacher running this session can do that.';
    end if;
    if p_action = 'pause' then
        update edu_group_participants set teacher_paused = true
         where session_id = p_session_id and student_id = p_student_id;
    elsif p_action = 'resume' then
        update edu_group_participants set teacher_paused = false
         where session_id = p_session_id and student_id = p_student_id;
    elsif p_action = 'extend' then
        -- capped: at most 60 min per click, 120 min extra in total
        update edu_group_participants
           set extra_seconds = least(extra_seconds + greatest(0, least(coalesce(p_seconds, 300), 3600)), 7200)
         where session_id = p_session_id and student_id = p_student_id;
    elsif p_action = 'reset' then
        update edu_group_participants
           set reset_count = reset_count + 1, current_question_index = 0, current_rit = null,
               status = 'joined', teacher_paused = false, extra_seconds = 0
         where session_id = p_session_id and student_id = p_student_id;
    else
        raise exception 'Unknown action: %', p_action;
    end if;
    if not found then
        raise exception 'That student is not in this session.';
    end if;
end;
$function$;
revoke execute on function public.teacher_control_participant(uuid, uuid, text, integer) from public, anon;
grant execute on function public.teacher_control_participant(uuid, uuid, text, integer) to authenticated;

-- Live board now also reports per-student pause / extra time.
drop function if exists public.get_live_leaderboard(uuid);
create function public.get_live_leaderboard(p_session_id uuid)
 returns table(student_id uuid, display_name text, status text, is_connected boolean,
               current_question_index integer, current_rit integer,
               teacher_paused boolean, extra_seconds integer)
 language sql
 security definer
 set search_path to 'public'
as $function$
    select
        p.student_id,
        case when pr.use_nickname and pr.nickname is not null and pr.nickname != ''
             then pr.nickname
             else coalesce(pr.display_name, 'Student') end as display_name,
        p.status,
        (now() - p.last_seen_at) < interval '20 seconds' as is_connected,
        p.current_question_index,
        p.current_rit,
        p.teacher_paused,
        p.extra_seconds
    from edu_group_participants p
    left join map_profiles pr on pr.id = p.student_id
    where p.session_id = p_session_id
      and (
        exists (select 1 from edu_group_participants me where me.session_id = p_session_id and me.student_id = auth.uid())
        or exists (select 1 from edu_group_sessions s where s.id = p_session_id and s.teacher_id = auth.uid())
      );
$function$;

-- ---------------------------------------------------------------------
-- 2. Assigned practice (whole class, or one student when student_id set)
-- ---------------------------------------------------------------------
create table if not exists public.edu_assignments (
    id          uuid        primary key default gen_random_uuid(),
    class_id    uuid        not null references public.edu_classes(id) on delete cascade,
    teacher_id  uuid        not null references auth.users(id) on delete cascade,
    student_id  uuid        references auth.users(id) on delete cascade,
    app_id      text        not null default 'map-reading',
    mode        text        not null check (char_length(mode) between 1 and 40),
    title       text        not null check (char_length(title) between 1 and 120),
    note        text        check (note is null or char_length(note) <= 500),
    due_at      timestamptz,
    created_at  timestamptz not null default now()
);
create index if not exists edu_assignments_class_idx on public.edu_assignments (class_id, created_at desc);
alter table public.edu_assignments enable row level security;

create policy "assignment manage: class teacher" on public.edu_assignments for all
    using (is_class_teacher(class_id))
    with check (is_class_teacher(class_id) and teacher_id = auth.uid());
create policy "assignment read: assigned member" on public.edu_assignments for select
    using (is_class_member(class_id) and (student_id is null or student_id = auth.uid()));

-- Completion = a finished, non-cancelled session in the assigned mode after
-- the assignment was created (practice sessions are synced from 2026-09-27).
create or replace function public.get_assignment_progress(p_assignment_id uuid)
 returns table(student_id uuid, display_name text, completed boolean,
               attempts integer, best_accuracy numeric, last_completed timestamptz)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
    select
        m.student_id,
        case when p.use_nickname and coalesce(p.nickname,'') <> ''
             then p.nickname else coalesce(p.display_name,'Student') end,
        count(s.id) > 0,
        count(s.id)::integer,
        max(s.correct_count::numeric / nullif(s.question_count, 0)),
        max(s.completed_at)
    from edu_assignments a
    join edu_class_members m
      on m.class_id = a.class_id and (a.student_id is null or m.student_id = a.student_id)
    left join map_profiles p on p.id = m.student_id
    left join map_test_sessions s
      on s.user_id = m.student_id and s.mode = a.mode and s.cancelled = false
     and s.completed_at is not null and s.completed_at >= a.created_at
    where a.id = p_assignment_id and is_class_teacher(a.class_id)
    group by m.student_id, p.display_name, p.use_nickname, p.nickname;
$function$;

-- ---------------------------------------------------------------------
-- 3. Class analytics (teacher only). RIT fields use real adaptive tests only;
--    accuracy and by-skill totals include practice (useful for weak skills).
-- ---------------------------------------------------------------------
create or replace function public.get_class_analytics(p_class_id uuid)
 returns table(student_id uuid, display_name text, tests_completed integer, practice_completed integer,
               first_rit integer, latest_rit integer, best_rit integer, avg_accuracy numeric,
               last_active timestamptz, by_type jsonb)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
    with s as (
        select m.student_id, t.id, t.mode, t.rit_end, t.correct_count, t.question_count,
               t.completed_at, t.by_type, coalesce(t.practice_only, false) as practice_only
        from edu_class_members m
        left join map_test_sessions t
          on t.user_id = m.student_id and t.cancelled = false and t.completed_at is not null
         and t.mode <> 'trial_20'
        where m.class_id = p_class_id and is_class_teacher(p_class_id)
    ),
    bt as (
        select s.student_id, e.key as skill,
               sum(coalesce((e.value->>'correct')::int, 0)) as correct,
               sum(coalesce((e.value->>'total')::int, 0)) as total,
               max(e.value->>'ccss') as ccss
        from s cross join lateral jsonb_each(coalesce(s.by_type, '{}'::jsonb)) e
        group by s.student_id, e.key
    ),
    bta as (
        select student_id, jsonb_object_agg(skill, jsonb_build_object('correct', correct, 'total', total, 'ccss', ccss)) as by_type
        from bt group by student_id
    )
    select
        s.student_id,
        case when p.use_nickname and coalesce(p.nickname,'') <> ''
             then p.nickname else coalesce(p.display_name,'Student') end,
        (count(s.id) filter (where not s.practice_only))::integer,
        (count(s.id) filter (where s.practice_only))::integer,
        (array_agg(s.rit_end order by s.completed_at asc)  filter (where not s.practice_only and s.rit_end is not null))[1],
        (array_agg(s.rit_end order by s.completed_at desc) filter (where not s.practice_only and s.rit_end is not null))[1],
        max(s.rit_end) filter (where not s.practice_only),
        avg(s.correct_count::numeric / nullif(s.question_count, 0)),
        max(s.completed_at),
        coalesce(bta.by_type, '{}'::jsonb)
    from s
    left join map_profiles p on p.id = s.student_id
    left join bta on bta.student_id = s.student_id
    group by s.student_id, p.display_name, p.use_nickname, p.nickname, bta.by_type;
$function$;

-- ---------------------------------------------------------------------
-- 4. Hygiene (migration map_revoke_anon_function_execute): MAP/edu
--    SECURITY DEFINER functions are for signed-in users only.
-- ---------------------------------------------------------------------
revoke execute on function public.current_plan() from public, anon;
revoke execute on function public.my_class_count() from public, anon;
revoke execute on function public.is_class_member(uuid) from public, anon;
revoke execute on function public.is_class_teacher(uuid) from public, anon;
revoke execute on function public.is_session_participant(uuid) from public, anon;
revoke execute on function public.is_session_teacher(uuid) from public, anon;
revoke execute on function public.join_class_by_code(text) from public, anon;
revoke execute on function public.join_group_session(text) from public, anon;
revoke execute on function public.get_class_leaderboard(uuid) from public, anon;
revoke execute on function public.get_live_leaderboard(uuid) from public, anon;
revoke execute on function public.get_assignment_progress(uuid) from public, anon;
revoke execute on function public.get_class_analytics(uuid) from public, anon;
grant execute on function public.current_plan(), public.my_class_count(), public.is_class_member(uuid),
    public.is_class_teacher(uuid), public.is_session_participant(uuid), public.is_session_teacher(uuid),
    public.join_class_by_code(text), public.join_group_session(text), public.get_class_leaderboard(uuid),
    public.get_live_leaderboard(uuid), public.get_assignment_progress(uuid), public.get_class_analytics(uuid)
    to authenticated;

-- ---------------------------------------------------------------------
-- 5. Student profile for teachers (migration map_student_sessions_for_teacher)
-- ---------------------------------------------------------------------
create or replace function public.get_student_sessions(p_class_id uuid, p_student_id uuid)
 returns table(mode text, rit_end integer, lexile_end integer, question_count integer, correct_count integer,
               completed_at timestamptz, practice_only boolean, by_type jsonb)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
    select s.mode, s.rit_end, s.lexile_end, s.question_count, s.correct_count,
           s.completed_at, coalesce(s.practice_only, false), s.by_type
    from map_test_sessions s
    where s.user_id = p_student_id
      and s.cancelled = false and s.completed_at is not null and s.mode <> 'trial_20'
      and is_class_teacher(p_class_id)
      and exists (select 1 from edu_class_members m where m.class_id = p_class_id and m.student_id = p_student_id)
    order by s.completed_at desc
    limit 300;
$function$;
revoke execute on function public.get_student_sessions(uuid, uuid) from public, anon;
grant execute on function public.get_student_sessions(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 6. Leaderboard seasons + practice board (migration map_class_leaderboard_period)
-- ---------------------------------------------------------------------
create or replace function public.get_class_leaderboard_period(p_class_id uuid, p_since timestamptz default null)
 returns table(user_id uuid, display_name text, best_rit integer, first_rit integer, latest_rit integer,
               avg_accuracy numeric, tests_completed integer, practice_completed integer, questions_answered integer)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
    select
        m.student_id,
        case when p.use_nickname and coalesce(p.nickname,'') <> ''
             then p.nickname else coalesce(p.display_name,'Student') end,
        max(s.rit_end) filter (where s.mode in ('adaptive_40','adaptive_40_sets','adaptive_100')),
        (array_agg(s.rit_end order by s.completed_at asc)  filter (where s.mode in ('adaptive_40','adaptive_40_sets','adaptive_100')))[1],
        (array_agg(s.rit_end order by s.completed_at desc) filter (where s.mode in ('adaptive_40','adaptive_40_sets','adaptive_100')))[1],
        avg(s.correct_count::numeric / nullif(s.question_count, 0)) filter (where s.mode in ('adaptive_40','adaptive_40_sets','adaptive_100')),
        (count(s.id) filter (where s.mode in ('adaptive_40','adaptive_40_sets','adaptive_100')))::integer,
        (count(s.id) filter (where coalesce(s.practice_only, false)))::integer,
        coalesce(sum(s.question_count), 0)::integer
    from edu_class_members m
    join map_test_sessions s
      on s.user_id = m.student_id and s.cancelled = false and s.completed_at is not null
     and s.mode <> 'trial_20'
     and (p_since is null or s.completed_at >= p_since)
    left join map_profiles p on p.id = m.student_id
    where m.class_id = p_class_id
      and (is_class_member(p_class_id) or is_class_teacher(p_class_id))
    group by m.student_id, p.display_name, p.use_nickname, p.nickname;
$function$;
revoke execute on function public.get_class_leaderboard_period(uuid, timestamptz) from public, anon;
grant execute on function public.get_class_leaderboard_period(uuid, timestamptz) to authenticated;
