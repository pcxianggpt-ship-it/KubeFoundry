import { flushPromises, mount } from '@vue/test-utils';
import ElementPlus from 'element-plus';
import { ElMessageBox } from 'element-plus';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import NodeConfigView from './NodeConfigView.vue';
import { copyNodes, createNode, deleteNode, listNodes, startNodeTest, updateNode } from '../api/client';

vi.mock('../api/client', () => ({
  copyNodes: vi.fn(),
  createNode: vi.fn(),
  deleteNode: vi.fn(),
  listNodes: vi.fn(),
  startNodeTest: vi.fn(),
  updateNode: vi.fn()
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

describe('NodeConfigView', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    FakeEventSource.instances = [];
    vi.stubGlobal('EventSource', FakeEventSource);
    listNodes.mockResolvedValue({ items: [
      { id: 1, hostname: 'cp-1', ip: '10.0.0.1', roles: ['control_plane', 'registry'], ssh_user: 'root', ssh_port: 22, has_password: true, is_draft: false, node_test_status: 'pending' },
      { id: 2, hostname: 'worker-1', ip: '10.0.0.2', role: 'worker', ssh_user: 'root', ssh_port: 22, has_password: true, is_draft: false, node_test_status: 'failed', node_test_message: '连接超时' }
    ] });
  });

  it('显示密码占位、中文状态并通过SSE更新节点活动', async () => {
    startNodeTest.mockResolvedValue({ job_id: 91, status: 'pending' });
    const wrapper = mount(NodeConfigView, {
      props: { clusterId: 42 },
      global: { plugins: [ElementPlus] }
    });
    await flushPromises();

    expect(wrapper.text()).toContain('密码已保存');
    expect(wrapper.text()).toContain('控制节点、镜像仓库');
    expect(wrapper.text()).toContain('测试失败');
    await wrapper.get('[data-testid="test-all-nodes"]').trigger('click');
    await flushPromises();
    expect(startNodeTest).toHaveBeenCalledWith(42);
    expect(FakeEventSource.instances[0].url).toBe('/api/jobs/91/events');

    FakeEventSource.instances[0].emit('node.status', {
      payload: { node_id: 2, hostname: 'worker-1', status: 'key_installing', message: '正在安装公钥' }
    });
    await wrapper.vm.$nextTick();
    expect(wrapper.text()).toContain('配置免密中');
    expect(wrapper.text()).toContain('正在安装公钥');
  });

  it('复制节点保留密码状态，编辑后解除草稿且不发送空密码', async () => {
    copyNodes.mockResolvedValue({ items: [] });
    updateNode.mockResolvedValue({});
    const wrapper = mount(NodeConfigView, {
      props: { clusterId: 42 },
      global: { plugins: [ElementPlus] }
    });
    await flushPromises();

    await wrapper.get('[data-testid="select-node-1"] input').setValue(true);
    await wrapper.get('[data-testid="copy-selected-nodes"]').trigger('click');
    await flushPromises();
    expect(copyNodes).toHaveBeenCalledWith(42, [1]);

    await wrapper.get('[data-testid="edit-node-2"]').trigger('click');
    await wrapper.get('[data-testid="save-node"]').trigger('click');
    await flushPromises();
    expect(updateNode).toHaveBeenCalledWith(2, expect.not.objectContaining({ password: expect.anything() }));
  });

  it('失败节点提供原因和重试入口', async () => {
    startNodeTest.mockResolvedValue({ job_id: 92, status: 'pending' });
    const wrapper = mount(NodeConfigView, {
      props: { clusterId: 42 },
      global: { plugins: [ElementPlus] }
    });
    await flushPromises();

    expect(wrapper.text()).toContain('连接超时');
    expect(wrapper.get('[data-testid="retry-failed-nodes"]')).toBeTruthy();
    expect(wrapper.get('[data-testid="edit-node-2"]')).toBeTruthy();
    await wrapper.get('[data-testid="retry-failed-nodes"]').trigger('click');
    await flushPromises();
    expect(startNodeTest).toHaveBeenCalledWith(42);
  });

  it('新增节点并确认删除节点', async () => {
    createNode.mockResolvedValue({});
    deleteNode.mockResolvedValue();
    vi.spyOn(ElMessageBox, 'confirm').mockResolvedValue('confirm');
    const wrapper = mount(NodeConfigView, {
      props: { clusterId: 42 },
      global: { plugins: [ElementPlus] }
    });
    await flushPromises();

    await wrapper.get('[data-testid="add-node"]').trigger('click');
    await wrapper.get('[data-testid="node-hostname"]').setValue('worker-2');
    await wrapper.get('[data-testid="node-ip"]').setValue('10.0.0.3');
    await wrapper.get('[data-testid="node-password"]').setValue('test-only-value');
    await wrapper.get('[data-testid="save-node"]').trigger('click');
    await flushPromises();
    expect(createNode).toHaveBeenCalledWith(42, expect.objectContaining({
      hostname: 'worker-2',
      ip: '10.0.0.3'
    }));

    await wrapper.get('[data-testid="delete-node-1"]').trigger('click');
    await flushPromises();
    expect(deleteNode).toHaveBeenCalledWith(1);
  });
});
