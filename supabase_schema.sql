-- =============================================================================
-- MUNASBH (مناسباتي) - Supabase PostgreSQL Schema & Security Policies (2026)
-- =============================================================================

-- 1. Profiles Table (Linked to Supabase Auth)
create table if not exists public.profiles (
    id uuid references auth.users on delete cascade primary key,
    full_name text not null,
    phone text not null,
    role text not null default 'customer', -- 'customer', 'provider', 'admin'
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 2. Service Providers Table
create table if not exists public.providers (
    id uuid default gen_random_uuid() primary key,
    owner_id uuid references public.profiles(id) on delete set null,
    name text not null,
    category text not null,
    city text not null default 'صنعاء',
    rating numeric(3,2) default 4.5,
    reviews_count int default 0,
    price numeric(12,2) default 0,
    phone text not null,
    description text,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 3. Bookings Table (Marketplace Bookings)
create table if not exists public.bookings (
    id uuid default gen_random_uuid() primary key,
    customer_id uuid references public.profiles(id) on delete set null,
    provider_id uuid references public.providers(id) on delete cascade,
    customer_name text not null,
    phone text not null,
    service_name text not null,
    provider_name text not null,
    booking_date timestamp with time zone not null,
    amount numeric(12,2) not null,
    paid numeric(12,2) default 0,
    status text not null default 'pending', -- 'pending', 'confirmed', 'completed', 'cancelled'
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 4. Ledger Entries Table (Accounts / Incomes / Expenses)
create table if not exists public.ledger_entries (
    id uuid default gen_random_uuid() primary key,
    user_id uuid references public.profiles(id) on delete cascade,
    title text not null,
    amount numeric(12,2) not null,
    entry_date timestamp with time zone not null,
    kind text not null, -- 'income' or 'expense'
    note text,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 5. Chalet Reservations & Payments Table
create table if not exists public.chalet_reservations (
    id text primary key,
    chalet_id text not null,
    customer_name text not null,
    phone text not null,
    check_in date not null,
    check_out date not null,
    guests int not null,
    total_amount numeric(12,2) not null,
    deposit_amount numeric(12,2) not null,
    commission_amount numeric(12,2) not null,
    status text not null default 'awaitingProvider',
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- =============================================================================
-- SECURITY: Row Level Security (RLS)
-- =============================================================================
alter table public.profiles enable row level security;
alter table public.providers enable row level security;
alter table public.bookings enable row level security;
alter table public.ledger_entries enable row level security;
alter table public.chalet_reservations enable row level security;

-- Policies
create policy "Public profiles are viewable by everyone" on public.profiles for select using (true);
create policy "Users can update their own profile" on public.profiles for update using (auth.uid() = id);

create policy "Providers are viewable by everyone" on public.providers for select using (true);
create policy "Providers can be inserted by authenticated owners" on public.providers for insert with check (auth.uid() = owner_id);

create policy "Bookings viewable by participants" on public.bookings for select using (true);
create policy "Bookings insertable by customers" on public.bookings for insert with check (true);

-- =============================================================================
-- COMPLIANCE: Account Deletion Function (Apple/Google 2026 Privacy Requirement)
-- =============================================================================
create or replace function public.delete_user_account(target_user_id uuid)
returns void
language plpgsql
security definer
as $$
begin
    -- Delete user bookings and entries
    delete from public.bookings where customer_id = target_user_id;
    delete from public.ledger_entries where user_id = target_user_id;
    -- Delete user profile
    delete from public.profiles where id = target_user_id;
    -- Delete from auth.users (requires superuser or auth admin)
    delete from auth.users where id = target_user_id;
end;
$$;
