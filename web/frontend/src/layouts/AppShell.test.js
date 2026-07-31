import { mount, RouterLinkStub } from '@vue/test-utils';
import { afterEach, describe, expect, it, vi } from 'vitest';

import AppShell from './AppShell.vue';

describe('AppShell', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('提供产品导航和可访问的移动端菜单按钮', async () => {
    const wrapper = mount(AppShell, {
      slots: { default: '<p>工作区内容</p>' },
      global: {
        stubs: { RouterLink: RouterLinkStub }
      }
    });

    expect(wrapper.text()).toContain('KubeFoundry');
    expect(wrapper.text()).toContain('集群配置');
    expect(wrapper.text()).toContain('集群安装');
    expect(wrapper.text()).toContain('工作区内容');

    const menuButton = wrapper.get('button[aria-label="打开导航菜单"]');
    await menuButton.trigger('click');
    expect(wrapper.get('.app-sidebar').classes()).toContain('is-open');
    expect(wrapper.get('button[aria-label="关闭导航菜单"]')).toBeTruthy();
  });

  it('移动端关闭菜单时移出焦点顺序并支持Escape关闭', async () => {
    const listeners = new Set();
    vi.stubGlobal('matchMedia', vi.fn(() => ({
      matches: true,
      addEventListener: (name, listener) => listeners.add(listener),
      removeEventListener: (name, listener) => listeners.delete(listener)
    })));
    const wrapper = mount(AppShell, {
      slots: { default: '<p>移动工作区</p>' },
      global: { stubs: { RouterLink: RouterLinkStub } }
    });
    await wrapper.vm.$nextTick();

    expect(wrapper.get('.app-sidebar').attributes('inert')).toBe('');
    await wrapper.get('button[aria-label="打开导航菜单"]').trigger('click');
    expect(wrapper.get('.app-sidebar').attributes('inert')).toBeUndefined();
    await wrapper.trigger('keydown', { key: 'Escape' });
    expect(wrapper.get('.app-sidebar').attributes('inert')).toBe('');
  });
});
