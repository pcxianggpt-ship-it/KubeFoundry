import { flushPromises, mount } from '@vue/test-utils';
import ElementPlus from 'element-plus';
import { createMemoryHistory } from 'vue-router';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import PrecheckView from './PrecheckView.vue';
import InstallConfirmView from './InstallConfirmView.vue';
import InstallOverviewView from './InstallOverviewView.vue';
import JobExecutionView from './JobExecutionView.vue';
import { createAppRouter } from '../router';
import {
  getCluster,
  getClusterSettings,
  getClusterJob,
  getJob,
  getJobLogs,
  getJobSteps,
  getPrecheckResults,
  listJobs,
  listNodes,
  resumeInstallJob,
  startComponentInstall,
  startInstall,
  startPrecheck
} from '../api/client';

vi.mock('../api/client', () => ({
  getCluster: vi.fn(),
  getClusterSettings: vi.fn(),
  getClusterJob: vi.fn(),
  getJob: vi.fn(),
  getJobLogs: vi.fn(),
  getJobSteps: vi.fn(),
  getPrecheckResults: vi.fn(),
  listJobs: vi.fn(),
  listNodes: vi.fn(),
  resumeInstallJob: vi.fn(),
  startComponentInstall: vi.fn(),
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
    getClusterJob.mockImplementation((_clusterId, jobId) => getJob(jobId));
  });

  it('预检查全部成功后进入安装确认，但不自动开始安装', async () => {
    startPrecheck.mockResolvedValue({ job_id: 81, status: 'pending' });
    const { router, wrapper } = await mountAt(PrecheckView, '/cluster-install/42/precheck', { clusterId: 42 });

    await wrapper.get('[data-testid="start-precheck"]').trigger('click');
    await flushPromises();
    expect(FakeEventSource.instances[0].url).toBe('/api/jobs/81/events');

    FakeEventSource.instances[0].emit('job.status', { payload: { status: 'success' } });
    await flushPromises();

    expect(getPrecheckResults).toHaveBeenCalledWith(81);
    expect(router.currentRoute.value.fullPath).toBe('/cluster-install/42/confirm');
    expect(startInstall).not.toHaveBeenCalled();
  });

  it('安装概览从开始安装入口进入预检查页', async () => {
    getCluster.mockResolvedValue({ id: 42, name: '生产集群', status: 'draft', configuration_locked: false });
    listJobs.mockResolvedValue({ items: [] });
    const { router, wrapper } = await mountAt(InstallOverviewView, '/cluster-install/42/overview');

    await wrapper.get('[data-testid="start-install-from-overview"]').trigger('click');
    await flushPromises();

    expect(router.currentRoute.value.fullPath).toBe('/cluster-install/42/precheck');
  });

  it('安装概览在集群锁定时提供重置入口', async () => {
    getCluster.mockResolvedValue({ id: 42, name: '生产集群', status: 'installed', configuration_locked: true });
    listJobs.mockResolvedValue({ items: [] });
    const { router, wrapper } = await mountAt(InstallOverviewView, '/cluster-install/42/overview');

    expect(wrapper.get('[data-testid="start-install-from-overview"]').attributes('disabled')).toBeDefined();
    await wrapper.get('[data-testid="reset-cluster-from-overview"]').trigger('click');
    await flushPromises();

    expect(router.currentRoute.value.fullPath).toBe('/cluster-install/42/reset');
  });

  it('初次安装失败但配置仍锁定时提供重置入口', async () => {
    getCluster.mockResolvedValue({ id: 42, name: '生产集群', status: 'install_failed', configuration_locked: true });
    listJobs.mockResolvedValue({ items: [{ id: 88, cluster_id: 42, job_type: 'install', status: 'failed' }] });
    const { router, wrapper } = await mountAt(InstallOverviewView, '/cluster-install/42/overview');

    expect(wrapper.get('[data-testid="reset-cluster-from-overview"]').attributes('disabled')).toBeUndefined();
    await wrapper.get('[data-testid="reset-cluster-from-overview"]').trigger('click');
    await flushPromises();

    expect(router.currentRoute.value.fullPath).toBe('/cluster-install/42/reset');
  });

  it('存量集群可从安装概览启动组件补装任务', async () => {
    getCluster.mockResolvedValue({ id: 42, name: '生产集群', status: 'installed', configuration_locked: true });
    listJobs.mockResolvedValue({ items: [] });
    startComponentInstall.mockResolvedValue({ job_id: 123, status: 'pending' });
    const { router, wrapper } = await mountAt(InstallOverviewView, '/cluster-install/42/overview');

    await wrapper.get('[data-testid="start-component-install"]').trigger('click');
    await flushPromises();

    expect(startComponentInstall).toHaveBeenCalledWith('42');
    expect(router.currentRoute.value.fullPath).toBe('/cluster-install/42/jobs/123');
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
    expect(router.currentRoute.value.fullPath).toBe('/cluster-install/42/jobs/99');
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

    const { wrapper } = await mountAt(JobExecutionView, '/cluster-install/42/jobs/99');

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
    const { wrapper } = await mountAt(JobExecutionView, '/cluster-install/42/jobs/100');

    await wrapper.get('[data-testid="locate-failure"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-testid="job-stage-20"]').classes()).toContain('is-selected');
    expect(wrapper.get('[data-testid="job-node-201"]').classes()).toContain('is-selected');
    expect(wrapper.text()).toContain('软件包校验失败');
  });

  it('失败安装仅提交一次续跑请求并跳转到新任务', async () => {
    getJob.mockResolvedValue({ id: 100, cluster_id: 42, job_type: 'install', status: 'failed', run_mode: 'normal' });
    getCluster.mockResolvedValue({ id: 42, name: '生产集群', k8s_version: '1.30.14' });
    getJobSteps.mockResolvedValue({ items: [] });
    getJobLogs.mockResolvedValue({ items: [] });
    let acceptResume;
    resumeInstallJob.mockReturnValue(new Promise((resolve) => { acceptResume = resolve; }));
    const { router, wrapper } = await mountAt(JobExecutionView, '/cluster-install/42/jobs/100');

    const button = wrapper.get('[data-testid="resume-install-job"]');
    await button.trigger('click');
    await button.trigger('click');
    expect(resumeInstallJob).toHaveBeenCalledTimes(1);
    expect(resumeInstallJob).toHaveBeenCalledWith(42, 100);

    acceptResume({ job_id: 101, source_job_id: 100, run_mode: 'resume' });
    await flushPromises();
    expect(router.currentRoute.value.fullPath).toBe('/cluster-install/42/jobs/101');
  });

  it('续跑失败时停留在来源任务并显示安全错误', async () => {
    getJob.mockResolvedValue({ id: 100, cluster_id: 42, job_type: 'component_install', status: 'partial_success' });
    getCluster.mockResolvedValue({ id: 42, name: '生产集群' });
    getJobSteps.mockResolvedValue({ items: [] });
    getJobLogs.mockResolvedValue({ items: [] });
    resumeInstallJob.mockRejectedValue(new Error('来源快照不匹配'));
    const { router, wrapper } = await mountAt(JobExecutionView, '/cluster-install/42/jobs/100');

    await wrapper.get('[data-testid="resume-install-job"]').trigger('click');
    await flushPromises();

    expect(router.currentRoute.value.fullPath).toBe('/cluster-install/42/jobs/100');
    expect(wrapper.get('[data-testid="resume-error"]').text()).toContain('来源快照不匹配');
  });

  it('成功任务不提供续跑入口，续跑任务可返回来源任务', async () => {
    getJob.mockResolvedValue({
      id: 101, cluster_id: 42, job_type: 'install', status: 'success',
      run_mode: 'resume', source_job_id: 100
    });
    getCluster.mockResolvedValue({ id: 42, name: '生产集群' });
    getJobSteps.mockResolvedValue({ items: [] });
    getJobLogs.mockResolvedValue({ items: [] });
    const { wrapper } = await mountAt(JobExecutionView, '/cluster-install/42/jobs/101');

    expect(wrapper.find('[data-testid="resume-install-job"]').exists()).toBe(false);
    expect(wrapper.text()).toContain('此任务由任务 #100 续跑创建');
    expect(wrapper.get('.job-lineage a').attributes('href')).toBe('/cluster-install/42/jobs/100');
  });

  it('区分前置验证跳过和依赖跳过，并显示安全阶段消息', async () => {
    getJob.mockResolvedValue({ id: 102, cluster_id: 42, job_type: 'install', status: 'failed' });
    getCluster.mockResolvedValue({ id: 42, name: '生产集群' });
    getJobSteps.mockResolvedValue({ items: [
      { id: 10, name: '镜像仓库', order: 1, status: 'skipped', status_reason: 'PREVERIFY_SATISFIED', nodes: [
        { id: 100, node_id: 1, hostname: 'cp-1', status: 'skipped', message: 'PREVERIFY_SATISFIED' }
      ] },
      { id: 20, name: '工作节点加入', order: 2, status: 'skipped', status_reason: 'JOB_ABORTED', nodes: [] }
    ] });
    getJobLogs.mockResolvedValue({ items: [] });
    const { wrapper } = await mountAt(JobExecutionView, '/cluster-install/42/jobs/102');

    expect(wrapper.text()).toContain('已验证并跳过');
    expect(wrapper.text()).toContain('执行前验证通过，已安全跳过安装');
    expect(wrapper.text()).toContain('因依赖跳过');
  });

  it('任务切换后忽略旧任务迟到的 SSE 事件', async () => {
    getJob.mockImplementation(async (jobId) => ({
      id: Number(jobId), cluster_id: 42, job_type: 'install', status: 'running'
    }));
    getCluster.mockResolvedValue({ id: 42, name: '生产集群' });
    getJobSteps.mockResolvedValue({ items: [{
      id: 10, name: '安装依赖', order: 1, status: 'running',
      nodes: [{ id: 100, node_id: 1, hostname: 'cp-1', status: 'running', message: '执行中' }]
    }] });
    getJobLogs.mockResolvedValue({ items: [] });
    const { router, wrapper } = await mountAt(JobExecutionView, '/cluster-install/42/jobs/103');
    const oldStream = FakeEventSource.instances[0];

    await router.push('/cluster-install/42/jobs/104');
    await flushPromises();
    oldStream.emit('node.status', { payload: { node_id: 1, status: 'failed', message: '旧任务迟到事件' } });
    await flushPromises();

    expect(wrapper.text()).not.toContain('旧任务迟到事件');
    expect(wrapper.text()).toContain('执行中');
  });

  it('旧任务地址加载任务后重定向到包含集群 ID 的规范地址', async () => {
    getJob.mockResolvedValue({ id: 101, cluster_id: 42, job_type: 'install', status: 'success' });
    const { router } = await mountAt(JobExecutionView, '/jobs/101/execution');

    expect(router.currentRoute.value.fullPath).toBe('/cluster-install/42/jobs/101');
  });
});
