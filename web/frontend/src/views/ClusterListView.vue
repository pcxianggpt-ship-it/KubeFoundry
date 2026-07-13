<template>
  <section class="page-view cluster-list-view">
    <header class="page-header">
      <div>
        <p class="page-eyebrow">集群部署</p>
        <h1>集群部署</h1>
        <p>查看部署状态并继续当前最需要处理的阶段。</p>
      </div>
      <div class="page-actions">
        <el-button
          data-testid="refresh-clusters"
          :icon="Refresh"
          :loading="loading"
          @click="loadClusters"
        >
          刷新
        </el-button>
        <RouterLink
          data-testid="create-cluster"
          class="el-button el-button--primary"
          :class="{ 'is-disabled': loading }"
          :aria-disabled="String(loading)"
          :tabindex="loading ? -1 : undefined"
          :to="{ name: 'cluster-workspace', params: { clusterId: 'new', stage: 'cluster-info' } }"
          @click="loading && $event.preventDefault()"
        >
          <Plus aria-hidden="true" />
          新建集群
        </RouterLink>
      </div>
    </header>

    <section v-if="loading" class="cluster-list-loading" aria-busy="true" aria-label="正在加载集群">
      <el-skeleton :rows="4" animated />
    </section>

    <section v-else-if="errorMessage" class="state-panel state-panel--error" role="alert">
      <WarningFilled aria-hidden="true" />
      <div>
        <h2>集群加载失败</h2>
        <p>{{ errorMessage }}</p>
      </div>
      <el-button data-testid="retry-clusters" :icon="Refresh" @click="loadClusters">重新加载</el-button>
    </section>

    <section v-else-if="clusters.length === 0" class="state-panel state-panel--empty" role="status">
      <Box aria-hidden="true" />
      <div>
        <h2>还没有集群</h2>
        <p>创建首个集群后，部署状态和下一步操作会显示在这里。</p>
      </div>
    </section>

    <div v-else class="cluster-table-wrap">
      <table class="cluster-table">
        <thead>
          <tr>
            <th scope="col">集群</th>
            <th scope="col">Kubernetes</th>
            <th scope="col">节点</th>
            <th scope="col">部署状态</th>
            <th scope="col">更新时间</th>
            <th scope="col"><span class="visually-hidden">操作</span></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="cluster in clusters" :key="cluster.id" class="cluster-row">
            <td>
              <RouterLink
                class="cluster-name"
                :to="workspaceRoute(cluster, 'cluster-info')"
              >
                {{ cluster.name || `集群 ${cluster.id}` }}
              </RouterLink>
              <small>{{ cluster.description || '未填写说明' }}</small>
            </td>
            <td>{{ cluster.k8s_version || '-' }}</td>
            <td>{{ cluster.node_count ?? '-' }}</td>
            <td>
              <span class="status-label" :class="`status-label--${presentation(cluster).tone}`">
                <component :is="presentation(cluster).icon" aria-hidden="true" />
                {{ presentation(cluster).statusText }}
              </span>
            </td>
            <td>{{ formatUpdatedAt(cluster.updated_at) }}</td>
            <td class="cluster-row__action-cell">
              <RouterLink
                v-if="presentation(cluster).to"
                class="cluster-row__action"
                :to="presentation(cluster).to"
              >
                {{ presentation(cluster).actionText }}
                <ArrowRight aria-hidden="true" />
              </RouterLink>
              <span
                v-else
                class="cluster-row__action is-disabled"
                aria-disabled="true"
                title="当前任务信息尚未就绪"
              >
                {{ presentation(cluster).actionText }}
              </span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>
</template>

<script setup>
import { onMounted, ref } from 'vue';
import { RouterLink } from 'vue-router';
import {
  ArrowRight,
  Box,
  CircleCheckFilled,
  Clock,
  EditPen,
  Plus,
  Refresh,
  WarningFilled
} from '@element-plus/icons-vue';

import { listClusters, listJobs } from '../api/client';
import { safeErrorMessage } from '../utils/redaction';

