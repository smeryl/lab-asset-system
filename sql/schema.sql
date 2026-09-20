-- =====================================================================
--  LABORATORY ASSET MANAGEMENT SYSTEM - FULL DATABASE SCHEMA
--  Run this ENTIRE file in Supabase -> SQL Editor -> New Query -> Run
--
--  SAFE TO RE-RUN. It drops and rebuilds the four public tables.
--  Your login accounts live in auth.users and are NOT touched.
--  public.users is automatically refilled from auth.users at the end.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. CLEAN SLATE
-- ---------------------------------------------------------------------
drop table if exists public.audit_logs        cascade;
drop table if exists public.borrowing_requests cascade;
drop table if exists public.equipment          cascade;
drop table if exists public.users              cascade;

drop function if exists public.handle_new_user()          cascade;
drop function if exists public.my_role()                  cascade;
drop function if exists public.is_admin()                 cascade;
drop function if exists public.is_staff_or_admin()        cascade;
drop function if exists public.write_audit_log()          cascade;
drop function if exists public.enforce_request_rules()    cascade;
drop function if exists public.audit_equipment_changes()  cascade;


-- ---------------------------------------------------------------------
-- 1. TABLES
-- ---------------------------------------------------------------------

-- 1.1 USERS  (profile table mirroring auth.users)
create table public.users (
  id         uuid primary key references auth.users(id) on delete cascade,
  email      text not null,
  full_name  text,
  role       text not null default 'requester'
             check (role in ('admin', 'staff', 'requester')),
  created_at timestamptz not null default now()
);

-- 1.2 EQUIPMENT
create table public.equipment (
  id          bigint generated always as identity primary key,
  asset_tag   text not null unique,
  name        text not null,
  category    text,
  location    text,
  status      text not null default 'available'
              check (status in ('available','borrowed','maintenance','damaged','retired')),
  notes       text,
  created_at  timestamptz not null default now()
);

-- 1.3 BORROWING REQUESTS
create table public.borrowing_requests (
  id            bigint generated always as identity primary key,
  requester_id  uuid   not null,
  equipment_id  bigint not null,
  approver_id   uuid,
  status        text   not null default 'pending'
                check (status in ('pending','approved','rejected','released','returned','overdue','closed')),
  notes         text,
  request_date  timestamptz not null default now(),
  due_date      timestamptz,
  approval_date timestamptz,
  release_date  timestamptz,
  return_date   timestamptz,
  is_damaged    boolean not null default false,

  -- Named constraints so PostgREST joins (users!requester_id) always resolve
  constraint borrowing_requests_requester_id_fkey
      foreign key (requester_id) references public.users(id) on delete cascade,
  constraint borrowing_requests_equipment_id_fkey
      foreign key (equipment_id) references public.equipment(id) on delete cascade,
  constraint borrowing_requests_approver_id_fkey
      foreign key (approver_id)  references public.users(id) on delete set null
);

-- 1.4 AUDIT LOGS
create table public.audit_logs (
  id          bigint generated always as identity primary key,
  user_id     uuid,
  action      text not null,
  module      text not null,
  record_id   bigint,
  description text,
  created_at  timestamptz not null default now(),

  constraint audit_logs_user_id_fkey
      foreign key (user_id) references public.users(id) on delete set null
);

create index idx_requests_requester on public.borrowing_requests(requester_id);
create index idx_requests_status    on public.borrowing_requests(status);
create index idx_equipment_status   on public.equipment(status);
create index idx_audit_created      on public.audit_logs(created_at desc);


-- ---------------------------------------------------------------------
-- 2. HELPER FUNCTIONS
--    SECURITY DEFINER = these bypass RLS, which PREVENTS the classic
--    "infinite recursion detected in policy for relation users" error.
-- ---------------------------------------------------------------------
create function public.my_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role from public.users where id = auth.uid();
$$;

create function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select role from public.users where id = auth.uid()) = 'admin', false);
$$;

create function public.is_staff_or_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select role from public.users where id = auth.uid()) in ('staff','admin'), false);
$$;


-- ---------------------------------------------------------------------
-- 3. AUTO-CREATE PROFILE ON SIGNUP
--    Without this, a new user can log in but has NO row in public.users,
--    so getCurrentUser() returns null and every page bounces to login.
-- ---------------------------------------------------------------------
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users (id, email, full_name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)),
    coalesce(new.raw_user_meta_data ->> 'role', 'requester')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ---------------------------------------------------------------------
