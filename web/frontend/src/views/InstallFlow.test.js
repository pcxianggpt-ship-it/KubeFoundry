import { flushPromises, mount } from '@vue/test-utils';
import ElementPlus from 'element-plus';
import { createMemoryHistory } from 'vue-router';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import PrecheckView from './PrecheckView.vue';
import InstallConfirmView from './InstallConfirmView.vue';
import JobExecutionView from './JobExecutionView.vue';
import { createAppRouter } from '../router';
import {
  getCluster,
  getClusterSettings,
  getJob,
  getJobLogs,
  getJobSteps,
  getPrecheckResults,
  listJobs,
  listNodes,
  startInstall,
  startPrecheck
} from '../api/client';

vi.mock('../api/client', () => ({
  getCluster: vi.fn(),
  getClusterSettings: vi.fn(),
  getJob: vi.fn(),
  getJobLogs: vi.fn(),
  getJobSteps: vi.fn(),
  getPrecheckResults: vi.fn(),
  listJobs: vi.fn(),
  listNodes: vi.fn(),
  startInstall: vi.fn(),
  startPrecheck: vi.fn()
}));

class FakeEventSource {
  static instances = [];
  constructor(url) {
    this.url = url;
    this.listeners = new Map();
    FakeEventSource.instances.push(this);
  }
  addEventListener(name, listener) { this.listeners.set(name, listener); }
  emit(name, payload) { this.listeners.get(name)?.({ data: JSON.stringify(payload) }); }
  close() { this.closed = true; }
}

async function mountAt(component, path, props = {}) {
  const router = createAppRouter(createMemoryHistory());
  await router.push(path);
  await router.isReady();
  const wrapper = mount(component, {
    props,
    global: { plugins: [ElementPlus, router] }
  });
  await flushPromises();
  return { router, wrapper };
}

