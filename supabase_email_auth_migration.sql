-- Apply once to an existing project created with supabase_schema.sql.
-- Email-based customer accounts do not require a phone number.

update public.profiles
set phone = null
where btrim(phone) = '';

alter table public.profiles
    alter column phone drop not null;

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
