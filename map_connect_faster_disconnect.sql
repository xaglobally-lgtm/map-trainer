-- MAP Connect: faster disconnect detection (45s -> 20s silence threshold).
-- APPLY ONLY AFTER the client with LIVE_HEARTBEAT_MS = 10000 is deployed —
-- older clients heartbeat every 20s and would flicker "disconnected".
-- Only change vs. the live definition: interval '45 seconds' -> '20 seconds'.
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
        (now() - p.last_seen_at) < interval '20 seconds' as is_connected,
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
