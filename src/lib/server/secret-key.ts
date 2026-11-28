// Supabase's secret keys start with sb_secret_. The legacy service_role key, a JWT, doesn't, and
// FABA doesn't use it. astro.config.mjs can't check this: astro:env checks every secret on each
// request, so a mistyped key would break every page, not just account deletion.

/** Whether a value is a Supabase secret key, not a missing, mistyped or legacy one. */
export function isSecretKey(value: string | undefined): value is string {
  return value?.startsWith('sb_secret_') ?? false;
}
