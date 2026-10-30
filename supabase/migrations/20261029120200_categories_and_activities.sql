-- Categories and activities. Design document section 10.3.
-- Row Level Security is on with no policies yet (Iteration 1 tasks DB-2 and DB-6).
CREATE TABLE public.categories (
  id text PRIMARY KEY CHECK (id ~ '^[a-z][a-z0-9-]*$'),
  name text NOT NULL,
  icon text NOT NULL,
  color_token text NOT NULL,
  sort_order INTEGER NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER categories_set_updated_at
BEFORE UPDATE ON public.categories
FOR EACH ROW
EXECUTE FUNCTION private.set_updated_at();

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

-- The fixed list from the roadmap. Icons and color tokens are placeholders until the design
-- tokens exist (Iteration 1 task UX-4). "Online & Remote" stays inactive while FABA serves
-- Rexburg only (ADR-017).
INSERT INTO public.categories
  (id, name, icon, color_token, sort_order, is_active)
VALUES
  ('outdoors', 'Outdoors', 'mountain', 'category-outdoors', 1, TRUE),
  ('sports', 'Sports & Fitness', 'ball', 'category-sports', 2, TRUE),
  ('games', 'Games', 'dice', 'category-games', 3, TRUE),
  ('food', 'Food & Socials', 'utensils', 'category-food', 4, TRUE),
  ('arts', 'Arts & Crafts', 'palette', 'category-arts', 5, TRUE),
  ('learning', 'Learning & Hobbies', 'book', 'category-learning', 6, TRUE),
  ('service', 'Service', 'heart-hand', 'category-service', 7, TRUE),
  ('family', 'Family', 'people', 'category-family', 8, TRUE),
  ('online', 'Online & Remote', 'globe', 'category-online', 9, FALSE),
  ('other', 'Other', 'sparkle', 'category-other', 10, TRUE);

-- Activities are cancelled or hidden, never deleted. Every activity has a place: there are no
-- online activities while FABA serves Rexburg only (ADR-017).
CREATE TABLE public.activities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organizer_id uuid REFERENCES public.profiles (id)
    ON DELETE SET NULL,
  category_id text NOT NULL REFERENCES public.categories (id),
  title text NOT NULL CHECK (char_length(title) BETWEEN 3 AND 80),
  description text CHECK (char_length(description) <= 2000),
  starts_at timestamptz NOT NULL,
  ends_at timestamptz,
  timezone text NOT NULL DEFAULT 'America/Denver',
  location_name text NOT NULL CHECK (char_length(location_name) BETWEEN 1 AND 120),
  cost_note text CHECK (char_length(cost_note) <= 60),
  status text NOT NULL DEFAULT 'published' CHECK (status IN ('published', 'cancelled')),
  cancel_reason text,
  cancelled_at timestamptz,
  hidden_at timestamptz,
  hidden_reason text,
  hidden_by uuid REFERENCES public.profiles (id)
    ON DELETE SET NULL,
  -- Maintained only by rsvp() (ADR-008).
  going_count INTEGER NOT NULL DEFAULT 0 CHECK (going_count >= 0),
  guest_total INTEGER NOT NULL DEFAULT 0 CHECK (guest_total >= 0),
  version INTEGER NOT NULL DEFAULT 1,
  idempotency_key uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (ends_at > starts_at),
  CHECK ((status = 'cancelled') = (cancelled_at IS NOT NULL))
);

CREATE TRIGGER activities_set_updated_at
BEFORE UPDATE ON public.activities
FOR EACH ROW
EXECUTE FUNCTION private.set_updated_at();

ALTER TABLE public.activities ENABLE ROW LEVEL SECURITY;

CREATE INDEX activities_feed_idx ON public.activities (starts_at)
WHERE status = 'published' AND hidden_at IS NULL;

CREATE INDEX activities_organizer_idx ON public.activities (organizer_id, starts_at DESC);

CREATE INDEX activities_category_idx ON public.activities (category_id, starts_at)
WHERE status = 'published' AND hidden_at IS NULL;

CREATE UNIQUE INDEX activities_idempotency_idx ON public.activities (organizer_id, idempotency_key);
