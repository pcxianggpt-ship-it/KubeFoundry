import { afterEach, describe, expect, it, vi } from 'vitest';

import { copyNodes, getJob, resetCluster, resumeInstallJob, startInstall, startNodeTest, updateComponents } from './client';


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

  it('sends both server-side remote reset confirmations', async () => {
    const fetch = vi.fn().mockResolvedValue({
      ok: true,
      status: 202,
      text: async () => JSON.stringify({ job_id: 9, status: 'pending' })
    });
    vi.stubGlobal('fetch', fetch);

    await resetCluster(7, true, 'RESET production');

    expect(fetch).toHaveBeenCalledWith('/api/clusters/7/reset', expect.objectContaining({
      method: 'POST',
      body: JSON.stringify({ acknowledged: true, confirmation_phrase: 'RESET production' })
    }));
  });

  it('creates a resume job without client-controlled start step', async () => {
    const fetch = vi.fn().mockResolvedValue({
      ok: true,
      status: 202,
      text: async () => JSON.stringify({ job_id: 18, source_job_id: 11, run_mode: 'resume' })
    });
    vi.stubGlobal('fetch', fetch);

    await resumeInstallJob(7, 11);

    expect(fetch).toHaveBeenCalledWith('/api/clusters/7/jobs/11/resume', expect.objectContaining({
      method: 'POST'
    }));
    expect(fetch.mock.calls[0][1].body).toBeUndefined();
  });

  it('sends the Kubemate component aggregate unchanged', async () => {
    const fetch = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      text: async () => JSON.stringify({ enabled: true, groups: [] })
    });
    vi.stubGlobal('fetch', fetch);
    const configuration = { enabled: true, groups: [{ key: 'traefik', enabled: true, config: {} }] };

    await updateComponents(7, configuration);

    expect(fetch).toHaveBeenCalledWith('/api/clusters/7/components', expect.objectContaining({
      method: 'PUT', body: JSON.stringify(configuration)
    }));
  });

});
