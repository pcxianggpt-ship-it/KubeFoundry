<template>
  <section class="page-view job-execution-view">
    <header class="workspace-header execution-header">
      <div><RouterLink v-if="job.cluster_id" class="back-link" :to="clusterRoute"><ArrowLeft />返回安装概览</RouterLink><p class="page-eyebrow">{{ jobTypeLabel }}任务 #{{ job.id || route.params.jobId }}</p><h1>{{ cluster.name || '集群任务进度' }}</h1></div>
      <span class="status-label" :class="`status-label--${statusTone}`"><component :is="statusIcon" />{{ jobStatusLabel(job.status) }}</span>
    </header>
    <el-skeleton v-if="loading" :rows="9" animated aria-label="正在恢复安装任务" />
    <section v-else-if="errorMessage" class="state-panel state-panel--error" role="alert">
      <WarningFilled /><div><h2>任务恢复失败</h2><p>{{ errorMessage }}</p></div><el-button data-testid="retry-job" :icon="Refresh" @click="loadSnapshot(true)">重新加载</el-button>
    </section>
    <template v-else>
      <section class="execution-overview">
        <div class="progress-copy"><span>整体进度</span><strong>{{ completedStages }}/{{ stages.length }} 个阶段</strong></div>
        <el-progress :percentage="progress" :status="job.status === 'failed' ? 'exception' : job.status === 'success' ? 'success' : undefined" />
        <div class="execution-meta"><span>Kubernetes {{ cluster.k8s_version || '-' }}</span><span>{{ connected ? '实时连接中' : terminal ? '任务已结束' : '实时连接已中断' }}</span></div>
      </section>
      <el-alert v-if="job.status === 'failed'" :title="`${jobTypeLabel}任务失败，可定位首个失败节点查看诊断和日志。`" type="error" show-icon :closable="false">
        <template #default><el-button data-testid="locate-failure" link type="primary" @click="locateFailure">定位失败位置</el-button></template>
      </el-alert>
      <div class="execution-layout">
        <aside class="execution-stage-panel"><div class="panel-heading"><h2>{{ jobTypeLabel }}阶段</h2><span>{{ stages.length }} 项</span></div><JobStageList :stages="stages" :selected-id="selectedStageId" @select="selectStage" /></aside>
        <main class="execution-detail">
          <div class="execution-filters">
            <el-select v-model="selectedStageId" placeholder="全部阶段" aria-label="按阶段筛选"><el-option label="全部阶段" value="" /><el-option v-for="stage in stages" :key="stage.id" :label="stage.name" :value="stage.id" /></el-select>
            <el-select v-model="selectedNodeId" placeholder="全部节点" aria-label="按节点筛选"><el-option label="全部节点" value="" /><el-option v-for="node in nodeOptions" :key="node.node_id" :label="node.hostname" :value="node.node_id" /></el-select>
            <el-button data-testid="refresh-job-snapshot" :icon="Refresh" @click="loadSnapshot(true)">刷新快照</el-button>
          </div>
          <NodeExecutionTable :nodes="visibleNodes" :selected-node-id="selectedNodeId" @select="selectNode" />
          <LiveLogViewer :logs="filteredLogs" :connected="connected" :terminal="terminal" />
        </main>
      </div>
    </template>
  </section>
</template>

<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { ArrowLeft, CircleCheckFilled, Clock, Refresh, WarningFilled } from '@element-plus/icons-vue';
import { RouterLink, useRoute } from 'vue-router';
import JobStageList from '../components/jobs/JobStageList.vue';
import NodeExecutionTable from '../components/jobs/NodeExecutionTable.vue';
import LiveLogViewer from '../components/jobs/LiveLogViewer.vue';
import { isTerminalJob, jobStatusLabel } from '../components/jobs/jobStatus';
import { getCluster, getJob, getJobLogs, getJobSteps } from '../api/client';
import { safeErrorMessage } from '../utils/redaction';

const route = useRoute();
const job = ref({}); const cluster = ref({}); const stages = ref([]); const logs = ref([]);
const loading = ref(true); const connected = ref(false); const errorMessage = ref('');
const selectedStageId = ref(''); const selectedNodeId = ref('');
let eventSource; let logId = 0;

const terminal = computed(() => isTerminalJob(job.value.status));
const completedStages = computed(() => stages.value.filter((stage) => ['success', 'skipped'].includes(stage.status)).length);
const progress = computed(() => stages.value.length ? Math.round(completedStages.value / stages.value.length * 100) : 0);
const statusTone = computed(() => job.value.status === 'success' ? 'success' : terminal.value ? 'error' : 'running');
const statusIcon = computed(() => job.value.status === 'success' ? CircleCheckFilled : terminal.value ? WarningFilled : Clock);
const clusterRoute = computed(() => ({ name: 'install-overview', params: { clusterId: String(job.value.cluster_id) } }));
const jobTypeLabel = computed(() => ({ install: '安装', reset: '重置', precheck: '预检查' }[job.value.job_type] || '集群'));
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
onBeforeUnmount(disconnect);
function items(payload) { return Array.isArray(payload) ? payload : payload?.items || []; }

async function loadSnapshot(reconnect) {
  if (loading.value && !reconnect) return;
  if (reconnect) disconnect();
  loading.value = !job.value.id; errorMessage.value = '';
  try {
    const jobPayload = await getJob(route.params.jobId);
    job.value = jobPayload?.data || jobPayload;
    const [clusterPayload, stepPayload, logPayload] = await Promise.all([
      getCluster(job.value.cluster_id), getJobSteps(route.params.jobId), loadLogs()
    ]);
    cluster.value = clusterPayload?.data || clusterPayload;
    stages.value = normalizeStages(items(stepPayload).sort((a, b) => a.order - b.order));
    logs.value = normalizeLogs(logPayload);
    if (!selectedStageId.value) selectedStageId.value = (stages.value.find((stage) => ['running', 'failed', 'interrupted'].includes(stage.status)) || stages.value[0])?.id || '';
    if (reconnect && !isTerminalJob(job.value.status)) connect();
  } catch (error) { errorMessage.value = safeErrorMessage(error, '安装任务加载失败，请重试。'); }
  finally { loading.value = false; }
}

async function loadLogs() {
  try { return await getJobLogs(route.params.jobId); }
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
  eventSource = new EventSource(`/api/jobs/${route.params.jobId}/events`); connected.value = true;
  eventSource.onopen = () => { connected.value = true; };
  ['job.status', 'step.status', 'node.status', 'log'].forEach((type) => eventSource.addEventListener(type, (event) => handleEvent(type, event)));
  eventSource.onerror = () => { connected.value = false; };
}
async function handleEvent(type, event) {
  const payload = parseEvent(event);
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
</script>
