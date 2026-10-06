<template>
  <section class="page-view job-execution-view">
    <div class="execution-toolbar">
      <nav class="execution-breadcrumb" aria-label="当前位置">
        <RouterLink :to="{ name: 'cluster-install-list' }">集群安装</RouterLink>
        <span aria-hidden="true">/</span>
        <span aria-current="page">{{ cluster.name || '集群任务' }}</span>
        <span v-if="job.id" class="execution-job-number">任务 #{{ job.id }}</span>
      </nav>
      <RouterLink class="el-button" :to="{ name: 'cluster-install-list' }"><ArrowLeft aria-hidden="true" />返回集群</RouterLink>
    </div>
    <header class="execution-hero">
      <div class="execution-heading-row">
      <div class="execution-title-line">
        <h1>{{ jobTypeLabel }}进度</h1>
        <span v-if="!loading && !errorMessage" class="execution-current-status" :class="`execution-tone--${statusTone}`"><StepStatusIcon :status="job.status" />{{ currentStatusLabel }}</span>
      </div>
      <div v-if="!loading && !errorMessage && resumeAvailable" class="execution-hero-actions">
        <div class="execution-retry-buttons">
          <el-button data-testid="resume-install-job" type="primary" :loading="retryMode === 'resume'" :disabled="retrying" @click="retryJob('resume')">断点续跑</el-button>
          <el-button data-testid="rerun-install-job" :loading="retryMode === 'rerun'" :disabled="retrying" @click="retryJob('rerun')">全量重跑</el-button>
        </div>
        <p class="field-hint">断点续跑复用已完成记录，全量重跑重新检查全部步骤。</p>
      </div>
      </div>
      <div v-if="!loading && !errorMessage" class="execution-hero-meta">
        <span>Kubernetes {{ cluster.k8s_version || '-' }}</span>
        <span aria-hidden="true">·</span><span>{{ completedSteps }} / {{ stages.length }} 步骤</span>
      </div>
      <section v-if="!loading && !errorMessage" class="execution-overview" aria-label="整体进度">
        <div class="progress-copy"><span class="visually-hidden">{{ completedSteps }} / {{ stages.length }} 个步骤已完成</span><span>{{ progress }}%</span></div>
        <el-progress :percentage="progress" :show-text="false" :stroke-width="10" :status="progressState" />
      </section>
    </header>
    <el-skeleton v-if="loading" :rows="9" animated aria-label="正在恢复安装任务" />
    <section v-else-if="errorMessage" class="state-panel state-panel--error" role="alert">
      <WarningFilled /><div><h2>任务恢复失败</h2><p>{{ errorMessage }}</p></div><el-button data-testid="retry-job" :icon="Refresh" @click="loadSnapshot(true)">重新加载</el-button>
    </section>
    <template v-else>
      <el-alert v-if="resumeError" class="execution-notice" data-testid="resume-error" :title="resumeError" type="error" show-icon :closable="false" />
      <section v-if="job.source_job_id" class="job-lineage execution-notice" :aria-label="`${retryKind}任务来源`">
        <div><strong>此任务由任务 #{{ job.source_job_id }} {{ retryKind }}创建</strong><p>来源任务保持只读，可返回查看原失败现场。</p></div>
        <RouterLink class="el-button" :to="sourceJobRoute">查看来源任务</RouterLink>
      </section>
      <div class="execution-layout">
        <aside class="execution-stage-panel">
          <div class="panel-heading execution-stage-heading visually-hidden"><h2>{{ jobTypeLabel }}部署单元</h2><span>{{ deploymentUnits.length }} 个单元 · {{ stages.length }} 个步骤</span></div>
          <div class="execution-stage-scroll" role="region" aria-label="部署步骤，可滚动查看" tabindex="0">
          <DeploymentUnitList :units="deploymentUnits" :selected-id="selectedStageId" :aria-label="`${jobTypeLabel}部署单元`" @select="selectStage" />
          <div v-if="!deploymentUnits.length" class="execution-empty" role="status">暂未生成部署步骤。</div>
          </div>
          <div class="execution-stage-footer">
            <RouterLink v-if="job.cluster_id" class="back-link" :to="clusterRoute"><ArrowLeft aria-hidden="true" />返回安装概览</RouterLink>
            <small>{{ runModeLabel }}</small>
          </div>
        </aside>
        <section class="execution-detail" aria-label="执行详情">
          <div class="execution-node-heading">
            <h2>节点执行情况</h2>
            <el-button v-if="job.status === 'failed'" class="locate-failure-button" data-testid="locate-failure" link type="danger" @click="locateFailure">定位失败位置</el-button>
            <span class="execution-updated">{{ updatedAt ? `更新于 ${updatedAt}` : '等待更新' }}</span>
          </div>
          <NodeExecutionTable :nodes="visibleNodes" :node-details="nodeDetails" :selected-node-id="selectedNodeId" @select="selectNode" />
          <LiveLogViewer :logs="filteredLogs" :connected="connected" :terminal="terminal">
            <template #tools>
              <el-select v-model="selectedNodeId" class="log-node-filter" filterable :placeholder="`全部节点（${nodeOptions.length} 台）`" aria-label="按节点筛选">
                <el-option :label="`全部节点（${nodeOptions.length} 台）`" value="" />
                <el-option v-for="node in nodeOptions" :key="node.node_id" :label="node.hostname" :value="node.node_id" />
              </el-select>
              <el-select v-model="selectedStageId" placeholder="全部步骤" aria-label="按步骤筛选" @change="selectedNodeId = ''"><el-option label="全部步骤" value="" /><el-option v-for="stage in stages" :key="stage.id" :label="stage.name" :value="stage.id" /></el-select>
              <el-button data-testid="refresh-job-snapshot" :icon="Refresh" aria-label="刷新任务快照" title="刷新快照" @click="loadSnapshot(true)" />
            </template>
          </LiveLogViewer>
        </section>
      </div>
    </template>
  </section>
