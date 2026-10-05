<template>
  <div ref="shell" class="app-frame" @keydown.esc="closeNavigation(true)">
    <a class="skip-link" href="#main-workspace">跳至主内容</a>
    <template v-if="theme === 'apple'">
      <header class="app-global-bar">
        <div class="app-global-inner">
          <RouterLink class="brand-link" :to="{ name: 'cluster-config-list' }" @click="closeNavigation()">
            <strong>KubeFoundry</strong>
          </RouterLink>
          <button
            ref="menuButton"
            class="mobile-menu-button"
            type="button"
            :aria-label="navigationOpen ? '关闭导航菜单' : '打开导航菜单'"
            :aria-expanded="navigationOpen"
            aria-controls="app-navigation"
            @click="navigationOpen = !navigationOpen"
          >
            <Close v-if="navigationOpen" aria-hidden="true" />
            <Menu v-else aria-hidden="true" />
          </button>

          <nav
            id="app-navigation"
            class="app-navigation primary-navigation"
            aria-label="主导航"
            :class="{ 'is-open': navigationOpen }"
            :aria-hidden="isMobile && !navigationOpen ? 'true' : undefined"
            :inert="isMobile && !navigationOpen ? '' : undefined"
          >
            <RouterLink :to="{ name: 'cluster-config-list' }" :class="{ 'is-section-active': !installSection }" @click="closeNavigation()">
              <span>集群配置</span>
            </RouterLink>
            <RouterLink :to="{ name: 'cluster-install-list' }" :class="{ 'is-section-active': installSection }" @click="closeNavigation()">
              <span>集群安装</span>
            </RouterLink>
          </nav>

          <div class="service-connection" role="status">
            <component :is="serviceConnected ? CircleCheckFilled : WarningFilled" :class="{ 'is-connected': serviceConnected }" aria-hidden="true" />
            <span>{{ serviceConnected === null ? '正在连接' : serviceConnected ? '连接正常' : '服务未连接' }}</span>
          </div>
        </div>
      </header>

      <div class="app-subnav">
        <div class="app-subnav-inner">
          <RouterLink class="app-section-title" :to="sectionRoute">{{ sectionTitle }}</RouterLink>
          <span class="app-section-context">{{ pageContext }}</span>
          <ThemeSwitcher location="apple" />
          <span class="app-version">v{{ version }}</span>
        </div>
      </div>
    </template>

    <template v-else>
      <div class="mobile-brand">
        <RouterLink :to="{ name: 'cluster-config-list' }">KubeFoundry</RouterLink>
        <ThemeSwitcher location="classic-mobile" />
      </div>
      <button
        ref="menuButton"
        class="mobile-menu-button"
        type="button"
        :aria-label="navigationOpen ? '关闭导航菜单' : '打开导航菜单'"
        :aria-expanded="navigationOpen"
        aria-controls="app-navigation"
        @click="navigationOpen = !navigationOpen"
      >
        <Close v-if="navigationOpen" aria-hidden="true" />
        <Menu v-else aria-hidden="true" />
      </button>
      <aside
        id="app-navigation"
        class="app-sidebar"
        :class="{ 'is-open': navigationOpen }"
        :aria-hidden="isMobile && !navigationOpen ? 'true' : undefined"
        :inert="isMobile && !navigationOpen ? '' : undefined"
      >
        <RouterLink class="brand-link" :to="{ name: 'cluster-config-list' }" @click="closeNavigation()">
          <strong>KubeFoundry</strong>
        </RouterLink>
        <span class="app-version">v{{ version }}</span>
        <nav aria-label="主导航" class="primary-navigation">
          <RouterLink :to="{ name: 'cluster-config-list' }" :class="{ 'is-section-active': !installSection }" @click="closeNavigation()">
            <Setting aria-hidden="true" /><span>集群配置</span>
          </RouterLink>
          <RouterLink :to="{ name: 'cluster-install-list' }" :class="{ 'is-section-active': installSection }" @click="closeNavigation()">
            <Box aria-hidden="true" /><span>集群安装</span>
          </RouterLink>
        </nav>
        <ThemeSwitcher location="classic" />
        <div class="sidebar-connection" role="status">
          <component :is="serviceConnected ? CircleCheckFilled : WarningFilled" :class="{ 'is-connected': serviceConnected }" aria-hidden="true" />
          <span>{{ serviceConnected === null ? '正在连接' : serviceConnected ? '连接正常' : '服务未连接' }}</span>
        </div>
      </aside>
    </template>

    <button
      v-if="navigationOpen"
      class="navigation-backdrop"
      type="button"
      aria-label="关闭导航菜单"
      @click="closeNavigation(true)"
    ></button>

    <!-- 两版共用工作区，不重新挂载页面，保留未保存表单和任务连接。 -->
    <main id="main-workspace" class="app-main" tabindex="-1">
      <slot>
        <RouterView />
      </slot>
    </main>
  </div>
