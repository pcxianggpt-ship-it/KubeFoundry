<template>
  <section class="live-log-viewer" aria-label="实时日志">
    <header>
      <h2>实时日志</h2>
      <div v-if="$slots.filters || $slots.tools" class="log-header-actions"><slot name="filters" /><slot name="tools" /></div>
    </header>
    <div class="log-toolbar"><span class="connection-state">{{ connected ? '实时连接中' : terminal ? '任务已结束' : '连接已中断' }}</span></div>
    <ol v-if="logs.length" ref="logList" tabindex="0" aria-label="日志内容，可滚动查看">
      <li v-for="entry in logs" :key="entry.id" :class="{ 'log-entry--error': isError(entry) }">
        <time>{{ formatTime(entry.created_at || entry.time) }}</time>
        <span class="log-level" :class="`log-level--${level(entry).toLowerCase()}`">{{ level(entry) }}</span>
        <code><span v-if="entry.stage_name" class="log-scope">[{{ entry.stage_name }}] </span><span v-if="entry.hostname" class="log-scope">[{{ entry.hostname }}] </span>{{ message(entry) }}</code>
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

function level(entry) {
  const value = entry.level || entry.severity || (entry.message || '').match(/\[(INFO|WARN|WARNING|ERROR|FATAL|SUCCESS|DEBUG)\]/i)?.[1];
  return value ? String(value).toUpperCase() : 'INFO';
}
function message(entry) { return (entry.message || '').replace(/^\s*\[(?:INFO|WARN|WARNING|ERROR|FATAL|SUCCESS|DEBUG)\]\s*/i, ''); }

function isError(entry) {
  return ['error', 'fatal'].includes(String(entry.level || entry.severity || '').toLowerCase())
    || /\[(?:ERROR|FATAL)\]/i.test(entry.message || '');
}

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
