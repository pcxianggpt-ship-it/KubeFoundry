<template>
  <section class="page-view install-confirm-view">
    <header class="workspace-header">
      <div><RouterLink class="back-link" :to="backRoute"><ArrowLeft />返回安装概览</RouterLink><p class="page-eyebrow">安装确认</p><h1>确认集群安装范围</h1></div>
      <span class="status-label status-label--ready"><CircleCheckFilled />预检查通过</span>
    </header>
    <el-skeleton v-if="loading" :rows="8" animated aria-label="正在加载安装确认信息" />
    <section v-else-if="errorMessage" class="state-panel state-panel--error" role="alert">
      <WarningFilled /><div><h2>确认信息加载失败</h2><p>{{ errorMessage }}</p></div><el-button :icon="Refresh" @click="load">重新加载</el-button>
    </section>
    <template v-else>
      <section class="confirm-summary" aria-label="安装目标摘要">
        <div><span>目标集群</span><strong>{{ cluster.name }}</strong></div>
        <div><span>Kubernetes 版本</span><strong>{{ cluster.k8s_version }}</strong></div>
        <div><span>服务器范围</span><strong>{{ nodes.length }} 个节点</strong></div>
        <div><span>镜像仓库</span><strong>{{ registrySummary }}</strong></div>
      </section>
      <section class="confirm-details">
        <div><h2>网络与介质</h2><dl>
          <dt>Pod 网段</dt><dd>10.244.0.0/16（固定）</dd>
          <dt>Service 网段</dt><dd>10.96.0.0/16（固定）</dd>
          <dt>Kubernetes 工作目录</dt><dd>{{ cluster.kubernetes_work_dir || '-' }}</dd>
          <dt>离线介质目录</dt><dd>{{ settings.paths?.install_media || '-' }}</dd>
        </dl></div>
        <div><h2>节点清单</h2><ul class="confirm-node-list"><li v-for="node in nodes" :key="node.id"><strong>{{ node.hostname }}</strong><span>{{ roleLabel(node.roles) }}</span><el-tag type="success" size="small">免密已验证</el-tag></li></ul></div>
      </section>
      <el-alert title="安装将修改目标服务器的软件包、网络、容器运行时和 Kubernetes 服务。任务开始后请勿关闭管理服务。" type="warning" show-icon :closable="false" />
      <footer class="confirm-actions">
        <el-checkbox data-testid="confirm-install-risk" v-model="riskConfirmed">我已核对目标集群、节点范围和关键配置</el-checkbox>
        <el-button data-testid="start-install" type="primary" :icon="VideoPlay" :loading="starting" :disabled="!riskConfirmed" @click="start">开始安装</el-button>
      </footer>
    </template>
  </section>
</template>

<script setup>
import { computed, onMounted, ref } from 'vue';
import { ArrowLeft, CircleCheckFilled, Refresh, VideoPlay, WarningFilled } from '@element-plus/icons-vue';
import { RouterLink, useRoute, useRouter } from 'vue-router';
import { getCluster, getClusterSettings, listJobs, listNodes, startInstall } from '../api/client';
import { safeErrorMessage } from '../utils/redaction';

const route = useRoute();
const router = useRouter();
const clusterId = String(route.params.clusterId);
const cluster = ref({});
const nodes = ref([]);
const settings = ref({ paths: {}, env: {}, advanced: {} });
const loading = ref(true);
const starting = ref(false);
const riskConfirmed = ref(false);
const errorMessage = ref('');
const backRoute = computed(() => ({ name: 'install-overview', params: { clusterId } }));
const registrySummary = computed(() => {
  const registry = nodes.value.find((node) => node.roles?.includes('registry'));
  return registry ? `${registry.hostname} (${registry.ip}:5000)` : '未找到 Registry 节点';
});

onMounted(load);
function items(payload) { return Array.isArray(payload) ? payload : payload?.items || []; }
async function load() {
  loading.value = true; errorMessage.value = '';
  try {
    const [clusterPayload, nodePayload, settingPayload, jobPayload] = await Promise.all([
      getCluster(clusterId), listNodes(clusterId), getClusterSettings(clusterId), listJobs(clusterId)
    ]);
    cluster.value = clusterPayload?.data || clusterPayload;
    nodes.value = items(nodePayload);
    settings.value = settingPayload || settings.value;
    const passed = items(jobPayload).some((job) => job.job_type === 'precheck' && job.status === 'success');
    if (!passed) throw new Error('未找到成功的部署预检查，请返回预检查阶段重新执行。');
  } catch (error) { errorMessage.value = safeErrorMessage(error, '安装确认信息加载失败，请重试。'); }
  finally { loading.value = false; }
}
async function start() {
  if (!riskConfirmed.value || starting.value) return;
  starting.value = true; errorMessage.value = '';
  try {
    const accepted = await startInstall(clusterId);
    await router.push({ name: 'cluster-job-execution', params: { clusterId, jobId: String(accepted.job_id || accepted.id) } });
  } catch (error) { errorMessage.value = safeErrorMessage(error, '安装任务启动失败，请检查预检查状态。'); }
  finally { starting.value = false; }
}
function roleLabel(roles) {
  return (roles || []).map((role) => ({ control_plane: '控制节点', worker: '工作节点', registry: '镜像仓库' }[role] || role)).join('、');
}
</script>
