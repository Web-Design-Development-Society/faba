# ADR-020: Production shares staging's Google OAuth client

- **Status:** Accepted
- **Date:** 2026-11-27
- **Decided by:** Zack Alvey (FND-09)
- **Related:** FND-09, FND-10; risk R-AUTH-2; [ADR-005](005-eligibility-gate.md), [ADR-014](014-cloudflare-and-supabase-stack.md), [ADR-016](016-independent-of-byu-idaho.md); design document section 11.2

## Context

FND-09 and ADR-014 gave each environment its own Google OAuth client. Production got a new "FABA production" client, set up like staging's: an External consent screen that asks only for basic scopes.

After the first release, Google refused a `byui.edu` account at `tofaba.org` with `Error 400: admin_policy_enforced`. BYU-Idaho's Google Workspace had blocked the new client. The same account could still sign in to staging, through the "FABA staging" client. Google doesn't say why it treats the two clients differently.

This is risk R-AUTH-2. ADR-016 says to revisit it and contact IT if the Workspace blocks FABA, but IT might take weeks to answer, or say no.

## Decision

- Production uses the "FABA staging" client, which the Workspace allows. Both Supabase projects have its client ID and secret.
- The client's authorized redirect URIs list both projects' callbacks:
  - `https://qptrhaxvrozdozhuhagb.supabase.co/auth/v1/callback` (staging)
  - `https://ncfuqxwvpxkqfjjcbpuo.supabase.co/auth/v1/callback` (production)
- Its consent screen is published, not in **Testing**, and lists `tofaba.org` as an authorized domain.
- Local development keeps its own dev client.
- FABA doesn't contact IT for now, so ADR-016 stands.

## Consequences

- **Don't delete or replace this client.** Deleting it stops sign-in on staging and production at once, and a new client may be blocked like production's was. The client is still named "FABA staging" in Google Cloud, which is fine.
- A change to the client or its consent screen reaches staging and production together, so there's no way to try it on staging first.
- **To rotate the secret,** add a new one to the client in Google Cloud, put it in both Supabase projects, then disable the old one. Google accepts both in between, so sign-in keeps working.
- Staging's Supabase project now holds a secret production depends on. It needs the same owners and MFA as production (FND-09).
- The "FABA production" client isn't used and can be deleted.
- FND-09 criterion 3 is met with clients for dev and staging.
- R-AUTH-2 remains. If the Workspace blocks this client too, revisit ADR-016 and ask IT to allow-list the client ID. To give production its own client later, ask IT to allow-list it first, and try it with a `byui.edu` account before switching.
