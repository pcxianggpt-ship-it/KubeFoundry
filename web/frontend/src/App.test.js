import { flushPromises, mount } from '@vue/test-utils';
import ElementPlus from 'element-plus';
import { createMemoryHistory } from 'vue-router';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import App from './App.vue';
import { createAppRouter } from './router';
import { listClusters } from './api/client';

vi.mock('./api/client', () => ({
  getCluster: vi.fn(),
  getJob: vi.fn(),
  listClusters: vi.fn()
}));

describe('App', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    listClusters.mockResolvedValue({ items: [] });
  });

  it('通过路由渲染集群首页', async () => {
    const router = createAppRouter(createMemoryHistory());
    await router.push('/');
    await router.isReady();

    const wrapper = mount(App, {
      global: {
        plugins: [ElementPlus, router]
      }
    });
    await flushPromises();

    expect(wrapper.get('h1').text()).toBe('集群部署');
    expect(wrapper.text()).toContain('还没有集群');
  });
});
