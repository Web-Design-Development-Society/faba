-- Moderation and admin tools (MOD-08). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(11);

-- Ada is an admin, Max a moderator, Oz owns a group, Rae reports it, Mia is a member.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-000000000801', 'ada@byui.edu', '{"full_name": "Ada Admin"}'),
  ('c0000000-0000-4000-8000-000000000802', 'max@byui.edu', '{"full_name": "Max Mod"}'),
  ('c0000000-0000-4000-8000-000000000803', 'oz@byui.edu', '{"full_name": "Oz Owner"}'),
  ('c0000000-0000-4000-8000-000000000804', 'rae@byui.edu', '{"full_name": "Rae Reporter"}'),
  ('c0000000-0000-4000-8000-000000000805', 'mia@byui.edu', '{"full_name": "Mia Member"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id BETWEEN 'c0000000-0000-4000-8000-000000000801' AND 'c0000000-0000-4000-8000-000000000805';

UPDATE public.profiles SET role = 'admin' WHERE id = 'c0000000-0000-4000-8000-000000000801';
UPDATE public.profiles SET role = 'moderator' WHERE id = 'c0000000-0000-4000-8000-000000000802';

INSERT INTO public.groups
  (id, slug, name, category_id, join_policy, owner_id)
VALUES
  (
    'c0000000-0000-4000-8000-000000000810',
    'reported-group',
    'Reported Group',
    'outdoors',
    'open',
    'c0000000-0000-4000-8000-000000000803'
  );

-- Rae reports the group. Max, a moderator, is told; Oz can't report their own.
SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000804", "email": "rae@byui.edu"}',
  TRUE
);

SELECT isnt(
  public.report_content(
    'group',
    'c0000000-0000-4000-8000-000000000810',
    'spam',
    'Looks like an ad'
  ),
  NULL,
  'a member can report a group'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000803", "email": "oz@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.report_content('group', 'c0000000-0000-4000-8000-000000000810', 'other')$$,
  '22023',
  NULL,
  'a group''s owner can''t report it'
);

RESET ROLE;

SELECT results_eq(
  $$select count(*)::int from public.notifications where recipient_id = 'c0000000-0000-4000-8000-000000000802' and type = 'report_received'$$,
  $$values (1)$$,
  'moderators are told about a new report'
);

-- Max adds a note. Only moderators read notes.
SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000802", "email": "max@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.add_moderator_note('group', 'c0000000-0000-4000-8000-000000000810', 'Checked; the ad is a real event.')$$,
  'a moderator adds a note'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000805", "email": "mia@byui.edu"}',
  TRUE
);

SELECT results_eq(
  $$select count(*)::int from public.moderator_notes$$,
  $$values (0)$$,
  'a member can''t read moderators'' notes'
);

-- The audit log is for admins. Ada filters it by actor.
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000801", "email": "ada@byui.edu"}',
  TRUE
);

RESET ROLE;

INSERT INTO private.audit_log (actor_id, action, target_type, target_id, reason)
VALUES
  (
    'c0000000-0000-4000-8000-000000000802',
    'hide',
    'activity',
    '00000000-0000-4000-8000-000000000999',
    'Off topic'
  );

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000801", "email": "ada@byui.edu"}',
  TRUE
);

SELECT results_eq(
  $$select count(*)::int from public.admin_audit_log(actor => 'c0000000-0000-4000-8000-000000000802')$$,
  $$values (1)$$,
  'an admin reads the audit log, filtered by who did it'
);

-- Ada makes Mia a moderator, with a reason. Then Max, a moderator, can't read the audit log.
SELECT lives_ok(
  $$select public.admin_set_role('c0000000-0000-4000-8000-000000000805', 'moderator', 'Helps with reports')$$,
  'an admin changes a role, with a reason'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000802", "email": "max@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select count(*) from public.admin_audit_log()$$,
  '42501',
  NULL,
  'a moderator can''t read the audit log'
);

SELECT throws_ok(
  $$select public.admin_save_category('outdoors', 'Outdoors!', true)$$,
  '42501',
  NULL,
  'a moderator can''t change categories'
);

-- Ada adds a tag.
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000801", "email": "ada@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.admin_save_tag('quiet', 'Quiet', true, 90)$$,
  'an admin adds a tag'
);

RESET ROLE;

SELECT results_eq(
  $$select name from public.tags where id = 'quiet'$$,
  $$values ('Quiet'::text)$$,
  'the new tag is saved'
);

SELECT * FROM finish();
ROLLBACK;
