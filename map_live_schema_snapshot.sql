-- =====================================================================
-- MAP Trainer — LIVE SCHEMA SNAPSHOT (reconstructed 2026-09-26)
-- =====================================================================
-- Generated from the production catalog of Supabase project
-- iwpfhalextbzbvcajtxu (pg_catalog / pg_policies / pg_get_functiondef).
--
-- WHY THIS FILE EXISTS: three migrations were applied via the SQL editor
-- and never committed (map_backend_schema.sql, map_schema_rename_migration.sql,
-- map_connect_v1_migration.sql). They are not in Supabase's migration
-- history either, so they cannot be recovered verbatim. This snapshot is
-- the authoritative record of every map_/edu_ object as it exists live.
--
-- DO NOT RUN AGAINST PRODUCTION — everything here already exists.
-- Use it as reference, or to rebuild a fresh/dev project.
-- Scope: only map_* / edu_* tables and the functions they depend on.
-- Note: edu_classes / edu_class_members keep their pre-rename constraint
-- names (map_classes_*, map_class_members_*) — harmless, left as-is.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------
create table public.map_profiles (
    id            uuid        not null,
    role          text        not null,
    display_name  text        not null,
    created_at    timestamptz not null default now(),
    use_nickname  boolean     not null default false,
    nickname      text
);

create table public.map_subscriptions (
    id                     uuid        not null default gen_random_uuid(),
    user_id                uuid        not null,
    plan                   text        not null default 'free',
    status                 text        not null default 'active',
    stripe_customer_id     text,
    stripe_subscription_id text,
    current_period_end     timestamptz,
    created_at             timestamptz not null default now(),
    updated_at             timestamptz not null default now()
);

create table public.map_test_sessions (
    id                 uuid        not null default gen_random_uuid(),
    user_id            uuid        not null,
    mode               text        not null,
    band_start         text,
    band_end           text,
    rit_start          integer,
    rit_end            integer,
    lexile_end         integer,
    total_time_seconds integer,
    question_count     integer,
    correct_count      integer,
    cancelled          boolean     not null default false,
    practice_only      boolean     not null default false,
    started_at         timestamptz not null,
    completed_at       timestamptz,
    by_type            jsonb,
    app_id             text        not null default 'map-reading'
);

create table public.map_history_points (
    id          uuid        not null default gen_random_uuid(),
    user_id     uuid        not null,
    session_id  uuid,
    recorded_at timestamptz not null default now(),
    rit         integer,
    lexile      integer
);

create table public.map_flagged_questions (
    id            uuid        not null default gen_random_uuid(),
    user_id       uuid,
    session_id    uuid,
    question_seed text,
    question_type text,
    reason        text,
    created_at    timestamptz not null default now()
);

create table public.edu_classes (
    id         uuid        not null default gen_random_uuid(),
    teacher_id uuid        not null,
    name       text        not null,
    join_code  text        not null,
    created_at timestamptz not null default now(),
    app_id     text        not null default 'map-reading'
);

create table public.edu_class_members (
    class_id   uuid        not null,
    student_id uuid        not null,
    joined_at  timestamptz not null default now()
);

create table public.edu_group_sessions (
    id                       uuid        not null default gen_random_uuid(),
    teacher_id               uuid        not null,
    class_id                 uuid,
    app_id                   text        not null default 'map-reading',
    name                     text        not null,
    join_code                text        not null,
    mode                     text        not null default 'adaptive_40',
    status                   text        not null default 'waiting',
    started_at               timestamptz,
    ended_at                 timestamptz,
    created_at               timestamptz not null default now(),
    show_student_leaderboard boolean     not null default true
);

create table public.edu_group_participants (
    id                     uuid        not null default gen_random_uuid(),
    session_id             uuid        not null,
    student_id             uuid        not null,
    status                 text        not null default 'joined',
    current_question_index integer     not null default 0,
    current_rit            integer,
    joined_at              timestamptz not null default now(),
    last_seen_at           timestamptz not null default now()
);


-- ---------------------------------------------------------------------
-- 2. Constraints (PK / unique / check first, then FKs)
-- ---------------------------------------------------------------------
alter table public.map_profiles add constraint map_profiles_pkey primary key (id);
alter table public.map_profiles add constraint map_profiles_role_check
    check (role = any (array['student','parent','teacher']));

alter table public.map_subscriptions add constraint map_subscriptions_pkey primary key (id);
alter table public.map_subscriptions add constraint map_subscriptions_plan_check
    check (plan = any (array['free','pro','educator','connect']));
