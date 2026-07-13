import { createMemoryHistory } from 'vue-router';
import { describe, expect, it } from 'vitest';

import { createAppRouter } from './router';

describe('router', () => {
  it('从地址恢复集群和流水线阶段', async () => {
    const router = createAppRouter(createMemoryHistory());

    await router.push('/clusters/42/precheck');
    await router.isReady();

    expect(router.currentRoute.value.name).toBe('cluster-workspace');
    expect(router.currentRoute.value.params).toMatchObject({
      clusterId: '42',
      stage: 'precheck'
    });
  });

  it('缺少阶段时重定向到集群信息', async () => {
    const router = createAppRouter(createMemoryHistory());

    await router.push('/clusters/9');
    await router.isReady();

    expect(router.currentRoute.value.fullPath).toBe('/clusters/9/cluster-info');
  });
});
