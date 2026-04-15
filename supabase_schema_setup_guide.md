# Family Shopping List - Supabase Setup Guide

## Source of truth

Use [`supabase_schema.sql`](./supabase_schema.sql) as the only schema file.

The older schema draft in this guide used a different data model from the app:
- `bigint` IDs instead of UUIDs
- a signup trigger instead of first-login family bootstrap
- non-rerunnable SQL

That drift is what caused the current setup confusion.

## Step 1: Create a Supabase project

Create a project at <https://supabase.com>.

## Step 2: Run the schema

Open Supabase SQL Editor, paste the contents of [`supabase_schema.sql`](./supabase_schema.sql), and run it.

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

## Step 5: Family bootstrap and invites

The app supports two compatible paths:

1. Preferred path: use the SQL functions in `supabase_schema.sql` for atomic family bootstrap and invite-code joins.
2. Fallback path: if those functions are missing, the frontend can still bootstrap a family directly and use the family UUID as the share code.

For the cleanest setup, keep the repo schema and the deployed frontend on the same revision.
