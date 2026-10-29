# ADR-016: FABA runs independently of BYU-Idaho

- **Status:** Accepted
- **Date:** 2026-10-29
- **Decided by:** Zack Alvey (FND-02, open questions 2, 3, 6 and 10)
- **Related:** FND-03, FND-05; risks R-AUTH-2, R-POL-1, R-POL-2, R-SAFE-1; design document section 9.14; ADR-005

## Context

The design document left several questions for the university: whether IT would allow FABA's Google sign-in, what approvals the name and domain need, whether risk management wants more than a disclaimer, and which privacy policies apply. FABA is a separate app from the school, and it doesn't use official university systems beyond a basic Google sign-in.

## Decision

FABA doesn't seek university approval or involvement:

- **Google sign-in (question 2):** FABA owns an External Google OAuth app that requests only `openid email profile`. IT isn't asked to approve it or host it.
- **Name, domain and branding (question 3):** an independent domain, not under `byui.edu`; no university logos or marks; and a clear "not an official BYU-Idaho site" disclaimer in the footer and the guidelines. There's no institutional contact.
- **Liability (question 6):** an "at your own risk; FABA doesn't supervise activities" disclaimer on the guidelines page and on every Outdoors and Sports activity page. No waivers, and no risk-management review.
- **Privacy (question 10):** the data inventory and retention table in section 9.14, with self-service account deletion and a plain-language privacy notice. No institutional policy is applied.

## Consequences

- **FND-03:** no longer waits on IT or an institutional contact. It becomes: configure the External consent screen with basic scopes and prove a real `byui.edu` sign-in works.
- **FND-05:** the privacy notice follows section 9.14 only, and the note about asking risk management goes.
- Risk R-AUTH-2 remains. If the university's Google Workspace blocks FABA's app, revisit this ADR and contact IT.
- If the university raises a concern about the name or positioning (R-POL-1), revisit this ADR.