</template>

<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { ArrowLeft, Refresh, WarningFilled } from '@element-plus/icons-vue';
import { RouterLink, useRoute, useRouter } from 'vue-router';
import DeploymentUnitList from '../components/jobs/DeploymentUnitList.vue';
import NodeExecutionTable from '../components/jobs/NodeExecutionTable.vue';
import LiveLogViewer from '../components/jobs/LiveLogViewer.vue';
import StepStatusIcon from '../components/jobs/StepStatusIcon.vue';
import { groupDeploymentUnits } from '../components/jobs/deploymentUnits';
import { canResumeJob, executionStatusTone, isTerminalJob, jobStatusLabel } from '../components/jobs/jobStatus';
import { getCluster, getClusterJob, getJob, getJobLogs, getJobSteps, listNodes, resumeInstallJob, rerunInstallJob } from '../api/client';
import { safeErrorMessage } from '../utils/redaction';

const route = useRoute();
const router = useRouter();
const job = ref({}); const cluster = ref({}); const stages = ref([]); const logs = ref([]);
const loading = ref(true); const connected = ref(false); const errorMessage = ref('');
const retryMode = ref(''); const resumeError = ref('');
const selectedStageId = ref(''); const selectedNodeId = ref('');
const nodeDetails = ref([]); const updatedAt = ref('');
let eventSource; let logId = 0; let loadSequence = 0;

const terminal = computed(() => isTerminalJob(job.value.status));
const completedSteps = computed(() => stages.value.filter((stage) => ['success', 'skipped'].includes(stage.status)).length);
const progress = computed(() => stages.value.length ? Math.round(completedSteps.value / stages.value.length * 100) : 0);
const deploymentUnits = computed(() => groupDeploymentUnits(stages.value));
const statusTone = computed(() => executionStatusTone(job.value.status));
const progressState = computed(() => ['failed', 'interrupted'].includes(job.value.status)
  ? 'exception' : ['success', 'partial_success'].includes(job.value.status) ? 'success' : undefined);
const clusterRoute = computed(() => ({ name: 'install-overview', params: { clusterId: String(job.value.cluster_id) } }));
const sourceJobRoute = computed(() => ({ name: 'cluster-job-execution', params: {
  clusterId: String(job.value.cluster_id), jobId: String(job.value.source_job_id)
} }));
const resumeAvailable = computed(() => canResumeJob(job.value));
const retrying = computed(() => Boolean(retryMode.value));
const retryKind = computed(() => job.value.run_mode === 'rerun' ? '全量重跑' : '断点续跑');
const runModeLabel = computed(() => ['resume', 'rerun'].includes(job.value.run_mode)
  ? `${retryKind.value}任务${job.value.source_job_id ? ` · 来源 #${job.value.source_job_id}` : ''}`
  : '正常执行');
