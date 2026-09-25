-- MAP Trainer — architecture fixes (run once in the Supabase SQL editor).
-- Safe to re-run: every step uses IF EXISTS / OR REPLACE / guarded blocks.

-- ── 1. Four-tier plans (free / pro / educator / connect) ──────────────────
alter table map_subscriptions drop constraint if exists map_subscriptions_plan_check;
update map_subscriptions set plan = 'pro' where plan = 'full';
alter table map_subscriptions add constraint map_subscriptions_plan_check
    check (plan in ('free','pro','educator','connect'));

-- ── 2. Helper functions (SECURITY DEFINER = bypass RLS inside them, which
-- is what breaks the policy-recursion loop between related tables) ──────
create or replace function current_plan() returns text
language sql stable security definer set search_path = public as $$
    select coalesce(
        (select plan from map_subscriptions
          where user_id = auth.uid() and status = 'active' limit 1),
        'free');
$$;

create or replace function is_class_member(p_class_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
    select exists (select 1 from edu_class_members
                    where class_id = p_class_id and student_id = auth.uid());
$$;

create or replace function is_class_teacher(p_class_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
    select exists (select 1 from edu_classes
                    where id = p_class_id and teacher_id = auth.uid());
$$;

create or replace function my_class_count() returns integer
language sql stable security definer set search_path = public as $$
    select count(*)::integer from edu_classes where teacher_id = auth.uid();
$$;

create or replace function is_session_participant(p_session_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
    select exists (select 1 from edu_group_participants
                    where session_id = p_session_id and student_id = auth.uid());
$$;

create or replace function is_session_teacher(p_session_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
    select exists (select 1 from edu_group_sessions
                    where id = p_session_id and teacher_id = auth.uid());
$$;

-- ── 3. Classes: members can read their class; creation requires an
-- Educator (max 2 classes) or Connect plan — enforced server-side ────────
drop policy if exists "teacher owns their classes" on edu_classes;
drop policy if exists "class read: teacher or member" on edu_classes;
drop policy if exists "class insert: educator or connect" on edu_classes;
drop policy if exists "class update: teacher" on edu_classes;
drop policy if exists "class delete: teacher" on edu_classes;

create policy "class read: teacher or member" on edu_classes
    for select using (teacher_id = auth.uid() or is_class_member(id));

create policy "class insert: educator or connect" on edu_classes
    for insert with check (
        teacher_id = auth.uid()
        and (
            current_plan() = 'connect'
            or (current_plan() = 'educator' and my_class_count() < 2)
        )
    );

create policy "class update: teacher" on edu_classes
    for update using (teacher_id = auth.uid());

create policy "class delete: teacher" on edu_classes
    for delete using (teacher_id = auth.uid());

-- Roster: student sees own row, teacher sees their roster. Inserts only
-- happen through join_class_by_code() below (validates code + cap).
drop policy if exists "teacher sees roster" on edu_class_members;
drop policy if exists "student leaves class" on edu_class_members;
create policy "teacher sees roster" on edu_class_members
    for select using (is_class_teacher(class_id));
create policy "student leaves class" on edu_class_members
    for delete using (student_id = auth.uid());

create or replace function join_class_by_code(p_code text)
returns table (class_id uuid, class_name text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
    v_class edu_classes%rowtype;
    v_count integer;
begin
    if auth.uid() is null then raise exception 'Please sign in first.'; end if;
    select * into v_class from edu_classes where join_code = upper(trim(p_code));
    if not found then raise exception 'No class found with that code.'; end if;
    select count(*) into v_count from edu_class_members m where m.class_id = v_class.id;
    if v_count >= 40 then raise exception 'This class is full (40 students).'; end if;
    insert into edu_class_members (class_id, student_id)
        values (v_class.id, auth.uid()) on conflict do nothing;
    return query select v_class.id, v_class.name;
end;
$$;
grant execute on function join_class_by_code(text) to authenticated;

-- ── 4. Connect sessions: fix the recursive/ambiguous policies ────────────
drop policy if exists "teacher owns their sessions" on edu_group_sessions;
drop policy if exists "student sees a session they've joined" on edu_group_sessions;
drop policy if exists "session read: teacher or participant" on edu_group_sessions;
drop policy if exists "session insert: connect plan" on edu_group_sessions;
drop policy if exists "session update: teacher" on edu_group_sessions;
drop policy if exists "session delete: teacher" on edu_group_sessions;

create policy "session read: teacher or participant" on edu_group_sessions
    for select using (teacher_id = auth.uid() or is_session_participant(id));
create policy "session insert: connect plan" on edu_group_sessions
    for insert with check (teacher_id = auth.uid() and current_plan() = 'connect');
create policy "session update: teacher" on edu_group_sessions
    for update using (teacher_id = auth.uid());
create policy "session delete: teacher" on edu_group_sessions
    for delete using (teacher_id = auth.uid());

drop policy if exists "student manages own participant row" on edu_group_participants;
drop policy if exists "teacher sees participants in their own sessions" on edu_group_participants;
drop policy if exists "participant read: self or teacher" on edu_group_participants;
drop policy if exists "participant update: self (heartbeat/progress)" on edu_group_participants;
drop policy if exists "participant update: teacher (pause etc.)" on edu_group_participants;

create policy "participant read: self or teacher" on edu_group_participants
    for select using (student_id = auth.uid() or is_session_teacher(session_id));
create policy "participant update: self (heartbeat/progress)" on edu_group_participants
    for update using (student_id = auth.uid());
create policy "participant update: teacher (pause etc.)" on edu_group_participants
    for update using (is_session_teacher(session_id));

create or replace function join_group_session(p_code text)
returns table (session_id uuid, session_name text, session_status text, session_mode text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
    v_s edu_group_sessions%rowtype;
begin
    if auth.uid() is null then raise exception 'Please sign in first.'; end if;
    select * into v_s from edu_group_sessions where join_code = upper(trim(p_code));
    if not found then raise exception 'No live session found with that code.'; end if;
    if v_s.status = 'ended' then raise exception 'That session has already ended.'; end if;
    insert into edu_group_participants (session_id, student_id)
        values (v_s.id, auth.uid())
        on conflict (session_id, student_id) do update set last_seen_at = now();
    return query select v_s.id, v_s.name, v_s.status, v_s.mode;
end;
$$;
grant execute on function join_group_session(text) to authenticated;

-- Realtime needs the tables in its publication (live leaderboard, pause).
do $$
begin
    begin alter publication supabase_realtime add table edu_group_sessions;
    exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table edu_group_participants;
    exception when duplicate_object then null; end;
end $$;

-- ── 5. Class leaderboard: only real Simulation results count (no trial,
-- no 5-question tech test, no Training practice) ─────────────────────────
create or replace function get_class_leaderboard(p_class_id uuid)
returns table (
    user_id uuid, display_name text, best_rit integer, first_rit integer,
    latest_rit integer, avg_accuracy numeric, tests_completed integer
)
language sql security definer set search_path = public as $$
    select
        m.student_id,
        case when p.use_nickname and coalesce(p.nickname,'') <> ''
             then p.nickname else coalesce(p.display_name,'Student') end,
        max(s.rit_end),
        (array_agg(s.rit_end order by s.completed_at asc))[1],
        (array_agg(s.rit_end order by s.completed_at desc))[1],
        avg(s.correct_count::numeric / nullif(s.question_count, 0)),
        count(s.id)::integer
    from edu_class_members m
    join map_test_sessions s
        on s.user_id = m.student_id and s.cancelled = false
       and s.completed_at is not null
       and s.mode in ('adaptive_40','adaptive_40_sets','adaptive_100')
    left join map_profiles p on p.id = m.student_id
    where m.class_id = p_class_id
      and (is_class_member(p_class_id) or is_class_teacher(p_class_id))
    group by m.student_id, p.display_name, p.use_nickname, p.nickname;
$$;
grant execute on function get_class_leaderboard(uuid) to authenticated;
