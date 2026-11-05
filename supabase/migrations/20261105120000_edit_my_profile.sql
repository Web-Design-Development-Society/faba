-- Members edit their own profile (PROF-02). Design document sections 9.8 and 10.3. Unlike
-- activities and RSVPs, members update their own profile directly (ADR-004): column-level grants
-- name what they may change, and Row Level Security limits them to their own row while they're
-- active. Role, status, email, the photo and the guidelines stay out of reach.

-- Interests are category slugs, which the form checks. This keeps a direct request from storing
-- an endless list.
ALTER TABLE public.profiles
ADD CONSTRAINT profiles_interests_check CHECK (cardinality(interests) <= 20);

GRANT UPDATE (display_name, use_initials, department, bio, interests)
ON public.profiles
TO authenticated;

CREATE POLICY "Active members update their own profile" ON public.profiles
FOR UPDATE
TO authenticated
USING (id = (SELECT auth.uid()) AND (SELECT private.is_active_member()))
WITH CHECK (id = (SELECT auth.uid()));

-- The form shows the member's faculty type back to them. Moderators get access with the
-- moderation stories. Email visibility is PROF-04's, and email changes only through
-- sync_my_identity() (AUTH-05).
CREATE POLICY "Members read their own private profile" ON public.profile_private
FOR SELECT
TO authenticated
USING (user_id = (SELECT auth.uid()));

GRANT UPDATE (faculty_type) ON public.profile_private TO authenticated;

CREATE POLICY "Active members update their own private profile" ON public.profile_private
FOR UPDATE
TO authenticated
USING (user_id = (SELECT auth.uid()) AND (SELECT private.is_active_member()))
WITH CHECK (user_id = (SELECT auth.uid()));