</template>

<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { RouterLink, RouterView, useRoute } from 'vue-router';
import { Box, CircleCheckFilled, Close, Menu, Setting, WarningFilled } from '@element-plus/icons-vue';
import { version } from '../../package.json';
import ThemeSwitcher from '../components/ThemeSwitcher.vue';
import { theme } from '../themes/theme';

const route = useRoute();
const installSection = computed(() => route?.path.startsWith('/cluster-install') || route?.path.startsWith('/jobs'));
const sectionTitle = computed(() => installSection.value ? '集群安装' : '集群配置');
const sectionRoute = computed(() => ({ name: installSection.value ? 'cluster-install-list' : 'cluster-config-list' }));
const pageContext = computed(() => {
  if (route?.params?.jobId) return '任务进度';
  const context = { 'cluster-info': '集群信息', nodes: '服务器节点', components: 'Kubemate 组件', precheck: '部署预检查' };
  return context[route?.params?.stage] || ({ 'install-overview': '安装概览', 'install-confirm': '安装确认', 'reset-confirm': '远程重置', 'install-precheck': '部署预检查' }[route?.name]) || 'Kubernetes 部署工作区';
});

const navigationOpen = ref(false);
const isMobile = ref(false);
const menuButton = ref(null);
const shell = ref(null);
let mediaQuery;
const serviceConnected = ref(null);
let healthTimer;
let healthController;

async function checkService() {
  healthController = new AbortController();
  const timeout = setTimeout(() => healthController.abort(), 5000);
  try {
    const response = await fetch('/api/health', { signal: healthController.signal });
    const health = await response.json();
    serviceConnected.value = response.ok && health.status === 'ok';
  } catch {
    serviceConnected.value = false;
  } finally {
    clearTimeout(timeout);
  }
}

onMounted(() => {
  checkService();
  healthTimer = setInterval(checkService, 30000);
  configureNavigation();
});

watch(() => route?.path, () => closeNavigation());
watch(theme, async () => {
  const switchingControl = shell.value?.querySelector('.theme-switcher select:focus');
  closeNavigation();
  configureNavigation();
  if (!switchingControl) return;
  await nextTick();
  const location = theme.value === 'apple' ? 'apple' : isMobile.value ? 'classic-mobile' : 'classic';
  shell.value?.querySelector(`[data-theme-location="${location}"] select`)?.focus();
});

onBeforeUnmount(() => {
  mediaQuery?.removeEventListener?.('change', updateMobile);
  clearInterval(healthTimer);
  healthController?.abort();
});

function updateMobile(event) {
  isMobile.value = event.matches;
  if (!event.matches) navigationOpen.value = false;
}

function configureNavigation() {
  mediaQuery?.removeEventListener?.('change', updateMobile);
  if (!window.matchMedia) return;
  mediaQuery = window.matchMedia(theme.value === 'apple' ? '(max-width: 833px)' : '(max-width: 820px)');
  updateMobile(mediaQuery);
  mediaQuery.addEventListener?.('change', updateMobile);
}

async function closeNavigation(restoreFocus = false) {
  navigationOpen.value = false;
  if (restoreFocus && isMobile.value) {
    await nextTick();
    menuButton.value?.focus();
  }
}
</script>