alter table public.map_subscriptions add constraint map_subscriptions_status_check
    check (status = any (array['active','canceled','past_due']));

alter table public.map_test_sessions     add constraint map_test_sessions_pkey     primary key (id);
alter table public.map_history_points    add constraint map_history_points_pkey    primary key (id);
alter table public.map_flagged_questions add constraint map_flagged_questions_pkey primary key (id);

alter table public.edu_classes add constraint map_classes_pkey primary key (id);
alter table public.edu_classes add constraint map_classes_join_code_key unique (join_code);

alter table public.edu_class_members add constraint map_class_members_pkey primary key (class_id, student_id);

alter table public.edu_group_sessions add constraint edu_group_sessions_pkey primary key (id);
alter table public.edu_group_sessions add constraint edu_group_sessions_join_code_key unique (join_code);
alter table public.edu_group_sessions add constraint edu_group_sessions_status_check
    check (status = any (array['waiting','active','paused','ended']));

alter table public.edu_group_participants add constraint edu_group_participants_pkey primary key (id);
alter table public.edu_group_participants add constraint edu_group_participants_session_id_student_id_key
    unique (session_id, student_id);
alter table public.edu_group_participants add constraint edu_group_participants_status_check
    check (status = any (array['joined','active','paused','finished']));

-- Foreign keys
alter table public.map_profiles          add constraint map_profiles_id_fkey
    foreign key (id) references auth.users(id) on delete cascade;
alter table public.map_subscriptions     add constraint map_subscriptions_user_id_fkey
    foreign key (user_id) references auth.users(id) on delete cascade;
alter table public.map_test_sessions     add constraint map_test_sessions_user_id_fkey
    foreign key (user_id) references auth.users(id) on delete cascade;
alter table public.map_history_points    add constraint map_history_points_user_id_fkey
    foreign key (user_id) references auth.users(id) on delete cascade;
alter table public.map_history_points    add constraint map_history_points_session_id_fkey
    foreign key (session_id) references public.map_test_sessions(id) on delete set null;
alter table public.map_flagged_questions add constraint map_flagged_questions_user_id_fkey
    foreign key (user_id) references auth.users(id) on delete set null;
alter table public.map_flagged_questions add constraint map_flagged_questions_session_id_fkey
    foreign key (session_id) references public.map_test_sessions(id) on delete set null;
alter table public.edu_classes           add constraint map_classes_teacher_id_fkey
    foreign key (teacher_id) references auth.users(id) on delete cascade;
alter table public.edu_class_members     add constraint map_class_members_class_id_fkey
    foreign key (class_id) references public.edu_classes(id) on delete cascade;
alter table public.edu_class_members     add constraint map_class_members_student_id_fkey
    foreign key (student_id) references auth.users(id) on delete cascade;
alter table public.edu_group_sessions    add constraint edu_group_sessions_teacher_id_fkey
    foreign key (teacher_id) references auth.users(id) on delete cascade;
alter table public.edu_group_sessions    add constraint edu_group_sessions_class_id_fkey
    foreign key (class_id) references public.edu_classes(id) on delete set null;
alter table public.edu_group_participants add constraint edu_group_participants_session_id_fkey
    foreign key (session_id) references public.edu_group_sessions(id) on delete cascade;
alter table public.edu_group_participants add constraint edu_group_participants_student_id_fkey
    foreign key (student_id) references auth.users(id) on delete cascade;


-- ---------------------------------------------------------------------
-- 3. Indexes (non-constraint)
-- ---------------------------------------------------------------------
create unique index map_subscriptions_user_id_idx  on public.map_subscriptions  using btree (user_id);
create index        map_test_sessions_user_id_idx  on public.map_test_sessions  using btree (user_id, started_at desc);
create index        map_history_points_user_id_idx on public.map_history_points using btree (user_id, recorded_at);


-- ---------------------------------------------------------------------
-- 4. Functions (all SECURITY DEFINER, search_path pinned to public)
--    Must exist before the policies in section 5 that call them.
-- ---------------------------------------------------------------------
create or replace function public.current_plan()
 returns text
 language sql
 stable security definer
 set search_path to 'public'
as $function$
    select coalesce(
        (select plan from map_subscriptions
          where user_id = auth.uid() and status = 'active' limit 1),
        'free');
$function$;

create or replace function public.my_class_count()
 returns integer
 language sql
 stable security definer
 set search_path to 'public'
as $function$
    select count(*)::integer from edu_classes where teacher_id = auth.uid();
$function$;

