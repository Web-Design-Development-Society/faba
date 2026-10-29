# ADR-015: Any byui.edu account can join; no faculty attestation

- **Status:** Accepted
- **Date:** 2026-10-29
- **Decided by:** Zack Alvey (FND-02, open question 1)
- **Related:** AUTH-02, PROF-01, MOD-01; risk R-AUTH-1; ADR-005

## Context

Every `byui.edu` email, including students' and staff's, has a Google account. The design document's default was a required Welcome checkbox ("I'm a BYU-Idaho faculty member and agree to the guidelines"), a "Not faculty" report reason, and a board-maintained allow-list if abuse happened.

Some students take part in faculty activities as teaching assistants and adjuncts, and sign-in should stay as simple as possible.

## Decision

- Any `byui.edu` Google account can sign in and join. FABA doesn't try to tell faculty apart from students or staff.
- There's no faculty attestation and no allow-list.
- Accounts from any other domain are still refused at sign-up ([ADR-005](005-eligibility-gate.md)).

## Consequences

- **PROF-01:** the Welcome checkbox becomes agreement to the guidelines only, and the note about attestation goes.
- **AUTH-02:** the note pointing to the attestation default goes.
- **MOD-01:** the "Not faculty" report reason goes. Moderators can still suspend anyone who misuses FABA.
- Risk R-AUTH-1 is accepted rather than mitigated.
