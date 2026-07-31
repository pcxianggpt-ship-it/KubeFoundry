import { flushPromises, mount, RouterLinkStub } from '@vue/test-utils';
import ElementPlus from 'element-plus';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import ClusterListView from './ClusterListView.vue';
import { listClusters, listJobs } from '../api/client';

vi.mock('../api/client', () => ({
  listClusters: vi.fn(),
  listJobs: vi.fn()
}));

function mountView(mode = 'config') {
  return mount(ClusterListView, {
    props: { mode },
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
        { id: 5, name: '生产集群', status: 'installed', latest_job_id: 51 }
      ]
    });

    const wrapper = mountView('install');
    await flushPromises();

    expect(wrapper.findAll('.cluster-row')).toHaveLength(5);
    expect(wrapper.text()).toContain('配置未完成');
    expect(wrapper.text()).toContain('预检查通过');
    expect(wrapper.text()).toContain('正在安装');
    expect(wrapper.text()).toContain('安装失败');
    expect(wrapper.text()).toContain('安装成功');

    const actions = wrapper.findAllComponents(RouterLinkStub).filter((link) => link.classes('cluster-row__action'));
    expect(actions.map((link) => link.text())).toEqual([
      '查看安装状态',
      '开始安装',
      '查看进度',
      '查看失败原因',
      '查看执行记录'
    ]);
    expect(actions.map((link) => link.props('to'))).toEqual([
      { name: 'install-overview', params: { clusterId: '1' } },
      { name: 'install-overview', params: { clusterId: '2' } },
      { name: 'job-execution', params: { jobId: '31' } },
      { name: 'job-execution', params: { jobId: '41' } },
      { name: 'job-execution', params: { jobId: '51' } }
    ]);
    expect(wrapper.find('[data-testid="create-cluster"]').exists()).toBe(false);
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

    const wrapper = mountView('install');
    await flushPromises();

    const actions = wrapper.findAllComponents(RouterLinkStub)
      .filter((link) => link.classes('cluster-row__action'));
    expect(actions.map((link) => link.text())).toEqual(['查看进度', '开始安装', '查看执行记录']);
    expect(actions.map((link) => link.props('to'))).toEqual([
      { name: 'job-execution', params: { jobId: '101' } },
      { name: 'install-overview', params: { clusterId: '11' } },
      { name: 'job-execution', params: { jobId: '121' } }
    ]);
  });

  it('提供加载、空数据、错误重试和无目标任务禁用状态', async () => {
    let resolveClusters;
    listClusters.mockReturnValue(new Promise((resolve) => {
      resolveClusters = resolve;
    }));

    const wrapper = mountView('install');
    expect(wrapper.get('[aria-busy="true"]')).toBeTruthy();

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

  it('配置模块保留新建集群和配置工作区入口', async () => {
    listClusters.mockResolvedValue({ items: [{ id: 8, name: '配置中', status: 'draft' }] });
    const wrapper = mountView('config');
    await flushPromises();

    expect(wrapper.get('h1').text()).toBe('集群配置');
    expect(wrapper.getComponent('[data-testid="create-cluster"]').props('to')).toEqual({
      name: 'cluster-config-workspace',
      params: { clusterId: 'new', stage: 'cluster-info' }
    });
    const clusterLink = wrapper.findAllComponents(RouterLinkStub)
      .find((link) => link.classes('cluster-name'));
    expect(clusterLink.props('to')).toEqual({
      name: 'cluster-config-workspace',
      params: { clusterId: '8', stage: 'cluster-info' }
    });
  });
});