-- 4. BUSINESS RULES (BR-A4-01 .. BR-A4-09) ENFORCED IN THE DATABASE
-- ---------------------------------------------------------------------
create function public.enforce_request_rules()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  eq_status text;
begin
  if (tg_op = 'INSERT') then
    select status into eq_status from public.equipment where id = new.equipment_id;

    -- BR-A4-01 / BR-A4-09: only available equipment may be requested
    if eq_status is distinct from 'available' then
      raise exception 'BR-A4-01: Equipment is % and cannot be requested.', coalesce(eq_status,'missing');
    end if;

    new.status := 'pending';
    return new;
  end if;

  if (tg_op = 'UPDATE') then

    -- BR-A4-03: only an administrator may approve or reject
    if new.status in ('approved','rejected') and old.status <> new.status then
      if not public.is_admin() then
        raise exception 'BR-A4-03: Only an administrator may approve or reject requests.';
      end if;
      -- BR-A4-02: nobody may approve their own request
      if new.requester_id = auth.uid() then
        raise exception 'BR-A4-02: You cannot approve or reject your own request.';
      end if;
      new.approver_id   := auth.uid();
      new.approval_date := now();
    end if;

    -- BR-A4-04 / BR-A4-07: only APPROVED requests may be released
    if new.status = 'released' and old.status <> 'released' then
      if old.status <> 'approved' then
        raise exception 'BR-A4-04: Only approved requests may be released (current status: %).', old.status;
      end if;
      new.release_date := now();
      -- BR-A4-05: released equipment becomes borrowed
      update public.equipment set status = 'borrowed' where id = new.equipment_id;
    end if;

    -- BR-A4-08: a returned transaction cannot be processed twice
    if new.status = 'returned' and old.status <> 'returned' then
      if old.status not in ('released','overdue') then
        raise exception 'BR-A4-08: Only released or overdue transactions can be returned (current status: %).', old.status;
      end if;
      new.return_date := now();
      -- BR-A4-06: returned equipment becomes available unless damaged
      update public.equipment
         set status = case when new.is_damaged then 'damaged' else 'available' end
       where id = new.equipment_id;
    end if;

    return new;
  end if;

  return new;
end;
$$;

create trigger trg_request_rules
  before insert or update on public.borrowing_requests
  for each row execute function public.enforce_request_rules();


-- ---------------------------------------------------------------------
-- 5. AUDIT TRAIL (BR-A4-10)
-- ---------------------------------------------------------------------
create function public.write_audit_log()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  tag text;
begin
  select asset_tag into tag from public.equipment
   where id = coalesce(new.equipment_id, old.equipment_id);

  if (tg_op = 'INSERT') then
    insert into public.audit_logs (user_id, action, module, record_id, description)
    values (auth.uid(), 'CREATED', 'Borrowing', new.id,
            'Submitted borrowing request for ' || coalesce(tag,'asset'));

  elsif (tg_op = 'UPDATE' and old.status is distinct from new.status) then
    insert into public.audit_logs (user_id, action, module, record_id, description)
    values (auth.uid(), upper(new.status), 'Borrowing', new.id,
            upper(new.status) || ' borrowing request for ' || coalesce(tag,'asset'));
  end if;

  return null;
end;
$$;

create trigger trg_audit_requests
  after insert or update on public.borrowing_requests
  for each row execute function public.write_audit_log();


create function public.audit_equipment_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (tg_op = 'INSERT') then
    insert into public.audit_logs (user_id, action, module, record_id, description)
    values (auth.uid(), 'CREATED', 'Equipment', new.id,
            'Registered asset ' || new.asset_tag || ' (' || new.name || ')');
  elsif (tg_op = 'UPDATE' and old.status is distinct from new.status) then
    insert into public.audit_logs (user_id, action, module, record_id, description)
    values (auth.uid(), 'UPDATED', 'Equipment', new.id,
            'Asset ' || new.asset_tag || ' status ' || old.status || ' -> ' || new.status);
  elsif (tg_op = 'DELETE') then
    insert into public.audit_logs (user_id, action, module, record_id, description)
    values (auth.uid(), 'DELETED', 'Equipment', old.id,
            'Removed asset ' || old.asset_tag);
  end if;
  return null;
end;
$$;

create trigger trg_audit_equipment
  after insert or update or delete on public.equipment
  for each row execute function public.audit_equipment_changes();


-- ---------------------------------------------------------------------
-- 6. ROW LEVEL SECURITY
--    THIS IS THE PART THAT WAS MAKING YOUR PAGES SHOW NOTHING.
--    RLS with no matching SELECT policy returns an EMPTY ARRAY and NO
--    ERROR, so the page silently renders blank.
-- ---------------------------------------------------------------------
alter table public.users              enable row level security;
alter table public.equipment          enable row level security;
alter table public.borrowing_requests enable row level security;
alter table public.audit_logs         enable row level security;

