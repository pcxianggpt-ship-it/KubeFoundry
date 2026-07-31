import { createMemoryHistory } from 'vue-router';
import { describe, expect, it } from 'vitest';

import { createAppRouter } from './router';

describe('router', () => {
  it('从地址恢复集群配置阶段，并兼容旧地址', async () => {
    const router = createAppRouter(createMemoryHistory());

    await router.push('/clusters/42/precheck');
    await router.isReady();

    expect(router.currentRoute.value.name).toBe('cluster-config-workspace');
    expect(router.currentRoute.value.params).toMatchObject({
      clusterId: '42',
      stage: 'precheck'
    });
  });

  it('缺少阶段时重定向到集群信息', async () => {
    const router = createAppRouter(createMemoryHistory());

    await router.push('/clusters/9');
    await router.isReady();

    expect(router.currentRoute.value.fullPath).toBe('/cluster-config/9/cluster-info');
  });

  it('安装确认和任务执行使用独立页面路由', async () => {
    const router = createAppRouter(createMemoryHistory());
    await router.push('/clusters/9/install');
    await router.isReady();
    expect(router.currentRoute.value.fullPath).toBe('/cluster-install/9/overview');
    expect(router.currentRoute.value.name).toBe('install-overview');

    await router.push('/cluster-install/9/reset');
    expect(router.currentRoute.value.name).toBe('reset-confirm');

    await router.push('/jobs/88/execution');
    expect(router.currentRoute.value.name).toBe('job-execution');
    expect(router.currentRoute.value.params.jobId).toBe('88');
  });
});
