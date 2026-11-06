# Appointing moderators and admins

Moderators review reports at `/mod`, hide activities and suspend members. Admins can do the same, and can also suspend a moderator. In Phase 1, an admin changes a member's role in the Supabase dashboard (MOD-06). An admin screen arrives in Phase 3 (MOD-08).

Keep at least 2 admins, so the board never depends on one person. FABA refuses to remove the last one.

## Who has a role now

Open the project at <https://supabase.com/dashboard>, then **SQL Editor**:

```sql
SELECT p.display_name, pp.email, p.role, p.status
FROM public.profiles AS p
JOIN public.profile_private AS pp ON pp.user_id = p.id
WHERE p.role != 'member'
ORDER BY p.role, p.display_name;
```

## Change a role

1. Find the member's ID by their email. They must have signed in to FABA once.

   ```sql
   SELECT user_id FROM public.profile_private WHERE email = 'someone@byui.edu';
   ```

2. Set the role to `moderator`, `admin` or `member`, with a reason. The reason goes to the audit log, so say who asked and why in one sentence.

   ```sql
   SELECT private.set_member_role(
     '<their ID>',
     'moderator',
     'Joined the board in November; approved at the board meeting'
   );
   ```

3. The change applies on their next page load. They don't need to sign out. Moderators see **Open reports** on Me.

To take a role away, set it back to `member` the same way.

## When it refuses

| Error              | Meaning                                                    |
| ------------------ | ---------------------------------------------------------- |
| `REASON_REQUIRED`  | Add a reason                                               |
| `MEMBER_NOT_FOUND` | No account has that ID. Check the email                    |
| `ROLE_UNCHANGED`   | They already have that role                                |
| `LAST_ADMIN`       | They're the only active admin. Make someone else one first |
| A check violation  | The role is misspelled                                     |

## What's recorded

Each change writes a `set_role` row to the audit log, with the old and new role and your reason. Its actor is empty, because nobody is signed in to FABA in the dashboard. [Reading the audit log](audit-log.md) shows how to find it.
