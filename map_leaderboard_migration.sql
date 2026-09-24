-- MAP Trainer — Leaderboard migration (Phase Roadmap item C)
-- Run this in the Supabase SQL editor, same as map_backend_schema.sql.
--
-- Why this is needed: map_test_sessions' RLS policy only lets a student read
-- their OWN rows (correct, for privacy). A leaderboard needs to show OTHER
-- class members' scores too. Rather than loosen that policy (which would let
-- any signed-in user read anyone's session history directly), this adds one
-- narrow, SECURITY DEFINER function that returns only aggregated, name-level
-- leaderboard data, and only to people who are actually a member of (or the
-- teacher of) the specific class being asked about.

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
        coalesce(p.display_name, 'Student') as display_name,
        max(s.rit_end) as best_rit,
        (array_agg(s.rit_end order by s.completed_at asc))[1] as first_rit,
        (array_agg(s.rit_end order by s.completed_at desc))[1] as latest_rit,
        avg(s.correct_count::numeric / nullif(s.question_count, 0)) as avg_accuracy,
        count(s.id)::integer as tests_completed
    from map_class_members m
    join map_test_sessions s
        on s.user_id = m.student_id and s.cancelled = false and s.completed_at is not null
    left join map_profiles p on p.id = m.student_id
    where m.class_id = p_class_id
      and (
        -- caller must be a member of this class...
        exists (select 1 from map_class_members me where me.class_id = p_class_id and me.student_id = auth.uid())
        -- ...or the class's teacher
        or exists (select 1 from map_classes c where c.id = p_class_id and c.teacher_id = auth.uid())
      )
    group by m.student_id, p.display_name;
$$;

grant execute on function get_class_leaderboard(uuid) to authenticated;

-- A short, human-typeable join code generator (e.g. "FOX-482") used when a
-- teacher creates a class — done in JS at insert time (see the app code),
-- this migration just documents the format: uppercase word + 3 digits.
