import { flushPromises, mount } from '@vue/test-utils';
import ElementPlus, { ElMessageBox } from 'element-plus';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import App from './App.vue';
import {
  createCluster,
  createNode,
  getCluster,
  getClusterConfigYaml,
  getClusterSettings,
  getInstallPlan,
  getJob,
  getJobStepNodeLog,
  getJobSteps,
  getPrecheckResults,
  getSettings,
  listClusters,
  listJobs,
  listNodes,
  startInstall,
  startNodeTest,
  startPrecheck,
  updateCluster,
  updateClusterSettings,
  updateNode,
  copyNodes
} from './api/client';


vi.mock('./api/client', () => ({
  createCluster: vi.fn(),
  createNode: vi.fn(),
  deleteNode: vi.fn(),
  getCluster: vi.fn(),
  getClusterConfigYaml: vi.fn(),
  getClusterSettings: vi.fn(),
  getInstallPlan: vi.fn(),
  getJob: vi.fn(),
  getJobStepNodeLog: vi.fn(),
  getJobSteps: vi.fn(),
  getPrecheckResults: vi.fn(),
  getSettings: vi.fn(),
  importClusterYaml: vi.fn(),
  listClusters: vi.fn(),
  listJobs: vi.fn(),
  listNodes: vi.fn(),
  copyNodes: vi.fn(),
  startInstall: vi.fn(),
  startNodeTest: vi.fn(),
  startPrecheck: vi.fn(),
  updateCluster: vi.fn(),
  updateClusterSettings: vi.fn(),
  updateNode: vi.fn()
}));


function mountApp() {
  return mount(App, {
    global: {
      plugins: [ElementPlus]
    }
  });
}


