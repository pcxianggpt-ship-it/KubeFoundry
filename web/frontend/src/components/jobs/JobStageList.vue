<template>
  <ol class="job-stage-list" aria-label="安装阶段">
    <li v-for="(stage, index) in stages" :key="stage.id">
      <button
        type="button"
        :data-testid="`job-stage-${stage.id}`"
        :class="{ 'is-selected': stage.id === selectedId, 'is-failed': ['failed', 'interrupted'].includes(stage.status) }"
        :aria-current="stage.id === selectedId ? 'step' : undefined"
        @click="$emit('select', stage.id)"
      >
        <span class="job-stage-index">{{ String(index + 1).padStart(2, '0') }}</span>
        <span class="job-stage-copy"><strong>{{ stage.name }}</strong><small>{{ jobStatusLabel(stage.status) }}</small></span>
        <el-tag :type="jobStatusTone(stage.status)" size="small">{{ stageProgress(stage) }}</el-tag>
      </button>
    </li>
  </ol>
</template>

<script setup>
import { jobStatusLabel, jobStatusTone } from './jobStatus';

defineProps({
  stages: { type: Array, default: () => [] },
  selectedId: { type: [String, Number], default: '' }
});
defineEmits(['select']);

function stageProgress(stage) {
  const nodes = stage.nodes || [];
  if (!nodes.length) return jobStatusLabel(stage.status);
  const complete = nodes.filter((node) => ['success', 'failed', 'skipped'].includes(node.status)).length;
  return `${complete}/${nodes.length}`;
}
</script>
