-- ===== 20261026210000_initial_schema.sql =====
-- Nestly initial schema: families, caregivers, child profiles, activities,
-- per-caregiver reminders, per-user settings, family invites and activity photos.
--
-- Conventions shared with the Android Room database:
--   * ids are client-generated UUIDs so rows can be created offline.
--   * created_at / updated_at / deleted_at are set by the client; updated_at drives
--     last-write-wins conflict resolution and deletes are soft so they sync.
--   * server_updated_at is set by the server on every write and is the pull cursor.
--   * enum-like columns hold the Kotlin enum names verbatim.
--   * volumes are ml, weights kg, lengths cm, temperatures °C.

create schema if not exists private;
grant usage on schema private to authenticated;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.family (
    id                uuid primary key,
    name              text,
    created_by        uuid default auth.uid() references auth.users (id) on delete set null,
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz,
    server_updated_at timestamptz not null default now()
);

create table public.caregiver (
    id                uuid primary key,
    family_id         uuid not null references public.family (id) on delete cascade,
    -- Null for caregivers who don't use the app themselves.
    user_id           uuid references auth.users (id) on delete set null,
    name              text not null check (length(trim(name)) > 0),
    role              text not null default 'MEMBER' check (role in ('OWNER', 'MEMBER')),
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz,
    server_updated_at timestamptz not null default now(),
    unique (family_id, name),
    unique (family_id, user_id),
    unique (id, family_id)
);

create table public.profile (
    id                  uuid primary key,
    family_id           uuid not null references public.family (id) on delete cascade,
    name                text not null,
    birth_date          date,
    adjusted_birth_date date,
    sex                 text check (sex in ('MALE', 'FEMALE', 'OTHER')),
    profile_type        text not null default 'CHILD' check (profile_type in ('CHILD', 'PREGNANCY')),
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now(),
    deleted_at          timestamptz,
    server_updated_at   timestamptz not null default now(),
    unique (id, family_id)
);

create table public.activity (
    id                        uuid primary key,
    family_id                 uuid not null references public.family (id) on delete cascade,
    -- Null for caregiver-level activities such as pumping.
    profile_id                uuid,
    type                      text not null check (type in (
        'BOTTLE_FEED', 'BREASTFEED', 'PUMP', 'DIAPER', 'GROWTH', 'MILESTONE',
        'SLEEP', 'SOLIDS', 'ROUTINE', 'BABY_FIRST', 'MEDICAL', 'VACCINE'
    )),
    start_time                timestamptz not null,
    end_time                  timestamptz,
    time_zone                 text not null,
    note                      text,
    created_by_id             uuid,
    updated_by_id             uuid,

    bottle_milk_type          text check (bottle_milk_type in ('BREAST_MILK', 'FORMULA', 'MIXED')),
    bottle_breast_milk_ml     double precision,
    bottle_formula_ml         double precision,
    bottle_formula_name       text,
    bottle_total_ml           double precision,

    pump_duration_sec         bigint,
    pump_left_ml              double precision,
    pump_right_ml             double precision,
    pump_total_ml             double precision,

    breast_begin_side         text check (breast_begin_side in ('LEFT', 'RIGHT')),
    breast_end_side           text check (breast_end_side in ('LEFT', 'RIGHT')),
    breast_left_duration_sec  bigint,
    breast_right_duration_sec bigint,
    breast_is_manual_entry    boolean,

    diaper_type               text check (diaper_type in ('WET', 'DIRTY', 'MIXED', 'DRY')),
    diaper_color              text check (diaper_color in ('YELLOW', 'GREEN', 'BROWN', 'BLACK', 'RED', 'WHITE', 'ORANGE')),
    diaper_texture            text check (diaper_texture in ('RUN', 'MUSH', 'SOLID', 'MUCOUS', 'SEEDY', 'HARD')),
    diaper_detail             text,
    diaper_has_rash           boolean,

    growth_weight_kg          double precision,
    growth_height_cm          double precision,
    growth_head_cm            double precision,

    milestone_title           text,
    milestone_key             text,

    solids_meal_type          text check (solids_meal_type in ('BREAKFAST', 'LUNCH', 'DINNER', 'SNACK')),
    solids_foods              text[],
    -- When true (default), SOLIDS counts as the last feed for next-feed / FEED reminders.
    -- New solids entries can set false to keep the milk schedule. Bottle/breastfeed always reset.
    solids_resets_feed_schedule boolean not null default true,

    routine_name              text,

    baby_first_title          text,

    medical_temperature_c     double precision,
    medical_medication_name   text,
    medical_dose              double precision,
    medical_dose_unit         text,

    vaccine_vaccines          text[],

    -- Object path in the activity-photos bucket: {family_id}/{activity_id}/{file}.
    photo_path                text,
    -- Shared by the breastfeed and bottle rows saved together from one combo feed.
    combo_group_id            uuid,

    created_at                timestamptz not null default now(),
    updated_at                timestamptz not null default now(),
    deleted_at                timestamptz,
    server_updated_at         timestamptz not null default now(),

    check (end_time is null or end_time >= start_time),
    foreign key (profile_id, family_id) references public.profile (id, family_id) on delete cascade,
    foreign key (created_by_id, family_id) references public.caregiver (id, family_id) on delete set null (created_by_id),
    foreign key (updated_by_id, family_id) references public.caregiver (id, family_id) on delete set null (updated_by_id)
);

