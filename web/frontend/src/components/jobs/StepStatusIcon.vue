<template>
  <component
    :is="icon"
    class="step-status-icon"
    :class="[`execution-tone--${tone}`, { 'is-spinning': status === 'running' }]"
    aria-hidden="true"
  />
</template>

<script setup>
import { computed } from 'vue';
import { CircleCheckFilled, CircleCloseFilled, Clock, Loading, Remove } from '@element-plus/icons-vue';
import { executionStatusTone } from './jobStatus';

const props = defineProps({
  status: { type: String, default: '' },
  reason: { type: String, default: '' }
});
const tone = computed(() => executionStatusTone(props.status, props.reason));
const icon = computed(() => {
  if (tone.value === 'success') return CircleCheckFilled;
  if (tone.value === 'error') return CircleCloseFilled;
  if (props.status === 'running') return Loading;
  if (['skipped', 'canceled'].includes(props.status)) return Remove;
  return Clock;
});
</script>