const jobTypeLabel = computed(() => ({ install: '安装', component_install: '组件补装', reset: '重置', precheck: '预检查' }[job.value.job_type] || '集群'));
const currentStatusLabel = computed(() => job.value.status === 'running' ? `正在${jobTypeLabel.value}` : `${jobTypeLabel.value}${jobStatusLabel(job.value.status)}`);
const selectedStage = computed(() => stages.value.find((stage) => stage.id === selectedStageId.value));
const visibleNodes = computed(() => selectedStage.value?.nodes || stages.value.flatMap((stage) => stage.nodes || []));
const nodeOptions = computed(() => {
  const map = new Map();
  stages.value.flatMap((stage) => stage.nodes || []).forEach((node) => { if (!map.has(node.node_id)) map.set(node.node_id, node); });
  return [...map.values()];
});
const filteredLogs = computed(() => logs.value.filter((entry) =>
  (!selectedStageId.value || !entry.stage_id || entry.stage_id === selectedStageId.value)
  && (!selectedNodeId.value || !entry.node_id || entry.node_id === selectedNodeId.value)));

onMounted(() => loadSnapshot(true));
watch(() => route.params.jobId, () => {
  selectedStageId.value = '';
  selectedNodeId.value = '';
  stages.value = [];
  logs.value = [];
  job.value = {};
  resumeError.value = '';
  loadSnapshot(true);
});
onBeforeUnmount(disconnect);
function items(payload) { return Array.isArray(payload) ? payload : payload?.items || []; }

async function loadSnapshot(reconnect) {
  const sequence = ++loadSequence;
  const requestedJobId = String(route.params.jobId);
  if (loading.value && !reconnect) return;
  if (reconnect) disconnect();
  loading.value = !job.value.id; errorMessage.value = '';
  try {
    const jobPayload = route.params.clusterId
      ? await getClusterJob(route.params.clusterId, route.params.jobId)
      : await getJob(route.params.jobId);
    if (sequence !== loadSequence || requestedJobId !== String(route.params.jobId)) return;
    const loadedJob = jobPayload?.data || jobPayload;
    if (!route.params.clusterId) {
      await router.replace({ name: 'cluster-job-execution', params: {
        clusterId: String(loadedJob.cluster_id), jobId: requestedJobId
      } });
      return;
    }
    const [clusterPayload, stepPayload, logPayload, nodePayload] = await Promise.all([
      getCluster(loadedJob.cluster_id), getJobSteps(requestedJobId), loadLogs(requestedJobId),
      listNodes(loadedJob.cluster_id).catch(() => ({ items: [] }))
    ]);
    if (sequence !== loadSequence || requestedJobId !== String(route.params.jobId)) return;
    job.value = loadedJob;
    cluster.value = clusterPayload?.data || clusterPayload;
    stages.value = normalizeStages(items(stepPayload).sort((a, b) => a.order - b.order));
    logs.value = normalizeLogs(logPayload);
    nodeDetails.value = items(nodePayload);
    updatedAt.value = new Date().toLocaleTimeString('zh-CN', { hour12: false });
    if (!selectedStageId.value) selectedStageId.value = (stages.value.find((stage) => ['running', 'failed', 'interrupted'].includes(stage.status)) || stages.value[0])?.id || '';
    if (reconnect && !isTerminalJob(job.value.status)) connect();
  } catch (error) { errorMessage.value = safeErrorMessage(error, '安装任务加载失败，请重试。'); }
  finally { if (sequence === loadSequence) loading.value = false; }
}

