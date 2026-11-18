-- Sample groups for staging (FND-10), so the group and activity pages have something to show: four
-- groups the sample personas run and belong to, one with a request to join, group updates, and a
-- few of the sample activities posted under them, plus comments and updates on some activities.
-- It needs staging_accounts.sql and sample_data.sql first, and the Seed staging workflow runs it
-- after them. Nobody is notified, since nothing goes through the app.
-- Running it again starts the groups over, so anyone who joined them leaves, and gives the
-- personas' newest activities fresh comments and updates. It's one statement because
-- `supabase db query` runs only one at a time.
DO $$
DECLARE
  maya CONSTANT uuid := '00000000-0000-4000-8000-000000000001';
  oscar CONSTANT uuid := '00000000-0000-4000-8000-000000000002';
  morgan CONSTANT uuid := '00000000-0000-4000-8000-000000000003';
  ada CONSTANT uuid := '00000000-0000-4000-8000-000000000004';
  personas CONSTANT uuid[] := ARRAY[
    maya,
    oscar,
    morgan,
    ada,
    '00000000-0000-4000-8000-000000000005'::uuid
  ];
  trail CONSTANT uuid := '00000000-0000-4000-9000-000000000001';
  books CONSTANT uuid := '00000000-0000-4000-9000-000000000002';
  games CONSTANT uuid := '00000000-0000-4000-9000-000000000003';
  service CONSTANT uuid := '00000000-0000-4000-9000-000000000004';
  seeded CONSTANT uuid[] := ARRAY[trail, books, games, service];