const validStages = new Set(['cluster-info', 'nodes', 'settings', 'precheck', 'install']);
const clusters = ref([]);
const loading = ref(true);
const errorMessage = ref('');

onMounted(loadClusters);

function normalizeList(payload) {
  if (Array.isArray(payload)) return payload;
  if (payload && Array.isArray(payload.items)) return payload.items;
  if (payload && Array.isArray(payload.data)) return payload.data;
  return [];
}

async function loadClusters() {
  loading.value = true;
  errorMessage.value = '';
  try {
    const listed = normalizeList(await listClusters());
    clusters.value = await Promise.all(listed.map(enrichClusterStatus));
  } catch (error) {
    clusters.value = [];
    errorMessage.value = safeErrorMessage(error);
  } finally {
    loading.value = false;
  }
}

async function enrichClusterStatus(cluster) {
  try {
    const jobs = normalizeList(await listJobs(cluster.id))
      .slice()
      .sort((left, right) => Number(right.id || 0) - Number(left.id || 0));
    const install = jobs.find((job) => job.job_type === 'install');
    if (install) {
      if (['pending', 'running'].includes(install.status)) {
        return { ...cluster, status: 'installing', active_job_id: install.id };
      }
      if (['failed', 'interrupted', 'canceled'].includes(install.status)) {
        return { ...cluster, status: 'install_failed', latest_job_id: install.id };
      }
      if (install.status === 'success') {
        return { ...cluster, status: 'installed', latest_job_id: install.id };
      }
    }
    const precheck = jobs.find((job) => job.job_type === 'precheck');
    if (precheck?.status === 'success') {
      return { ...cluster, status: 'precheck_passed', latest_job_id: precheck.id };
    }
  } catch (error) {
    // Keep the cluster list usable if historical task lookup is temporarily unavailable.
  }
  return cluster;
}

function workspaceRoute(cluster, fallbackStage) {
  const requestedStage = cluster.current_stage;
  const stage = validStages.has(requestedStage) ? requestedStage : fallbackStage;
  return {
    name: 'cluster-workspace',
    params: { clusterId: String(cluster.id), stage }
  };
}

function fixedWorkspaceRoute(cluster, stage) {
  return {
    name: 'cluster-workspace',
    params: { clusterId: String(cluster.id), stage }
  };
}

function jobRoute(cluster) {
  const jobId = cluster.active_job_id ?? cluster.latest_job_id ?? cluster.job_id;
  if (jobId === undefined || jobId === null || jobId === '') return null;
  return { name: 'job-execution', params: { jobId: String(jobId) } };
}

function presentation(cluster) {
  const status = cluster.status || 'draft';
  if (['precheck_passed', 'precheck_success'].includes(status)) {
    return {
      actionText: '开始安装',
      icon: CircleCheckFilled,
      statusText: '预检查通过',
      tone: 'ready',
      to: fixedWorkspaceRoute(cluster, 'install')
    };
  }
  if (['installing', 'running'].includes(status)) {
    return {
      actionText: '查看进度',
      icon: Clock,
      statusText: '正在安装',
      tone: 'running',
      to: jobRoute(cluster)
    };
  }
  if (['install_failed', 'failed'].includes(status)) {
    return {
      actionText: '查看失败原因',
      icon: WarningFilled,
      statusText: '安装失败',
      tone: 'error',
      to: jobRoute(cluster)
    };
  }
  if (['installed', 'success'].includes(status)) {
    return {
      actionText: '查看集群',
      icon: CircleCheckFilled,
      statusText: '安装成功',
      tone: 'success',
      to: fixedWorkspaceRoute(cluster, 'cluster-info')
    };
  }
  return {
    actionText: '继续配置',
    icon: EditPen,
    statusText: '配置未完成',
    tone: 'incomplete',
    to: workspaceRoute(cluster, 'cluster-info')
  };
}

function formatUpdatedAt(value) {
  if (!value) return '-';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '-';
  return new Intl.DateTimeFormat('zh-CN', {
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false
  }).format(date);
}
</script>
