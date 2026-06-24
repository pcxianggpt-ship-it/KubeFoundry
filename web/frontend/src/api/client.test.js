import { afterEach, describe, expect, it, vi } from 'vitest';

import { copyNodes, getJob, startInstall, startNodeTest } from './client';


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

  it('calls copy nodes and node test endpoints', async () => {
    const fetch = vi.fn()
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        text: async () => JSON.stringify({ items: [] })
      })
      .mockResolvedValueOnce({
        ok: true,
        status: 202,
        text: async () => JSON.stringify({ job_id: 9, status: 'pending' })
      });
    vi.stubGlobal('fetch', fetch);

    await copyNodes(1, [2, 3]);
    expect(fetch).toHaveBeenCalledWith('/api/clusters/1/nodes/copy', expect.objectContaining({ method: 'POST' }));

    await startNodeTest(1);
    expect(fetch).toHaveBeenCalledWith('/api/clusters/1/node-test', expect.objectContaining({ method: 'POST' }));
  });
});
