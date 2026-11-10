-- A member's attendance history is private to them (FR-PROF-5, FR-HIST-3, R-PRIV-1). Design
-- document section 9.8. Who's going is shown only until an activity is over, by the rule rsvp()
-- and isOver() use: when it ends, or 3 hours after it starts without an end time. After that each
-- member reads only their own RSVP, so nobody can list where a colleague has been through the Data
-- API. That includes the organizer, and going_count and maybe_count still say how many.
DROP POLICY "Active members read their own RSVPs and who's going" ON public.rsvps;

CREATE POLICY "Active members read their own RSVPs and who's going" ON public.rsvps
FOR SELECT
TO authenticated
USING (
  (SELECT private.is_active_member())
  AND (
    rsvps.user_id = (SELECT auth.uid())
    OR (
      rsvps.status != 'not_going'
      AND EXISTS (
        SELECT
        FROM public.activities AS a
        WHERE
          a.id = rsvps.activity_id
          AND coalesce(a.ends_at, a.starts_at + INTERVAL '3 hours') > now()
          AND (rsvps.status = 'going' OR a.organizer_id = (SELECT auth.uid()))
      )
    )
  )
);
