import { describe, expect, it } from 'vitest';

import { GET } from '../../src/pages/api/health/index';

describe('GET /api/health', () => {
  it('reports ok with the environment and an ISO timestamp', async () => {
    const response = await GET();
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.status).toBe('ok');
    expect(body.environment).toBe('test');
    expect(new Date(body.timestamp).toISOString()).toBe(body.timestamp);
  });
});
