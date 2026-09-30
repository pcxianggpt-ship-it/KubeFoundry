import { flushPromises, mount } from '@vue/test-utils';
import ElementPlus from 'element-plus';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import KubemateComponentsView from './KubemateComponentsView.vue';
import { listComponents, updateComponents } from '../api/client';

vi.mock('../api/client', () => ({
  listComponents: vi.fn(),
  updateComponents: vi.fn()
}));

const groups = [
  { key: 'nfs', name: 'NFS 存储', enabled: false, available: true, components: ['nfs_exports'], status: 'not_installed', config: {} },
  { key: 'kubemate', name: 'Kubemate 管理组件', enabled: false, available: true, components: ['kubemate_ui'], status: 'not_installed', config: {} },
  { key: 'traefik', name: 'Traefik 网关', enabled: true, available: true, components: ['traefik'], status: 'installed', config: {} },
  { key: 'storage_observability', name: '存储与日志套件', enabled: true, available: true, components: ['openebs', 'minio', 'loki', 'alloy'], status: 'not_installed', config: {} },
  { key: 'prometheus', name: 'Prometheus 监控', enabled: false, available: true, components: ['prometheus'], status: 'not_installed', config: {} },
  { key: 'redis_sentinel', name: 'Redis 哨兵模式', enabled: false, available: true, components: ['redis_sentinel'], status: 'not_installed', config: {} }
];

describe('KubemateComponentsView', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    listComponents.mockResolvedValue({ groups });
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
    expect(wrapper.text()).toContain('OpenEBS');
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
});
