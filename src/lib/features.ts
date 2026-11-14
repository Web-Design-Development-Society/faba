// Features that are built but switched off, so they can come back without being written again.

/**
 * Leagues (LEAG-01 to LEAG-09), on hold since 2026-11-14 while FABA starts with basic groups
 * (ADR-018). While this is false, there's no Start a league, no Seasons on a league's page, no
 * League badge on its card, and no "A sub is needed" in Me → Notifications. The league pages
 * answer "not found", and the league Actions refuse. Their code, tests and database stay, so
 * setting this to true brings leagues back.
 */
export const LEAGUES = false;
