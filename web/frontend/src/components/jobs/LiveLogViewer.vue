<template>
  <section class="live-log-viewer" aria-label="实时日志">
    <header>
      <div><p class="section-kicker">实时输出</p><h2>任务日志</h2></div>
      <span class="connection-state">{{ connected ? '实时连接中' : terminal ? '任务已结束' : '连接已中断' }}</span>
    </header>
    <ol v-if="logs.length" ref="logList">
      <li v-for="entry in logs" :key="entry.id">
        <time>{{ formatTime(entry.created_at || entry.time) }}</time>
        <span v-if="entry.stage_name" class="log-scope">{{ entry.stage_name }}</span>
        <span v-if="entry.hostname" class="log-scope">{{ entry.hostname }}</span>
        <code>{{ entry.message }}</code>
      </li>
    </ol>
    <div v-else class="log-empty" role="status">当前筛选范围还没有日志。</div>
  </section>
</template>

<script setup>
import { nextTick, ref, watch } from 'vue';

const props = defineProps({
  logs: { type: Array, default: () => [] },
  connected: { type: Boolean, default: false },
  terminal: { type: Boolean, default: false }
});
const logList = ref(null);

watch(() => props.logs.length, async () => {
  await nextTick();
  if (logList.value) logList.value.scrollTop = logList.value.scrollHeight;
});

function formatTime(value) {
  if (!value) return '--:--:--';
  const date = new Date(String(value).replace(' ', 'T'));
  if (Number.isNaN(date.getTime())) return String(value).slice(-8);
  return date.toLocaleTimeString('zh-CN', { hour12: false });
}
</script>
