begin;

-- REC-584: optional self-reported contact details, kept separate from public
-- profiles and verified Clerk/contact matching identities. No exact location.
create table app.home_metro_areas (
  id text primary key,
  name text not null,
  country_code text not null check (country_code ~ '^[A-Z]{2}$')
);
revoke all on app.home_metro_areas from public, anon, authenticated;
insert into app.home_metro_areas (id, name, country_code) values
  ('los-angeles', 'Los Angeles', 'US'),
  ('orange-county', 'Orange County', 'US'),
  ('inland-empire', 'Inland Empire', 'US'),
  ('new-york', 'New York', 'US'),
  ('san-francisco', 'San Francisco Bay Area', 'US'),
  ('chicago', 'Chicago', 'US'),
  ('boston', 'Boston', 'US'),
  ('washington', 'Washington, DC', 'US'),
  ('philadelphia', 'Philadelphia', 'US'),
  ('miami', 'Miami–Fort Lauderdale', 'US'),
  ('atlanta', 'Atlanta', 'US'),
  ('dallas', 'Dallas–Fort Worth', 'US'),
  ('houston', 'Houston', 'US'),
  ('austin', 'Austin', 'US'),
  ('san-antonio', 'San Antonio', 'US'),
  ('seattle', 'Seattle', 'US'),
  ('portland', 'Portland', 'US'),
  ('san-diego', 'San Diego', 'US'),
  ('sacramento', 'Sacramento', 'US'),
  ('las-vegas', 'Las Vegas', 'US'),
  ('phoenix', 'Phoenix', 'US'),
  ('denver', 'Denver', 'US'),
  ('salt-lake-city', 'Salt Lake City', 'US'),
  ('minneapolis', 'Minneapolis–Saint Paul', 'US'),
  ('detroit', 'Detroit', 'US'),
  ('st-louis', 'St. Louis', 'US'),
  ('kansas-city', 'Kansas City', 'US'),
  ('nashville', 'Nashville', 'US'),
  ('charlotte', 'Charlotte', 'US'),
  ('raleigh', 'Raleigh–Durham', 'US'),
  ('tampa', 'Tampa Bay', 'US'),
  ('orlando', 'Orlando', 'US'),
  ('new-orleans', 'New Orleans', 'US'),
  ('pittsburgh', 'Pittsburgh', 'US'),
  ('cleveland', 'Cleveland', 'US'),
  ('columbus', 'Columbus', 'US'),
  ('indianapolis', 'Indianapolis', 'US'),
  ('cincinnati', 'Cincinnati', 'US'),
  ('milwaukee', 'Milwaukee', 'US'),
  ('baltimore', 'Baltimore', 'US'),
  ('honolulu', 'Honolulu', 'US'),
  ('toronto', 'Toronto', 'CA'),
  ('vancouver', 'Vancouver', 'CA'),
  ('montreal', 'Montréal', 'CA'),
  ('mexico-city', 'Mexico City', 'MX'),
  ('london', 'London', 'GB'),
  ('paris', 'Paris', 'FR'),
  ('berlin', 'Berlin', 'DE'),
  ('amsterdam', 'Amsterdam', 'NL'),
  ('madrid', 'Madrid', 'ES'),
  ('barcelona', 'Barcelona', 'ES'),
  ('rome', 'Rome', 'IT'),
  ('sydney', 'Sydney', 'AU'),
  ('melbourne', 'Melbourne', 'AU'),
  ('tokyo', 'Tokyo', 'JP'),
  ('seoul', 'Seoul', 'KR'),
  ('singapore', 'Singapore', 'SG'),
  ('hong-kong', 'Hong Kong', 'HK'),
  ('dubai', 'Dubai', 'AE'),
  ('mumbai', 'Mumbai', 'IN'),
  ('delhi', 'Delhi', 'IN'),
  ('sao-paulo', 'São Paulo', 'BR');

create table public.account_contact_details (
  user_id text primary key references public.profiles(id) on delete cascade,
  metro_id text,
  home_city jsonb check (home_city is null or jsonb_typeof(home_city) = 'object'),
  home_country_code text check (home_country_code ~ '^[A-Z]{2}$'),
  phone_country_code text not null check (phone_country_code ~ '^[A-Z]{2}$'),
  phone_e164 text check (phone_e164 ~ '^\+[1-9][0-9]{6,14}$'),
  updated_at timestamptz not null default now()
);
alter table public.account_contact_details enable row level security;
revoke all on public.account_contact_details from public, anon, authenticated;
grant select, insert, update, delete on public.account_contact_details to service_role;
comment on table public.account_contact_details is
  'Owner-private worldwide home city and optional unverified phone. No SMS consent or verification is implied. Never use phone for identity/contact matching without separate proof.';

