-- Zako News v1. No existing habit records are uploaded or modified.
begin;
create schema if not exists zako_private;
revoke all on schema zako_private from public, anon, authenticated;

-- Keep validation limits centralized; the client mirrors these for immediate feedback.
create function zako_private.valid_text(value text, maximum integer, allow_empty boolean default false)
returns boolean language sql immutable set search_path = '' as $$
  select value is not null and char_length(value) <= maximum
    and (allow_empty or char_length(btrim(value)) > 0)
    and value !~ '[[:cntrl:]]'
    and value !~* '(https?://|www[.]|[[:alnum:]_-]+[.][a-z]{2,}([/:[:space:]]|$))';
$$;
create function zako_private.comment_limit() returns integer
language sql immutable set search_path = '' as $$ select 30; $$;

create table public.zako_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check(zako_private.valid_text(display_name, 10)),
  updated_at timestamptz not null default now()
);
create table public.zako_news_posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users(id) on delete cascade,
  source_key text not null check(char_length(source_key) between 1 and 180),
  kind text not null check(kind in ('achievement','failure')),
  display_name text not null check(zako_private.valid_text(display_name, 10)),
  task_title text not null check(zako_private.valid_text(task_title, 80)),
  comment text not null default '' check(zako_private.valid_text(comment, zako_private.comment_limit(), true)),
  occurred_at timestamptz not null,
  created_at timestamptz not null default now(),
  is_public boolean not null default true,
  moderation_status text not null default 'visible' check(moderation_status in ('pending','visible','hidden')),
  deleted_at timestamptz,
  unique(author_id, source_key)
);
create table public.zako_news_reactions (
  post_id uuid not null references public.zako_news_posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reaction text not null check(reaction in ('cheer','tease','strong')),
  created_at timestamptz not null default now(),
  primary key(post_id, user_id)
);
create table public.zako_news_reports (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.zako_news_posts(id) on delete cascade,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reason text not null check(reason in ('inappropriate','privacy','harassment','spam','other')),
  created_at timestamptz not null default now(),
  unique(post_id, reporter_id)
);
create table public.zako_user_blocks (
  id uuid primary key default gen_random_uuid(),
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null,
  created_at timestamptz not null default now(),
  unique(blocker_id, blocked_id),
  check(blocker_id <> blocked_id)
);
create index zako_news_feed_idx on public.zako_news_posts(created_at desc, id desc)
  where is_public and deleted_at is null and moderation_status = 'visible';
create index zako_news_author_idx on public.zako_news_posts(author_id, created_at desc);
create index zako_news_expiry_idx on public.zako_news_posts(occurred_at);
create index zako_reactions_user_idx on public.zako_news_reactions(user_id);
create index zako_reports_reporter_idx on public.zako_news_reports(reporter_id);
create index zako_blocks_target_idx on public.zako_user_blocks(blocked_id);

-- Deny direct table reads/writes, including author UUIDs. Only the narrow RPCs below
-- are exposed. Owner policies are defense in depth if grants are changed later.
alter table public.zako_profiles enable row level security;
alter table public.zako_news_posts enable row level security;
alter table public.zako_news_reactions enable row level security;
alter table public.zako_news_reports enable row level security;
alter table public.zako_user_blocks enable row level security;
create policy own_profile on public.zako_profiles for all to authenticated
  using(user_id = (select auth.uid())) with check(user_id = (select auth.uid()));
create policy own_posts on public.zako_news_posts for all to authenticated
  using(author_id = (select auth.uid())) with check(author_id = (select auth.uid()));
create policy own_reactions on public.zako_news_reactions for all to authenticated
  using(user_id = (select auth.uid())) with check(user_id = (select auth.uid()));
create policy own_reports on public.zako_news_reports for all to authenticated
  using(reporter_id = (select auth.uid())) with check(reporter_id = (select auth.uid()));
create policy own_blocks on public.zako_user_blocks for all to authenticated
  using(blocker_id = (select auth.uid())) with check(blocker_id = (select auth.uid()));
revoke all on public.zako_profiles, public.zako_news_posts, public.zako_news_reactions,
  public.zako_news_reports, public.zako_user_blocks from public, anon, authenticated;