BEGIN
  -- Start over. An activity keeps its group until it's taken off it, and the members, group updates
  -- and follows go with the groups.
  UPDATE public.activities
  SET
    group_id = NULL,
    visibility = 'members'
  WHERE group_id = ANY (seeded);
  DELETE FROM public.groups WHERE id = ANY (seeded);
  DELETE FROM public.activity_comments AS c
  USING public.activities AS a
  WHERE c.activity_id = a.id AND a.organizer_id = ANY (personas) AND c.author_id = ANY (personas);
  DELETE FROM public.activity_updates AS u
  USING public.activities AS a
  WHERE u.activity_id = a.id AND a.organizer_id = ANY (personas);

  INSERT INTO public.groups
    (id, slug, name, description, category_id, join_policy, owner_id, created_at)
  VALUES
    (
      trail,
      'rexburg-trail-runners',
      'Rexburg Trail Runners',
      'Easy miles on the trails around Rexburg, most Saturdays. Every pace is welcome.',
      'outdoors',
      'open',
      oscar,
      now() - INTERVAL '60 days'
    ),
    (
      books,
      'faculty-book-club',
      'Faculty Book Club',
      'One book a month, chosen by the group, talked over at the library.',
      'learning',
      'approval',
      morgan,
      now() - INTERVAL '45 days'
    ),
    (
      games,
      'board-game-lunch',
      'Board Game Lunch',
      'Quick games over lunch. Bring one if you have it.',
      'games',
      'open',
      maya,
      now() - INTERVAL '30 days'
    ),
    (
      service,
      'family-service-crew',
      'Family Service Crew',
      'Service projects the whole family can join.',
      'service',
      'open',
      ada,
      now() - INTERVAL '20 days'
    );

  -- Owners, organizers and members, and Oscar asking to join the book club.
  INSERT INTO public.group_members (group_id, user_id, role, status, joined_at)
  VALUES
    (trail, oscar, 'owner', 'active', now() - INTERVAL '60 days'),
    (trail, morgan, 'organizer', 'active', now() - INTERVAL '50 days'),
    (trail, maya, 'member', 'active', now() - INTERVAL '40 days'),
    (trail, ada, 'member', 'active', now() - INTERVAL '10 days'),
    (books, morgan, 'owner', 'active', now() - INTERVAL '45 days'),
    (books, ada, 'organizer', 'active', now() - INTERVAL '40 days'),
    (books, maya, 'member', 'active', now() - INTERVAL '30 days'),
    (books, oscar, 'member', 'pending', now() - INTERVAL '1 day'),
    (games, maya, 'owner', 'active', now() - INTERVAL '30 days'),
    (games, ada, 'member', 'active', now() - INTERVAL '25 days'),
    (games, oscar, 'member', 'active', now() - INTERVAL '5 days'),
    (service, ada, 'owner', 'active', now() - INTERVAL '20 days'),
    (service, morgan, 'member', 'active', now() - INTERVAL '15 days');

  -- A few of the sample activities, posted under the group by one of its organizers, soonest
  -- first. One of the board game lunches is for the group's members only.
  UPDATE public.activities AS a
  SET
    group_id = g.group_id,
    visibility = g.visibility
  FROM (
    SELECT
      a.id,
      p.group_id,
      CASE
        WHEN
          p.group_id = games
          AND row_number() OVER (
            PARTITION BY p.group_id
            ORDER BY a.starts_at
          ) = 2
        THEN
          'group'
        ELSE 'members'
      END AS visibility,
      row_number() OVER (
        PARTITION BY p.group_id
        ORDER BY a.starts_at
      ) AS n
    FROM public.activities AS a
    JOIN (
      VALUES
        (trail, ARRAY['outdoors', 'sports'], ARRAY[oscar, morgan]),
        (books, ARRAY['learning', 'arts'], ARRAY[morgan, ada]),
        (games, ARRAY['games', 'food'], ARRAY[maya]),
        (service, ARRAY['service', 'family'], ARRAY[ada])
    ) AS p (group_id, categories, organizers)
      ON a.category_id = ANY (p.categories) AND a.organizer_id = ANY (p.organizers)
    WHERE a.status = 'published' AND a.hidden_at IS NULL AND a.starts_at > now()
  ) AS g
  WHERE a.id = g.id AND g.n <= 3;

  -- The groups' updates, from their organizers.
  INSERT INTO public.activity_updates (group_id, author_id, body, created_at)
  VALUES
    (
      trail,
      oscar,
      'New route this month: the loop around R Mountain. About 4 miles.',
      now() - INTERVAL '6 days'
    ),
    (
      trail,
      morgan,
      'The trail is muddy after the rain, so bring shoes you don''t mind getting dirty.',
      now() - INTERVAL '2 days'
    ),
    (
      books,
      morgan,
      'Next month''s book is at the library desk. Pick up a copy any time.',
      now() - INTERVAL '4 days'
    ),
    (
      games,
      maya,
      'We''ll have Catan and Ticket to Ride. Bring another game if you like.',
      now() - INTERVAL '3 days'
    ),
    (
      service,
      ada,
      'Next project: sorting donations at the food pantry. Kids 8 and up are welcome.',
      now() - INTERVAL '1 day'
    );

  -- On the personas' three soonest activities: an update from the organizer, a question from
  -- someone else, and the organizer's answer.
  WITH
    soonest AS (
      SELECT id, organizer_id, row_number() OVER (ORDER BY starts_at) AS n
      FROM public.activities
      WHERE
        organizer_id = ANY (personas)
        AND status = 'published'
        AND hidden_at IS NULL
        AND starts_at > now()
      ORDER BY starts_at
      LIMIT 3
    )
  INSERT INTO public.activity_updates (activity_id, author_id, body, created_at)
  SELECT
    id,
    organizer_id,
    'Parking is free in the lot behind the building after 5.',
    now() - INTERVAL '1 day'
  FROM soonest
  WHERE n = 1;

  WITH
    soonest AS (
      SELECT id, organizer_id, row_number() OVER (ORDER BY starts_at) AS n
      FROM public.activities
      WHERE
        organizer_id = ANY (personas)
        AND status = 'published'
        AND hidden_at IS NULL
        AND starts_at > now()
      ORDER BY starts_at
      LIMIT 3
    )
  INSERT INTO public.activity_comments (activity_id, author_id, body, created_at)
  SELECT
    s.id,
    c.author,
    c.body,
    now() - c.ago
  FROM soonest AS s
  CROSS JOIN LATERAL (
    VALUES
      (
        CASE WHEN s.organizer_id = maya THEN ada ELSE maya END,
        'Is this a good one for beginners?',
        INTERVAL '20 hours'
      ),
      (s.organizer_id, 'Yes! Everyone is welcome, and we go at an easy pace.', INTERVAL '18 hours'),
      (
        CASE WHEN s.organizer_id = morgan THEN oscar ELSE morgan END,
        'Can I bring my kids?',
        INTERVAL '5 hours'
      )
  ) AS c (author, body, ago)
  WHERE s.n <= 2 OR c.ago = INTERVAL '5 hours';
END;
$$;
