-- The audit log's target types, once more. The comments migration (20261115100000) listed the types
-- it knew, and left out league_game, which override_score() audits (LEAG-05). This restores it, with
-- comment kept.
ALTER TABLE private.audit_log DROP CONSTRAINT audit_log_target_type_check;

ALTER TABLE private.audit_log
ADD CONSTRAINT audit_log_target_type_check
  CHECK (
    target_type IN (
      'activity',
      'profile',
      'report',
      'activity_update',
      'group',
      'comment',
      'league_game'
    )
  );