async function loadLogs(jobId = route.params.jobId) {
  try { return await getJobLogs(jobId); }
  catch (error) { if (error?.status === 404) return { items: [] }; throw error; }
}
function normalizeLogs(payload) { return items(payload).map((entry) => ({ id: entry.id || `snapshot-${++logId}`, message: entry.message || entry.content || '', ...entry })); }
function normalizeStages(values) {
  if (job.value.status !== 'interrupted') return values;
  return values.map((stage) => ({
    ...stage,
    status: stage.status === 'running' ? 'interrupted' : stage.status,
    nodes: (stage.nodes || []).map((node) => ({
      ...node,
      status: node.status === 'running' ? 'interrupted' : node.status
    }))
  }));
}
function connect() {
  disconnect();
  const subscribedJobId = String(route.params.jobId);
  eventSource = new EventSource(`/api/jobs/${subscribedJobId}/events`); connected.value = true;
  eventSource.onopen = () => { connected.value = true; };
  ['job.status', 'step.status', 'node.status', 'log'].forEach((type) => eventSource.addEventListener(
    type, (event) => handleEvent(type, event, subscribedJobId)
  ));
  eventSource.onerror = () => { connected.value = false; };
}
async function handleEvent(type, event, subscribedJobId) {
  if (subscribedJobId !== String(route.params.jobId)) return;
  const payload = parseEvent(event);
  updatedAt.value = new Date().toLocaleTimeString('zh-CN', { hour12: false });
  appendEventLog(type, payload);
  if (type === 'job.status') job.value.status = payload.status || job.value.status;
  if (type === 'step.status') { const stage = stages.value.find((item) => item.id === Number(payload.step_id)); if (stage) stage.status = payload.status; }
  if (type === 'node.status') {
    const stage = stages.value.find((item) => item.status === 'running');
    const node = (stage?.nodes || []).find((item) => item.node_id === Number(payload.node_id));
    if (node) Object.assign(node, { status: payload.status, message: payload.message || node.message, exit_code: payload.exit_code ?? node.exit_code });
  }
  if (type === 'job.status' && isTerminalJob(payload.status)) { connected.value = false; disconnect(); await loadSnapshot(false); }
}
function appendEventLog(type, payload) {
  if (!payload.message && type !== 'job.status') return;
  const activeStageId = stages.value.find((stage) => stage.status === 'running')?.id || '';
  logs.value.push({ id: `event-${++logId}`, created_at: new Date().toISOString(), message: safeErrorMessage({ message: payload.message || `任务状态：${jobStatusLabel(payload.status)}` }), stage_id: Number(payload.step_id) || activeStageId, node_id: Number(payload.node_id) || '', hostname: payload.hostname || '' });
  if (logs.value.length > 1000) logs.value = logs.value.slice(-1000);
}
function parseEvent(event) { try { const parsed = JSON.parse(event.data); return parsed.payload || parsed; } catch (error) { return {}; } }
function disconnect() { eventSource?.close(); eventSource = null; connected.value = false; }
function selectStage(id) { selectedStageId.value = id; selectedNodeId.value = ''; }
function selectNode(nodeId) { selectedNodeId.value = nodeId; }
function locateFailure() {
  const stage = stages.value.find((item) => item.status === 'failed' || (item.nodes || []).some((node) => node.status === 'failed'));
  if (!stage) return; selectedStageId.value = stage.id;
  const node = (stage.nodes || []).find((item) => item.status === 'failed'); selectedNodeId.value = node?.node_id || '';
}
async function retryJob(mode) {
  if (!resumeAvailable.value || retrying.value) return;
  const sourceJobId = job.value.id;
  const clusterId = job.value.cluster_id;
  const label = mode === 'rerun' ? '全量重跑' : '断点续跑';
  retryMode.value = mode;
  resumeError.value = '';
  try {
    const submit = mode === 'rerun' ? rerunInstallJob : resumeInstallJob;
    const accepted = await submit(clusterId, sourceJobId);
    if (String(route.params.jobId) !== String(sourceJobId)) return;
    const newJobId = accepted?.job_id || accepted?.id;
    if (!newJobId) throw new Error(`${label}请求已接受，但未返回新任务编号。`);
    await router.push({ name: 'cluster-job-execution', params: {
      clusterId: String(clusterId), jobId: String(newJobId)
    } });
  } catch (error) {
    if (String(route.params.jobId) === String(sourceJobId)) {
      resumeError.value = safeErrorMessage(error, `${label}任务创建失败，请核对任务状态和集群配置。`);
    }
  } finally {
    retryMode.value = '';
  }
}
</script>
