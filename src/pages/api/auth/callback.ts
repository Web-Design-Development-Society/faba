// Google calls this endpoint after the user has logged in with google.
import type { APIRoute } from 'astro';

export const GET = (async () => {
  // redirect to appropriate page
  return new Response('Hello World');
}) satisfies APIRoute;
