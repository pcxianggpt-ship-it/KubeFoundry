import { flushPromises, mount } from '@vue/test-utils';
import ElementPlus from 'element-plus';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import KubemateComponentsView from './KubemateComponentsView.vue';
import { listComponents, listNodes, updateComponents } from '../api/client';

vi.mock('../api/client', () => ({
  listComponents: vi.fn(),
  listNodes: vi.fn(),
  updateComponents: vi.fn()
}));

const groups = [
  { key: 'nfs', name: 'NFS 存储', enabled: false, available: true, components: ['nfs_exports'], status: 'not_installed', config: {} },
  { key: 'kubemate', name: 'Kubemate 管理组件', enabled: false, available: true, components: ['kubemate_ui'], status: 'not_installed', config: {} },
  { key: 'traefik', name: 'Traefik 网关', enabled: true, available: true, components: ['traefik'], status: 'installed', config: {} },
  { key: 'storage_observability', name: '存储与日志套件', enabled: true, available: true, components: ['minio', 'loki', 'alloy'], status: 'not_installed', config: {} },
  { key: 'prometheus', name: 'Prometheus 监控', enabled: false, available: true, components: ['prometheus'], status: 'not_installed', config: {} },
  { key: 'redis_sentinel', name: 'Redis 哨兵模式', enabled: false, available: true, components: ['redis_sentinel'], status: 'not_installed', config: {} }
];

