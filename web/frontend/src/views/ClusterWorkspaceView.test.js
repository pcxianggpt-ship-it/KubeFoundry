import { flushPromises, mount } from '@vue/test-utils';
import ElementPlus from 'element-plus';
import { createMemoryHistory } from 'vue-router';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import ClusterWorkspaceView from './ClusterWorkspaceView.vue';
import { createAppRouter } from '../router';
import { createCluster, getCluster, updateCluster } from '../api/client';

vi.mock('../api/client', () => ({
  getCluster: vi.fn(),
  createCluster: vi.fn(),
  updateCluster: vi.fn(),
  listClusters: vi.fn(),
  listJobs: vi.fn().mockResolvedValue({ items: [] }),
  getPrecheckResults: vi.fn().mockResolvedValue({ items: [] }),
  startPrecheck: vi.fn()
}));

async function mountAt(path) {
  const router = createAppRouter(createMemoryHistory());
  await router.push(path);
  await router.isReady();
  const wrapper = mount(ClusterWorkspaceView, {
    global: {
      plugins: [ElementPlus, router]
    }
  });
  await flushPromises();
  return { router, wrapper };
}

describe('ClusterWorkspaceView', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    getCluster.mockResolvedValue({
      id: 42,
      name: '生产集群',
      status: 'precheck_passed',
      k8s_version: '1.30.14',
      node_count: 3
    });
  });

  it('刷新后按 URL 恢复当前阶段并显示中文内容', async () => {
    const { wrapper } = await mountAt('/clusters/42/settings');

    expect(getCluster).toHaveBeenCalledWith('42');
    expect(wrapper.get('[data-stage-key="settings"]').attributes('aria-current')).toBe('step');
    expect(wrapper.get('h1').text()).toBe('生产集群');
    expect(wrapper.get('[data-testid="stage-content"]').text()).toContain('安装配置');
  });

  it('显示加载、错误重试和阶段禁用状态', async () => {
    let rejectCluster;
    getCluster.mockReturnValue(new Promise((resolve, reject) => {
      rejectCluster = reject;
    }));

    const router = createAppRouter(createMemoryHistory());
    await router.push('/clusters/42/precheck');
    await router.isReady();
    const wrapper = mount(ClusterWorkspaceView, {
      global: { plugins: [ElementPlus, router] }
    });

    expect(wrapper.get('[aria-busy="true"]')).toBeTruthy();
    rejectCluster(new Error('集群加载失败'));
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain('集群加载失败');

    getCluster.mockResolvedValueOnce({ id: 42, name: '待配置', status: 'draft' });
    await wrapper.get('[data-testid="retry-workspace"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-stage-key="install"] .pipeline-stage__status').text()).toBe('暂不可用');
  });

  it('创建集群后替换为持久化集群路由', async () => {
    createCluster.mockResolvedValue({ id: 88, name: '新生产集群', status: 'draft' });

    const { router, wrapper } = await mountAt('/clusters/new/cluster-info');
    await wrapper.get('[data-testid="cluster-name"]').setValue('新生产集群');
    await wrapper.get('[data-testid="save-cluster"]').trigger('click');
    await flushPromises();

    expect(getCluster).not.toHaveBeenCalledWith('new');
    expect(createCluster).toHaveBeenCalledWith(expect.objectContaining({ name: '新生产集群' }));
    expect(router.currentRoute.value.fullPath).toBe('/clusters/88/cluster-info');
  });

  it('编辑已有集群时调用更新接口并刷新页面数据', async () => {
    updateCluster.mockResolvedValue({ id: 42, name: '更新后的集群', status: 'draft' });
    const { wrapper } = await mountAt('/clusters/42/cluster-info');

    await wrapper.get('[data-testid="cluster-name"]').setValue('更新后的集群');
    await wrapper.get('[data-testid="save-cluster"]').trigger('click');
    await flushPromises();

    expect(updateCluster).toHaveBeenCalledWith('42', expect.objectContaining({ name: '更新后的集群' }));
    expect(wrapper.get('h1').text()).toBe('更新后的集群');
  });
});
