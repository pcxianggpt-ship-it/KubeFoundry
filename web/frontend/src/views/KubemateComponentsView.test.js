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
  { key: 'redis_sentinel', name: 'Redis 哨兵模式', enabled: false, available: false, components: ['redis_sentinel'], status: 'not_installed', config: {} }
];

describe('KubemateComponentsView', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    listComponents.mockResolvedValue({ groups });
    updateComponents.mockResolvedValue({ groups });
  });

  it('显示六组中文信息、实际状态和不可用的 Redis 组', async () => {
    const wrapper = mount(KubemateComponentsView, {
      props: { clusterId: 42 },
      global: { plugins: [ElementPlus] }
    });
    await flushPromises();

    expect(wrapper.findAll('.component-group')).toHaveLength(6);
    expect(wrapper.text()).toContain('存储与日志套件');
    expect(wrapper.text()).toContain('OpenEBS');
    expect(wrapper.text()).toContain('已安装');
    expect(wrapper.text()).toContain('脚本待完善，当前版本不可安装。');
    expect(wrapper.get('[data-testid="group-switch-redis_sentinel"] input').attributes('disabled')).toBeDefined();
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
        expect.objectContaining({ key: 'storage_observability', enabled: true, config: {} })
      ])
    }));
    expect(updateComponents.mock.calls[0][1]).not.toHaveProperty('enabled');
    expect(wrapper.emitted('next')).toHaveLength(1);
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
