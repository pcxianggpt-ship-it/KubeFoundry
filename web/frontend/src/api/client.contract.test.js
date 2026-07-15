import { beforeEach, describe, expect, it, vi } from 'vitest';

import * as client from './client';

const EXPECTED_EXPORTS = [
  'copyNodes',
  'createCluster',
  'createNode',
  'deleteNode',
  'getCluster',
  'getClusterSettings',
  'getInstallPlan',
  'getJob',
  'getJobLogs',
  'getJobSteps',
  'getPrecheckResults',
  'getSettings',
  'listClusters',
  'listJobs',
  'listNodes',
  'startInstall',
  'startNodeTest',
  'startPrecheck',
  'updateCluster',
  'updateClusterSettings',
  'updateNode',
  'updateSettings'
];

describe('Java Web API 客户端契约', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn().mockImplementation(() => Promise.resolve(new Response('{}', {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    }))));
  });

  it('只暴露 Java 后端支持的接口，不保留 Python 专有接口', () => {
    expect(Object.keys(client).sort()).toEqual(EXPECTED_EXPORTS);
  });

  it('请求路径和方法与 Java 控制器保持一致', async () => {
    await client.listClusters();
    await client.getCluster(7);
    await client.createCluster({ name: 'contract' });
    await client.updateCluster(7, { description: 'updated' });
    await client.listNodes(7);
    await client.createNode(7, { hostname: 'cp-1' });
    await client.updateNode(9, { hostname: 'cp-2' });
    await client.deleteNode(9);
    await client.copyNodes(7, [9]);
    await client.getSettings();
    await client.updateSettings({ paths: {} });
    await client.getClusterSettings(7);
    await client.updateClusterSettings(7, { paths: {} });
    await client.startPrecheck(7);
    await client.startNodeTest(7);
    await client.startInstall(7);
    await client.listJobs(7);
    await client.getInstallPlan();
    await client.getJob(11);
    await client.getJobSteps(11);
    await client.getJobLogs(11);
    await client.getPrecheckResults(11);

    expect(fetch.mock.calls.map(([path, options = {}]) => [path, options.method || 'GET'])).toEqual([
      ['/api/clusters', 'GET'],
      ['/api/clusters/7', 'GET'],
      ['/api/clusters', 'POST'],
      ['/api/clusters/7', 'PUT'],
      ['/api/clusters/7/nodes', 'GET'],
      ['/api/clusters/7/nodes', 'POST'],
      ['/api/nodes/9', 'PUT'],
      ['/api/nodes/9', 'DELETE'],
      ['/api/clusters/7/nodes/copy', 'POST'],
      ['/api/settings', 'GET'],
      ['/api/settings', 'PUT'],
      ['/api/clusters/7/settings', 'GET'],
      ['/api/clusters/7/settings', 'PUT'],
      ['/api/clusters/7/precheck', 'POST'],
      ['/api/clusters/7/node-test', 'POST'],
      ['/api/clusters/7/install', 'POST'],
      ['/api/jobs?cluster_id=7', 'GET'],
      ['/api/install-plan', 'GET'],
      ['/api/jobs/11', 'GET'],
      ['/api/jobs/11/steps', 'GET'],
      ['/api/jobs/11/logs', 'GET'],
      ['/api/jobs/11/precheck-results', 'GET']
    ]);
  });
});
