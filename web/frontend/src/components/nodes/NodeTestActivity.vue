<template>
  <aside class="node-activity" aria-label="节点测试活动">
    <header>
      <h3>测试活动</h3>
      <span class="connection-state">{{ connected ? '实时连接中' : '等待任务' }}</span>
    </header>
    <ol v-if="items.length">
      <li v-for="item in items" :key="item.id">
        <time>{{ item.time }}</time>
        <span>{{ item.message }}</span>
      </li>
    </ol>
    <p v-else class="muted">运行节点测试后，免密配置过程会显示在这里。</p>
  </aside>
</template>

<script setup>
defineProps({
  items: { type: Array, default: () => [] },
  connected: { type: Boolean, default: false }
});
</script>
