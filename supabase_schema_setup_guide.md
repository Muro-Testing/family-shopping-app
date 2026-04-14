# Family Shopping List - Supabase Setup Guide

## ✅ Complete Authentication + Family Groups System

---

## Step 1: Create Supabase Project
Go to https://supabase.com and create new project

---

## Step 2: Run this SQL in SQL Editor:

```sql
-- Enable auth
create extension if not exists "uuid-ossp";

-- Families table
create table families (
  id uuid primary key default uuid_generate_v4(),
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  name text default 'My Family',
  invite_code text unique
);

alter table families enable row level security;

create policy "Family members can view their family" on families
  for select using (
    id in (select family_id from family_members where user_id = auth.uid())
  );

-- Family members
create table family_members (
  id uuid primary key default uuid_generate_v4(),
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  user_id uuid references auth.users(id) on delete cascade not null,
  family_id uuid references families(id) on delete cascade not null,
  name text,
  avatar_color text default '#007AFF',
  unique(user_id, family_id)
);

alter table family_members enable row level security;

create policy "Users can view family members" on family_members
  for select using (
    family_id in (select family_id from family_members where user_id = auth.uid())
  );

create policy "Users can update own profile" on family_members
  for update using (user_id = auth.uid());

-- Shopping lists
create table shopping_lists (
  id bigint generated always as identity primary key,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  family_id uuid references families(id) on delete cascade not null,
  name text not null,
  created_by uuid references auth.users(id)
);

alter table shopping_lists enable row level security;

create policy "Family members can manage lists" on shopping_lists
  for all using (
    family_id in (select family_id from family_members where user_id = auth.uid())
  );

-- Shopping items
create table shopping_items (
  id bigint generated always as identity primary key,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  family_id uuid references families(id) on delete cascade not null,
  list_id bigint references shopping_lists(id) on delete cascade not null,
  name text not null,
  quantity text default '1',
  checked boolean default false,
  checked_at timestamp with time zone,
  created_by uuid references auth.users(id),
  checked_by uuid references auth.users(id),
  completed_trip_id bigint
);

alter table shopping_items enable row level security;

create policy "Family members can manage items" on shopping_items
  for all using (
    family_id in (select family_id from family_members where user_id = auth.uid())
  );

-- Shopping trips
create table shopping_trips (
  id bigint generated always as identity primary key,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  family_id uuid references families(id) on delete cascade not null,
  completed_at timestamp with time zone default now(),
  total_amount numeric not null,
  completed_by uuid references auth.users(id),
  items jsonb
);

alter table shopping_trips enable row level security;

create policy "Family members can view trips" on shopping_trips
  for select using (
    family_id in (select family_id from family_members where user_id = auth.uid())
  );

-- Realtime publication
alter publication supabase_realtime add table shopping_lists, shopping_items, shopping_trips, family_members;

-- Auto create family on signup
create function public.handle_new_user() 
returns trigger as $$
declare
  new_family_id uuid;
begin
  insert into families default values returning id into new_family_id;
  insert into family_members (user_id, family_id) values (new.id, new_family_id);
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
```

---

## Step 3: Enable Email Auth

Go to Authentication → Providers → Email
Enable Email provider

---

## Step 4: Paste Project Settings

Go to Settings → API
Copy URL and ANON KEY into the top of the file.

✅ Done.