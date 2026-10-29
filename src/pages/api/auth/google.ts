// Users call this API endpoint to log in
import type { APIRoute } from 'astro';

export const prerender = false;

export const GET = (async () => {
  // redirect to google
  return new Response('Hello World');
}) satisfies APIRoute;
