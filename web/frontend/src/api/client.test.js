import { afterEach, describe, expect, it, vi } from 'vitest';

import { getJob, startInstall } from './client';


describe('API client', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('returns parsed JSON for a successful request', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      text: async () => JSON.stringify({ id: 7, status: 'success' })
    }));

    await expect(getJob(7)).resolves.toEqual({
      id: 7,
      status: 'success'
    });
  });

  it('throws the backend error message', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: false,
      status: 409,
      text: async () => JSON.stringify({
        error: 'cluster already has an active install job',
        job_id: 42
      })
    }));

    const error = await startInstall(1).catch((caught) => caught);

    expect(error.message).toBe(
      'cluster already has an active install job'
    );
    expect(error.status).toBe(409);
    expect(error.jobId).toBe(42);
    expect(error.payload).toEqual({
      error: 'cluster already has an active install job',
      job_id: 42
    });
  });
});