create table public.reminder (
    id                uuid primary key,
    family_id         uuid not null references public.family (id) on delete cascade,
    -- Reminders are personal: each caregiver keeps their own schedule.
    caregiver_id      uuid not null,
    -- Null for pump reminders, which aren't tied to a child.
    profile_id        uuid,
    kind              text not null check (kind in ('FEED', 'PUMP', 'DIAPER', 'SLEEP')),
    interval_minutes  integer not null check (interval_minutes > 0),
    enabled           boolean not null default true,
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz,
    server_updated_at timestamptz not null default now(),
    unique nulls not distinct (caregiver_id, profile_id, kind),
    foreign key (caregiver_id, family_id) references public.caregiver (id, family_id) on delete cascade,
    foreign key (profile_id, family_id) references public.profile (id, family_id) on delete cascade
);

create table public.user_settings (
    user_id           uuid primary key default auth.uid() references auth.users (id) on delete cascade,
    volume_unit       text not null default 'ML' check (volume_unit in ('ML', 'OZ')),
    weight_unit       text not null default 'KG' check (weight_unit in ('KG', 'LB')),
    length_unit       text not null default 'CM' check (length_unit in ('CM', 'IN')),
    temp_unit         text not null default 'F' check (temp_unit in ('C', 'F')),
    card_order        text[] not null default '{}',
    disabled_toggles  text[] not null default '{}',
    filters           text[] not null default '{}',
    updated_at        timestamptz not null default now(),
    server_updated_at timestamptz not null default now()
);

