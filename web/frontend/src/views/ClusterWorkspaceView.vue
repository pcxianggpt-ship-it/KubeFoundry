<template>
  <section class="page-view cluster-workspace-view">
    <header class="workspace-header">
      <div>
        <RouterLink class="back-link" :to="{ name: 'cluster-list' }">
          <ArrowLeft aria-hidden="true" />
          返回集群列表
        </RouterLink>
        <p class="page-eyebrow">集群部署空间</p>
        <h1>{{ cluster?.name || (cluster?.id === 'new' ? '新建集群' : (loading ? '正在加载集群' : '未选择集群')) }}</h1>
      </div>
      <span v-if="cluster" class="status-label" :class="`status-label--${statusPresentation.tone}`">
        <component :is="statusPresentation.icon" aria-hidden="true" />
        {{ statusPresentation.text }}
      </span>
    </header>

    <section v-if="loading" class="workspace-loading" aria-busy="true" aria-label="正在加载集群工作区">
      <el-skeleton :rows="7" animated />
    </section>

    <section v-else-if="errorMessage" class="state-panel state-panel--error" role="alert">
      <WarningFilled aria-hidden="true" />
      <div>
        <h2>工作区加载失败</h2>
        <p>{{ errorMessage }}</p>
      </div>
      <el-button data-testid="retry-workspace" :icon="Refresh" @click="loadWorkspace">重新加载</el-button>
    </section>

    <template v-else-if="cluster">
      <DeploymentPipeline
        :cluster-id="cluster.id"
        :active-stage="activeStage"
        :stage-states="stageStates"
      />

      <section class="stage-content" data-testid="stage-content">
        <ClusterInfoStage
          v-if="activeStage === 'cluster-info'"
          :cluster="cluster"
          :saving="savingCluster"
          @save="saveCluster"
        />

        <NodeConfigView
          v-else-if="activeStage === 'nodes'"
          :cluster-id="cluster.id"
          @cluster-updated="refreshCluster"
        />

        <InstallSettingsStage
          v-else-if="activeStage === 'settings'"
          :cluster-id="cluster.id"
        />

        <PrecheckView v-else-if="activeStage === 'precheck'" :cluster-id="cluster.id" />
      </section>
    </template>

    <section v-else class="state-panel state-panel--empty" role="status">
      <Box aria-hidden="true" />
      <div>
        <h2>未选择集群</h2>
        <p>返回集群列表选择要继续部署的集群。</p>
      </div>
    </section>
  </section>
</template>

<script setup>
import { computed, ref, watch } from 'vue';
import { RouterLink, useRoute, useRouter } from 'vue-router';
import {
  ArrowLeft,
  Box,
  CircleCheckFilled,
  Clock,
  EditPen,
  Refresh,
  WarningFilled
} from '@element-plus/icons-vue';

import DeploymentPipeline from '../components/deployment/DeploymentPipeline.vue';
import ClusterInfoStage from '../components/deployment/ClusterInfoStage.vue';
import InstallSettingsStage from '../components/deployment/InstallSettingsStage.vue';
import NodeConfigView from './NodeConfigView.vue';
import PrecheckView from './PrecheckView.vue';
import { createCluster, getCluster, updateCluster } from '../api/client';
import { safeErrorMessage } from '../utils/redaction';

const route = useRoute();
const router = useRouter();
const cluster = ref(null);
const loading = ref(true);
const savingCluster = ref(false);
const errorMessage = ref('');
let loadSequence = 0;

const activeStage = computed(() => route.params.stage || 'cluster-info');

const effectiveStatus = computed(() => {
  return cluster.value?.status || 'draft';
});

const nodeReady = computed(() => cluster.value?.node_test_status === 'success');

const statusPresentation = computed(() => {
  const status = effectiveStatus.value;
  if (['precheck_passed', 'precheck_success'].includes(status)) {
    return { icon: CircleCheckFilled, text: '预检查通过', tone: 'ready' };
  }
  if (['installing', 'running'].includes(status)) {
    return { icon: Clock, text: '正在安装', tone: 'running' };
  }
  if (['install_failed', 'failed', 'interrupted'].includes(status)) {
    return { icon: WarningFilled, text: '安装失败', tone: 'error' };
  }
  if (['installed', 'success'].includes(status)) {
    return { icon: CircleCheckFilled, text: '安装成功', tone: 'success' };
  }
  if (nodeReady.value && activeStage.value === 'precheck') {
    return { icon: CircleCheckFilled, text: '可执行预检查', tone: 'ready' };
  }
  if (nodeReady.value) {
    return { icon: CircleCheckFilled, text: '节点测试通过', tone: 'ready' };
  }
  return { icon: EditPen, text: '配置未完成', tone: 'incomplete' };
});

