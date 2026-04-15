# Family Shopping List - Supabase Setup Guide

## Source of truth

Use [`../supabase_schema.sql`](../supabase_schema.sql) as the only schema file.

The older schema draft in this guide used a different data model from the app:
- `bigint` IDs instead of UUIDs
- a signup trigger instead of first-login family bootstrap
- non-rerunnable SQL

That drift is what caused the current setup confusion.

## Step 1: Create a Supabase project

Create a project at <https://supabase.com>.

## Step 2: Run the schema

Open Supabase SQL Editor, paste the contents of [`../supabase_schema.sql`](../supabase_schema.sql), and run it.

The schema is safe to rerun because it:
- uses `CREATE TABLE IF NOT EXISTS`
- drops and recreates policies
- only adds realtime publication entries when they are missing

## Step 3: Enable Email auth

Go to `Authentication -> Providers -> Email` and enable the email provider.

## Step 4: Check the app credentials

The current app already has a Supabase project URL and anon key embedded in [index.html](/d:/CodingProjects/Toyota%20Test/family-shopping-app/index.html:795).

If you switch to another Supabase project, update:
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

## Step 5: First-user bootstrap behavior

On first login, the app will:
1. look for a `family_members` row for the signed-in user
2. create a new `families` row if none exists
3. insert the user into `family_members`
4. create a default shopping list if the family has none

That flow depends on the current `supabase_schema.sql` policies, so do not mix in the old trigger-based schema.
