import { flushPromises, mount, RouterLinkStub } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, onMounted, ref } from 'vue';

import AppShell from './AppShell.vue';
import { createAppRouter } from '../router';
import { createMemoryHistory, routeLocationKey } from 'vue-router';
import { initializeTheme, setTheme } from '../themes/theme';

const routeProvider = { [routeLocationKey]: { path: '/cluster-config' } };

describe('AppShell', () => {
  beforeEach(() => {
    localStorage.clear();
    initializeTheme();
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, json: async () => ({ status: 'ok' }) }));
  });
  afterEach(() => { vi.unstubAllGlobals(); vi.useRealTimers(); });

  it('顶部连接状态来自健康接口，服务不可用时更新且卸载后停止检查', async () => {
    vi.useFakeTimers();
    const fetchHealth = vi.fn().mockResolvedValue({ ok: true, json: async () => ({ status: 'ok' }) });
    vi.stubGlobal('fetch', fetchHealth);
    const wrapper = mount(AppShell, { slots: { default: '<p>工作区</p>' }, global: {
      provide: routeProvider, stubs: { RouterLink: RouterLinkStub }
    } });
    await flushPromises();
    expect(wrapper.get('.service-connection').text()).toBe('连接正常');
    fetchHealth.mockRejectedValue(new Error('offline'));
    await vi.advanceTimersByTimeAsync(30000);
    expect(wrapper.get('.service-connection').text()).toBe('服务未连接');
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
    expect(wrapper.get('.app-navigation').classes()).toContain('is-open');
    expect(wrapper.get('button[aria-label="关闭导航菜单"]')).toBeTruthy();
    wrapper.unmount();
  });

  it.each(['apple', 'classic'])('%s 版移动端关闭菜单时移出焦点顺序并支持Escape关闭', async theme => {
    setTheme(theme);
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

    expect(wrapper.get('#app-navigation').attributes('inert')).toBe('');
    await wrapper.get('button[aria-label="打开导航菜单"]').trigger('click');
    expect(wrapper.get('#app-navigation').attributes('inert')).toBeUndefined();
    await wrapper.trigger('keydown', { key: 'Escape' });
    expect(wrapper.get('#app-navigation').attributes('inert')).toBe('');
    wrapper.unmount();
  });

  it('两版切换保留工作区组件、未保存输入和健康检查连接', async () => {
    const mounted = vi.fn();
    const Workspace = defineComponent({
      setup() { const draft = ref('原有配置'); onMounted(mounted); return { draft }; },
      template: '<input v-model="draft" aria-label="未保存配置" />'
    });
    const wrapper = mount(AppShell, { slots: { default: Workspace }, global: { provide: routeProvider, stubs: { RouterLink: RouterLinkStub } } });
    await flushPromises();
    const main = wrapper.get('main').element;
    const draft = wrapper.get('input');
    await draft.setValue('尚未保存的配置');
    await wrapper.get('[data-theme-location="apple"] select').setValue('classic');
    expect(wrapper.find('.app-global-bar').exists()).toBe(false);
    expect(wrapper.find('.app-sidebar').exists()).toBe(true);
    expect(wrapper.get('main').element).toBe(main);
    expect(wrapper.get('input').element).toBe(draft.element);
    expect(wrapper.get('input').element.value).toBe('尚未保存的配置');
    expect(wrapper.get('.sidebar-connection').text()).toBe('连接正常');
    await wrapper.get('[data-theme-location="classic"] select').setValue('apple');
    expect(wrapper.find('.app-sidebar').exists()).toBe(false);
    expect(wrapper.find('.app-global-bar').exists()).toBe(true);
    expect(wrapper.get('input').element.value).toBe('尚未保存的配置');
    expect(mounted).toHaveBeenCalledTimes(1);
    expect(fetch).toHaveBeenCalledTimes(1);
    wrapper.unmount();
  });

  it('两版遵循各自导航断点，更换监听器且恢复换肤控件焦点', async () => {
    const listeners = new Set();
    const matchMedia = vi.fn(query => ({
      matches: query.includes('833'),
      addEventListener: (name, listener) => listeners.add(listener),
      removeEventListener: (name, listener) => listeners.delete(listener)
    }));
    vi.stubGlobal('matchMedia', matchMedia);
    const wrapper = mount(AppShell, { attachTo: document.body, slots: { default: '<p>工作区</p>' }, global: { provide: routeProvider, stubs: { RouterLink: RouterLinkStub } } });
    const select = wrapper.get('[data-theme-location="apple"] select');
    select.element.focus();
    await wrapper.get('.mobile-menu-button').trigger('click');
    await select.setValue('classic');
    await flushPromises();
    expect(matchMedia).toHaveBeenLastCalledWith('(max-width: 820px)');
    expect(wrapper.get('.app-sidebar').attributes('inert')).toBeUndefined();
    expect(wrapper.find('.navigation-backdrop').exists()).toBe(false);
    expect(document.activeElement).toBe(wrapper.get('[data-theme-location="classic"] select').element);
    expect(listeners.size).toBe(1);
    setTheme('apple');
    await flushPromises();
    expect(wrapper.get('.app-navigation').attributes('inert')).toBe('');
    expect(matchMedia).toHaveBeenLastCalledWith('(max-width: 833px)');
    expect(listeners.size).toBe(1);
    wrapper.unmount();
    expect(listeners.size).toBe(0);
  });

  it('嵌套任务路由仍高亮安装导航，提供跳至主内容入口', async () => {
    const router = createAppRouter(createMemoryHistory());
    await router.push('/cluster-install/42/jobs/81');
    const wrapper = mount(AppShell, { slots: { default: '<p>任务详情</p>' }, global: { plugins: [router] } });
    expect(wrapper.get('.primary-navigation .is-section-active').text()).toBe('集群安装');
    expect(wrapper.get('.app-section-title').text()).toBe('集群安装');
    expect(wrapper.get('.app-section-context').text()).toBe('任务进度');
    expect(wrapper.get('.skip-link').attributes('href')).toBe('#main-workspace');
    await router.push('/cluster-config/42/nodes');
    expect(wrapper.get('.primary-navigation .is-section-active').text()).toBe('集群配置');
    expect(wrapper.get('.app-section-context').text()).toBe('服务器节点');
    wrapper.unmount();
  });

  it.each(['apple', 'classic'])('%s 版移动端切换路由后关闭导航，Escape关闭后恢复菜单按钮焦点', async theme => {
    setTheme(theme);
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, json: async () => ({ status: 'ok' }) }));
    vi.stubGlobal('matchMedia', vi.fn(() => ({ matches: true, addEventListener: vi.fn(), removeEventListener: vi.fn() })));
    const router = createAppRouter(createMemoryHistory());
    await router.push('/cluster-config');
    const wrapper = mount(AppShell, {
      attachTo: document.body,
      slots: { default: '<p>工作区</p>' },
      global: { plugins: [router] }
    });
    await flushPromises();
    const menu = wrapper.get('.mobile-menu-button');
    await menu.trigger('click');
    await router.push('/cluster-install');
    expect(wrapper.get('#app-navigation').attributes('inert')).toBe('');
    await menu.trigger('click');
    await wrapper.trigger('keydown', { key: 'Escape' });
    await flushPromises();
    expect(document.activeElement).toBe(menu.element);
    expect(wrapper.get('#app-navigation').attributes('inert')).toBe('');
    wrapper.unmount();
  });
});
