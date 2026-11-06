# Moving a member to a new account

FABA ties an account to a Google account, not an email address. When the same person signs in with a different Google account, FABA makes a new, empty account (design document section 9.7). There's no merge feature. Instead, an admin moves what they organize and their RSVPs to the new account in the Supabase dashboard (OPS-01).

This isn't for a member whose byui.edu address changes, for example after a name change, while their Google account stays the same. They keep their FABA account. Updating the address it shows comes with AUTH-05.

## Before you start

- **Confirm it's the same person.** Ask them to email the board from both addresses, or from the new one with someone on the board who knows them. Never move an account on one request you can't check.
- **They must have signed in with the new account once,** so it exists. If it hasn't accepted the guidelines yet, that's fine.
- Agree with them whether to delete the old account afterwards. Usually yes.

## Move it

Open the project at <https://supabase.com/dashboard>, then **SQL Editor**.

1. Find both accounts' IDs by email:

   ```sql
   SELECT p.id, pp.email, p.display_name, p.status, p.created_at
   FROM public.profiles AS p
   JOIN public.profile_private AS pp ON pp.user_id = p.id
   WHERE pp.email IN ('old.address@byui.edu', 'new.address@byui.edu');
   ```

2. Move everything from the old account to the new one, with a reason for the audit log:

   ```sql
   SELECT private.transfer_account(
     '<old account ID>',
     '<new account ID>',
     'New Google account; confirmed by email from both addresses'
   );
   ```

   It moves:
   - every activity the old account organizes, past and upcoming
   - its RSVPs. Where both accounts answered the same activity, the new account's answer stays, and the going count drops by the duplicate.

   It doesn't change either profile, copy the old profile's details, or move reports the old account sent. If something fails, nothing moves.

3. Check it:

   ```sql
   SELECT title, starts_at FROM public.activities WHERE organizer_id = '<new account ID>';
   ```

## Delete the old account

Once the member agrees:

1. Record it in the audit log:

   ```sql
   SELECT private.audit(
     'delete_account',
     'profile',
     '<old account ID>',
     'Moved to <new account ID>; deleted by an admin at the member''s request'
   );
   ```

2. Go to **Authentication → Users**, find the old address, and choose **Delete user**. Its profile and private details go with it. It has nothing left in activities or RSVPs.

## An organizer who's no longer eligible

When someone's address stops being byui.edu, for example after they leave BYU-Idaho, FABA marks their account ineligible the next time they sign in (AUTH-05). Their upcoming activities stay up, marked "Organizer no longer active". If they come back with a new Google account, move everything as above. Otherwise, a moderator decides, with the board, what happens to each upcoming activity, and an admin does it here. Each change and its audit row go in one transaction.

Find their upcoming activities:

```sql
SELECT a.id, a.title, a.starts_at, a.going_count
FROM public.activities AS a
JOIN public.profiles AS p ON p.id = a.organizer_id
WHERE p.status = 'ineligible' AND a.status = 'published' AND a.starts_at > now()
ORDER BY a.starts_at;
```

To give one to a member who agrees to host it, who then goes as its organizer:

```sql
BEGIN;
UPDATE public.activities SET organizer_id = '<new organizer''s ID>' WHERE id = '<activity ID>';
INSERT INTO public.rsvps (activity_id, user_id, status)
VALUES ('<activity ID>', '<new organizer''s ID>', 'going')
ON CONFLICT (activity_id, user_id) DO UPDATE SET status = 'going';
UPDATE public.activities AS a
SET going_count = (
  SELECT count(*) FROM public.rsvps AS r WHERE r.activity_id = a.id AND r.status = 'going'
)
WHERE a.id = '<activity ID>';
SELECT private.audit(
  'data_fix',
  'activity',
  '<activity ID>',
  'New organizer; the last one is no longer eligible'
);
COMMIT;
```

To cancel one, so the people going see it's off:

```sql
BEGIN;
UPDATE public.activities
SET
  status = 'cancelled',
  cancelled_at = now(),
  cancel_reason = 'Its organizer is no longer at BYU-Idaho.'
WHERE id = '<activity ID>';
SELECT private.audit(
  'data_fix',
  'activity',
  '<activity ID>',
  'Cancelled; the organizer is no longer eligible'
);
COMMIT;
```

## When it refuses

| Error              | Meaning                                     |
| ------------------ | ------------------------------------------- |
| `REASON_REQUIRED`  | Add a reason                                |
| `SAME_ACCOUNT`     | Both IDs are the same                       |
| `MEMBER_NOT_FOUND` | One of the IDs has no account. Check step 1 |

Each transfer writes a `data_fix` row to the audit log, with both IDs and how many activities and RSVPs moved. [Reading the audit log](audit-log.md) shows how to find it.
