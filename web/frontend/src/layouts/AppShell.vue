<template>
  <div class="app-frame" @keydown.esc="closeNavigation(true)">
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
        <span class="brand-mark" aria-hidden="true">KF</span>
        <span>
          <strong>KubeFoundry</strong>
          <small>集群运维工作台</small>
        </span>
      </RouterLink>

      <nav aria-label="主导航" class="primary-navigation">
        <RouterLink :to="{ name: 'cluster-config-list' }" @click="closeNavigation()">
          <Grid aria-hidden="true" />
          <span>集群配置</span>
        </RouterLink>
        <RouterLink :to="{ name: 'cluster-install-list' }" @click="closeNavigation()">
          <Promotion aria-hidden="true" />
          <span>集群安装</span>
        </RouterLink>
      </nav>

      <div class="sidebar-footer">
        <span class="connection-indicator" aria-hidden="true"></span>
        <span>控制台已就绪</span>
      </div>
    </aside>

    <button
      v-if="navigationOpen"
      class="navigation-backdrop"
      type="button"
      aria-label="关闭导航菜单"
      @click="closeNavigation(true)"
    ></button>

    <main class="app-main">
      <slot>
        <RouterView />
      </slot>
    </main>
  </div>
</template>

<script setup>
import { nextTick, onBeforeUnmount, onMounted, ref } from 'vue';
import { RouterLink, RouterView } from 'vue-router';
import { Close, Grid, Menu, Promotion } from '@element-plus/icons-vue';

const navigationOpen = ref(false);
const isMobile = ref(false);
const menuButton = ref(null);
let mediaQuery;

onMounted(() => {
  if (!window.matchMedia) return;
  mediaQuery = window.matchMedia('(max-width: 820px)');
  updateMobile(mediaQuery);
  mediaQuery.addEventListener?.('change', updateMobile);
});

onBeforeUnmount(() => mediaQuery?.removeEventListener?.('change', updateMobile));

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
