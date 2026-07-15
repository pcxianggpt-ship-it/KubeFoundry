<template>
  <nav class="deployment-pipeline" aria-label="集群部署阶段">
    <ol>
      <li
        v-for="(stage, index) in stages"
        :key="stage.key"
        :data-stage-key="stage.key"
        :class="`is-${resolveState(stage.key, index)}`"
        :aria-current="stage.key === activeStage ? 'step' : undefined"
      >
        <RouterLink
          v-if="resolveState(stage.key, index) !== 'blocked'"
          class="pipeline-stage"
          :to="stageRoute(stage.key)"
        >
          <span class="pipeline-stage__marker">
            <component :is="stateIcon(resolveState(stage.key, index))" aria-hidden="true" />
          </span>
          <span class="pipeline-stage__copy">
            <span class="pipeline-stage__number">{{ String(index + 1).padStart(2, '0') }}</span>
            <strong class="pipeline-stage__title">{{ stage.title }}</strong>
            <span class="pipeline-stage__status">{{ stateText(resolveState(stage.key, index)) }}</span>
          </span>
        </RouterLink>
        <span v-else class="pipeline-stage is-disabled" aria-disabled="true">
          <span class="pipeline-stage__marker">
            <Lock aria-hidden="true" />
          </span>
          <span class="pipeline-stage__copy">
            <span class="pipeline-stage__number">{{ String(index + 1).padStart(2, '0') }}</span>
            <strong class="pipeline-stage__title">{{ stage.title }}</strong>
            <span class="pipeline-stage__status">暂不可用</span>
          </span>
        </span>
      </li>
    </ol>
  </nav>
</template>

<script setup>
import { CircleCheckFilled, Clock, Lock, WarningFilled } from '@element-plus/icons-vue';
import { RouterLink } from 'vue-router';

const stages = [
  { key: 'cluster-info', title: '集群信息' },
  { key: 'nodes', title: '服务器节点' },
  { key: 'settings', title: '安装配置' },
  { key: 'precheck', title: '部署预检查' },
  { key: 'install', title: '执行安装' }
];

const props = defineProps({
  clusterId: {
    type: [String, Number],
    required: true
  },
  activeStage: {
    type: String,
    required: true
  },
  stageStates: {
    type: Object,
    default: () => ({})
  }
});

const stateLabels = {
  completed: '已完成',
  current: '进行中',
  blocked: '暂不可用',
  error: '失败',
  pending: '未开始'
};

function resolveState(stageKey, index) {
  if (props.stageStates[stageKey]) return props.stageStates[stageKey];
  const activeIndex = stages.findIndex((stage) => stage.key === props.activeStage);
  if (index < activeIndex) return 'completed';
  if (index === activeIndex) return 'current';
  return 'pending';
}

function stageRoute(stage) {
  if (stage === 'install') {
    return {
      name: 'install-confirm',
      params: { clusterId: String(props.clusterId) }
    };
  }
  return {
    name: 'cluster-workspace',
    params: {
      clusterId: String(props.clusterId),
      stage
    }
  };
}

function stateText(state) {
  return stateLabels[state] || stateLabels.pending;
}

function stateIcon(state) {
  if (state === 'completed') return CircleCheckFilled;
  if (state === 'error') return WarningFilled;
  if (state === 'blocked') return Lock;
  return Clock;
}
</script>