describe('安装流程', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    FakeEventSource.instances = [];
    vi.stubGlobal('EventSource', FakeEventSource);
    listJobs.mockResolvedValue({ items: [] });
    getPrecheckResults.mockResolvedValue({ items: [
      { id: 1, hostname: 'cp-1', check_name: '操作系统', severity: 'error', status: 'success', message: '通过' }
    ] });
  });

  it('预检查全部成功后进入安装概览，但不自动开始安装', async () => {
    startPrecheck.mockResolvedValue({ job_id: 81, status: 'pending' });
    const { router, wrapper } = await mountAt(PrecheckView, '/cluster-install/42/precheck', { clusterId: 42 });

    await wrapper.get('[data-testid="start-precheck"]').trigger('click');
    await flushPromises();
    expect(FakeEventSource.instances[0].url).toBe('/api/jobs/81/events');

    FakeEventSource.instances[0].emit('job.status', { payload: { status: 'success' } });
    await flushPromises();

    expect(getPrecheckResults).toHaveBeenCalledWith(81);
    expect(router.currentRoute.value.fullPath).toBe('/cluster-install/42/overview');
    expect(startInstall).not.toHaveBeenCalled();
  });

  it('确认页展示目标信息，只有点击开始安装才创建任务并跳转', async () => {
    getCluster.mockResolvedValue({ id: 42, name: '生产集群', k8s_version: '1.30.14', kubernetes_work_dir: '/data/k8s_install' });
    listNodes.mockResolvedValue({ items: [
      { id: 1, hostname: 'cp-1', ip: '10.0.0.1', roles: ['control_plane', 'registry'], node_test_status: 'success' },
      { id: 2, hostname: 'worker-1', ip: '10.0.0.2', roles: ['worker'], node_test_status: 'success' }
    ] });
    getClusterSettings.mockResolvedValue({ paths: { install_media: '/opt/kf/media' }, advanced: { max_parallel_nodes: 2 } });
    listJobs.mockResolvedValue({ items: [{ id: 80, cluster_id: 42, job_type: 'precheck', status: 'success' }] });
    startInstall.mockResolvedValue({ job_id: 99, status: 'pending' });

    const { router, wrapper } = await mountAt(InstallConfirmView, '/cluster-install/42/confirm');

    expect(wrapper.text()).toContain('生产集群');
    expect(wrapper.text()).toContain('1.30.14');
    expect(wrapper.text()).toContain('2 个节点');
    expect(startInstall).not.toHaveBeenCalled();

    await wrapper.get('[data-testid="confirm-install-risk"] input').setValue(true);
    await wrapper.get('[data-testid="start-install"]').trigger('click');
    await flushPromises();
    expect(startInstall).toHaveBeenCalledWith('42');
    expect(router.currentRoute.value.fullPath).toBe('/jobs/99/execution');
  });

  it('执行页刷新时先恢复任务快照，再订阅实时事件', async () => {
    const order = [];
    getJob.mockImplementation(async () => { order.push('job'); return { id: 99, cluster_id: 42, job_type: 'install', status: 'running' }; });
    getCluster.mockImplementation(async () => { order.push('cluster'); return { id: 42, name: '生产集群', k8s_version: '1.30.14' }; });
    getJobSteps.mockImplementation(async () => { order.push('steps'); return { items: [
      { id: 10, name: '安装 containerd', order: 1, status: 'running', nodes: [{ id: 100, node_id: 1, hostname: 'cp-1', status: 'running', message: '正在安装' }] }
    ] }; });
    getJobLogs.mockImplementation(async () => { order.push('logs'); return { items: [{ id: 1, message: '任务已启动', created_at: '2026-07-15 15:00:00' }] }; });
    const OriginalEventSource = globalThis.EventSource;
    vi.stubGlobal('EventSource', class extends OriginalEventSource {
      constructor(url) { order.push('sse'); super(url); }
    });

    const { wrapper } = await mountAt(JobExecutionView, '/jobs/99/execution');

    expect(order.slice(0, 4).sort()).toEqual(['cluster', 'job', 'logs', 'steps']);
    expect(order[4]).toBe('sse');
    expect(wrapper.text()).toContain('安装 containerd');
    expect(wrapper.text()).toContain('cp-1');
    expect(wrapper.text()).toContain('任务已启动');
    expect(FakeEventSource.instances[0].url).toBe('/api/jobs/99/events');

    FakeEventSource.instances[0].emit('node.status', { payload: { node_id: 1, hostname: 'cp-1', status: 'success', message: 'containerd 安装完成' } });
    await flushPromises();
    expect(wrapper.text()).toContain('containerd 安装完成');

    await wrapper.get('[data-testid="refresh-job-snapshot"]').trigger('click');
    await flushPromises();
    expect(FakeEventSource.instances).toHaveLength(2);
  });

  it('安装失败时可以定位首个失败阶段和节点', async () => {
    getJob.mockResolvedValue({ id: 100, cluster_id: 42, job_type: 'install', status: 'failed' });
    getCluster.mockResolvedValue({ id: 42, name: '生产集群', k8s_version: '1.30.14' });
    getJobSteps.mockResolvedValue({ items: [
      { id: 10, name: '安装依赖', order: 1, status: 'success', nodes: [{ id: 101, node_id: 1, hostname: 'cp-1', status: 'success' }] },
      { id: 20, name: '安装 containerd', order: 2, status: 'failed', nodes: [{ id: 201, node_id: 2, hostname: 'worker-1', status: 'failed', message: '软件包校验失败' }] }
    ] });
    getJobLogs.mockResolvedValue({ items: [] });
    const { wrapper } = await mountAt(JobExecutionView, '/jobs/100/execution');

    await wrapper.get('[data-testid="locate-failure"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-testid="job-stage-20"]').classes()).toContain('is-selected');
    expect(wrapper.get('[data-testid="job-node-201"]').classes()).toContain('is-selected');
    expect(wrapper.text()).toContain('软件包校验失败');
  });
});
