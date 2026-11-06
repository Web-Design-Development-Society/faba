# Handling a takedown request

Someone asks the board to remove something from FABA: an activity, a member's profile, or their own information. They might be a member, someone named in an activity, or someone outside FABA. This runbook keeps the response consistent and on the record (OPS-01). Every step that changes data writes to the audit log, through the moderation tools or `private.audit()`.

Reports from members go through the queue at `/mod` instead (MOD-02). Use this runbook for requests that arrive by email or in person.

## 1. Acknowledge it

Reply within 2 business days, the same as for reports. Say who's handling it and roughly when. Keep the request in the board's email, not in FABA.

## 2. Find what it's about

Ask for the activity's or profile's link if they didn't send one. A moderator can open any activity or profile, including hidden activities and suspended members.

## 3. Decide

Hiding or suspending is enough for almost every request, and a moderator can undo it. Delete something permanently only when hiding isn't enough, for example a legal requirement, and only after a second admin agrees.

## 4. Act

| The request is about                                        | Do this                                                                                                                                                                                                                                                                            |
| ----------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **An activity**                                             | A moderator opens it, chooses **⋯ → Report**, picks **Other** and notes "Takedown request" and the date. Then, in `/mod`, they choose **Hide content** with the reason. Members stop seeing it, and its organizer sees the reason and can edit it. A moderator can unhide it later |
| **What a member wrote on their profile**                    | Moderators can't edit profiles. Ask the member to change it. If they won't, or it's serious, report the profile the same way and choose **Suspend member** in `/mod`                                                                                                               |
| **The requester's own information**, as a member            | Point them to **Me → Delete account**, which removes their profile, email and RSVPs, and cancels their upcoming activities                                                                                                                                                         |
| **The requester's own information**, but they can't sign in | Delete the account for them, as [Moving a member to a new account](transfer-account.md#delete-the-old-account) does: record it with `private.audit('delete_account', …)`, then delete the user in **Authentication → Users**                                                       |
| **Something hiding isn't enough for**                       | See [Delete permanently](#delete-permanently)                                                                                                                                                                                                                                      |

The hide and suspend reasons go to the audit log and, for a hidden activity, to its organizer. Write what was wrong, never the requester's name or email.

### Delete permanently

In the dashboard's **SQL Editor**, delete the activity and record it in the same transaction, so neither happens without the other. Its RSVPs go with it.

```sql
BEGIN;
DELETE FROM public.activities WHERE id = '<the activity''s ID>';
SELECT private.audit(
  'data_fix',
  'activity',
  '<the activity''s ID>',
  'Deleted for a takedown request; approved by two admins'
);
COMMIT;
```

## 5. Close it

Reply to the requester with what you did, and whether it can be undone. If you did nothing, say why.
