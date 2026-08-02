<template>
  <section class="precheck-view">
    <div class="section-heading">
      <div><p class="section-kicker">04 / 部署预检查</p><h2>部署预检查</h2></div>
      <el-button
        data-testid="start-precheck"
        type="primary"
        :icon="CircleCheck"
        :loading="running"
        :disabled="loading || running"
        @click="runPrecheck"
      >开始预检查</el-button>
    </div>

    <el-skeleton v-if="loading" :rows="5" animated aria-label="正在加载预检查状态" />
    <section v-else-if="errorMessage" class="inline-error" role="alert">
      <span>{{ errorMessage }}</span><el-button :icon="Refresh" @click="loadLatest">重试</el-button>
    </section>
    <template v-else>
      <el-alert
        v-if="running"
        title="正在检查所有节点，完成后将进入安装概览"
        type="info"
        show-icon
        :closable="false"
      />
      <el-alert
        v-else-if="jobFailed"
        title="预检查任务未完成，请查看失败项或重新执行"
        type="error"
        show-icon
        :closable="false"
      />
      <el-alert
        v-else-if="failedResults.length"
        title="预检查未通过，请处理失败项后重新检查"
        type="error"
        show-icon
        :closable="false"
      />
      <div v-if="results.length" class="precheck-table-wrap">
        <table class="precheck-table">
          <thead><tr><th>节点</th><th>检查项</th><th>级别</th><th>状态</th><th>结果</th></tr></thead>
          <tbody><tr v-for="item in results" :key="item.id">
            <td><strong>{{ item.hostname }}</strong><small>{{ item.ip || '' }}</small></td>
            <td>{{ item.check_name }}</td>
            <td>{{ severityLabel(item.severity) }}</td>
            <td><el-tag :type="resultTone(item.status)" size="small">{{ resultLabel(item.status) }}</el-tag></td>
            <td>{{ item.message || item.detail || '-' }}</td>
          </tr></tbody>
        </table>
      </div>
      <div v-else class="inline-state" role="status">
        <CircleCheck aria-hidden="true" />
        <div><strong>准备执行部署预检查</strong><p>检查节点连通性、系统环境、安装介质和关键配置。</p></div>
      </div>
    </template>
  </section>
</template>

<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { CircleCheck, Refresh } from '@element-plus/icons-vue';
import { useRouter } from 'vue-router';
import { getPrecheckResults, listJobs, startPrecheck } from '../api/client';
import { isTerminalJob } from '../components/jobs/jobStatus';
import { safeErrorMessage } from '../utils/redaction';

const props = defineProps({ clusterId: { type: [String, Number], required: true } });
const router = useRouter();
const loading = ref(true);
const running = ref(false);
const jobFailed = ref(false);
const errorMessage = ref('');
const results = ref([]);
let eventSource;
let currentJobId;

const failedResults = computed(() => results.value.filter((item) => item.status === 'fail' && item.severity === 'error'));

onMounted(loadLatest);
onBeforeUnmount(disconnect);
watch(() => props.clusterId, loadLatest);

function items(payload) { return Array.isArray(payload) ? payload : payload?.items || []; }

async function loadLatest() {
  disconnect();
  loading.value = true;
  errorMessage.value = '';
  jobFailed.value = false;
  try {
    const jobs = items(await listJobs(props.clusterId));
    const latest = jobs.filter((job) => job.job_type === 'precheck').sort((a, b) => b.id - a.id)[0];
    if (!latest) { results.value = []; return; }
    currentJobId = latest.id;
    results.value = items(await getPrecheckResults(latest.id));
    if (!isTerminalJob(latest.status)) {
      running.value = true;
      connect(latest.id);
    } else {
      running.value = false;
      jobFailed.value = latest.status !== 'success';
    }
  } catch (error) {
    errorMessage.value = safeErrorMessage(error, '预检查状态加载失败，请重试。');
  } finally {
    loading.value = false;
  }
}

async function runPrecheck() {
  if (running.value) return;
  running.value = true;
  jobFailed.value = false;
  results.value = [];
  errorMessage.value = '';
  try {
    const accepted = await startPrecheck(props.clusterId);
    currentJobId = accepted.job_id || accepted.id;
    connect(currentJobId);
  } catch (error) {
    running.value = false;
    errorMessage.value = safeErrorMessage(error, '预检查启动失败，请重试。');
  }
}

function connect(jobId) {
  disconnect();
  eventSource = new EventSource(`/api/jobs/${jobId}/events`);
  eventSource.addEventListener('precheck.result', refreshResults);
  eventSource.addEventListener('job.status', handleJobStatus);
  eventSource.onerror = () => { errorMessage.value = '实时连接已中断，刷新页面可恢复任务状态。'; };
}

async function refreshResults() {
  if (!currentJobId) return;
  try { results.value = items(await getPrecheckResults(currentJobId)); } catch (error) { /* 终态时再次读取 */ }
}

async function handleJobStatus(event) {
  const payload = parseEvent(event);
  if (!isTerminalJob(payload.status)) return;
  running.value = false;
  jobFailed.value = payload.status !== 'success';
  disconnect();
  await refreshResults();
  if (payload.status === 'success') {
    await router.push({ name: 'install-confirm', params: { clusterId: String(props.clusterId) } });
  }
}

function parseEvent(event) {
  try { const parsed = JSON.parse(event.data); return parsed.payload || parsed; } catch (error) { return {}; }
}

function disconnect() { eventSource?.close(); eventSource = null; }
function resultLabel(status) { return { pass: '通过', fail: '失败', warning: '警告', success: '通过' }[status] || '待检查'; }
function resultTone(status) { return ['pass', 'success'].includes(status) ? 'success' : status === 'fail' ? 'danger' : 'warning'; }
function severityLabel(severity) { return severity === 'error' ? '阻断' : severity === 'warning' ? '警告' : '提示'; }
</script>
