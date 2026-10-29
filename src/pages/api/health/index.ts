import type { APIRoute } from 'astro';

export const prerender = false;

export const GET = (async () => {
  return Response.json({
    status: 'ok',
    environment: import.meta.env.MODE,
    timestamp: new Date().toISOString(),
  });
}) satisfies APIRoute;
