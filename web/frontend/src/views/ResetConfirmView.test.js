import { flushPromises, mount } from '@vue/test-utils';
import ElementPlus from 'element-plus';
import { createMemoryHistory } from 'vue-router';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import ResetConfirmView from './ResetConfirmView.vue';
import { createAppRouter } from '../router';
import { getCluster, listNodes, resetCluster } from '../api/client';

vi.mock('../api/client', () => ({
  getCluster: vi.fn(),
  listNodes: vi.fn(),
  resetCluster: vi.fn()
}));

async function mountView() {
  const router = createAppRouter(createMemoryHistory());
  await router.push('/cluster-install/42/reset');
  await router.isReady();
  const wrapper = mount(ResetConfirmView, { global: { plugins: [ElementPlus, router] } });
  await flushPromises();
  return { router, wrapper };
}

describe('ResetConfirmView', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    getCluster.mockResolvedValue({
      id: 42,
      name: '生产集群',
      kubernetes_work_dir: '/data/k8s_install',
      configuration_locked: true
    });
    listNodes.mockResolvedValue({ items: [
      { id: 1, hostname: 'cp-1', roles: ['control_plane', 'registry'] },
      { id: 2, hostname: 'worker-1', roles: ['worker'] }
    ] });
  });

  it('显示清理范围，只有完成强确认后才能提交远程重置', async () => {
    resetCluster.mockResolvedValue({ job_id: 91 });
    const { router, wrapper } = await mountView();

    expect(wrapper.text()).toContain('远程重置不可恢复');
    expect(wrapper.text()).toContain('/data/k8s_install/04.registry');
    expect(wrapper.get('button.el-button--danger').attributes('disabled')).toBeDefined();

    await wrapper.get('.el-checkbox input').setValue(true);
    await wrapper.get('input[placeholder="RESET 生产集群"]').setValue('RESET 生产集群');
    await wrapper.get('button.el-button--danger').trigger('click');
    await flushPromises();

    expect(resetCluster).toHaveBeenCalledWith('42', true, 'RESET 生产集群');
    expect(router.currentRoute.value.fullPath).toBe('/jobs/91/execution');
  });

  it('短语不匹配时保持提交按钮禁用', async () => {
    const { wrapper } = await mountView();
    await wrapper.get('.el-checkbox input').setValue(true);
    await wrapper.get('input[placeholder="RESET 生产集群"]').setValue('RESET 错误集群');

    expect(wrapper.get('button.el-button--danger').attributes('disabled')).toBeDefined();
    expect(resetCluster).not.toHaveBeenCalled();
  });
});
