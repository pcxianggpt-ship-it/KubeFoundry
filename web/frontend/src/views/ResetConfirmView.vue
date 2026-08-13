<template>
  <section class="page-view reset-confirm-view">
    <header class="workspace-header">
      <div>
        <RouterLink class="back-link" :to="overviewRoute"><ArrowLeft aria-hidden="true" />返回安装概览</RouterLink>
        <p class="page-eyebrow">远程重置</p>
        <h1>确认清理 {{ cluster?.name || '集群' }}</h1>
      </div>
    </header>

    <el-skeleton v-if="loading" :rows="7" animated aria-label="正在加载重置范围" />
    <section v-else-if="errorMessage && !cluster" class="state-panel state-panel--error" role="alert">
      <WarningFilled aria-hidden="true" />
      <div><h2>重置范围加载失败</h2><p>{{ errorMessage }}</p></div>
      <el-button :icon="Refresh" @click="load">重新加载</el-button>
    </section>
    <template v-else-if="cluster">
      <el-alert title="远程重置不可恢复" type="error" show-icon :closable="false">
        <template #default>将清理 KubeFoundry 管理的 Kubernetes 数据、网络配置及 Registry 容器。集群配置和任务历史会保留。</template>
      </el-alert>
      <section class="reset-scope" aria-label="远程重置范围">
        <div><h2>目标节点</h2><ul><li v-for="node in nodes" :key="node.id"><strong>{{ node.hostname }}</strong><span>{{ roleLabel(node.roles) }}</span></li></ul></div>
        <div><h2>受管清理目录</h2><ul><li>{{ cluster.kubernetes_work_dir }}/kubelet_root</li><li>{{ cluster.kubernetes_work_dir }}/etcd_root</li><li>{{ cluster.kubernetes_work_dir }}/containerd_root</li><li v-if="hasRegistry">{{ cluster.kubernetes_work_dir }}/04.registry</li></ul></div>
      </section>
      <section class="reset-confirmation" aria-labelledby="reset-confirmation-title">
        <h2 id="reset-confirmation-title">强确认</h2>
        <el-checkbox v-model="acknowledged">我已了解远程集群数据将被清理</el-checkbox>
        <el-form-item :label="`请输入 ${expectedPhrase} 继续`">
          <el-input v-model="confirmationPhrase" :placeholder="expectedPhrase" autocomplete="off" />
        </el-form-item>
        <p v-if="errorMessage" class="form-error" role="alert">{{ errorMessage }}</p>
        <div class="section-actions">
          <RouterLink class="el-button" :to="overviewRoute">取消</RouterLink>
          <el-button type="danger" :loading="submitting" :disabled="!canSubmit" @click="submit">创建重置任务</el-button>
        </div>
      </section>
    </template>
  </section>
</template>

<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { ArrowLeft, Refresh, WarningFilled } from '@element-plus/icons-vue';
import { RouterLink, useRoute, useRouter } from 'vue-router';
import { getCluster, listNodes, resetCluster } from '../api/client';
import { safeErrorMessage } from '../utils/redaction';

const route = useRoute();
const router = useRouter();
const cluster = ref(null);
const nodes = ref([]);
const loading = ref(true);
const submitting = ref(false);
const acknowledged = ref(false);
const confirmationPhrase = ref('');
const errorMessage = ref('');
const clusterId = computed(() => String(route.params.clusterId));
const expectedPhrase = computed(() => `RESET ${cluster.value?.name || ''}`.trim());
const canSubmit = computed(() => acknowledged.value && confirmationPhrase.value === expectedPhrase.value && !submitting.value);
const hasRegistry = computed(() => nodes.value.some((node) => node.roles?.includes('registry')));
const overviewRoute = computed(() => ({ name: 'install-overview', params: { clusterId: clusterId.value } }));

onMounted(load);
watch(clusterId, load);

function items(payload) { return Array.isArray(payload) ? payload : payload?.items || []; }
function roleLabel(roles) { return (roles || []).map((role) => ({ control_plane: '控制节点', worker: '工作节点', registry: '镜像仓库' }[role] || role)).join('、'); }

async function load() {
  loading.value = true;
  errorMessage.value = '';
  try {
    const [clusterPayload, nodePayload] = await Promise.all([getCluster(clusterId.value), listNodes(clusterId.value)]);
    cluster.value = clusterPayload?.data || clusterPayload;
    nodes.value = items(nodePayload);
  } catch (error) {
    errorMessage.value = safeErrorMessage(error, '无法加载远程重置范围。');
  } finally {
    loading.value = false;
  }
}

async function submit() {
  if (!canSubmit.value) return;
  submitting.value = true;
  errorMessage.value = '';
  try {
    const accepted = await resetCluster(clusterId.value, acknowledged.value, confirmationPhrase.value);
    await router.push({ name: 'cluster-job-execution', params: { clusterId: clusterId.value, jobId: String(accepted.job_id || accepted.id) } });
  } catch (error) {
    errorMessage.value = safeErrorMessage(error, '远程重置任务创建失败。');
  } finally {
    submitting.value = false;
  }
}
</script>
