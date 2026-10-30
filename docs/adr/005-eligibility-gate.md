# ADR-005: Four-layer byui.edu eligibility gate

- **Status:** Accepted
- **Date:** 2026-10-28, updated 2026-10-29 (consent screen and sign-in test)
- **Decided by:** FABA design document, section 13.2. Consent screen settled by Zack Alvey (FND-02).
- **Related:** design document section 9.7; AUTH-01, AUTH-02, FND-03; ADR-015, ADR-016

## Context

FABA is for the BYU-Idaho community, and everyone there has a `byui.edu` Google account. Sign-in must keep other accounts out without asking anyone to prove their job.

## Decision

Sign-in uses Google through Supabase Auth, with four layers:

1. **`hd=byui.edu`** on the Google request nudges the account chooser toward school accounts. It's user experience only and never trusted.
2. **The before-user-created hook** rejects any email whose domain isn't exactly `byui.edu` (case-insensitive), so no other account is ever created. The member sees a clear "use your byui.edu account" message (AUTH-02).
3. **The callback check** re-checks the domain and `email_verified` on every sign-in, which catches accounts whose email changed.
4. **`private.is_active_member()`** in every RLS policy requires a `byui.edu` email claim and an `active` profile.

Roles come from the database, not from JWT claims.

**Consent screen (settled 2026-10-29):** FABA owns an **External** Google OAuth app that requests only `openid email profile`. BYU-Idaho IT isn't asked to approve it or host it as an Internal app ([ADR-016](016-independent-of-byu-idaho.md)).

## Sign-in test (FND-03, 2026-10-29)

**Setup:** a development Google OAuth client on an External consent screen, with local Supabase (FND-06) as its only redirect URI. Supabase asked Google for the basic `email` and `profile` scopes, with `hd=byui.edu` and `prompt=select_account`. Nobody at BYU-Idaho was asked to approve anything.

**Result:** a real `byui.edu` account signed in, and BYU-Idaho's Google Workspace didn't block the External app.

- Supabase created the user with `email_verified` true, and Google's `hd` claim was `byui.edu`, so the account is managed by the university's Workspace rather than being a personal Google account.
- The `on_auth_user_created` trigger created the profile, with the Google name and photo, and the `profile_private` row.

**Not yet proven:** sign-in with the production client in production. Members will use the production client set up in FND-09, and FND-10 tests sign-in in production.

## Consequences

- This is a domain gate, not employment verification. [ADR-015](015-any-byui-account-can-join.md) accepts that students and staff can join.
- Risk R-AUTH-2 is lower: the university's Google Workspace allowed an External app in the sign-in test above. Phase 0 still isn't done until a real `byui.edu` sign-in works in production (FND-10). If that's blocked, revisit this ADR and contact IT.
