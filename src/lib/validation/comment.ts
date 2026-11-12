// Comments on activities (ACT-12): flat and plain text, up to 500 characters, as the database's
// CHECK constraint says. post_comment() checks the rest.
import { z } from 'astro/zod';

export const COMMENT_MAX = 500;

/** Posting a comment on an activity. */
export const newComment = z.object({
  activity_id: z.uuid({ error: 'Pick an activity.' }),
  body: z
    .string({ error: 'Write a comment first.' })
    .trim()
    .min(1, 'Write a comment first.')
    .max(COMMENT_MAX, `Use ${COMMENT_MAX} characters or fewer for the comment.`),
});

/** Deleting your own comment. */
export const commentRemoval = z.object({ comment_id: z.uuid({ error: 'Pick a comment.' }) });
