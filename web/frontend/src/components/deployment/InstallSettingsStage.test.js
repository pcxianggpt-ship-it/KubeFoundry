import { flushPromises, mount } from '@vue/test-utils';
import ElementPlus from 'element-plus';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import InstallSettingsStage from './InstallSettingsStage.vue';
import { getClusterSettings, updateClusterSettings } from '../../api/client';

vi.mock('../../api/client', () => ({
  getClusterSettings: vi.fn(),
  updateClusterSettings: vi.fn()
}));

describe('InstallSettingsStage', () => {
  beforeEach(() => vi.clearAllMocks());

  it('加载并保存集群安装配置', async () => {
    getClusterSettings.mockResolvedValue({
      paths: { k8s_home: '/data/k8s', install_media: '/media/k8s' },
      env: { kubelet_root: '/data/k8s/kubelet' },
      advanced: { enable_ipv6_dual_stack: false }
    });
    updateClusterSettings.mockResolvedValue({});

    const wrapper = mount(InstallSettingsStage, {
      props: { clusterId: 42 },
      global: { plugins: [ElementPlus] }
    });
    await flushPromises();

    expect(getClusterSettings).toHaveBeenCalledWith(42);
    expect(wrapper.get('[data-testid="k8s-home"]').element.value).toBe('/data/k8s');
    await wrapper.get('[data-testid="install-media"]').setValue('/srv/media');
    await wrapper.get('[data-testid="save-settings"]').trigger('click');
    await flushPromises();

    expect(updateClusterSettings).toHaveBeenCalledWith(42, expect.objectContaining({
      paths: expect.objectContaining({ install_media: '/srv/media' })
    }));
    expect(wrapper.text()).toContain('安装配置已保存');
  });

  it('加载失败后提供重试且错误文本脱敏', async () => {
    getClusterSettings
      .mockRejectedValueOnce(new Error('password=secret'))
      .mockResolvedValueOnce({ paths: {} });

    const wrapper = mount(InstallSettingsStage, {
      props: { clusterId: 42 },
      global: { plugins: [ElementPlus] }
    });
    await flushPromises();

    expect(wrapper.get('[role="alert"]').text()).not.toContain('secret');
    await wrapper.get('[data-testid="retry-settings"]').trigger('click');
    await flushPromises();
    expect(getClusterSettings).toHaveBeenCalledTimes(2);
  });
});
