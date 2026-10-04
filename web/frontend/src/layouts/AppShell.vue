<template>
  <div class="app-frame" @keydown.esc="closeNavigation(true)">
    <a class="skip-link" href="#main-workspace">跳至主内容</a>
    <RouterLink class="mobile-brand" :to="{ name: 'cluster-config-list' }">KubeFoundry</RouterLink>
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
        <RouterLink :to="{ name: 'cluster-config-list' }" :class="{ 'is-section-active': route?.path.startsWith('/cluster-config') }" @click="closeNavigation()">
          <Setting aria-hidden="true" />
          <span>集群配置</span>
        </RouterLink>
        <RouterLink :to="{ name: 'cluster-install-list' }" :class="{ 'is-section-active': route?.path.startsWith('/cluster-install') }" @click="closeNavigation()">
          <Box aria-hidden="true" />
          <span>集群安装</span>
        </RouterLink>
      </nav>

      <div class="sidebar-connection" role="status">
        <component :is="serviceConnected ? CircleCheckFilled : WarningFilled" :class="{ 'is-connected': serviceConnected }" aria-hidden="true" />
        <span>{{ serviceConnected === null ? '正在连接' : serviceConnected ? '连接正常' : '服务未连接' }}</span>
      </div>
    </aside>

    <button
      v-if="navigationOpen"
      class="navigation-backdrop"
      type="button"
      aria-label="关闭导航菜单"
      @click="closeNavigation(true)"
    ></button>

    <main id="main-workspace" class="app-main" tabindex="-1">
      <slot>
        <RouterView />
      </slot>
    </main>
  </div>
</template>

<script setup>
import { nextTick, onBeforeUnmount, onMounted, ref } from 'vue';
import { RouterLink, RouterView, useRoute } from 'vue-router';
import { Box, CircleCheckFilled, Close, Menu, Setting, WarningFilled } from '@element-plus/icons-vue';
import { version } from '../../package.json';

const route = useRoute();

const navigationOpen = ref(false);
const isMobile = ref(false);
const menuButton = ref(null);
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
  if (!window.matchMedia) return;
  mediaQuery = window.matchMedia('(max-width: 820px)');
  updateMobile(mediaQuery);
  mediaQuery.addEventListener?.('change', updateMobile);
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

async function closeNavigation(restoreFocus = false) {
  navigationOpen.value = false;
  if (restoreFocus && isMobile.value) {
    await nextTick();
    menuButton.value?.focus();
  }
}
</script>
