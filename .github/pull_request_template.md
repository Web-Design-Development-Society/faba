## What and why

<!-- Which stories does this cover? For example: Closes #16 (AUTH-01). Keep pull requests to about
400 changed lines, not counting generated types. -->

## Screenshots

<!-- For UI changes, add mobile (375 px wide) and desktop screenshots. Otherwise delete this
section. -->

## Migration?

- [ ] No
- [ ] Yes. It follows expand/contract, so rolling back the Worker doesn't break the database, and
      `src/lib/db.types.ts` is regenerated (`npm run db:types`).

## RLS or permission change?

- [ ] No
- [ ] Yes. A database-literate technical owner needs to review it (see `.github/CODEOWNERS`).

## Testing done

<!-- What did you run or check, and on which devices? -->

## Rollback notes

<!-- How do we undo this if it goes wrong? "Revert the commit" is fine when that's true. -->

## Review checklist

- [ ] Authorization is enforced in Postgres, not only in the UI.
- [ ] The Supabase secret key is used only in `src/lib/server/admin.ts`.
- [ ] No `set:html` with user content.
- [ ] The mobile layout is checked at 375 px.
- [ ] Every interactive element has an accessible name.
- [ ] Copy follows the voice guide.
