create table if not exists public.feedback_responses (
 token uuid primary key,
 experience text not null check (experience in ('yes','no')),
 scores integer[] not null check (array_length(scores,1)=5 and scores <@ array[1,2,3,4,5] and array_position(scores,null) is null),
 created_at timestamptz not null default now()
);
alter table public.feedback_responses enable row level security;
revoke all on public.feedback_responses from anon, authenticated;
create or replace function public.survey_results() returns jsonb
language sql security definer set search_path=public as $$
 with groups(g) as (values ('all'),('yes'),('no')),
 summary as (select g, (select count(*) from feedback_responses r where g='all' or r.experience=g) n,
 (select jsonb_agg(v order by i) from (select i,(select avg(r.scores[i]) from feedback_responses r where g='all' or r.experience=g) v from generate_series(1,5) i) m) means,
 (select jsonb_agg(v order by i) from (select i,(select jsonb_agg(c order by j) from (select j,(select count(*) from feedback_responses r where (g='all' or r.experience=g) and r.scores[i]=j) c from generate_series(1,5) j) d) v from generate_series(1,5) i) m) distribution from groups)
 select jsonb_object_agg(g,jsonb_build_object('n',n,'means',means,'distribution',distribution)) from summary;
$$;
create or replace function public.submit_survey(p_token uuid,p_experience text,p_scores integer[]) returns jsonb
language plpgsql security definer set search_path=public as $$
begin
 if p_experience not in ('yes','no') or p_experience is null or array_length(p_scores,1) is distinct from 5 or not (p_scores <@ array[1,2,3,4,5]) or array_position(p_scores,null) is not null then raise exception 'Invalid response'; end if;
 insert into feedback_responses(token,experience,scores) values(p_token,p_experience,p_scores) on conflict(token) do nothing;
 return survey_results();
end; $$;
revoke all on function public.survey_results() from public;
revoke all on function public.submit_survey(uuid,text,integer[]) from public;
grant execute on function public.survey_results() to anon,authenticated;
grant execute on function public.submit_survey(uuid,text,integer[]) to anon,authenticated;