const stageStates = computed(() => {
  if (cluster.value?.id === 'new') {
    return {
      'cluster-info': 'current',
      nodes: 'blocked',
      settings: 'blocked',
      precheck: 'blocked',
      install: 'blocked'
    };
  }
  const status = effectiveStatus.value;
  if (['precheck_passed', 'precheck_success'].includes(status)) {
    return {
      'cluster-info': 'completed',
      nodes: 'completed',
      settings: 'completed',
      precheck: 'completed',
      install: 'current'
    };
  }
  if (['installing', 'running'].includes(status)) {
    return {
      'cluster-info': 'completed',
      nodes: 'completed',
      settings: 'completed',
      precheck: 'completed',
      install: 'current'
    };
  }
  if (['install_failed', 'failed', 'interrupted'].includes(status)) {
    return {
      'cluster-info': 'completed',
      nodes: 'completed',
      settings: 'completed',
      precheck: 'completed',
      install: 'error'
    };
  }
  if (['installed', 'success'].includes(status)) {
    return {
      'cluster-info': 'completed',
      nodes: 'completed',
      settings: 'completed',
      precheck: 'completed',
      install: 'completed'
    };
  }
  if (nodeReady.value) {
    return {
      'cluster-info': 'completed',
      nodes: 'completed',
      settings: activeStage.value === 'settings' ? 'current' : 'completed',
      precheck: activeStage.value === 'precheck' ? 'current' : 'pending',
      install: 'blocked'
    };
  }
  return {
    'cluster-info': activeStage.value === 'cluster-info' ? 'current' : 'completed',
    nodes: activeStage.value === 'nodes' ? 'current' : 'pending',
    settings: activeStage.value === 'settings' ? 'current' : 'blocked',
    precheck: 'blocked',
    install: 'blocked'
  };
});

watch(() => route.fullPath, loadWorkspace, { immediate: true });

async function loadWorkspace() {
  const sequence = ++loadSequence;
  loading.value = true;
  errorMessage.value = '';
  cluster.value = null;
  try {
    const clusterId = route.params.clusterId;
    if (!clusterId) throw new Error('未找到任务所属集群');
    if (clusterId === 'new') {
      cluster.value = {
        id: 'new',
        name: '',
        status: 'draft',
        k8s_version: '1.30.14',
        pod_subnet: '10.244.0.0/16',
        service_subnet: '10.96.0.0/16',
        registry_hostname: 'registry',
        registry_ip: '',
        registry_port: 5000
      };
      return;
    }
    const loadedCluster = await getCluster(clusterId);
    if (sequence === loadSequence) cluster.value = loadedCluster?.data || loadedCluster;
  } catch (error) {
    if (sequence === loadSequence) errorMessage.value = safeErrorMessage(error);
  } finally {
    if (sequence === loadSequence) loading.value = false;
  }
}

async function saveCluster(payload) {
  if (savingCluster.value) return;
  savingCluster.value = true;
  errorMessage.value = '';
  try {
    const creating = route.params.clusterId === 'new';
    const saved = creating
      ? await createCluster(payload)
      : await updateCluster(route.params.clusterId, payload);
    cluster.value = saved?.data || saved;
    if (creating) {
      await router.replace({
        name: 'cluster-workspace',
        params: { clusterId: String(cluster.value.id), stage: 'cluster-info' }
      });
    }
  } catch (error) {
    errorMessage.value = safeErrorMessage(error);
  } finally {
    savingCluster.value = false;
  }
}

async function refreshCluster() {
  if (!cluster.value?.id || cluster.value.id === 'new') return;
  try {
    cluster.value = await getCluster(cluster.value.id);
  } catch (error) {
    errorMessage.value = safeErrorMessage(error);
  }
}
</script>
