import { flushPromises, mount, RouterLinkStub } from '@vue/test-utils';
import ElementPlus from 'element-plus';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import ClusterListView from './ClusterListView.vue';
import { listClusters, listJobs } from '../api/client';

vi.mock('../api/client', () => ({
  listClusters: vi.fn(),
  listJobs: vi.fn()
}));

function mountView() {
  return mount(ClusterListView, {
    global: {
      plugins: [ElementPlus],
      stubs: { RouterLink: RouterLinkStub }
    }
  });
}

describe('ClusterListView', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    listJobs.mockResolvedValue({ items: [] });
  });

  it('按五种集群状态显示中文主操作并直达目标路由', async () => {
    listClusters.mockResolvedValue({
      items: [
        { id: 1, name: '待配置', status: 'configuration_incomplete', current_stage: 'nodes' },
        { id: 2, name: '待安装', status: 'precheck_passed', current_stage: 'nodes' },
        { id: 3, name: '安装中', status: 'installing', active_job_id: 31 },
        { id: 4, name: '安装失败', status: 'install_failed', latest_job_id: 41 },
        { id: 5, name: '生产集群', status: 'installed' }
      ]
    });

    const wrapper = mountView();
    await flushPromises();

    expect(wrapper.findAll('.cluster-row')).toHaveLength(5);
    expect(wrapper.text()).toContain('配置未完成');
    expect(wrapper.text()).toContain('预检查通过');
    expect(wrapper.text()).toContain('正在安装');
    expect(wrapper.text()).toContain('安装失败');
    expect(wrapper.text()).toContain('安装成功');

    const actions = wrapper.findAllComponents(RouterLinkStub).filter((link) => link.classes('cluster-row__action'));
    expect(actions.map((link) => link.text())).toEqual([
      '继续配置',
      '开始安装',
      '查看进度',
      '查看失败原因',
      '查看集群'
    ]);
    expect(actions.map((link) => link.props('to'))).toEqual([
      { name: 'cluster-workspace', params: { clusterId: '1', stage: 'nodes' } },
      { name: 'cluster-workspace', params: { clusterId: '2', stage: 'install' } },
      { name: 'job-execution', params: { jobId: '31' } },
      { name: 'job-execution', params: { jobId: '41' } },
      { name: 'cluster-workspace', params: { clusterId: '5', stage: 'cluster-info' } }
    ]);
    expect(wrapper.getComponent('[data-testid="create-cluster"]').props('to')).toEqual({
      name: 'cluster-workspace',
      params: { clusterId: 'new', stage: 'cluster-info' }
    });
  });

  it('使用现有任务聚合Java集群响应的安装状态和任务入口', async () => {
    listClusters.mockResolvedValue({ items: [
      { id: 10, name: '执行中', status: 'draft' },
      { id: 11, name: '预检完成', status: 'draft' },
      { id: 12, name: '已完成', status: 'draft' }
    ] });
    listJobs.mockImplementation((clusterId) => Promise.resolve({ items: {
      10: [{ id: 101, job_type: 'install', status: 'running' }],
      11: [{ id: 111, job_type: 'precheck', status: 'success' }],
      12: [{ id: 121, job_type: 'install', status: 'success' }]
    }[clusterId] }));

    const wrapper = mountView();
    await flushPromises();

    const actions = wrapper.findAllComponents(RouterLinkStub)
      .filter((link) => link.classes('cluster-row__action'));
    expect(actions.map((link) => link.text())).toEqual(['查看进度', '开始安装', '查看集群']);
    expect(actions.map((link) => link.props('to'))).toEqual([
      { name: 'job-execution', params: { jobId: '101' } },
      { name: 'cluster-workspace', params: { clusterId: '11', stage: 'install' } },
      { name: 'cluster-workspace', params: { clusterId: '12', stage: 'cluster-info' } }
    ]);
  });

  it('提供加载、空数据、错误重试和无目标任务禁用状态', async () => {
    let resolveClusters;
    listClusters.mockReturnValue(new Promise((resolve) => {
      resolveClusters = resolve;
    }));

    const wrapper = mountView();
    expect(wrapper.get('[aria-busy="true"]')).toBeTruthy();
    expect(wrapper.get('[data-testid="create-cluster"]').attributes('aria-disabled')).toBe('true');
    expect(wrapper.get('[data-testid="create-cluster"]').attributes('tabindex')).toBe('-1');

    resolveClusters({ items: [] });
    await flushPromises();
    expect(wrapper.text()).toContain('还没有集群');

    listClusters.mockRejectedValueOnce(new Error('服务暂时不可用'));
    await wrapper.get('[data-testid="refresh-clusters"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain('服务暂时不可用');

    listClusters.mockResolvedValueOnce({ items: [{ id: 6, name: '缺少任务', status: 'installing' }] });
    await wrapper.get('[data-testid="retry-clusters"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('.cluster-row__action.is-disabled').attributes('aria-disabled')).toBe('true');
  });
});
