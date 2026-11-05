-- Suitable for a fresh Supabase project. Back up any legacy chalet data before
-- applying the final DROP statement at the end of this file.

create table if not exists public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    full_name text not null,
    phone text unique,
    role text not null default 'customer'
        check (role in ('customer', 'provider', 'admin')),
    created_at timestamptz not null default now()
);

create table if not exists public.providers (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null unique references public.profiles(id) on delete cascade,
    full_name text not null,
    phone text not null,
    category text not null
        check (category in ('wedding_hall', 'artist', 'photographer', 'wedding_service')),
    business_name text not null,
    city text not null,
    description text not null default '',
    starting_price numeric(12,2) not null default 0
        check (starting_price >= 0),
    max_guests integer check (max_guests is null or max_guests > 0),
    deposit_percent numeric(5,2) not null default 20
        check (deposit_percent >= 0 and deposit_percent <= 100),
    verification_status text not null default 'pending'
        check (verification_status in ('pending', 'approved', 'rejected', 'suspended')),
    rejection_reason text,
    verified_at timestamptz,
    verified_by uuid references public.profiles(id) on delete set null,
    created_at timestamptz not null default now()
);

create table if not exists public.provider_verification_documents (
    provider_id uuid primary key references public.providers(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    id_card_path text not null,
    ownership_doc_path text not null,
    created_at timestamptz not null default now()
);

create table if not exists public.provider_packages (
    id uuid primary key default gen_random_uuid(),
    provider_id uuid not null references public.providers(id) on delete cascade,
    name text not null,
    price numeric(12,2) not null check (price > 0),
    included_guests integer not null default 0 check (included_guests >= 0),
    additional_guest_price numeric(12,2) not null default 0
        check (additional_guest_price >= 0),
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    unique(provider_id, name)
);

create table if not exists public.provider_seasonal_rates (
    id uuid primary key default gen_random_uuid(),
    provider_id uuid not null references public.providers(id) on delete cascade,
    start_date date not null,
    end_date date not null,
    multiplier numeric(6,3) not null check (multiplier > 0),
    check (end_date >= start_date)
);

create table if not exists public.bookings (
    id uuid primary key default gen_random_uuid(),
    customer_id uuid not null references public.profiles(id) on delete cascade,
    customer_name text not null,
    customer_phone text not null,
    provider_id uuid references public.providers(id) on delete set null,
    service_name text not null,
    event_date timestamptz not null,
    shift_type text not null default 'evening'
        check (shift_type in ('morning', 'evening', 'full_day')),
    package_name text not null default '',
    guest_count integer check (guest_count is null or guest_count > 0),
    total_amount numeric(12,2) not null check (total_amount >= 0),
    deposit_amount numeric(12,2) not null default 0
        check (deposit_amount >= 0 and deposit_amount <= total_amount),
    deposit_paid numeric(12,2) not null default 0
        check (deposit_paid >= 0 and deposit_paid <= deposit_amount),
    status text not null default 'pending'
        check (status in ('pending', 'confirmed', 'completed', 'cancelled')),
    created_at timestamptz not null default now()
);

create table if not exists public.ledger_entries (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles(id) on delete cascade,
    booking_id uuid references public.bookings(id) on delete set null,
    title text not null,
    amount numeric(12,2) not null check (amount >= 0),
    entry_date timestamptz not null,
    kind text not null check (kind in ('income', 'expense')),
    note text not null default '',
    created_at timestamptz not null default now()
);

create table if not exists public.reports (
    id uuid primary key default gen_random_uuid(),
    reporter_id uuid not null references public.profiles(id) on delete cascade,
    provider_id uuid references public.providers(id) on delete cascade,
    booking_id uuid references public.bookings(id) on delete cascade,
    reason text not null,
    details text not null default '',
    status text not null default 'open'
        check (status in ('open', 'reviewing', 'resolved', 'dismissed')),
    admin_note text,
    created_at timestamptz not null default now(),
    resolved_at timestamptz
);

create index if not exists bookings_customer_date_idx
    on public.bookings(customer_id, event_date);
create index if not exists bookings_provider_date_idx
    on public.bookings(provider_id, event_date);
create index if not exists providers_status_category_idx
    on public.providers(verification_status, category);
create index if not exists provider_packages_lookup_idx
    on public.provider_packages(provider_id, is_active);
create index if not exists provider_seasonal_rates_dates_idx
    on public.provider_seasonal_rates(provider_id, start_date, end_date);
create index if not exists reports_status_created_idx
    on public.reports(status, created_at);

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from public.profiles
        where id = (select auth.uid()) and role = 'admin'
    );