create function zako_private.viewer() returns uuid
language plpgsql stable set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  return auth.uid();
end $$;
create function zako_private.visible(p public.zako_news_posts, viewer uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select p.is_public and p.deleted_at is null and p.moderation_status = 'visible'
    and p.occurred_at > now() - interval '7 days'
    and not exists(select 1 from public.zako_user_blocks b where b.blocker_id = viewer and b.blocked_id = p.author_id);
$$;

create function public.zako_feed(p_before timestamptz default null, p_before_id uuid default null,
  p_limit integer default 20, p_ids uuid[] default null, p_mine boolean default false)
returns table(id uuid, kind text, display_name text, task_title text, comment text,
  occurred_at timestamptz, created_at timestamptz, is_mine boolean,
  cheer_count bigint, tease_count bigint, strong_count bigint, my_reaction text)
language plpgsql stable security definer set search_path = '' as $$
declare viewer uuid := zako_private.viewer();
begin
  return query
  select p.id,p.kind,p.display_name,p.task_title,p.comment,p.occurred_at,p.created_at,p.author_id=viewer,
    (select count(*) from public.zako_news_reactions r where r.post_id=p.id and r.reaction='cheer'),
    (select count(*) from public.zako_news_reactions r where r.post_id=p.id and r.reaction='tease'),
    (select count(*) from public.zako_news_reactions r where r.post_id=p.id and r.reaction='strong'),
    (select r.reaction from public.zako_news_reactions r where r.post_id=p.id and r.user_id=viewer)
  from public.zako_news_posts p
  where zako_private.visible(p,viewer) and (not p_mine or p.author_id=viewer)
    and (p_ids is null or p.id=any(p_ids))
    and (p_before is null or (p.created_at,p.id)<(p_before,coalesce(p_before_id,'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
  order by p.created_at desc,p.id desc limit greatest(1,least(p_limit,50));
end $$;

create function public.zako_publish(p_source_key text, p_kind text, p_display_name text,
  p_task_title text, p_occurred_at timestamptz) returns uuid
language plpgsql security definer set search_path = '' as $$
declare viewer uuid := zako_private.viewer(); result uuid;
begin
  -- Serialize creation per account: bounded posting and retry checks are race-safe.
  perform pg_advisory_xact_lock(hashtextextended(viewer::text, 0));
  select id into result from public.zako_news_posts where author_id=viewer and source_key=p_source_key;
  if result is not null then return result; end if;
  if p_occurred_at < now()-interval '7 days' or p_occurred_at > now()+interval '5 minutes' then
    raise exception 'Invalid event date' using errcode='22023'; end if;
  if (select count(*) from public.zako_news_posts where author_id=viewer and created_at>now()-interval '1 hour') >= 60 then
    raise exception 'Posting limit reached' using errcode='22023'; end if;
  insert into public.zako_profiles(user_id,display_name) values(viewer,p_display_name)
    on conflict(user_id) do update set display_name=excluded.display_name,updated_at=now();
  insert into public.zako_news_posts(author_id,source_key,kind,display_name,task_title,occurred_at)
    values(viewer,p_source_key,p_kind,p_display_name,p_task_title,p_occurred_at) returning id into result;
  return result;
end $$;

create function public.zako_comment(p_post_id uuid, p_comment text) returns void
language plpgsql security definer set search_path = '' as $$
declare viewer uuid := zako_private.viewer();
begin
  update public.zako_news_posts set comment=p_comment where id=p_post_id and author_id=viewer
    and deleted_at is null and moderation_status='visible' and occurred_at>now()-interval '7 days';
  if not found then raise exception 'Post unavailable' using errcode='42501'; end if;
end $$;
create function public.zako_delete(p_post_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare viewer uuid := zako_private.viewer();
begin
  update public.zako_news_posts set deleted_at=coalesce(deleted_at,now()),is_public=false
    where id=p_post_id and author_id=viewer;
  if not found then raise exception 'Post unavailable' using errcode='42501'; end if;
end $$;
create function public.zako_react(p_post_id uuid, p_reaction text) returns void
language plpgsql security definer set search_path = '' as $$
declare viewer uuid := zako_private.viewer();
begin
  perform 1 from public.zako_news_posts p where p.id=p_post_id and zako_private.visible(p,viewer) for share;
  if not found then raise exception 'Post unavailable' using errcode='42501'; end if;
  if p_reaction is null then
    delete from public.zako_news_reactions where post_id=p_post_id and user_id=viewer;
  else
    insert into public.zako_news_reactions(post_id,user_id,reaction) values(p_post_id,viewer,p_reaction)
      on conflict(post_id,user_id) do update set reaction=excluded.reaction;
  end if;
end $$;
create function public.zako_report(p_post_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare viewer uuid := zako_private.viewer();
begin
  perform 1 from public.zako_news_posts p where p.id=p_post_id and zako_private.visible(p,viewer) and p.author_id<>viewer;
  if not found then raise exception 'Post unavailable' using errcode='42501'; end if;
  insert into public.zako_news_reports(post_id,reporter_id,reason) values(p_post_id,viewer,p_reason)
    on conflict(post_id,reporter_id) do nothing;
end $$;
create function public.zako_block(p_post_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare viewer uuid := zako_private.viewer(); target public.zako_news_posts;
begin
  select * into target from public.zako_news_posts p where p.id=p_post_id and zako_private.visible(p,viewer) and p.author_id<>viewer;
  if not found then raise exception 'Post unavailable' using errcode='42501'; end if;
  insert into public.zako_user_blocks(blocker_id,blocked_id,display_name) values(viewer,target.author_id,target.display_name)
    on conflict(blocker_id,blocked_id) do nothing;
end $$;
create function public.zako_blocks() returns table(id uuid, display_name text, created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
declare viewer uuid := zako_private.viewer();
begin return query select b.id,b.display_name,b.created_at from public.zako_user_blocks b
  where b.blocker_id=viewer order by b.created_at desc; end $$;
create function public.zako_unblock(p_block_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare viewer uuid := zako_private.viewer();
begin delete from public.zako_user_blocks where id=p_block_id and blocker_id=viewer; end $$;

-- Lock down all newly-created functions, then grant only the public RPC surface.
revoke all on all functions in schema zako_private from public, anon, authenticated;
do $$ declare f regprocedure; begin
  for f in select oid::regprocedure from pg_proc where pronamespace='public'::regnamespace and proname in
    ('zako_feed','zako_publish','zako_comment','zako_delete','zako_react','zako_report','zako_block','zako_blocks','zako_unblock') loop
    execute format('revoke all on function %s from public, anon, authenticated',f);
    execute format('grant execute on function %s to authenticated',f);
  end loop;
end $$;

create function zako_private.purge_expired() returns void language sql security definer set search_path = '' as $$
  delete from public.zako_news_posts where occurred_at <= now()-interval '7 days';
$$;
revoke all on function zako_private.purge_expired() from public, anon, authenticated;
create extension if not exists pg_cron;
select cron.schedule('zako-news-retention', '17 * * * *', 'select zako_private.purge_expired()');
commit;
