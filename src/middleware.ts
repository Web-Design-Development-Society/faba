import { defineMiddleware } from 'astro:middleware';
// Importing astro:env/server checks every variable in env.schema (astro.config.mjs), so a
// missing or invalid one fails every request with a clear error instead of breaking later.
// Iteration 1 task AU-5 adds the session and eligibility checks here.
import 'astro:env/server';

export const onRequest = defineMiddleware((_context, next) => next());
