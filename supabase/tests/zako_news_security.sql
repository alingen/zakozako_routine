-- Run after the migration as postgres (SQL Editor or psql). Everything rolls back.
-- No real posts/users are read, changed, or deleted by these fixtures.
begin;
do $$
declare
  a uuid := gen_random_uuid(); b uuid := gen_random_uuid();
  p uuid; p2 uuid; blocked_post uuid; result uuid; block_id uuid;
  checks integer := 0; n integer; rejected boolean;
begin
  insert into auth.users(id) values(a),(b);
  perform set_config('request.jwt.claim.sub',a::text,true);
  perform set_config('role','authenticated',true);
  p := public.zako_publish('fixture-one','achievement','テストA','本を読む',now());
  result := public.zako_publish('fixture-one','achievement','テストA','本を読む',now());
  assert p=result, 'Retry duplicated a post'; checks:=checks+1;
  perform public.zako_comment(p,'できた');
  assert (select comment='できた' from public.zako_feed(p_ids=>array[p])), 'Comment did not update original'; checks:=checks+1;

  rejected:=false;
  begin perform public.zako_comment(p,repeat('あ',31)); exception when check_violation then rejected:=true; end;
  assert rejected, 'Oversized comment accepted'; checks:=checks+1;
  rejected:=false;
  begin perform public.zako_comment(p,'https://example.com'); exception when check_violation then rejected:=true; end;
  assert rejected, 'URL accepted'; checks:=checks+1;
  rejected:=false;
  begin perform public.zako_comment(p,E'first\nsecond'); exception when check_violation then rejected:=true; end;
  assert rejected, 'Newline accepted'; checks:=checks+1;

  perform set_config('request.jwt.claim.sub',b::text,true);
  assert (select count(*)=1 from public.zako_feed(p_ids=>array[p])), 'Other users cannot see public post'; checks:=checks+1;
  assert not (select to_jsonb(f) ? 'author_id' from public.zako_feed(p_ids=>array[p]) f), 'Author identity leaked'; checks:=checks+1;
  rejected:=false;
  begin perform public.zako_comment(p,'stolen'); exception when insufficient_privilege then rejected:=true; end;
  assert rejected, 'Other user updated post'; checks:=checks+1;
  rejected:=false;
  begin perform public.zako_delete(p); exception when insufficient_privilege then rejected:=true; end;
  assert rejected, 'Other user deleted post'; checks:=checks+1;
  rejected:=false;
  begin perform 1 from public.zako_news_posts; exception when insufficient_privilege then rejected:=true; end;
  assert rejected, 'Raw table / author ID accessible'; checks:=checks+1;
  rejected:=false;
  begin perform 1 from public.zako_news_reports; exception when insufficient_privilege then rejected:=true; end;
  assert rejected, 'Raw reports accessible'; checks:=checks+1;
  rejected:=false;
  begin perform 1 from public.zako_user_blocks; exception when insufficient_privilege then rejected:=true; end;
  assert rejected, 'Raw blocks accessible'; checks:=checks+1;

  perform public.zako_react(p,'cheer'); perform public.zako_react(p,'cheer');
  assert (select cheer_count=1 from public.zako_feed(p_ids=>array[p])), 'Duplicate reaction'; checks:=checks+1;
  perform public.zako_react(p,'strong');
  assert (select cheer_count=0 and strong_count=1 from public.zako_feed(p_ids=>array[p])), 'Reaction change duplicated'; checks:=checks+1;
  perform public.zako_react(p,null);
  assert (select strong_count=0 from public.zako_feed(p_ids=>array[p])), 'Reaction removal failed'; checks:=checks+1;
  perform public.zako_report(p,'privacy'); perform public.zako_report(p,'privacy');
  perform public.zako_block(p);
  assert (select count(*)=0 from public.zako_feed(p_ids=>array[p])), 'Block did not hide current post'; checks:=checks+1;
  select id into block_id from public.zako_blocks();
  perform set_config('request.jwt.claim.sub',a::text,true);
  p2:=public.zako_publish('fixture-two','failure','テストA','SNS',now());
  assert (select count(*)=0 from public.zako_blocks()), 'Other block list leaked'; checks:=checks+1;
  perform set_config('request.jwt.claim.sub',b::text,true);
  assert (select count(*)=0 from public.zako_feed(p_ids=>array[p2])), 'Block did not hide future post'; checks:=checks+1;
  perform public.zako_unblock(block_id);
  assert (select count(*)=1 from public.zako_feed(p_ids=>array[p2])), 'Unblock failed'; checks:=checks+1;

  perform set_config('role','postgres',true);
  assert (select count(*)=1 from public.zako_news_reports where post_id=p and reporter_id=b), 'Duplicate report'; checks:=checks+1;
  update public.zako_news_posts set moderation_status='hidden' where id=p;
  update public.zako_news_posts set is_public=false where id=p2;
  perform set_config('role','authenticated',true);
  assert (select count(*)=0 from public.zako_feed(p_ids=>array[p,p2])), 'Hidden/private post leaked'; checks:=checks+1;
  perform set_config('request.jwt.claim.sub',a::text,true);
  perform public.zako_delete(p);
  result:=public.zako_publish('fixture-one','achievement','テストA','本を読む',now());
  assert result=p, 'Retry recreated deleted post'; checks:=checks+1;

  perform set_config('role','postgres',true);
  update public.zako_news_posts set occurred_at=now()-interval '8 days',is_public=true,moderation_status='visible' where id=p2;
  perform set_config('role','authenticated',true);
  assert (select count(*)=0 from public.zako_feed(p_ids=>array[p2])), 'Expired post leaked'; checks:=checks+1;
  perform set_config('role','postgres',true);
  assert (select count(*)=5 from pg_tables where schemaname='public'
    and tablename in ('zako_profiles','zako_news_posts','zako_news_reactions','zako_news_reports','zako_user_blocks') and rowsecurity), 'RLS missing'; checks:=checks+1;
  perform set_config('role','anon',true);
  rejected:=false;
  begin perform public.zako_feed(); exception when insufficient_privilege then rejected:=true; end;
  assert rejected, 'Unauthenticated RPC allowed'; checks:=checks+1;
  perform set_config('role','postgres',true);
  raise notice '% Zako News security assertions passed', checks;
end $$;
select '25 Zako News security assertions passed (fixtures rolled back)' as result;
rollback;
