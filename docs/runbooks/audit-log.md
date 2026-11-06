# Reading the audit log

FABA records moderation and role changes, account deletions and admin data fixes in `private.audit_log` (MOD-05). The board uses it to review decisions. In Phase 1, admins read it in the Supabase dashboard. A viewer arrives in Phase 3 (MOD-08).

## Read it

Open the project at <https://supabase.com/dashboard>, then **SQL Editor**. The log is in the `private` schema, which the Data API never exposes, so this is the only way to read it.

The latest 50 rows, with names where the account still exists:

```sql
SELECT
  a.created_at,
  actor.display_name AS actor,
  a.action,
  a.target_type,
  a.target_id,
  a.reason,
  a.metadata
FROM private.audit_log AS a
LEFT JOIN public.profiles AS actor ON actor.id = a.actor_id
ORDER BY a.created_at DESC
LIMIT 50;
```

To see everything that happened to one member, activity or report, filter by the target:

```sql
SELECT *
FROM private.audit_log
WHERE target_type = 'profile' AND target_id = '<the member''s ID>'
ORDER BY created_at;
```

To see what one moderator did, filter by `actor_id = '<their ID>'` instead.

## What a row says

| Column                        | Meaning                                                                                                                                        |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `actor_id`                    | The member who did it. Empty for a runbook run in the dashboard                                                                                |
| `action`                      | `hide`, `unhide`, `suspend`, `reinstate`, `dismiss_report`, `set_role`, `delete_account`, `data_fix`, `transfer_activity` or `cancel_activity` |
| `target_type` and `target_id` | An `activity`, `profile` or `report`, and its ID                                                                                               |
| `reason`                      | The reason given, 500 characters at most. Moderation actions require one (MOD-02). Account deletion has none                                   |
| `metadata`                    | Details, such as the old and new role. Never names or emails                                                                                   |
| `created_at`                  | When it happened                                                                                                                               |

Rows keep the member's ID after they delete their account, but no personal data (PROF-05).

## Record an admin data fix

When a runbook changes data by hand, record it in the same transaction. If anything fails, neither the fix nor its row is saved:

```sql
BEGIN;
-- The fix itself.
SELECT private.audit(
  'data_fix',
  'activity',
  '<the activity''s ID>',
  'Why, in one sentence',
  '{"ticket": "<link>"}'
);
COMMIT;
```

Moderation and role changes write their rows themselves, from the database functions that make them.

## What nobody can do

- Members, visitors and the Worker's secret key can't read, add, change or delete rows.
- The database refuses to change a row, even in the dashboard.
- It refuses to delete one until the row is 3 years old, the retention period in section 9.14 of the design document. The retention job (PRIV-02) deletes older rows.
