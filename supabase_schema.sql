-- FULL DATABASE SCHEMA FOR FAMILY SHOPPING APP
-- Safe to re-run in Supabase SQL Editor

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1. Families table
CREATE TABLE IF NOT EXISTS families (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);

ALTER TABLE families ADD COLUMN IF NOT EXISTS invite_code text;
CREATE UNIQUE INDEX IF NOT EXISTS families_invite_code_idx ON families(invite_code);


-- 2. Family Members table
CREATE TABLE IF NOT EXISTS family_members (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    family_id uuid REFERENCES families(id) ON DELETE CASCADE NOT NULL,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    UNIQUE(family_id, user_id)
);

ALTER TABLE family_members ADD COLUMN IF NOT EXISTS display_name text;

CREATE OR REPLACE FUNCTION public.generate_family_invite_code()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    candidate text;
BEGIN
    LOOP
        candidate := upper(encode(gen_random_bytes(4), 'hex'));
        EXIT WHEN NOT EXISTS (
            SELECT 1
            FROM public.families
            WHERE invite_code = candidate
        );
    END LOOP;

    RETURN candidate;
END;
$$;

CREATE OR REPLACE FUNCTION public.current_user_display_name()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
    SELECT COALESCE(NULLIF(split_part(email, '@', 1), ''), 'Family Member')
    FROM auth.users
    WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.is_family_member(target_family_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.family_members fm
        WHERE fm.family_id = target_family_id
          AND fm.user_id = auth.uid()
    );
$$;

