import { flushPromises, mount, RouterLinkStub } from '@vue/test-utils';
import { afterEach, describe, expect, it, vi } from 'vitest';

import AppShell from './AppShell.vue';
import { createAppRouter } from '../router';
import { createMemoryHistory, routeLocationKey } from 'vue-router';

const routeProvider = { [routeLocationKey]: { path: '/cluster-config' } };

describe('AppShell', () => {
  afterEach(() => { vi.unstubAllGlobals(); vi.useRealTimers(); });

  it('侧栏连接状态来自健康接口，服务不可用时更新且卸载后停止检查', async () => {
    vi.useFakeTimers();
    const fetchHealth = vi.fn().mockResolvedValue({ ok: true, json: async () => ({ status: 'ok' }) });
    vi.stubGlobal('fetch', fetchHealth);
    const wrapper = mount(AppShell, { slots: { default: '<p>工作区</p>' }, global: {
      provide: routeProvider, stubs: { RouterLink: RouterLinkStub }
    } });
    await flushPromises();
    expect(wrapper.get('.sidebar-connection').text()).toBe('连接正常');
    fetchHealth.mockRejectedValue(new Error('offline'));
    await vi.advanceTimersByTimeAsync(30000);
    expect(wrapper.get('.sidebar-connection').text()).toBe('服务未连接');
    wrapper.unmount();
    const callCount = fetchHealth.mock.calls.length;
    await vi.advanceTimersByTimeAsync(30000);
    expect(fetchHealth).toHaveBeenCalledTimes(callCount);
  });

  it('提供产品导航和可访问的移动端菜单按钮', async () => {
    const wrapper = mount(AppShell, {
      slots: { default: '<p>工作区内容</p>' },
      global: {
        provide: routeProvider,
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
      global: { provide: routeProvider, stubs: { RouterLink: RouterLinkStub } }
    });
    await wrapper.vm.$nextTick();

    expect(wrapper.get('.app-sidebar').attributes('inert')).toBe('');
    await wrapper.get('button[aria-label="打开导航菜单"]').trigger('click');
    expect(wrapper.get('.app-sidebar').attributes('inert')).toBeUndefined();
    await wrapper.trigger('keydown', { key: 'Escape' });
    expect(wrapper.get('.app-sidebar').attributes('inert')).toBe('');
  });

  it('嵌套任务路由仍高亮安装导航，提供跳至主内容入口', async () => {
    const router = createAppRouter(createMemoryHistory());
    await router.push('/cluster-install/42/jobs/81');
    const wrapper = mount(AppShell, { slots: { default: '<p>任务详情</p>' }, global: { plugins: [router] } });
    expect(wrapper.get('.primary-navigation .is-section-active').text()).toBe('集群安装');
    expect(wrapper.get('.skip-link').attributes('href')).toBe('#main-workspace');
    await router.push('/cluster-config/42/nodes');
    expect(wrapper.get('.primary-navigation .is-section-active').text()).toBe('集群配置');
    wrapper.unmount();
  });
});