-- Narrow definers intentionally avoid granting direct table access. Identity
-- comes only from the authenticated JWT, with canonical account handling.
create function public.own_account_contact_details()
returns table (metro_id text, home_country_code text, phone_country_code text, phone_e164 text, home_city jsonb)
language plpgsql stable security definer set search_path = public, app
as $$
declare viewer_id text := app.current_user_id();
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  return query select d.metro_id, d.home_country_code, d.phone_country_code, d.phone_e164, d.home_city
    from public.account_contact_details d join public.profiles p on p.id = d.user_id
    where d.user_id = viewer_id and p.deleted_at is null;
end;
$$;

create function public.save_own_account_contact_details(input_details jsonb)
returns table (metro_id text, home_country_code text, phone_country_code text, phone_e164 text, home_city jsonb)
language plpgsql volatile security definer set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  selected_metro text := input_details->>'metro_id';
  home_country text := input_details->>'home_country_code';
  phone_country text := input_details->>'phone_country_code';
  phone text := input_details->>'phone_e164';
  city jsonb := nullif(input_details->'home_city', 'null'::jsonb);
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  perform 1 from public.profiles where id = viewer_id and deleted_at is null for share;
  if not found then raise exception 'profile_not_found'; end if;
  if input_details is null or jsonb_typeof(input_details) <> 'object'
    or exists (select 1 from jsonb_each(input_details) e
      where e.key not in ('metro_id','home_country_code','phone_country_code','phone_e164','home_city')
        or (e.key <> 'home_city' and jsonb_typeof(e.value) not in ('string','null')))
    or phone_country is null or phone_country !~ '^[A-Z]{2}$'
    or (home_country is not null and home_country !~ '^[A-Z]{2}$')
    or (phone is not null and phone !~ '^\+[1-9][0-9]{6,14}$')
    or (phone is not null and phone_country in ('US','CA') and phone !~ '^\+1[2-9][0-9]{9}$') then
    raise exception 'invalid_account_contact_details';
  end if;
  -- Persist any worldwide locality. The client cannot grant LA eligibility by
  -- supplying metro_id alongside a contradictory city: derive it here as well.
  if city is not null then
    if jsonb_typeof(city) <> 'object' then raise exception 'invalid_home_city'; end if;
    if exists (select 1 from jsonb_each(city) e
      where e.key not in ('name','country_code','region','county')
        or jsonb_typeof(e.value) not in ('string','null'))
      or nullif(btrim(city->>'name'), '') is null
      or length(city->>'name') > 200
      or coalesce(city->>'country_code', '') !~ '^[A-Z]{2}$'
      or length(coalesce(city->>'region', '')) > 200
      or length(coalesce(city->>'county', '')) > 200 then
      raise exception 'invalid_home_city';
    end if;
    home_country := city->>'country_code';
    selected_metro := case when home_country = 'US'
      and city->>'region' in ('CA','California')
      and replace(lower(city->>'county'), ' county', '') = 'los angeles'
      then 'los-angeles' else 'other' end;
  elsif selected_metro is not null and selected_metro <> 'other' then
    select m.country_code into home_country from app.home_metro_areas m where m.id = selected_metro;
    if not found then raise exception 'invalid_home_metro'; end if;
  end if;
  insert into public.account_contact_details as d
    (user_id, metro_id, home_country_code, phone_country_code, phone_e164, home_city)
    values (viewer_id, selected_metro, home_country, phone_country, phone, city)
    on conflict (user_id) do update set
      home_city = excluded.home_city, metro_id = excluded.metro_id, home_country_code = excluded.home_country_code,
      phone_country_code = excluded.phone_country_code, phone_e164 = excluded.phone_e164,
      updated_at = now();
  return query select * from public.own_account_contact_details();
end;
$$;
revoke all on function public.own_account_contact_details() from public, anon, authenticated;
revoke all on function public.save_own_account_contact_details(jsonb) from public, anon, authenticated;
grant execute on function public.own_account_contact_details() to authenticated;
grant execute on function public.save_own_account_contact_details(jsonb) to authenticated;

-- Hard deletes cascade. Also erase private contact details at soft deletion.
create function app.purge_deleted_account_contact_details()
returns trigger language plpgsql security definer set search_path = public, app
as $$
begin
  if new.deleted_at is not null then
    delete from public.account_contact_details where user_id = new.id;
  end if;
  return new;
end;
$$;
revoke all on function app.purge_deleted_account_contact_details() from public, anon, authenticated;
create trigger purge_deleted_account_contact_details
  after update of deleted_at on public.profiles
  for each row execute function app.purge_deleted_account_contact_details();

commit;
