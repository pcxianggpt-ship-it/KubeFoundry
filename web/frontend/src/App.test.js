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
  getJobSteps,
  getSettings,
  listClusters,
  listNodes,
  startInstall,
  startPrecheck,
  updateCluster,
  updateClusterSettings,
  upsertSshCredentials
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
  startInstall: vi.fn(),
  startPrecheck: vi.fn(),
  updateCluster: vi.fn(),
  updateClusterSettings: vi.fn(),
  updateNode: vi.fn(),
  upsertSshCredentials: vi.fn()
}));


function mountApp() {
  return mount(App, {
    global: {
      plugins: [ElementPlus]
    }
  });
}


describe('Web wizard', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.stubGlobal('EventSource', class {
      addEventListener() {}
      close() {}
    });
    listClusters.mockResolvedValue({ items: [] });
    getInstallPlan.mockResolvedValue({ items: [] });
    getSettings.mockResolvedValue({});
    getClusterSettings.mockResolvedValue({});
    listNodes.mockResolvedValue({ items: [] });
    getClusterConfigYaml.mockResolvedValue('');
    upsertSshCredentials.mockResolvedValue({});
    updateClusterSettings.mockResolvedValue({});
  });

  it('marks ecosystem components as unavailable in v0.1.0', async () => {
    const wrapper = mountApp();
    await flushPromises();

    expect(wrapper.text()).toContain('v0.2.0');
    const switches = wrapper.findAll('.component-row .el-switch');
    expect(switches.length).toBeGreaterThan(0);
    expect(switches.every((item) => item.classes().includes('is-disabled'))).toBe(true);
  });

  it('creates a cluster, adds a node, and starts precheck', async () => {
    const wrapper = mountApp();
    await flushPromises();
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
      ssh_user: 'root',
      ssh_port: 22
    });
    await wrapper.vm.saveNode();
    await wrapper.vm.runPrecheck();
    await flushPromises();

    expect(createCluster).toHaveBeenCalled();
    expect(upsertSshCredentials).toHaveBeenCalledWith(
      7,
      expect.objectContaining({ auth_type: 'key' })
    );
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
    expect(wrapper.vm.activeStep).toBe(8);
    expect(getJob).toHaveBeenCalledWith(42);
  });
});
