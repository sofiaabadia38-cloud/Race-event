-- ARENA RACE — DRIFT FAN VOTE | Rode no SQL Editor do Supabase
create table drivers(id uuid primary key default gen_random_uuid(), name text not null, number int, car text, team text, photo_url text, created_at timestamptz default now());
create table settings(id int primary key default 1 check(id=1), voting_open boolean default true, ranking_public boolean default true);
insert into settings default values;
create table votes(id bigserial primary key, driver_id uuid references drivers(id) on delete cascade, voter_token text unique not null, created_at timestamptz default now());
create table admins(user_id uuid primary key references auth.users(id) on delete cascade);

create function is_admin() returns boolean language sql security definer stable as $$ select exists(select 1 from admins where user_id=auth.uid()) $$;

alter table drivers enable row level security; alter table settings enable row level security;
alter table votes enable row level security; alter table admins enable row level security;
create policy d_read on drivers for select using (true);
create policy d_write on drivers for all using (is_admin()) with check (is_admin());
create policy s_read on settings for select using (true);
create policy s_upd on settings for update using (is_admin());
create policy a_read on admins for select using (user_id=auth.uid());
-- votes: sem policy = ninguém lê/escreve direto; só via funções abaixo

-- Voto validado no servidor (1 voto por token, votação precisa estar aberta)
create function cast_vote(p_driver uuid, p_token text) returns text language plpgsql security definer as $$
begin
  if length(coalesce(p_token,''))<32 then return 'invalid'; end if;
  if not (select voting_open from settings where id=1) then return 'closed'; end if;
  if not exists(select 1 from drivers where id=p_driver) then return 'invalid'; end if;
  insert into votes(driver_id,voter_token) values(p_driver,p_token);
  return 'ok';
exception when unique_violation then return 'duplicate';
end $$;

-- Resultados agregados (vazio para o público se o ranking estiver oculto)
create function get_results() returns table(driver_id uuid, total bigint) language sql security definer as $$
  select d.id, count(v.id) from drivers d left join votes v on v.driver_id=d.id
  where is_admin() or (select ranking_public from settings where id=1)
  group by d.id
$$;

create function reset_votes() returns void language plpgsql security definer as $$
begin if not is_admin() then raise exception 'forbidden'; end if; delete from votes where true; end $$;

grant execute on function cast_vote, get_results to anon, authenticated;
grant execute on function reset_votes to authenticated;

-- Realtime + Storage de fotos
alter publication supabase_realtime add table drivers, settings;
insert into storage.buckets(id,name,public) values('drivers','drivers',true);
create policy img_read on storage.objects for select using (bucket_id='drivers');
create policy img_write on storage.objects for all using (bucket_id='drivers' and is_admin()) with check (bucket_id='drivers' and is_admin());

-- Depois de criar o usuário admin em Authentication > Users, libere-o:
-- insert into admins(user_id) select id from auth.users where email='sofiaabadia38@gmail.com';