$$;

create or replace function public.admin_set_provider_status(
    target_provider_id uuid,
    new_status text,
    reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if not public.is_admin() then
        raise exception 'Unauthorized' using errcode = '42501';
    end if;
    if new_status not in ('approved', 'rejected', 'suspended') then
        raise exception 'Invalid provider status' using errcode = '22023';
    end if;
    if new_status = 'rejected' and nullif(trim(reason), '') is null then
        raise exception 'A rejection reason is required' using errcode = '22023';
    end if;

    update public.providers
    set verification_status = new_status,
        rejection_reason = case
            when new_status = 'rejected' then nullif(trim(reason), '')
            else null
        end,
        verified_at = case
            when new_status = 'approved' then now()
            else null
        end,
        verified_by = auth.uid()
    where id = target_provider_id;

    if not found then
        raise exception 'Provider not found' using errcode = 'P0002';
    end if;
end;
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_admin() to anon;

create or replace function public.admin_list_providers()
returns table (
    id uuid,
    full_name text,
    phone text,
    category text,
    business_name text,
    city text,
    description text,
    verification_status text,
    rejection_reason text,
    created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
    if not public.is_admin() then
        raise exception 'Unauthorized' using errcode = '42501';
    end if;
    return query
    select p.id, profile.full_name, profile.phone, p.category,
           p.business_name, p.city, p.description, p.verification_status,
           p.rejection_reason, p.created_at
    from public.providers p
    join public.profiles profile on profile.id = p.user_id
    order by p.created_at desc;
end;
$$;

revoke all on function public.admin_list_providers() from public;
grant execute on function public.admin_list_providers() to authenticated;

create or replace function public.provider_is_approved(target_provider_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from public.providers
        where id = target_provider_id and verification_status = 'approved'
    );
$$;

create or replace function public.current_user_owns_provider(target_provider_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from public.providers
        where id = target_provider_id and user_id = (select auth.uid())
    );
$$;

create or replace function public.get_current_provider_status()
returns text
language sql
stable
security definer
set search_path = public
as $$
    select verification_status from public.providers
    where user_id = (select auth.uid())
    limit 1;
$$;

create or replace function public.get_current_provider_profile()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select
        (to_jsonb(p) - 'user_id' - 'verified_by')
        || jsonb_build_object(
            'provider_packages',
            coalesce((
                select jsonb_agg(to_jsonb(package_row))
                from public.provider_packages package_row
                where package_row.provider_id = p.id and package_row.is_active
            ), '[]'::jsonb),
            'provider_seasonal_rates',
            coalesce((
                select jsonb_agg(to_jsonb(rate_row))
                from public.provider_seasonal_rates rate_row
                where rate_row.provider_id = p.id
            ), '[]'::jsonb)
        )
    from public.providers p
    where p.user_id = (select auth.uid())
    limit 1;
$$;

revoke all on function public.provider_is_approved(uuid) from public;
revoke all on function public.current_user_owns_provider(uuid) from public;
revoke all on function public.get_current_provider_status() from public;
revoke all on function public.get_current_provider_profile() from public;
revoke all on function public.admin_set_provider_status(uuid, text, text) from public;
grant execute on function public.provider_is_approved(uuid) to anon, authenticated;
grant execute on function public.current_user_owns_provider(uuid) to anon, authenticated;
grant execute on function public.get_current_provider_status() to authenticated;
grant execute on function public.get_current_provider_profile() to authenticated;
grant execute on function public.admin_set_provider_status(uuid, text, text) to authenticated;

create or replace function public.update_provider_pricing(
    target_provider_id uuid,
    new_starting_price numeric,
    new_deposit_percent numeric,
    new_max_guests integer,
    package_prices jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    package_entry record;
begin
    if not public.current_user_owns_provider(target_provider_id)
       and not public.is_admin() then
        raise exception 'Not authorized to update provider pricing'
            using errcode = '42501';
    end if;
    if new_starting_price is null or new_starting_price <= 0
       or new_deposit_percent is null
       or new_deposit_percent < 0 or new_deposit_percent > 100
       or (new_max_guests is not null and new_max_guests < 1)
       or package_prices is null
       or jsonb_typeof(package_prices) <> 'object' then
        raise exception 'Invalid provider pricing'
            using errcode = '22023';
    end if;

    update public.providers
    set starting_price = new_starting_price,
        deposit_percent = new_deposit_percent,
        max_guests = new_max_guests
    where id = target_provider_id;
    if not found then
        raise exception 'Provider not found' using errcode = 'P0002';
    end if;

    for package_entry in
        select key, value from jsonb_each_text(package_prices)
    loop
        if package_entry.value !~ '^[0-9]+([.][0-9]{1,2})?$'
           or package_entry.value::numeric <= 0 then
            raise exception 'Invalid price for package %', package_entry.key
                using errcode = '22023';
        end if;
        update public.provider_packages
        set price = package_entry.value::numeric
        where provider_id = target_provider_id
          and name = package_entry.key;
        if not found then
            raise exception 'Package not found: %', package_entry.key
                using errcode = 'P0002';
        end if;
    end loop;
end;
$$;

revoke all on function public.update_provider_pricing(
    uuid, numeric, numeric, integer, jsonb
) from public;
grant execute on function public.update_provider_pricing(
    uuid, numeric, numeric, integer, jsonb
) to authenticated;

create or replace function public.prevent_provider_status_self_approval()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.verification_status is distinct from old.verification_status
       and not public.is_admin() then
        raise exception 'Only administrators can change verification status'
            using errcode = '42501';
    end if;
    return new;
end;
$$;

drop trigger if exists protect_provider_verification_status on public.providers;
create trigger protect_provider_verification_status
    before update on public.providers
    for each row execute procedure public.prevent_provider_status_self_approval();

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.profiles (id, full_name, phone, role)
    values (
        new.id,
        coalesce(
            nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
            nullif(trim(new.raw_user_meta_data ->> 'name'), ''),
            'مستخدم'
        ),
        nullif(coalesce(new.phone, new.raw_user_meta_data ->> 'phone', ''), ''),
        'customer'
    )
    on conflict (id) do update
        set phone = coalesce(excluded.phone, public.profiles.phone);
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute procedure public.handle_new_auth_user();

alter table public.profiles enable row level security;
alter table public.providers enable row level security;
alter table public.provider_verification_documents enable row level security;
alter table public.provider_packages enable row level security;
alter table public.provider_seasonal_rates enable row level security;
alter table public.bookings enable row level security;
alter table public.ledger_entries enable row level security;
alter table public.reports enable row level security;

drop policy if exists "profiles_select_owner_or_admin" on public.profiles;
create policy "profiles_select_owner_or_admin"
    on public.profiles for select to authenticated
    using (id = (select auth.uid()) or public.is_admin());

drop policy if exists "profiles_insert_self_customer" on public.profiles;
create policy "profiles_insert_self_customer"
    on public.profiles for insert to authenticated
    with check (id = (select auth.uid()) and role = 'customer');

drop policy if exists "profiles_update_owner_or_admin" on public.profiles;
create policy "profiles_update_owner_or_admin"
    on public.profiles for update to authenticated
    using (id = (select auth.uid()) or public.is_admin())
    with check (
        public.is_admin()
        or (id = (select auth.uid()) and role = 'customer')
    );

drop policy if exists "providers_select_approved_owner_admin" on public.providers;
create policy "providers_select_approved_owner_admin"
    on public.providers for select to anon, authenticated
    using (
        verification_status = 'approved'
        or user_id = (select auth.uid())
        or public.is_admin()
    );

drop policy if exists "provider_docs_select_owner_admin" on public.provider_verification_documents;
create policy "provider_docs_select_owner_admin"
    on public.provider_verification_documents for select to authenticated
    using (user_id = (select auth.uid()) or public.is_admin());

drop policy if exists "provider_packages_select_public_owner_admin" on public.provider_packages;
create policy "provider_packages_select_public_owner_admin"
    on public.provider_packages for select to anon, authenticated
    using (
        public.provider_is_approved(provider_id)
        or public.current_user_owns_provider(provider_id)
        or public.is_admin()
    );

drop policy if exists "provider_packages_manage_owner_admin" on public.provider_packages;
create policy "provider_packages_manage_owner_admin"
    on public.provider_packages for all to authenticated
    using (public.current_user_owns_provider(provider_id) or public.is_admin())
    with check (public.current_user_owns_provider(provider_id) or public.is_admin());

drop policy if exists "provider_seasons_select_public_owner_admin" on public.provider_seasonal_rates;
create policy "provider_seasons_select_public_owner_admin"
    on public.provider_seasonal_rates for select to anon, authenticated
    using (
        public.provider_is_approved(provider_id)
        or public.current_user_owns_provider(provider_id)
        or public.is_admin()
    );

drop policy if exists "provider_seasons_manage_owner_admin" on public.provider_seasonal_rates;
create policy "provider_seasons_manage_owner_admin"
    on public.provider_seasonal_rates for all to authenticated
    using (public.current_user_owns_provider(provider_id) or public.is_admin())
    with check (public.current_user_owns_provider(provider_id) or public.is_admin());

drop policy if exists "providers_insert_self_pending" on public.providers;
create policy "providers_insert_self_pending"
    on public.providers for insert to authenticated
    with check (
        user_id = (select auth.uid())
        and verification_status = 'pending'
    );

drop policy if exists "providers_update_owner_or_admin" on public.providers;
create policy "providers_update_owner_or_admin"
    on public.providers for update to authenticated
    using (user_id = (select auth.uid()) or public.is_admin())
    with check (user_id = (select auth.uid()) or public.is_admin());

drop policy if exists "providers_delete_owner_or_admin" on public.providers;
create policy "providers_delete_owner_or_admin"
    on public.providers for delete to authenticated
    using (user_id = (select auth.uid()) or public.is_admin());

revoke all on public.providers from anon, authenticated;
grant select (
    id, full_name, phone, category, business_name, city, description,
    starting_price, max_guests, deposit_percent,
    verification_status, rejection_reason, verified_at, created_at
) on public.providers to anon, authenticated;
grant update (
    full_name, phone, category, business_name, city, description,
    starting_price, max_guests, deposit_percent
)
    on public.providers to authenticated;
revoke all on public.provider_verification_documents from anon, authenticated;
grant select on public.provider_verification_documents to authenticated;
revoke all on public.provider_packages from anon, authenticated;
grant select on public.provider_packages to anon, authenticated;
revoke all on public.provider_seasonal_rates from anon, authenticated;
grant select on public.provider_seasonal_rates to anon, authenticated;
grant insert, delete on public.provider_seasonal_rates to authenticated;

create or replace function public.register_provider(
    p_full_name text,
    p_phone text,
    p_category text,
    p_business_name text,
    p_city text,
    p_description text,
    p_starting_price numeric,
    p_max_guests integer,
    p_deposit_percent numeric,
    p_id_card_path text,
    p_ownership_doc_path text
)
returns uuid
language plpgsql
security definer
set search_path = public, storage
as $$
declare
    new_provider_id uuid;
begin
    if auth.uid() is null
       or nullif(trim(p_full_name), '') is null
       or nullif(trim(p_phone), '') is null
       or nullif(trim(p_business_name), '') is null
       or nullif(trim(p_city), '') is null
       or p_starting_price is null
       or p_starting_price <= 0
       or p_deposit_percent is null
       or p_deposit_percent < 0
       or p_deposit_percent > 100
       or (
           p_category = 'wedding_hall'
           and (p_max_guests is null or p_max_guests < 1)
       )
       or p_id_card_path not like auth.uid()::text || '/%'
       or p_ownership_doc_path not like auth.uid()::text || '/%' then
        raise exception 'Invalid provider registration' using errcode = '22023';
    end if;

    if not exists (
        select 1 from storage.objects
        where bucket_id = 'provider-documents'
          and name = p_id_card_path
    ) or not exists (
        select 1 from storage.objects
        where bucket_id = 'provider-documents'
          and name = p_ownership_doc_path
    ) then
        raise exception 'Provider documents are required' using errcode = '22023';
    end if;

    update public.profiles
    set full_name = trim(p_full_name),
        phone = trim(p_phone),
        role = 'provider'
    where id = auth.uid();

    if not found then
        raise exception 'Profile not found' using errcode = 'P0002';
    end if;

    insert into public.providers (
        user_id, full_name, phone, category, business_name, city,
        description, starting_price, max_guests, deposit_percent
    ) values (
        auth.uid(), trim(p_full_name), trim(p_phone), p_category,
        trim(p_business_name), trim(p_city), coalesce(trim(p_description), ''),
        p_starting_price, p_max_guests, p_deposit_percent
    )
    returning id into new_provider_id;

    insert into public.provider_verification_documents (
        provider_id, user_id, id_card_path, ownership_doc_path
    ) values (
        new_provider_id, auth.uid(), p_id_card_path, p_ownership_doc_path
    );

    if p_category = 'wedding_hall' then
        insert into public.provider_packages (
            provider_id, name, price, included_guests
        ) values (
            new_provider_id, 'الباقة الأساسية', p_starting_price, p_max_guests
        );
    end if;

    return new_provider_id;
end;
$$;

revoke all on function public.register_provider(
    text, text, text, text, text, text, numeric, integer, numeric, text, text
) from public;
grant execute on function public.register_provider(
    text, text, text, text, text, text, numeric, integer, numeric, text, text
) to authenticated;

create or replace function public.create_event_booking(
    target_provider_id uuid,
    event_day date,
    selected_shift text,
    selected_package text default '',
    number_of_guests integer default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    provider_row public.providers%rowtype;
    package_price numeric(12,2);
    included_guest_count integer;
    extra_guest_price numeric(12,2);
    seasonal_multiplier numeric(6,3) := 1;
    shift_multiplier numeric(5,2);
    booking_total numeric(12,2);
    booking_deposit numeric(12,2);
    new_booking_id uuid;
    customer_row public.profiles%rowtype;
begin
    if auth.uid() is null then
        raise exception 'Authentication required' using errcode = '42501';
    end if;
    if event_day is null or event_day < current_date then
        raise exception 'Event date must be today or later' using errcode = '22023';
    end if;
    if selected_shift is null
       or selected_shift not in ('morning', 'evening', 'full_day') then
        raise exception 'Invalid event shift' using errcode = '22023';
    end if;

    select * into provider_row
    from public.providers
    where id = target_provider_id
      and verification_status = 'approved';
    if not found then
        raise exception 'Provider is unavailable' using errcode = 'P0002';
    end if;

    select * into customer_row
    from public.profiles
    where id = auth.uid();
    if not found then
        raise exception 'Customer profile is required' using errcode = 'P0002';
    end if;

    if provider_row.max_guests is not null then
        if number_of_guests is null
           or number_of_guests < 1
           or number_of_guests > provider_row.max_guests then
            raise exception 'Guest count is outside provider capacity'
                using errcode = '22023';
        end if;
    elsif number_of_guests is not null and number_of_guests < 1 then
        raise exception 'Invalid guest count' using errcode = '22023';
    end if;

    package_price := provider_row.starting_price;
    included_guest_count := 0;
    extra_guest_price := 0;
    if nullif(trim(selected_package), '') is not null then
        select price, included_guests, additional_guest_price
        into package_price, included_guest_count, extra_guest_price
        from public.provider_packages
        where provider_id = target_provider_id
          and name = selected_package
          and is_active;
        if not found then
            raise exception 'Selected package is unavailable'
                using errcode = '22023';
        end if;
    elsif provider_row.category = 'wedding_hall' then
        raise exception 'A hall package is required' using errcode = '22023';
    end if;

    select multiplier into seasonal_multiplier
    from public.provider_seasonal_rates
    where provider_id = target_provider_id
      and event_day between start_date and end_date
    order by multiplier desc
    limit 1;
    seasonal_multiplier := coalesce(seasonal_multiplier, 1);

    case selected_shift
        when 'morning' then shift_multiplier := 0.8;
        when 'evening' then shift_multiplier := 1;
        when 'full_day' then shift_multiplier := 1.5;
    end case;

    booking_total := round(
        (
            package_price * shift_multiplier
            + greatest(coalesce(number_of_guests, 0) - included_guest_count, 0)
                * extra_guest_price
        ) * seasonal_multiplier,
        2
    );
    booking_deposit := round(
        booking_total * provider_row.deposit_percent / 100,
        2
    );

    perform pg_advisory_xact_lock(
        hashtext(target_provider_id::text),
        hashtext(event_day::text)
    );
    if exists (
        select 1 from public.bookings
        where provider_id = target_provider_id
          and event_date >= event_day::timestamp at time zone 'UTC'
          and event_date < (event_day + 1)::timestamp at time zone 'UTC'
          and status in ('pending', 'confirmed')
          and (
              selected_shift = 'full_day'
              or shift_type = 'full_day'
              or shift_type = selected_shift
          )
    ) then
        raise exception 'The provider is already booked for this date and shift'
            using errcode = '23505';
    end if;

    insert into public.bookings (
        customer_id, customer_name, customer_phone, provider_id, service_name,
        event_date, shift_type, package_name, guest_count, total_amount,
        deposit_amount
    ) values (
        auth.uid(), customer_row.full_name, customer_row.phone,
        target_provider_id, provider_row.category,
        event_day::timestamp at time zone 'UTC', selected_shift,
        coalesce(trim(selected_package), ''), number_of_guests,
        booking_total, booking_deposit
    )
    returning id into new_booking_id;

    return new_booking_id;
end;
$$;

revoke all on function public.create_event_booking(
    uuid, date, text, text, integer
) from public;
grant execute on function public.create_event_booking(
    uuid, date, text, text, integer
) to authenticated;

create or replace function public.get_provider_booked_slots(
    target_provider_id uuid,
    from_day date,
    through_day date
)
returns table(event_day date, shift_type text)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
    if from_day is null
       or through_day is null
       or through_day < from_day
       or through_day > from_day + 370 then
        raise exception 'Invalid availability range' using errcode = '22023';
    end if;
    if not public.provider_is_approved(target_provider_id)
       and not public.current_user_owns_provider(target_provider_id)
       and not public.is_admin() then
        raise exception 'Provider is unavailable' using errcode = '42501';
    end if;

    return query
    select (b.event_date at time zone 'UTC')::date, b.shift_type
    from public.bookings b
    where b.provider_id = target_provider_id
      and b.event_date >= from_day::timestamp at time zone 'UTC'
      and b.event_date < (through_day + 1)::timestamp at time zone 'UTC'
      and b.status in ('pending', 'confirmed');
end;
$$;

revoke all on function public.get_provider_booked_slots(uuid, date, date)
    from public;
grant execute on function public.get_provider_booked_slots(uuid, date, date)
    to anon, authenticated;

drop policy if exists "bookings_select_participants_or_admin" on public.bookings;
create policy "bookings_select_participants_or_admin"
    on public.bookings for select to authenticated
    using (
        customer_id = (select auth.uid())
        or public.current_user_owns_provider(bookings.provider_id)
        or public.is_admin()
    );

drop policy if exists "bookings_insert_customer_or_admin" on public.bookings;
create policy "bookings_insert_customer_or_admin"
    on public.bookings for insert to authenticated
    with check (
        (
            customer_id = (select auth.uid())
            and status = 'pending'
            and public.provider_is_approved(bookings.provider_id)
        )
        or public.is_admin()
    );

drop policy if exists "bookings_update_provider_or_admin" on public.bookings;
create policy "bookings_update_provider_or_admin"
    on public.bookings for update to authenticated
    using (
        public.current_user_owns_provider(bookings.provider_id)
        or public.is_admin()
    )
    with check (
        public.current_user_owns_provider(bookings.provider_id)
        or public.is_admin()
    );

drop policy if exists "bookings_delete_admin" on public.bookings;
create policy "bookings_delete_admin"
    on public.bookings for delete to authenticated
    using (public.is_admin());

drop policy if exists "ledger_select_owner_or_admin" on public.ledger_entries;
create policy "ledger_select_owner_or_admin"
    on public.ledger_entries for select to authenticated
    using (user_id = (select auth.uid()) or public.is_admin());

drop policy if exists "ledger_insert_owner_or_admin" on public.ledger_entries;
create policy "ledger_insert_owner_or_admin"
    on public.ledger_entries for insert to authenticated
    with check (user_id = (select auth.uid()) or public.is_admin());

drop policy if exists "ledger_update_owner_or_admin" on public.ledger_entries;
create policy "ledger_update_owner_or_admin"
    on public.ledger_entries for update to authenticated
    using (user_id = (select auth.uid()) or public.is_admin())
    with check (user_id = (select auth.uid()) or public.is_admin());

drop policy if exists "ledger_delete_owner_or_admin" on public.ledger_entries;
create policy "ledger_delete_owner_or_admin"
    on public.ledger_entries for delete to authenticated
    using (user_id = (select auth.uid()) or public.is_admin());

drop policy if exists "reports_select_reporter_or_admin" on public.reports;
create policy "reports_select_reporter_or_admin"
    on public.reports for select to authenticated
    using (reporter_id = (select auth.uid()) or public.is_admin());

drop policy if exists "reports_insert_reporter" on public.reports;
create policy "reports_insert_reporter"
    on public.reports for insert to authenticated
    with check (reporter_id = (select auth.uid()));

drop policy if exists "reports_update_admin" on public.reports;
create policy "reports_update_admin"
    on public.reports for update to authenticated
    using (public.is_admin())
    with check (public.is_admin());

revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (full_name, phone) on public.profiles to authenticated;

revoke all on public.bookings from anon, authenticated;
grant select on public.bookings to authenticated;
grant update (status) on public.bookings to authenticated;

revoke all on public.ledger_entries from anon, authenticated;
grant select, insert, update, delete on public.ledger_entries to authenticated;

revoke all on public.reports from anon, authenticated;
grant select on public.reports to authenticated;
grant insert (reporter_id, provider_id, booking_id, reason, details)
    on public.reports to authenticated;
grant update (status, admin_note, resolved_at) on public.reports to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'provider-documents',
    'provider-documents',
    false,
    5242880,
    array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "provider_docs_insert_own_folder" on storage.objects;
create policy "provider_docs_insert_own_folder"
    on storage.objects for insert to authenticated
    with check (
        bucket_id = 'provider-documents'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    );

drop policy if exists "provider_docs_select_owner_admin" on storage.objects;
create policy "provider_docs_select_owner_admin"
    on storage.objects for select to authenticated
    using (
        bucket_id = 'provider-documents'
        and (
            (storage.foldername(name))[1] = (select auth.uid())::text
            or public.is_admin()
        )
    );

drop policy if exists "provider_docs_update_owner_admin" on storage.objects;
create policy "provider_docs_update_owner_admin"
    on storage.objects for update to authenticated
    using (
        bucket_id = 'provider-documents'
        and (
            (storage.foldername(name))[1] = (select auth.uid())::text
            or public.is_admin()
        )
    )
    with check (
        bucket_id = 'provider-documents'
        and (
            (storage.foldername(name))[1] = (select auth.uid())::text
            or public.is_admin()
        )
    );

drop policy if exists "provider_docs_delete_owner_admin" on storage.objects;
create policy "provider_docs_delete_owner_admin"
    on storage.objects for delete to authenticated
    using (
        bucket_id = 'provider-documents'
        and (
            (storage.foldername(name))[1] = (select auth.uid())::text
            or public.is_admin()
        )
    );

create or replace function public.delete_user_account(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, storage, auth
as $$
begin
    if auth.uid() is null
       or (
           auth.uid() <> target_user_id
           and not public.is_admin()
       ) then
        raise exception 'Unauthorized' using errcode = '42501';
    end if;

    delete from storage.objects
    where bucket_id = 'provider-documents'
      and (storage.foldername(name))[1] = target_user_id::text;

    delete from auth.users where id = target_user_id;
end;
$$;

revoke all on function public.delete_user_account(uuid) from public;
grant execute on function public.delete_user_account(uuid) to authenticated;

-- This legacy table held local-prototype-only lodging records and has no
-- compatible event-booking semantics. Export/back up before applying.
drop table if exists public.chalet_reservations cascade;
