<template>
  <section class="page-view install-overview-view">
    <header class="page-header">
      <div>
        <p class="page-eyebrow">集群安装</p>
        <h1>{{ cluster?.name || '集群安装' }}</h1>
        <p>从预检查开始，确认安装范围并跟踪远程任务。</p>
      </div>
      <div class="page-actions">
        <el-button :icon="Refresh" :loading="loading" @click="load">刷新</el-button>
        <RouterLink class="el-button" :to="configRoute">查看配置</RouterLink>
      </div>
    </header>

    <el-skeleton v-if="loading" :rows="6" animated aria-label="正在加载集群安装状态" />
    <section v-else-if="errorMessage" class="state-panel state-panel--error" role="alert">
      <WarningFilled aria-hidden="true" />
      <div><h2>安装状态加载失败</h2><p>{{ errorMessage }}</p></div>
      <el-button :icon="Refresh" @click="load">重新加载</el-button>
    </section>
    <template v-else-if="cluster">
      <section class="install-overview-summary" aria-label="集群安装状态">
        <div><span>配置状态</span><strong>{{ configurationLabel }}</strong></div>
        <div><span>最近预检查</span><strong>{{ jobLabel(latestPrecheck) }}</strong></div>
        <div><span>最近安装</span><strong>{{ jobLabel(latestInstall) }}</strong></div>
        <div><span>最近重置</span><strong>{{ jobLabel(latestReset) }}</strong></div>
      </section>

      <section class="install-overview-actions" aria-label="安装操作">
        <div>
          <h2>部署预检查</h2>
          <p>检查当前节点、拓扑和离线介质后才可启动安装。</p>
          <RouterLink class="el-button el-button--primary" :to="precheckRoute">执行预检查</RouterLink>
        </div>
        <div>
          <h2>安装确认</h2>
          <p>确认固定网段、工作目录、节点角色和镜像仓库。</p>
          <RouterLink class="el-button" :class="{ 'is-disabled': !precheckPassed }" :aria-disabled="String(!precheckPassed)" :tabindex="precheckPassed ? undefined : -1" :to="confirmRoute" @click="!precheckPassed && $event.preventDefault()">进入安装确认</RouterLink>
        </div>
        <div v-if="resetAvailable">
          <h2>远程重置</h2>
          <p>清理受管 Kubernetes 数据。此操作不可恢复。</p>
          <RouterLink class="el-button el-button--danger is-plain" :to="resetRoute">开始远程重置</RouterLink>
        </div>
      </section>

      <section v-if="activeJob" class="inline-state" role="status">
        <Clock aria-hidden="true" />
        <div><strong>{{ jobTypeLabel(activeJob.job_type) }}正在执行</strong><p>页面刷新后可继续查看任务进度和日志。</p></div>
        <RouterLink class="el-button" :to="jobRoute(activeJob)">查看任务</RouterLink>
      </section>
    </template>
  </section>
</template>

<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { Clock, Refresh, WarningFilled } from '@element-plus/icons-vue';
import { RouterLink, useRoute } from 'vue-router';
import { getCluster, listJobs } from '../api/client';
import { safeErrorMessage } from '../utils/redaction';

const route = useRoute();
const cluster = ref(null);
const jobs = ref([]);
const loading = ref(true);
const errorMessage = ref('');
const clusterId = computed(() => String(route.params.clusterId));
const latestPrecheck = computed(() => latest('precheck'));
const latestInstall = computed(() => latest('install'));
const latestReset = computed(() => latest('reset'));
const precheckPassed = computed(() => latestPrecheck.value?.status === 'success');
const resetAvailable = computed(() => Boolean(cluster.value?.configuration_locked)
  && !activeJob.value && ['installed', 'reset_failed'].includes(cluster.value?.status));
const activeJob = computed(() => jobs.value.find((job) => ['install', 'reset'].includes(job.job_type)
  && ['pending', 'running'].includes(job.status)) || null);
const configurationLabel = computed(() => cluster.value?.configuration_locked ? '安装成功后已锁定' : '可编辑');
const configRoute = computed(() => ({ name: 'cluster-config-workspace', params: { clusterId: clusterId.value, stage: 'cluster-info' } }));
const precheckRoute = computed(() => ({ name: 'install-precheck', params: { clusterId: clusterId.value } }));
const confirmRoute = computed(() => ({ name: 'install-confirm', params: { clusterId: clusterId.value } }));
const resetRoute = computed(() => ({ name: 'reset-confirm', params: { clusterId: clusterId.value } }));

onMounted(load);
watch(clusterId, load);

function items(payload) { return Array.isArray(payload) ? payload : payload?.items || []; }
function latest(type) { return jobs.value.filter((job) => job.job_type === type).sort((a, b) => b.id - a.id)[0] || null; }
function jobLabel(job) { return job ? `${jobTypeLabel(job.job_type)}${statusLabel(job.status)}` : '暂无任务'; }
function jobTypeLabel(type) { return { precheck: '预检查', install: '安装', reset: '重置' }[type] || '任务'; }
function statusLabel(status) { return { pending: '等待中', running: '执行中', success: '成功', failed: '失败', interrupted: '已中断' }[status] || '未完成'; }
function jobRoute(job) { return { name: 'job-execution', params: { jobId: String(job.id) } }; }

async function load() {
  loading.value = true;
  errorMessage.value = '';
  try {
    const [clusterPayload, jobsPayload] = await Promise.all([getCluster(clusterId.value), listJobs(clusterId.value)]);
    cluster.value = clusterPayload?.data || clusterPayload;
    jobs.value = items(jobsPayload);
  } catch (error) {
    errorMessage.value = safeErrorMessage(error, '无法加载集群安装状态。');
  } finally {
    loading.value = false;
  }
}
</script>