create table public.family_invite (
    id           uuid primary key default gen_random_uuid(),
    family_id    uuid not null references public.family (id) on delete cascade,
    code         text not null unique,
    created_by   uuid default auth.uid() references auth.users (id) on delete set null,
    created_at   timestamptz not null default now(),
    expires_at   timestamptz not null default now() + interval '7 days',
    accepted_by  uuid references auth.users (id) on delete set null,
    accepted_at  timestamptz,
    revoked_at   timestamptz
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

create index caregiver_user_family_idx on public.caregiver (user_id, family_id);
create index caregiver_family_sync_idx on public.caregiver (family_id, server_updated_at);
create index profile_family_sync_idx on public.profile (family_id, server_updated_at);
create index activity_profile_type_start_idx on public.activity (profile_id, type, start_time);
create index activity_family_start_idx on public.activity (family_id, start_time);
create index activity_family_sync_idx on public.activity (family_id, server_updated_at);
create index activity_created_by_idx on public.activity (created_by_id);
create index activity_updated_by_idx on public.activity (updated_by_id);
create index reminder_family_idx on public.reminder (family_id);
create index reminder_profile_idx on public.reminder (profile_id);
create index reminder_caregiver_sync_idx on public.reminder (caregiver_id, server_updated_at);
create index family_created_by_idx on public.family (created_by);
create index family_invite_family_idx on public.family_invite (family_id);
create index family_invite_created_by_idx on public.family_invite (created_by);
create index family_invite_accepted_by_idx on public.family_invite (accepted_by);

-- ---------------------------------------------------------------------------
-- Membership helpers (security definer so policies don't recurse through caregiver RLS)
-- ---------------------------------------------------------------------------

create function private.my_family_ids()
returns setof uuid
language sql stable security definer
set search_path = ''
as $$
    select c.family_id
    from public.caregiver c
    where c.user_id = (select auth.uid()) and c.deleted_at is null
$$;

create function private.my_caregiver_ids()
returns setof uuid
language sql stable security definer
set search_path = ''
as $$
    select c.id
    from public.caregiver c
    where c.user_id = (select auth.uid()) and c.deleted_at is null
$$;

create function private.is_family_owner(fid uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
    select exists (
        select 1 from public.caregiver c
        where c.family_id = fid
          and c.user_id = (select auth.uid())
          and c.role = 'OWNER'
          and c.deleted_at is null
    )
$$;

create function private.family_has_members(fid uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
    select exists (select 1 from public.caregiver c where c.family_id = fid and c.user_id is not null)
$$;

revoke all on function private.my_family_ids() from public, anon;
revoke all on function private.my_caregiver_ids() from public, anon;
revoke all on function private.is_family_owner(uuid) from public, anon;
revoke all on function private.family_has_members(uuid) from public, anon;
grant execute on function private.my_family_ids() to authenticated;
grant execute on function private.my_caregiver_ids() to authenticated;
grant execute on function private.is_family_owner(uuid) to authenticated;
grant execute on function private.family_has_members(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

create function private.set_server_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.server_updated_at := now();
    return new;
end;
$$;

create trigger set_server_updated_at before insert or update on public.family
    for each row execute function private.set_server_updated_at();
create trigger set_server_updated_at before insert or update on public.caregiver
    for each row execute function private.set_server_updated_at();
create trigger set_server_updated_at before insert or update on public.profile
    for each row execute function private.set_server_updated_at();
create trigger set_server_updated_at before insert or update on public.activity
    for each row execute function private.set_server_updated_at();
create trigger set_server_updated_at before insert or update on public.reminder
    for each row execute function private.set_server_updated_at();
create trigger set_server_updated_at before insert or update on public.user_settings
    for each row execute function private.set_server_updated_at();

create function private.protect_family_columns()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.created_by := old.created_by;
    return new;
end;
$$;

create trigger protect_family_columns before update on public.family
    for each row execute function private.protect_family_columns();

-- Clients may rename or soft-delete caregivers, but account links, roles and the
-- removal of other signed-in members are owner-only or go through accept_family_invite.
create function private.protect_caregiver_columns()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if current_user not in ('authenticated', 'anon') then
        return new;
    end if;
    if new.family_id is distinct from old.family_id then
        raise exception 'caregiver family cannot change';
    end if;
    if new.user_id is distinct from old.user_id then
        raise exception 'caregiver account link cannot change';
    end if;
    if new.role is distinct from old.role and not private.is_family_owner(old.family_id) then
        raise exception 'only owners can change roles';
    end if;
    if old.deleted_at is null and new.deleted_at is not null
       and old.user_id is not null and old.user_id <> (select auth.uid())
       and not private.is_family_owner(old.family_id) then
        raise exception 'only owners can remove other members';
    end if;
    return new;
end;
$$;

create trigger protect_caregiver_columns before update on public.caregiver
    for each row execute function private.protect_caregiver_columns();

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.family enable row level security;
alter table public.caregiver enable row level security;
alter table public.profile enable row level security;
alter table public.activity enable row level security;
alter table public.reminder enable row level security;
alter table public.user_settings enable row level security;
alter table public.family_invite enable row level security;

revoke all on public.family, public.caregiver, public.profile, public.activity,
    public.reminder, public.user_settings, public.family_invite from anon;
grant select, insert, update, delete on public.family, public.caregiver, public.profile,
    public.activity, public.reminder, public.user_settings, public.family_invite to authenticated;

-- family: the creator can see it before their caregiver row exists.
create policy family_select on public.family for select to authenticated
    using (id in (select private.my_family_ids()) or created_by = (select auth.uid()));
create policy family_insert on public.family for insert to authenticated
    with check (created_by = (select auth.uid()));
create policy family_update on public.family for update to authenticated
    using (id in (select private.my_family_ids()))
    with check (id in (select private.my_family_ids()));
create policy family_delete on public.family for delete to authenticated
    using ((select private.is_family_owner(id)));

-- caregiver: members add name-only caregivers; the creator of a brand-new family
-- links themselves as its owner. Joining an existing family uses accept_family_invite.
create policy caregiver_select on public.caregiver for select to authenticated
    using (family_id in (select private.my_family_ids()) or user_id = (select auth.uid()));
create policy caregiver_insert on public.caregiver for insert to authenticated
    with check (
        (family_id in (select private.my_family_ids()) and user_id is null and role = 'MEMBER')
        or (
            user_id = (select auth.uid())
            and role = 'OWNER'
            and exists (select 1 from public.family f where f.id = family_id and f.created_by = (select auth.uid()))
            and not private.family_has_members(family_id)
        )
    );
create policy caregiver_update on public.caregiver for update to authenticated
    using (family_id in (select private.my_family_ids()))
    with check (family_id in (select private.my_family_ids()));
create policy caregiver_delete on public.caregiver for delete to authenticated
    using ((select private.is_family_owner(family_id)));

-- profile and activity: shared by every member of the family.
create policy profile_select on public.profile for select to authenticated
    using (family_id in (select private.my_family_ids()));
create policy profile_insert on public.profile for insert to authenticated
    with check (family_id in (select private.my_family_ids()));
create policy profile_update on public.profile for update to authenticated
    using (family_id in (select private.my_family_ids()))
    with check (family_id in (select private.my_family_ids()));
create policy profile_delete on public.profile for delete to authenticated
    using (family_id in (select private.my_family_ids()));

create policy activity_select on public.activity for select to authenticated
    using (family_id in (select private.my_family_ids()));
create policy activity_insert on public.activity for insert to authenticated
    with check (family_id in (select private.my_family_ids()));
create policy activity_update on public.activity for update to authenticated
    using (family_id in (select private.my_family_ids()))
    with check (family_id in (select private.my_family_ids()));
create policy activity_delete on public.activity for delete to authenticated
    using (family_id in (select private.my_family_ids()));

-- reminder: only the caregiver who owns it.
create policy reminder_select on public.reminder for select to authenticated
    using (caregiver_id in (select private.my_caregiver_ids()));
create policy reminder_insert on public.reminder for insert to authenticated
    with check (caregiver_id in (select private.my_caregiver_ids()));
create policy reminder_update on public.reminder for update to authenticated
    using (caregiver_id in (select private.my_caregiver_ids()))
    with check (caregiver_id in (select private.my_caregiver_ids()));
create policy reminder_delete on public.reminder for delete to authenticated
    using (caregiver_id in (select private.my_caregiver_ids()));

-- user_settings: one row per signed-in user.
create policy user_settings_select on public.user_settings for select to authenticated
    using (user_id = (select auth.uid()));
create policy user_settings_insert on public.user_settings for insert to authenticated
    with check (user_id = (select auth.uid()));
create policy user_settings_update on public.user_settings for update to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()));
create policy user_settings_delete on public.user_settings for delete to authenticated
    using (user_id = (select auth.uid()));

-- family_invite: members create and revoke; redemption goes through accept_family_invite.
create policy family_invite_select on public.family_invite for select to authenticated
    using (family_id in (select private.my_family_ids()));
create policy family_invite_insert on public.family_invite for insert to authenticated
    with check (family_id in (select private.my_family_ids()) and created_by = (select auth.uid()));
create policy family_invite_update on public.family_invite for update to authenticated
    using (family_id in (select private.my_family_ids()))
    with check (family_id in (select private.my_family_ids()));
create policy family_invite_delete on public.family_invite for delete to authenticated
    using (family_id in (select private.my_family_ids()));

-- ---------------------------------------------------------------------------
-- Invites
-- ---------------------------------------------------------------------------

create function private.generate_invite_code()
returns text
language plpgsql volatile
set search_path = ''
as $$
declare
    alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    bytes bytea := extensions.gen_random_bytes(8);
    result text := '';
begin
    for i in 0..7 loop
        result := result || substr(alphabet, (get_byte(bytes, i) % 32) + 1, 1);
    end loop;
    return result;
end;
$$;

alter table public.family_invite alter column code set default private.generate_invite_code();
grant execute on function private.generate_invite_code() to authenticated;

-- Joins the caller to the invite's family. If a name-only caregiver with the given
-- name already exists, the caller takes it over so their past entries stay attributed.
create function private.accept_family_invite(p_code text, p_caregiver_name text)
returns table (family_id uuid, caregiver_id uuid)
language plpgsql security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
    uid uuid := (select auth.uid());
    invite public.family_invite;
    existing public.caregiver;
    trimmed text := trim(p_caregiver_name);
    now_ts timestamptz := now();
begin
    if uid is null then
        raise exception 'not signed in';
    end if;
    if trimmed is null or trimmed = '' then
        raise exception 'caregiver name is required';
    end if;

    select * into invite from public.family_invite i
    where i.code = upper(trim(p_code))
      and i.accepted_at is null
      and i.revoked_at is null
      and i.expires_at > now_ts
    for update;
    if not found then
        raise exception 'invite is invalid or expired';
    end if;

    select * into existing from public.caregiver c
    where c.family_id = invite.family_id and c.user_id = uid;
    if found then
        update public.caregiver c set deleted_at = null, updated_at = now_ts where c.id = existing.id;
    else
        select * into existing from public.caregiver c
        where c.family_id = invite.family_id and c.name = trimmed;
        if found and existing.user_id is not null then
            raise exception 'that name is already used by another member';
        elsif found then
            update public.caregiver c
            set user_id = uid, deleted_at = null, updated_at = now_ts
            where c.id = existing.id;
        else
            insert into public.caregiver (id, family_id, user_id, name, role, created_at, updated_at)
            values (gen_random_uuid(), invite.family_id, uid, trimmed, 'MEMBER', now_ts, now_ts)
            returning * into existing;
        end if;
    end if;

    update public.family_invite i set accepted_by = uid, accepted_at = now_ts where i.id = invite.id;

    return query select invite.family_id, existing.id;
end;
$$;

revoke all on function private.accept_family_invite(text, text) from public, anon;
grant execute on function private.accept_family_invite(text, text) to authenticated;

create function public.accept_family_invite(code text, caregiver_name text)
returns table (family_id uuid, caregiver_id uuid)
language sql security invoker
set search_path = ''
as $$
    select * from private.accept_family_invite(code, caregiver_name)
$$;

revoke all on function public.accept_family_invite(text, text) from public, anon;
grant execute on function public.accept_family_invite(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Activity photos
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('activity-photos', 'activity-photos', false, 10485760,
        array['image/jpeg', 'image/png', 'image/webp', 'image/heic']);

-- Objects live at {family_id}/{activity_id}/{file}; members of that family get full access.
create policy activity_photos_select on storage.objects for select to authenticated
    using (bucket_id = 'activity-photos'
           and (storage.foldername(name))[1] in (select id::text from private.my_family_ids() as id));
create policy activity_photos_insert on storage.objects for insert to authenticated
    with check (bucket_id = 'activity-photos'
                and (storage.foldername(name))[1] in (select id::text from private.my_family_ids() as id));
create policy activity_photos_update on storage.objects for update to authenticated
    using (bucket_id = 'activity-photos'
           and (storage.foldername(name))[1] in (select id::text from private.my_family_ids() as id))
    with check (bucket_id = 'activity-photos'
                and (storage.foldername(name))[1] in (select id::text from private.my_family_ids() as id));
create policy activity_photos_delete on storage.objects for delete to authenticated
    using (bucket_id = 'activity-photos'
           and (storage.foldername(name))[1] in (select id::text from private.my_family_ids() as id));

-- ===== 20261026213000_index_composite_foreign_keys.sql =====
drop index public.activity_created_by_idx;
drop index public.activity_updated_by_idx;
drop index public.reminder_profile_idx;

create index activity_created_by_idx on public.activity (created_by_id, family_id);
create index activity_updated_by_idx on public.activity (updated_by_id, family_id);
create index activity_profile_family_idx on public.activity (profile_id, family_id);
create index reminder_caregiver_family_idx on public.reminder (caregiver_id, family_id);
create index reminder_profile_idx on public.reminder (profile_id, family_id);

-- ===== 20261027023727_keep_newer_rows.sql =====
-- Reconciled from remote migration 20261027023727 (keep_newer_rows).
-- Last-write-wins guard: an UPDATE whose client updated_at is older than the
-- stored row is silently dropped. Note: for online-only optimistic locking,
-- activity/profile updates also check the version column (see online_only
-- migration); this trigger remains as a safety net for stale writes.
create function private.keep_newer_row()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if new.updated_at < old.updated_at then
        return null;
    end if;
    return new;
end;
$$;

create trigger keep_newer_row before update on public.family
    for each row execute function private.keep_newer_row();
create trigger keep_newer_row before update on public.caregiver
    for each row execute function private.keep_newer_row();
create trigger keep_newer_row before update on public.profile
    for each row execute function private.keep_newer_row();
create trigger keep_newer_row before update on public.activity
    for each row execute function private.keep_newer_row();
create trigger keep_newer_row before update on public.reminder
    for each row execute function private.keep_newer_row();
create trigger keep_newer_row before update on public.user_settings
    for each row execute function private.keep_newer_row();

-- ===== 20261027023806_caregiver_upsert_policy.sql =====
-- Reconciled from remote migration 20261027023806 (caregiver_upsert_policy).
-- Allows PostgREST upsert (insert ... on conflict) on caregiver: an insert
-- whose id already belongs to a caregiver in one of the caller's families is
-- permitted, so upserts pass the insert policy before hitting the update policy.
create function private.is_existing_caregiver_in_my_family(cid uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
    select exists (
        select 1 from public.caregiver c
        where c.id = cid and c.family_id in (select private.my_family_ids())
    )
$$;

revoke all on function private.is_existing_caregiver_in_my_family(uuid) from public, anon;
grant execute on function private.is_existing_caregiver_in_my_family(uuid) to authenticated;

drop policy caregiver_insert on public.caregiver;
create policy caregiver_insert on public.caregiver for insert to authenticated
    with check (
        (family_id in (select private.my_family_ids()) and user_id is null and role = 'MEMBER')
        or private.is_existing_caregiver_in_my_family(id)
        or (
            user_id = (select auth.uid())
            and role = 'OWNER'
            and exists (select 1 from public.family f where f.id = family_id and f.created_by = (select auth.uid()))
            and not private.family_has_members(family_id)
        )
    );

-- ===== 20261027030000_online_only.sql =====
-- Online-only migration: optimistic locking + Realtime.
--
-- version: clients update with WHERE id = ? AND version = ? and send
-- version = version + 1 (client-managed increment). Zero rows back means the
-- row changed underneath the client -> conflict, refetch and retry.
-- keep_newer_row (older migration) still guards against stale updated_at.

alter table public.family    add column version int not null default 1;
alter table public.caregiver add column version int not null default 1;
alter table public.profile   add column version int not null default 1;
alter table public.activity  add column version int not null default 1;
alter table public.reminder  add column version int not null default 1;

-- Realtime: clients treat events as refetch triggers, so default replica
-- identity (primary key) is enough; no payload diffing is done client-side.
alter publication supabase_realtime add table public.activity;
alter publication supabase_realtime add table public.profile;
alter publication supabase_realtime add table public.caregiver;
alter publication supabase_realtime add table public.family;
alter publication supabase_realtime add table public.reminder;

-- ===== 20261027120000_appointments.sql =====
-- Doctor appointments: family-shared future/past appointments per child,
-- each with a checkable list of questions to ask and free-text notes.
-- Reminder timing is a local-device concern (AlarmManager); the lead time
-- is stored here so every caregiver's device can schedule its own alarm.

create table public.appointment (
    id                    uuid primary key,
    family_id             uuid not null references public.family (id) on delete cascade,
    profile_id            uuid not null,
    title                 text not null check (length(trim(title)) > 0),
    doctor_name           text,
    location              text,
    starts_at             timestamptz not null,
    time_zone             text not null,
    notes                 text,
    -- Null means no reminder; 0 = at appointment time.
    reminder_lead_minutes integer check (reminder_lead_minutes in (0, 60, 1440)),
    created_at            timestamptz not null default now(),
    updated_at            timestamptz not null default now(),
    deleted_at            timestamptz,
    server_updated_at     timestamptz not null default now(),
    version               int not null default 1,
    foreign key (profile_id, family_id) references public.profile (id, family_id) on delete cascade
);

create table public.appointment_question (
    id             uuid primary key,
    appointment_id uuid not null references public.appointment (id) on delete cascade,
    -- Denormalized so Realtime subscriptions can filter by family_id.
    family_id      uuid not null references public.family (id) on delete cascade,
    text           text not null check (length(trim(text)) > 0),
    is_done        boolean not null default false,
    sort_order     int not null default 0,
    created_at     timestamptz not null default now(),
    updated_at     timestamptz not null default now(),
    deleted_at     timestamptz,
    server_updated_at timestamptz not null default now(),
    version        int not null default 1
);

create index appointment_profile_starts_idx on public.appointment (profile_id, starts_at);
create index appointment_family_sync_idx on public.appointment (family_id, server_updated_at);
create index appointment_question_appointment_idx on public.appointment_question (appointment_id, sort_order);
create index appointment_question_family_sync_idx on public.appointment_question (family_id, server_updated_at);

create trigger set_server_updated_at before insert or update on public.appointment
    for each row execute function private.set_server_updated_at();
create trigger set_server_updated_at before insert or update on public.appointment_question
    for each row execute function private.set_server_updated_at();

alter table public.appointment enable row level security;
alter table public.appointment_question enable row level security;

revoke all on public.appointment, public.appointment_question from anon;
grant select, insert, update, delete on public.appointment, public.appointment_question to authenticated;

-- appointment and appointment_question: shared by every member of the family.
create policy appointment_select on public.appointment for select to authenticated
    using (family_id in (select private.my_family_ids()));
create policy appointment_insert on public.appointment for insert to authenticated
    with check (family_id in (select private.my_family_ids()));
create policy appointment_update on public.appointment for update to authenticated
    using (family_id in (select private.my_family_ids()))
    with check (family_id in (select private.my_family_ids()));
create policy appointment_delete on public.appointment for delete to authenticated
    using (family_id in (select private.my_family_ids()));

create policy appointment_question_select on public.appointment_question for select to authenticated
    using (family_id in (select private.my_family_ids()));
create policy appointment_question_insert on public.appointment_question for insert to authenticated
    with check (family_id in (select private.my_family_ids()));
create policy appointment_question_update on public.appointment_question for update to authenticated
    using (family_id in (select private.my_family_ids()))
    with check (family_id in (select private.my_family_ids()));
create policy appointment_question_delete on public.appointment_question for delete to authenticated
    using (family_id in (select private.my_family_ids()));

alter publication supabase_realtime add table public.appointment;
alter publication supabase_realtime add table public.appointment_question;

-- ===== 20261105000000_vitamin_d.sql =====
-- Daily Vitamin D drops. Additive: only widens the allowed activity types.
alter table public.activity drop constraint if exists activity_type_check;
alter table public.activity add constraint activity_type_check check (type in (
    'BOTTLE_FEED', 'BREASTFEED', 'PUMP', 'DIAPER', 'GROWTH', 'MILESTONE',
    'SLEEP', 'SOLIDS', 'ROUTINE', 'BABY_FIRST', 'MEDICAL', 'VACCINE', 'VITAMIN_D'
)) not valid;
alter table public.activity validate constraint activity_type_check;

-- ===== 20261106000000_notes.sql =====
-- Parent notes: free-form, family-shared notes per child. The body is plain
-- text with inline list markers ("• ", "1. ", "☐ " / "☑ ") so checklist state
-- lives in the text, same as appointment notes.

create table public.note (
    id                uuid primary key,
    family_id         uuid not null references public.family (id) on delete cascade,
    profile_id        uuid not null,
    title             text not null default '',
    body              text not null default '',
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz,
    server_updated_at timestamptz not null default now(),
    version           int not null default 1,
    foreign key (profile_id, family_id) references public.profile (id, family_id) on delete cascade,
    check (length(trim(title)) > 0 or length(trim(body)) > 0)
);

create index note_profile_updated_idx on public.note (profile_id, updated_at desc);
create index note_family_sync_idx on public.note (family_id, server_updated_at);

create trigger set_server_updated_at before insert or update on public.note
    for each row execute function private.set_server_updated_at();

alter table public.note enable row level security;

revoke all on public.note from anon;
grant select, insert, update, delete on public.note to authenticated;

-- note: shared by every member of the family.
create policy note_select on public.note for select to authenticated
    using (family_id in (select private.my_family_ids()));
create policy note_insert on public.note for insert to authenticated
    with check (family_id in (select private.my_family_ids()));
create policy note_update on public.note for update to authenticated
    using (family_id in (select private.my_family_ids()))
    with check (family_id in (select private.my_family_ids()));
create policy note_delete on public.note for delete to authenticated
    using (family_id in (select private.my_family_ids()));

alter publication supabase_realtime add table public.note;

-- ===== solids_resets_feed_schedule (apply on existing projects) =====
-- alter table public.activity
--     add column if not exists solids_resets_feed_schedule boolean not null default true;

