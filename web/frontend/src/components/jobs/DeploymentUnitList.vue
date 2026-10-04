<template>
  <ol class="deployment-unit-list" :aria-label="ariaLabel">
    <li v-for="(unit, index) in units" :key="unit.key" class="deployment-unit" :class="`execution-tone--${executionStatusTone(unit.summary.status)}`" :data-state="unit.summary.status">
      <button
        type="button"
        class="deployment-unit-toggle"
        :class="[`deployment-unit-toggle--${unit.summary.status}`, { 'is-active-unit': unit.steps.some(step => step.id === selectedId) }]"
        :data-testid="`deployment-unit-${unit.key}`"
        :aria-expanded="isExpanded(unit.key)"
        :aria-controls="`deployment-unit-steps-${unit.key}`"
        @click="toggle(unit.key)"
      >
        <span class="deployment-unit-index" aria-hidden="true">{{ index + 1 }}</span>
        <span class="deployment-unit-copy">
          <strong>{{ unit.name }}</strong>
          <small v-if="unit.summary.status === 'planned'">{{ unit.summary.total }} 个步骤</small>
          <small v-else>{{ unit.summary.completed }} / {{ unit.summary.total }} 步骤</small>
        </span>
        <span v-if="unit.summary.status !== 'planned'" class="deployment-unit-status">
          <StepStatusIcon :status="unit.summary.status" />
          <span>{{ unit.summary.label === '成功' ? '已完成' : unit.summary.label }}</span>
        </span>
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
            :data-status="executionStatusTone(step.status, step.status_reason)"
            :data-state="step.status || 'planned'"
            @click.stop="$emit('select', step.id)"
          >
            <StepStatusIcon :status="step.status" :reason="step.status_reason" />
            <span class="job-stage-copy"><strong>{{ step.name }}</strong></span>
            <span class="job-stage-status" :class="`execution-tone--${executionStatusTone(step.status, step.status_reason)}`">{{ stepLabel(step) }}</span>
          </button>
          <div v-else class="job-stage-plan-item">
            <StepStatusIcon />
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
import { executionStatusTone, stepStatusLabel } from './jobStatus';
import StepStatusIcon from './StepStatusIcon.vue';

const props = defineProps({
  units: { type: Array, default: () => [] },
  selectedId: { type: [String, Number], default: '' },
  selectable: { type: Boolean, default: true },
  ariaLabel: { type: String, default: '部署单元' }
});
defineEmits(['select']);

const expandedKey = ref('');
let initialized = false;

watch(() => props.units, (units) => {
  const active = units.find((unit) => unit.steps.some((step) => step.id === props.selectedId))
    || units.find((unit) => unit.summary.status === 'running')
    || units.find((unit) => unit.summary.status === 'failed');
  if (!initialized) {
    expandedKey.value = active?.key || '';
    initialized = true;
  } else if (!units.some((unit) => unit.key === expandedKey.value)) {
    expandedKey.value = '';
  }
}, { immediate: true, deep: true });

watch(() => props.selectedId, (selectedId) => {
  const selectedUnit = props.units.find((unit) => unit.steps.some((step) => step.id === selectedId));
  if (selectedUnit) expandedKey.value = selectedUnit.key;
});

function isExpanded(key) { return expandedKey.value === key; }
function toggle(key) {
  expandedKey.value = expandedKey.value === key ? '' : key;
}
function stepLabel(step) {
  return step.status ? stepStatusLabel(step.status, step.status_reason) : targetScopeLabel(step.target_scope);
}
function targetScopeLabel(scope) {
  return ({
    all_nodes: '所有节点', all_k8s_nodes: '全部 Kubernetes 节点', primary_control_plane: '主控制节点',
    other_control_planes: '其他控制节点', non_primary_k8s_nodes: '非主控 Kubernetes 节点',
    workers: '工作节点', registry: '镜像仓库节点', nfs_server: 'NFS 服务节点'
  })[scope] || '按计划执行';
}
</script>
