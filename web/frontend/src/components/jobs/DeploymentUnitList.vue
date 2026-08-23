<template>
  <ol class="deployment-unit-list" :aria-label="ariaLabel">
    <li v-for="(unit, index) in units" :key="unit.key" class="deployment-unit">
      <button
        type="button"
        class="deployment-unit-toggle"
        :class="`deployment-unit-toggle--${unit.summary.status}`"
        :data-testid="`deployment-unit-${unit.key}`"
        :aria-expanded="isExpanded(unit.key)"
        :aria-controls="`deployment-unit-steps-${unit.key}`"
        @click="toggle(unit.key)"
      >
        <span class="deployment-unit-index">{{ String(index + 1).padStart(2, '0') }}</span>
        <span class="deployment-unit-copy">
          <strong>{{ unit.name }}</strong>
          <small>{{ unit.summary.total }} 个步骤<span v-if="unit.summary.total && unit.summary.status !== 'planned'"> · {{ unit.summary.completed }}/{{ unit.summary.total }} 已结束</span></small>
        </span>
        <el-tag :type="unit.summary.tone" size="small">{{ unit.summary.label }}</el-tag>
        <ArrowDown class="deployment-unit-chevron" aria-hidden="true" />
      </button>
      <ol
        v-show="isExpanded(unit.key)"
        :id="`deployment-unit-steps-${unit.key}`"
        class="job-stage-list deployment-unit-steps"
        :aria-label="`${unit.name}步骤`"
      >
        <li v-for="step in unit.steps" :key="step.id ?? step.key">
          <button
            v-if="selectable"
            type="button"
            :data-testid="`job-stage-${step.id ?? step.key}`"
            :class="{ 'is-selected': step.id === selectedId, 'is-failed': ['failed', 'interrupted'].includes(step.status) }"
            :aria-current="step.id === selectedId ? 'step' : undefined"
            @click.stop="$emit('select', step.id)"
          >
            <span class="job-stage-index">{{ String(step.step_order_in_stage || step.order).padStart(2, '0') }}</span>
            <span class="job-stage-copy"><strong>{{ step.name }}</strong><small>{{ stepLabel(step) }}</small></span>
            <el-tag v-if="step.status" :type="stepStatusTone(step.status, step.status_reason)" size="small">{{ stepProgress(step) }}</el-tag>
          </button>
          <div v-else class="job-stage-plan-item">
            <span class="job-stage-index">{{ String(step.step_order_in_stage || step.order).padStart(2, '0') }}</span>
            <span class="job-stage-copy"><strong>{{ step.name }}</strong><small>{{ targetScopeLabel(step.target_scope) }}</small></span>
          </div>
        </li>
      </ol>
    </li>
  </ol>
</template>

<script setup>
import { ref, watch } from 'vue';
import { ArrowDown } from '@element-plus/icons-vue';
import { stepStatusLabel, stepStatusTone } from './jobStatus';

const props = defineProps({
  units: { type: Array, default: () => [] },
  selectedId: { type: [String, Number], default: '' },
  selectable: { type: Boolean, default: true },
  ariaLabel: { type: String, default: '部署单元' }
});
defineEmits(['select']);

const expandedKeys = ref(new Set());
let initialized = false;

watch(() => props.units, (units) => {
  const active = units.find((unit) => unit.summary.status === 'running')
    || units.find((unit) => unit.summary.status === 'failed');
  if (!initialized) {
    expandedKeys.value = new Set(active ? [active.key] : []);
    initialized = true;
  } else if (active) {
    expandedKeys.value = new Set([...expandedKeys.value, active.key]);
  }
}, { immediate: true, deep: true });

watch(() => props.selectedId, (selectedId) => {
  const selectedUnit = props.units.find((unit) => unit.steps.some((step) => step.id === selectedId));
  if (selectedUnit) expandedKeys.value = new Set([...expandedKeys.value, selectedUnit.key]);
});

function isExpanded(key) { return expandedKeys.value.has(key); }
function toggle(key) {
  const next = new Set(expandedKeys.value);
  if (next.has(key)) next.delete(key); else next.add(key);
  expandedKeys.value = next;
}
function stepLabel(step) {
  return step.status ? stepStatusLabel(step.status, step.status_reason) : targetScopeLabel(step.target_scope);
}
function stepProgress(step) {
  const nodes = step.nodes || [];
  if (!nodes.length) return stepStatusLabel(step.status, step.status_reason);
  const complete = nodes.filter((node) => ['success', 'failed', 'interrupted', 'skipped'].includes(node.status)).length;
  return `${complete}/${nodes.length}`;
}
function targetScopeLabel(scope) {
  return ({
    all_nodes: '所有节点', all_k8s_nodes: '全部 Kubernetes 节点', primary_control_plane: '主控制节点',
    other_control_planes: '其他控制节点', non_primary_k8s_nodes: '非主控 Kubernetes 节点',
    workers: '工作节点', registry: '镜像仓库节点', nfs_server: 'NFS 服务节点'
  })[scope] || '按计划执行';
}
</script>