describe('KubemateComponentsView', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    listComponents.mockResolvedValue({ groups });
    listNodes.mockResolvedValue([
      { id: 1, hostname: 'master-01', ip: '10.0.0.1', roles: ['control_plane'], is_draft: false },
      { id: 2, hostname: 'worker-01', ip: '10.0.0.2', roles: ['worker'], is_draft: false },
      { id: 3, hostname: 'draft-node', ip: '10.0.0.3', roles: ['worker'], is_draft: true }
    ]);
    updateComponents.mockResolvedValue({ groups });
  });

  it('显示六组中文信息、实际状态和可用的 Redis 组', async () => {
    const wrapper = mount(KubemateComponentsView, {
      props: { clusterId: 42 },
      global: { plugins: [ElementPlus] }
    });
    await flushPromises();

    expect(wrapper.findAll('.component-group')).toHaveLength(6);
    expect(wrapper.text()).toContain('存储与日志套件');
    expect(wrapper.text()).not.toContain('OpenEBS');
    expect(wrapper.text()).toContain('MinIO');
    expect(wrapper.text()).toContain('已安装');
    expect(wrapper.text()).not.toContain('脚本待完善，当前版本不可安装。');
    expect(wrapper.get('[data-testid="group-switch-redis_sentinel"] input').attributes('disabled')).toBeUndefined();
    expect(wrapper.get('[data-testid="group-switch-traefik"] input').attributes('disabled')).toBeDefined();
  });

  it('仅按组件组配置保存，不发送总开关', async () => {
    const wrapper = mount(KubemateComponentsView, {
      props: { clusterId: 42 },
      global: { plugins: [ElementPlus] }
    });
    await flushPromises();

    await wrapper.get('[data-testid="save-components"]').trigger('click');
    await flushPromises();

    expect(updateComponents).toHaveBeenCalledWith(42, expect.objectContaining({
      groups: expect.arrayContaining([
        expect.objectContaining({ key: 'storage_observability', enabled: true, config: expect.objectContaining({
          minio_pvc_size: '10Gi', minio_cpu_request: '250m', minio_cpu_limit: '2',
          minio_memory_request: '512Mi', minio_memory_limit: '4Gi'
        }) })
      ])
    }));
    expect(updateComponents.mock.calls[0][1]).not.toHaveProperty('enabled');
    expect(wrapper.emitted('next')).toHaveLength(1);
  });

  it('展示 MinIO 默认资源参数并阻止 request 大于 limit', async () => {
    const wrapper = mount(KubemateComponentsView, {
      props: { clusterId: 42 },
      global: { plugins: [ElementPlus] }
    });
    await flushPromises();

    expect(wrapper.get('[data-testid="minio-pvc-size"]').element.value).toBe('10Gi');
    await wrapper.get('[data-testid="minio-cpu-request"]').setValue('3');
    await wrapper.vm.$nextTick();
    expect(wrapper.get('[data-testid="save-components"]').attributes('disabled')).toBeDefined();
  });

  it('启用 NFS 后要求完整配置', async () => {
    listComponents.mockResolvedValue({ groups: groups.map((group) => (
      group.key === 'nfs' ? { ...group, enabled: true } : group
    )) });
    const wrapper = mount(KubemateComponentsView, {
      props: { clusterId: 42 },
      global: { plugins: [ElementPlus] }
    });
    await flushPromises();

    expect(wrapper.text()).toContain('启用 NFS 前，请填写完整且有效的 NFS 配置。');
    expect(wrapper.get('[data-testid="save-components"]').attributes('disabled')).toBeDefined();
  });

  async function nfsView(config = {}, props = {}) {
    listComponents.mockResolvedValue({ groups: groups.map(group => group.key === 'nfs'
      ? { ...group, enabled: true, config } : group) });
    const wrapper = mount(KubemateComponentsView, { props: { clusterId: 42, ...props }, global: { plugins: [ElementPlus] } });
    await flushPromises();
    return wrapper;
  }

  it('内部服务器仅允许选择已保存的节点，保存节点 IP 与受管模式', async () => {
    const wrapper = await nfsView();
    expect(wrapper.findAllComponents({ name: 'ElOption' }).map(option => option.props('value'))).toEqual(['10.0.0.1', '10.0.0.2']);
    wrapper.findComponent({ name: 'ElSelect' }).vm.$emit('update:modelValue', '10.0.0.2');
    await flushPromises();
    await wrapper.get('[data-testid="save-components"]').trigger('click');
    await flushPromises();
    expect(updateComponents.mock.calls[0][1].groups[0]).toEqual({ key: 'nfs', enabled: true, config: {
      server_address: '10.0.0.2', exports_mode: 'managed', share_path: '/data/k8s_install/nfs_root',
      worker_mount_path: '/data/k8s_install/nfs_root', storage_class: 'nfs-storage'
    } });
  });

  it('共享和挂载目录默认使用集群工作目录，StorageClass 有默认值', async () => {
    const wrapper = await nfsView({}, { kubernetesWorkDir: '/srv/kubernetes/' });
    expect(wrapper.get('[data-testid="nfs-share-path"]').element.value).toBe('/srv/kubernetes/nfs_root');
    expect(wrapper.get('[data-testid="nfs-mount-path"]').element.value).toBe('/srv/kubernetes/nfs_root');
    expect(wrapper.get('[data-testid="nfs-storage-class"]').element.value).toBe('nfs-storage');
  });

  it('默认值不覆盖已保存的自定义路径和 StorageClass', async () => {
    const wrapper = await nfsView({ share_path: '/exports/custom', worker_mount_path: '/mnt/custom', storage_class: 'custom-nfs' }, { kubernetesWorkDir: '/srv/kubernetes' });
    expect(wrapper.get('[data-testid="nfs-share-path"]').element.value).toBe('/exports/custom');
    expect(wrapper.get('[data-testid="nfs-mount-path"]').element.value).toBe('/mnt/custom');
    expect(wrapper.get('[data-testid="nfs-storage-class"]').element.value).toBe('custom-nfs');
  });

  it('切换外部服务器清空内部地址，输入有效 IP 后保存外部模式', async () => {
    const wrapper = await nfsView({ server_address: '10.0.0.2' });
    await wrapper.get('[data-testid="nfs-server-location"] input[value="external"]').setValue(true);
    await flushPromises();
    expect(wrapper.get('[data-testid="nfs-server-ip"]').element.value).toBe('');
    expect(wrapper.find('[data-testid="nfs-server-node"]').exists()).toBe(false);
    await wrapper.get('[data-testid="nfs-server-ip"]').setValue('10.0.0.99');
    await wrapper.get('[data-testid="save-components"]').trigger('click');
    await flushPromises();
    expect(updateComponents.mock.calls[0][1].groups[0].config).toMatchObject({ exports_mode: 'external', server_address: '10.0.0.99' });
  });

  it('外部改回内部必须重新选择节点，不能继续使用外部 IP', async () => {
    const wrapper = await nfsView({ exports_mode: 'external', server_address: '10.0.0.99' });
    await wrapper.get('[data-testid="nfs-server-location"] input[value="managed"]').setValue(true);
    await flushPromises();
    expect(wrapper.findComponent({ name: 'ElSelect' }).props('modelValue')).toBe('');
    expect(wrapper.get('[data-testid="save-components"]').attributes('disabled')).toBeDefined();
  });

  it('节点加载失败阻止内部保存，但允许有效外部配置保存', async () => {
    listNodes.mockRejectedValue(new Error('节点加载失败'));
    const wrapper = await nfsView({ server_address: '10.0.0.2' });
    expect(wrapper.text()).toContain('节点加载失败');
    expect(wrapper.get('[data-testid="save-components"]').attributes('disabled')).toBeDefined();
    await wrapper.get('[data-testid="nfs-server-location"] input[value="external"]').setValue(true);
    await wrapper.get('[data-testid="nfs-server-ip"]').setValue('10.0.0.99');
    await wrapper.get('[data-testid="save-components"]').trigger('click');
    await flushPromises();
    expect(updateComponents).toHaveBeenCalledOnce();
  });

  it('未填完就禁用 NFS 可以保存，清除未完成的配置', async () => {
    const wrapper = await nfsView();
    await wrapper.get('[data-testid="group-switch-nfs"] input').setValue(false);
    await wrapper.get('[data-testid="save-components"]').trigger('click');
    await flushPromises();
    expect(updateComponents.mock.calls[0][1].groups[0]).toEqual({ key: 'nfs', enabled: false, config: {} });
  });
});