-- Remove any old policies left over from your current project
do $$
declare p record;
begin
  for p in
    select policyname, tablename from pg_policies
     where schemaname = 'public'
       and tablename in ('users','equipment','borrowing_requests','audit_logs')
  loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

-- 6.1 USERS ----------------------------------------------------------
-- Everyone reads their own row; staff and admin read everyone
-- (staff need requester names on the borrowing desk).
create policy users_select on public.users
  for select to authenticated
  using (id = auth.uid() or public.is_staff_or_admin());

create policy users_update_self on public.users
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid() and role = public.my_role());  -- cannot self-promote

create policy users_admin_all on public.users
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- 6.2 EQUIPMENT ------------------------------------------------------
create policy equipment_select on public.equipment
  for select to authenticated
  using (true);                                   -- all roles may view

create policy equipment_admin_write on public.equipment
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy equipment_staff_update on public.equipment
  for update to authenticated
  using (public.is_staff_or_admin())
  with check (public.is_staff_or_admin());        -- staff may flag maintenance

-- 6.3 BORROWING REQUESTS --------------------------------------------
create policy requests_select on public.borrowing_requests
  for select to authenticated
  using (requester_id = auth.uid() or public.is_staff_or_admin());

create policy requests_insert on public.borrowing_requests
  for insert to authenticated
  with check (requester_id = auth.uid());

create policy requests_update on public.borrowing_requests
  for update to authenticated
  using (public.is_staff_or_admin())
  with check (public.is_staff_or_admin());

create policy requests_admin_delete on public.borrowing_requests
  for delete to authenticated
  using (public.is_admin());                      -- TC-A4-09: staff delete blocked

-- 6.4 AUDIT LOGS -----------------------------------------------------
create policy audit_admin_select on public.audit_logs
  for select to authenticated
  using (public.is_admin());
-- No insert policy on purpose: only the SECURITY DEFINER triggers write here.


-- ---------------------------------------------------------------------
-- 7. BACKFILL PROFILES FOR ACCOUNTS THAT ALREADY EXIST
-- ---------------------------------------------------------------------
insert into public.users (id, email, full_name, role)
select
  u.id,
  u.email,
  coalesce(u.raw_user_meta_data ->> 'full_name', split_part(u.email, '@', 1)),
  coalesce(u.raw_user_meta_data ->> 'role', 'requester')
from auth.users u
on conflict (id) do nothing;

-- Assign the demo roles from your README
update public.users set role = 'admin',     full_name = 'Admin User'     where email = 'admin@lab.com';
update public.users set role = 'staff',     full_name = 'Staff User'     where email = 'staff@lab.com';
update public.users set role = 'requester', full_name = 'Requester User' where email = 'request@lab.com';
update public.users set role = 'requester', full_name = 'Meryl Soriano'  where email = 'soriano@lab.com';


-- ---------------------------------------------------------------------
-- 8. SEED EQUIPMENT (so your pages have something to show immediately)
-- ---------------------------------------------------------------------
insert into public.equipment (asset_tag, name, category, location, status) values
  ('LAP-001', 'Dell Latitude 5440 Laptop', 'Computing',   'Lab A - Cabinet 1', 'available'),
  ('LAP-002', 'HP ProBook 450 Laptop',     'Computing',   'Lab A - Cabinet 1', 'available'),
  ('MIC-001', 'Olympus CX23 Microscope',   'Optics',      'Lab B - Bench 3',   'available'),
  ('MIC-002', 'Leica DM500 Microscope',    'Optics',      'Lab B - Bench 3',   'maintenance'),
  ('CEN-001', 'Eppendorf 5425 Centrifuge', 'Separation',  'Lab B - Bench 1',   'available'),
  ('PHM-001', 'Hanna HI2020 pH Meter',     'Measurement', 'Lab C - Shelf 2',   'available'),
  ('OSC-001', 'Rigol DS1054Z Oscilloscope','Electronics', 'Lab C - Shelf 4',   'available'),
  ('AUT-001', 'Tuttnauer 2540 Autoclave',  'Sterilizing', 'Lab B - Corner',    'available'),
  ('BAL-001', 'Ohaus PX224 Analytical Balance', 'Measurement', 'Lab C - Shelf 1', 'available'),
  ('PRJ-001', 'Epson EB-X51 Projector',    'AV',          'Storage Room',      'damaged')
on conflict (asset_tag) do nothing;


-- ---------------------------------------------------------------------
-- 9. VERIFY
-- ---------------------------------------------------------------------
select 'users' as table_name, count(*) from public.users
union all select 'equipment', count(*) from public.equipment
union all select 'borrowing_requests', count(*) from public.borrowing_requests
union all select 'audit_logs', count(*) from public.audit_logs;
