-- "Can't make it" is seen only by the member who gave it (RSVP-02, FR-RSVP-4). Design document
-- section 9.8.

-- Members read their own RSVPs and who's going to the activities they can see. Organizers also
-- read the other statuses of RSVPs to their own, such as maybe in Phase 2, but not not_going.
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
          AND (rsvps.status = 'going' OR a.organizer_id = (SELECT auth.uid()))
      )
    )
  )
);