CREATE OR REPLACE FUNCTION public.bootstrap_family()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    existing_family_id uuid;
    existing_family_name text;
    existing_invite_code text;
    new_family_id uuid;
    new_family_name text;
    new_invite_code text;
    member_name text;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT fm.family_id, f.name, f.invite_code
    INTO existing_family_id, existing_family_name, existing_invite_code
    FROM public.family_members fm
    JOIN public.families f ON f.id = fm.family_id
    WHERE fm.user_id = auth.uid()
    ORDER BY fm.created_at
    LIMIT 1;

    IF existing_family_id IS NOT NULL THEN
        RETURN jsonb_build_object(
            'family_id', existing_family_id,
            'family_name', existing_family_name,
            'invite_code', existing_invite_code
        );
    END IF;

    member_name := public.current_user_display_name();
    new_invite_code := public.generate_family_invite_code();

    INSERT INTO public.families (name, invite_code)
    VALUES ('My Family', new_invite_code)
    RETURNING id, name, invite_code
    INTO new_family_id, new_family_name, new_invite_code;

    DELETE FROM public.family_members
    WHERE user_id = auth.uid();

    INSERT INTO public.family_members (family_id, user_id, display_name)
    VALUES (new_family_id, auth.uid(), member_name);

    RETURN jsonb_build_object(
        'family_id', new_family_id,
        'family_name', new_family_name,
        'invite_code', new_invite_code
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.join_family_by_code(invite_code_input text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    target_family_id uuid;
    target_family_name text;
    normalized_code text;
    member_name text;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    normalized_code := upper(trim(invite_code_input));

    IF normalized_code IS NULL OR normalized_code = '' THEN
        RAISE EXCEPTION 'Invite code is required';
    END IF;

    SELECT id, name
    INTO target_family_id, target_family_name
    FROM public.families
    WHERE invite_code = normalized_code
    LIMIT 1;

    IF target_family_id IS NULL THEN
        RAISE EXCEPTION 'Family invite code not found';
    END IF;

    member_name := public.current_user_display_name();

    DELETE FROM public.family_members
    WHERE user_id = auth.uid()
      AND family_id <> target_family_id;

    INSERT INTO public.family_members (family_id, user_id, display_name)
    VALUES (target_family_id, auth.uid(), member_name)
    ON CONFLICT (family_id, user_id)
    DO UPDATE SET display_name = EXCLUDED.display_name;

    RETURN jsonb_build_object(
        'family_id', target_family_id,
        'family_name', target_family_name,
        'invite_code', normalized_code
    );
END;
$$;

UPDATE public.families
SET invite_code = public.generate_family_invite_code()
WHERE invite_code IS NULL;

UPDATE public.family_members fm
SET display_name = COALESCE(fm.display_name, NULLIF(split_part(u.email, '@', 1), ''), 'Family Member')
FROM auth.users u
WHERE fm.display_name IS NULL
  AND u.id = fm.user_id;

REVOKE ALL ON FUNCTION public.is_family_member(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.generate_family_invite_code() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.current_user_display_name() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.bootstrap_family() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.join_family_by_code(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_family_member(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bootstrap_family() TO authenticated;
GRANT EXECUTE ON FUNCTION public.join_family_by_code(text) TO authenticated;

ALTER TABLE families ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their family" ON families;
CREATE POLICY "Users can view their family" ON families
    FOR SELECT USING (
        public.is_family_member(id)
    );

DROP POLICY IF EXISTS "Authenticated users can create families" ON families;
CREATE POLICY "Authenticated users can create families" ON families
    FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Family members can update their family" ON families;
CREATE POLICY "Family members can update their family" ON families
    FOR UPDATE USING (
        public.is_family_member(id)
    );

ALTER TABLE family_members ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their family members" ON family_members;
CREATE POLICY "Users can view their family members" ON family_members
    FOR SELECT USING (
        public.is_family_member(family_id)
    );

DROP POLICY IF EXISTS "Users can add themselves to families" ON family_members;
CREATE POLICY "Users can add themselves to families" ON family_members
    FOR INSERT WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can update themselves in family_members" ON family_members;
CREATE POLICY "Users can update themselves in family_members" ON family_members
    FOR UPDATE USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can remove themselves from families" ON family_members;
CREATE POLICY "Users can remove themselves from families" ON family_members
    FOR DELETE USING (user_id = auth.uid());


-- 3. Shopping Lists table
CREATE TABLE IF NOT EXISTS shopping_lists (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    family_id uuid REFERENCES families(id) ON DELETE CASCADE NOT NULL,
    name text NOT NULL,
    created_by uuid REFERENCES auth.users(id),
    created_at timestamp with time zone DEFAULT now()
);

ALTER TABLE shopping_lists ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Family members can view lists" ON shopping_lists;
CREATE POLICY "Family members can view lists" ON shopping_lists
    FOR SELECT USING (
        public.is_family_member(family_id)
    );

DROP POLICY IF EXISTS "Family members can create lists" ON shopping_lists;
CREATE POLICY "Family members can create lists" ON shopping_lists
    FOR INSERT WITH CHECK (
        public.is_family_member(family_id)
    );

DROP POLICY IF EXISTS "Family members can update lists" ON shopping_lists;
CREATE POLICY "Family members can update lists" ON shopping_lists
    FOR UPDATE USING (
        public.is_family_member(family_id)
    );

DROP POLICY IF EXISTS "Family members can delete lists" ON shopping_lists;
CREATE POLICY "Family members can delete lists" ON shopping_lists
    FOR DELETE USING (
        public.is_family_member(family_id)
    );


-- 4. Shopping Items table
CREATE TABLE IF NOT EXISTS shopping_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    family_id uuid REFERENCES families(id) ON DELETE CASCADE NOT NULL,
    list_id uuid REFERENCES shopping_lists(id) ON DELETE CASCADE NOT NULL,
    name text NOT NULL,
    quantity text DEFAULT '1',
    checked boolean DEFAULT false,
    created_by uuid REFERENCES auth.users(id),
    checked_by uuid REFERENCES auth.users(id),
    checked_at timestamp with time zone,
    completed_trip_id uuid,
    created_at timestamp with time zone DEFAULT now()
);

ALTER TABLE shopping_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Family members can view items" ON shopping_items;
CREATE POLICY "Family members can view items" ON shopping_items
    FOR SELECT USING (
        public.is_family_member(family_id)
    );

DROP POLICY IF EXISTS "Family members can add items" ON shopping_items;
CREATE POLICY "Family members can add items" ON shopping_items
    FOR INSERT WITH CHECK (
        public.is_family_member(family_id)
    );

DROP POLICY IF EXISTS "Family members can update items" ON shopping_items;
CREATE POLICY "Family members can update items" ON shopping_items
    FOR UPDATE USING (
        public.is_family_member(family_id)
    );

DROP POLICY IF EXISTS "Family members can delete items" ON shopping_items;
CREATE POLICY "Family members can delete items" ON shopping_items
    FOR DELETE USING (
        public.is_family_member(family_id)
    );


-- 5. Shopping Trips table
CREATE TABLE IF NOT EXISTS shopping_trips (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    family_id uuid REFERENCES families(id) ON DELETE CASCADE NOT NULL,
    total_amount decimal(10,2) NOT NULL,
    completed_by uuid REFERENCES auth.users(id),
    items jsonb NOT NULL,
    completed_at timestamp with time zone DEFAULT now()
);

ALTER TABLE shopping_trips ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Family members can view trips" ON shopping_trips;
CREATE POLICY "Family members can view trips" ON shopping_trips
    FOR SELECT USING (
        public.is_family_member(family_id)
    );

DROP POLICY IF EXISTS "Family members can create trips" ON shopping_trips;
CREATE POLICY "Family members can create trips" ON shopping_trips
    FOR INSERT WITH CHECK (
        public.is_family_member(family_id)
    );

DROP POLICY IF EXISTS "Family members can delete trips" ON shopping_trips;
CREATE POLICY "Family members can delete trips" ON shopping_trips
    FOR DELETE USING (
        public.is_family_member(family_id)
    );


-- ENABLE REALTIME
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'shopping_lists'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE shopping_lists;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'shopping_items'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE shopping_items;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'shopping_trips'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE shopping_trips;
    END IF;
END $$;