create or replace function public.is_class_member(p_class_id uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
    select exists (select 1 from edu_class_members
                    where class_id = p_class_id and student_id = auth.uid());
$function$;

create or replace function public.is_class_teacher(p_class_id uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
    select exists (select 1 from edu_classes
                    where id = p_class_id and teacher_id = auth.uid());
$function$;

create or replace function public.is_session_participant(p_session_id uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
    select exists (select 1 from edu_group_participants
                    where session_id = p_session_id and student_id = auth.uid());
$function$;

create or replace function public.is_session_teacher(p_session_id uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
    select exists (select 1 from edu_group_sessions
                    where id = p_session_id and teacher_id = auth.uid());
$function$;

create or replace function public.join_class_by_code(p_code text)
 returns table(class_id uuid, class_name text)
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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
$function$;

create or replace function public.join_group_session(p_code text)
 returns table(session_id uuid, session_name text, session_status text, session_mode text)
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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
$function$;

create or replace function public.get_class_leaderboard(p_class_id uuid)
 returns table(user_id uuid, display_name text, best_rit integer, first_rit integer,
               latest_rit integer, avg_accuracy numeric, tests_completed integer)
 language sql
 security definer
 set search_path to 'public'
as $function$
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
$function$;

create or replace function public.get_live_leaderboard(p_session_id uuid)
 returns table(student_id uuid, display_name text, status text, is_connected boolean,
               current_question_index integer, current_rit integer)
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
$function$;


-- ---------------------------------------------------------------------
-- 5. Row Level Security
-- ---------------------------------------------------------------------
alter table public.map_profiles           enable row level security;
alter table public.map_subscriptions      enable row level security;
alter table public.map_test_sessions      enable row level security;
alter table public.map_history_points     enable row level security;
alter table public.map_flagged_questions  enable row level security;
alter table public.edu_classes            enable row level security;
alter table public.edu_class_members      enable row level security;
alter table public.edu_group_sessions     enable row level security;
alter table public.edu_group_participants enable row level security;

-- map_* : owner-only
create policy "own profile"      on public.map_profiles          for all    using (auth.uid() = id);
create policy "own subscription" on public.map_subscriptions     for select using (auth.uid() = user_id);
create policy "own sessions"     on public.map_test_sessions     for all    using (auth.uid() = user_id);
create policy "own history"      on public.map_history_points    for all    using (auth.uid() = user_id);
create policy "own flags"        on public.map_flagged_questions for all    using (auth.uid() = user_id);

-- edu_classes
create policy "class read: teacher or member" on public.edu_classes for select
    using (teacher_id = auth.uid() or is_class_member(id));
create policy "class insert: educator or connect" on public.edu_classes for insert
    with check (teacher_id = auth.uid()
                and (current_plan() = 'connect'
                     or (current_plan() = 'educator' and my_class_count() < 2)));
create policy "class update: teacher" on public.edu_classes for update using (teacher_id = auth.uid());
create policy "class delete: teacher" on public.edu_classes for delete using (teacher_id = auth.uid());

-- edu_class_members (inserts only via join_class_by_code RPC)
create policy "student sees own membership" on public.edu_class_members for select using (auth.uid() = student_id);
create policy "teacher sees roster"         on public.edu_class_members for select using (is_class_teacher(class_id));
create policy "student leaves class"        on public.edu_class_members for delete using (student_id = auth.uid());

-- edu_group_sessions
create policy "session read: teacher or participant" on public.edu_group_sessions for select
    using (teacher_id = auth.uid() or is_session_participant(id));
create policy "session insert: connect plan" on public.edu_group_sessions for insert
    with check (teacher_id = auth.uid() and current_plan() = 'connect');
create policy "session update: teacher" on public.edu_group_sessions for update using (teacher_id = auth.uid());
create policy "session delete: teacher" on public.edu_group_sessions for delete using (teacher_id = auth.uid());

-- edu_group_participants (inserts only via join_group_session RPC)
create policy "participant read: self or teacher" on public.edu_group_participants for select
    using (student_id = auth.uid() or is_session_teacher(session_id));
create policy "participant update: self (heartbeat/progress)" on public.edu_group_participants for update
    using (student_id = auth.uid());
create policy "participant update: teacher (pause etc.)" on public.edu_group_participants for update
    using (is_session_teacher(session_id));


-- ---------------------------------------------------------------------
-- 6. Realtime
-- ---------------------------------------------------------------------
alter publication supabase_realtime add table public.edu_group_sessions;
alter publication supabase_realtime add table public.edu_group_participants;