describe('Web wizard', () => {
  let eventSources;

  beforeEach(() => {
    vi.clearAllMocks();
    eventSources = [];
    vi.stubGlobal('EventSource', class {
      constructor(url) {
        this.url = url;
        this.listeners = {};
        eventSources.push(this);
      }
      addEventListener(name, handler) {
        this.listeners[name] = handler;
      }
      close() {
        this.closed = true;
      }
    });
    listClusters.mockResolvedValue({ items: [] });
    getInstallPlan.mockResolvedValue({ items: [] });
    getSettings.mockResolvedValue({});
    getClusterSettings.mockResolvedValue({});
    listNodes.mockResolvedValue({ items: [] });
    getClusterConfigYaml.mockResolvedValue('');
    updateClusterSettings.mockResolvedValue({});
    copyNodes.mockResolvedValue({ items: [] });
    startNodeTest.mockResolvedValue({ job_id: 22, status: 'pending' });
  });

  it('marks ecosystem components as unavailable in v0.1.0', async () => {
    const wrapper = mountApp();
    await flushPromises();

    expect(wrapper.text()).toContain('v0.2.0');
    const switches = wrapper.findAll('.component-row .el-switch');
    expect(switches.length).toBeGreaterThan(0);
    expect(switches.every((item) => item.classes().includes('is-disabled'))).toBe(true);
  });

  it('shows install targets and execution modes in Chinese', async () => {
    getInstallPlan.mockResolvedValue({
      items: [
        {
          order: 1,
          name: '替换 kubeadm',
          target_scope: 'primary_control_plane',
          mode: 'serial'
        },
        {
          order: 2,
          name: '添加工作节点',
          target_scope: 'workers',
          mode: 'parallel'
        }
      ]
    });

    const wrapper = mountApp();
    await flushPromises();

    expect(wrapper.text()).toContain('主控制节点');
    expect(wrapper.text()).toContain('工作节点');
    expect(wrapper.text()).toContain('串行');
    expect(wrapper.text()).toContain('并行');
  });

  it('hides install mode and ssh step, then shows node login and test controls', async () => {
    const wrapper = mountApp();
    await flushPromises();

    expect(wrapper.text()).not.toContain('安装模式');
    expect(wrapper.text()).not.toContain('SSH 配置');
    expect(wrapper.text()).not.toContain('私钥路径');
    expect(wrapper.text()).toContain('SSH 用户');
    expect(wrapper.text()).toContain('SSH 端口');
    expect(wrapper.text()).toContain('测试全部节点');
    expect(wrapper.text()).toContain('复制所选');
  });

  it('creates a cluster, adds a node, and starts precheck', async () => {
    const wrapper = mountApp();
    await flushPromises();
    expect(wrapper.text()).not.toContain('API Server 端口');
    expect(wrapper.vm.clusterForm).not.toHaveProperty('api_server_port');
    createCluster.mockResolvedValue({ id: 7, name: 'k8s-cluster' });
    createNode.mockResolvedValue({
      id: 9,
      cluster_id: 7,
      hostname: 'worker-1',
      ip: '10.0.0.11',
      role: 'worker'
    });
    listNodes.mockResolvedValue({
      items: [{
        id: 9,
        cluster_id: 7,
        hostname: 'worker-1',
        ip: '10.0.0.11',
        role: 'worker'
      }]
    });
    updateCluster.mockResolvedValue({ id: 7, name: 'k8s-cluster' });
    startPrecheck.mockResolvedValue({
      id: 21,
      cluster_id: 7,
      job_type: 'precheck',
      status: 'pending'
    });
    getJob.mockResolvedValue({
      id: 21,
      cluster_id: 7,
      job_type: 'precheck',
      status: 'running'
    });
    getJobSteps.mockResolvedValue({ items: [] });

    await wrapper.vm.saveCluster();
    wrapper.vm.openNodeDialog();
    await flushPromises();
    Object.assign(wrapper.vm.nodeForm, {
      hostname: 'worker-1',
      ip: '10.0.0.11',
      role: 'worker',
      password: 'Secret123!'
    });
    await wrapper.vm.saveNode();
    await wrapper.vm.runPrecheck();
    await flushPromises();

    expect(createCluster).toHaveBeenCalled();
    expect(createCluster.mock.calls[0][0]).not.toHaveProperty('api_server_port');
    expect(createCluster.mock.calls[0][0]).not.toHaveProperty('install_mode');
    expect(updateClusterSettings).toHaveBeenCalledWith(
      7,
      expect.objectContaining({ paths: expect.any(Object) })
    );
    expect(createNode).toHaveBeenCalledWith(
      7,
      expect.objectContaining({ hostname: 'worker-1' })
    );
    expect(startPrecheck).toHaveBeenCalledWith(7);
    expect(wrapper.vm.manualJobId).toBe(21);
  });

  it('reuses an existing cluster with the same name when saving', async () => {
    listClusters.mockResolvedValue({
      items: [{ id: 7, name: 'k8s-cluster' }]
    });
    updateCluster.mockResolvedValue({ id: 7, name: 'k8s-cluster' });

    const wrapper = mountApp();
    await flushPromises();

    await wrapper.vm.saveCluster();
    await flushPromises();

    expect(createCluster).not.toHaveBeenCalled();
    expect(updateCluster).toHaveBeenCalledWith(
      7,
      expect.objectContaining({ name: 'k8s-cluster' })
    );
    expect(wrapper.vm.selectedClusterId).toBe(7);
    expect(updateClusterSettings).toHaveBeenCalledWith(
      7,
      expect.objectContaining({ paths: expect.any(Object) })
    );
  });

  it('edits a copied node as formal and keeps saved password without sending an empty password', async () => {
    updateNode.mockResolvedValue({
      id: 9,
      hostname: 'worker-2',
      ip: '10.0.0.12',
      role: 'worker',
      ssh_user: 'admin',
      ssh_port: 2222,
      has_password: true,
      is_draft: false
    });
    const wrapper = mountApp();
    await flushPromises();

    wrapper.vm.selectedClusterId = 7;
    wrapper.vm.openNodeDialog({
      id: 9,
      hostname: 'worker-1',
      ip: '10.0.0.11',
      role: 'worker',
      ssh_user: 'admin',
      ssh_port: 2222,
      has_password: true,
      is_draft: true
    });
    await flushPromises();

    expect(wrapper.vm.nodePasswordPlaceholder).toContain('已保存');
    wrapper.vm.nodeForm.hostname = 'worker-2';
    wrapper.vm.nodeForm.ip = '10.0.0.12';
    await wrapper.vm.saveNode();

    expect(updateNode).toHaveBeenCalledWith(
      9,
      expect.objectContaining({
        hostname: 'worker-2',
        ip: '10.0.0.12',
        ssh_user: 'admin',
        ssh_port: 2222,
        is_draft: false
      })
    );
    expect(updateNode.mock.calls[0][1]).not.toHaveProperty('password');
  });

  it('drops a legacy API Server port returned by the backend', async () => {
    const wrapper = mountApp();
    await flushPromises();
    getCluster.mockResolvedValue({
      id: 7,
      name: 'legacy',
      api_server_port: 7443
    });

    wrapper.vm.selectedClusterId = 7;
    await wrapper.vm.handleClusterChange(7);

    expect(wrapper.vm.clusterForm).not.toHaveProperty('api_server_port');
  });

  it('binds the existing install job when the backend returns 409', async () => {
    const wrapper = mountApp();
    await flushPromises();
    wrapper.vm.selectedClusterId = 7;
    updateCluster.mockResolvedValue({ id: 7, name: 'k8s-cluster' });
    getCluster.mockResolvedValue({ id: 7, name: 'k8s-cluster' });
    getJob.mockResolvedValue({
      id: 42,
      cluster_id: 7,
      job_type: 'install',
      status: 'running'
    });
    getJobSteps.mockResolvedValue({ items: [] });
    const conflict = new Error('cluster already has an active install job');
    conflict.status = 409;
    conflict.jobId = 42;
    startInstall.mockRejectedValue(conflict);
    vi.spyOn(ElMessageBox, 'confirm').mockResolvedValue('confirm');

    await wrapper.vm.runInstall();
    await flushPromises();

    expect(wrapper.vm.manualJobId).toBe(42);
    expect(wrapper.vm.activeStep).toBe(7);
    expect(getJob).toHaveBeenCalledWith(42);
  });

  it('opens task history and restores a completed precheck job', async () => {
    const wrapper = mountApp();
    await flushPromises();
    wrapper.vm.selectedClusterId = 7;
    const job = {
      id: 31,
      cluster_id: 7,
      job_type: 'precheck',
      status: 'success'
    };
    listJobs.mockResolvedValue({ items: [job] });
    getJob.mockResolvedValue(job);
    getJobSteps.mockResolvedValue({
      items: [{
        id: 4,
        step_key: 'web-precheck-node-env',
        status: 'success',
        nodes: []
      }]
    });
    getPrecheckResults.mockResolvedValue({
      items: [{
        hostname: 'k8sc1',
        check_name: 'SSH 连通性',
        status: 'pass',
        message: 'SSH 连接成功'
      }]
    });

    await wrapper.vm.openJobHistory();
    expect(wrapper.vm.jobHistoryDialogVisible).toBe(true);
    expect(wrapper.vm.jobs).toEqual([job]);

    await wrapper.vm.bindHistoryJob(job);
    await flushPromises();

    expect(wrapper.vm.activeStep).toBe(4);
    expect(wrapper.vm.manualJobId).toBe(31);
    expect(wrapper.vm.precheckResults).toHaveLength(1);
    expect(eventSources).toHaveLength(0);
  });

  it('opens a node log from the step status panel', async () => {
    const wrapper = mountApp();
    await flushPromises();
    getJobStepNodeLog.mockResolvedValue({
      item: {
        id: 18,
        step_key: '16-install-containerd',
        hostname: 'k8sw1'
      },
      content: 'containerd installation completed'
    });

    await wrapper.vm.loadNodeLog({ id: 18, hostname: 'k8sw1' });
    await flushPromises();

    expect(getJobStepNodeLog).toHaveBeenCalledWith(18);
    expect(wrapper.vm.nodeLogDialogVisible).toBe(true);
    expect(wrapper.vm.nodeLogTitle).toContain('16-install-containerd');
    expect(wrapper.vm.nodeLogContent).toContain('installation completed');
  });

  it('connects SSE events, refreshes state, and closes on terminal status', async () => {
    vi.useFakeTimers();
    const wrapper = mountApp();
    await flushPromises();
    wrapper.vm.manualJobId = 44;
    getJob.mockResolvedValue({
      id: 44,
      job_type: 'install',
      status: 'success'
    });
    getJobSteps.mockResolvedValue({ items: [] });

    wrapper.vm.connectEvents();
    expect(eventSources).toHaveLength(1);
    expect(eventSources[0].url).toBe('/api/jobs/44/events');

    eventSources[0].listeners['step.status']({
      data: JSON.stringify({ payload: { status: 'running' } })
    });
    await vi.advanceTimersByTimeAsync(500);
    expect(getJob).toHaveBeenCalledWith(44);

    eventSources[0].listeners['job.status']({
      data: JSON.stringify({ payload: { status: 'success' } })
    });
    await vi.advanceTimersByTimeAsync(800);
    expect(eventSources[0].closed).toBe(true);
    expect(wrapper.vm.eventConnected).toBe(false);
    vi.useRealTimers();
  });
});
