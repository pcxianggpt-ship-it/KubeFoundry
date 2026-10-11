<template>
  <section class="kubemate-components-view">
    <div class="section-heading">
      <div>
        <p class="section-kicker">03 / Kubemate 组件</p>
        <h2>Kubemate 组件配置</h2>
        <p class="component-stage-intro">选择要在 Kubernetes 基础安装后部署的组件组。</p>
      </div>
      <el-button
        data-testid="save-components"
        type="primary"
        :icon="Check"
        :disabled="locked || loading || saving || nfsInvalid || minioInvalid || redisInvalid"
        :loading="saving"
        @click="save"
      >保存并下一步</el-button>
    </div>

    <el-skeleton v-if="loading" class="component-skeleton" :rows="8" animated aria-label="正在加载组件配置" />

    <section v-else-if="errorMessage" class="inline-error" role="alert">
      <span>{{ errorMessage }}</span>
      <el-button :icon="Refresh" @click="load">重新加载</el-button>
    </section>

    <template v-else>
      <el-alert
        v-if="locked"
        class="configuration-lock-alert"
        title="集群配置已锁定"
        type="warning"
        show-icon
        :closable="false"
      >安装任务进行中或集群已安装，组件配置当前只读。</el-alert>

      <ul class="component-group-list" aria-label="Kubemate 组件组">
        <li v-for="group in groups" :key="group.key" class="component-group" :class="{ 'is-unavailable': !group.available }">
          <div class="component-group__header">
            <div class="component-group__identity">
              <div class="component-group__title-line">
                <h3>{{ group.name }}</h3>
                <el-tag size="small" :type="statusType(group.status)">{{ statusLabel(group.status) }}</el-tag>
              </div>
              <p>{{ group.components.map(componentLabel).join('、') }}</p>
              <small v-if="!group.available">脚本待完善，当前版本不可安装。</small>
            </div>
            <el-switch
              v-model="group.enabled"
              :data-testid="`group-switch-${group.key}`"
              :aria-label="`启用 ${group.name}`"
              :disabled="groupReadOnly(group)"
              @change="enabled => initializeNfs(group, enabled)"
            />
          </div>

          <el-form
            v-if="group.key === 'nfs' && group.enabled"
            class="component-nfs-form"
            label-position="top"
            @submit.prevent
          >
            <div class="form-grid">
              <el-form-item class="component-nfs-location" label="NFS 服务器位置" required>
                <el-radio-group v-model="group.config.exports_mode" data-testid="nfs-server-location" :disabled="groupReadOnly(group)" @change="group.config.server_address = ''">
                  <el-radio-button value="managed">集群内部</el-radio-button>
                  <el-radio-button value="external">集群外部</el-radio-button>
                </el-radio-group>
              </el-form-item>
              <el-form-item v-if="group.config.exports_mode === 'managed'" label="NFS 服务器节点" required>
                <el-select v-model="group.config.server_address" data-testid="nfs-server-node" filterable placeholder="请选择集群节点" aria-label="NFS 服务器节点" :disabled="groupReadOnly(group) || nodesLoading || Boolean(nodesError)">
                  <el-option v-for="node in selectableNodes" :key="node.id" :value="node.ip" :label="`${node.hostname}（${node.ip}）`" />
                </el-select>
                <span v-if="nodesError" class="form-error">{{ nodesError }} <el-button link type="primary" :disabled="nodesLoading" @click="loadNodes">重试</el-button></span>
                <span v-else-if="!nodesLoading && !selectableNodes.length" class="field-hint">请先在服务器节点页面添加并保存节点。</span>
              </el-form-item>
              <el-form-item v-else label="NFS 服务器 IP" required>
                <el-input v-model="group.config.server_address" data-testid="nfs-server-ip" placeholder="例如 10.0.0.10" :disabled="groupReadOnly(group)" />
              </el-form-item>
              <el-form-item label="共享目录" required>
                <el-input v-model="group.config.share_path" data-testid="nfs-share-path" :placeholder="defaultNfsRoot" :disabled="groupReadOnly(group)" />
              </el-form-item>
              <el-form-item label="Worker 挂载目录" required>
                <el-input v-model="group.config.worker_mount_path" data-testid="nfs-mount-path" :placeholder="defaultNfsRoot" :disabled="groupReadOnly(group)" />
              </el-form-item>
              <el-form-item label="StorageClass 名称" required>
                <el-input v-model="group.config.storage_class" data-testid="nfs-storage-class" placeholder="nfs-storage" :disabled="groupReadOnly(group)" />
              </el-form-item>
            </div>
            <p v-if="nfsInvalid" class="form-error">启用 NFS 前，请填写完整且有效的 NFS 配置。</p>
          </el-form>

          <MinioResourceForm
            v-if="group.key === 'storage_observability' && group.enabled"
            :config="group.config"
            :errors="minioErrors"
            :disabled="groupReadOnly(group)"
          />
          <RedisPasswordForm
            v-if="group.key === 'redis_sentinel' && group.enabled"
            :config="group.config"
            :disabled="groupReadOnly(group)"
          />
        </li>
      </ul>
    </template>
  </section>
</template>

<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { Check, Refresh } from '@element-plus/icons-vue';
import { listComponents, listNodes, updateComponents } from '../api/client';
import { safeErrorMessage } from '../utils/redaction';
import MinioResourceForm from '../components/minio/MinioResourceForm.vue';
import { minioConfigErrors, normalizeMinioConfig } from '../components/minio/minioConfig';
import RedisPasswordForm from '../components/redis/RedisPasswordForm.vue';
import { redisPasswordError } from '../components/redis/redisConfig';

const props = defineProps({
  clusterId: { type: [String, Number], required: true },
  kubernetesWorkDir: { type: String, default: '/data/k8s_install' },
  locked: Boolean
});
const emit = defineEmits(['next']);
const groups = ref([]);
const loading = ref(true);
const saving = ref(false);
const errorMessage = ref('');
const nodes = ref([]);
const nodesLoading = ref(false);
const nodesError = ref('');
let loadSequence = 0;
let nodesSequence = 0;
const selectableNodes = computed(() => nodes.value.filter(node => !node.is_draft && node.ip));
const defaultNfsRoot = computed(() => `${(props.kubernetesWorkDir || '/data/k8s_install').replace(/\/+$/, '')}/nfs_root`);

const nfsGroup = computed(() => groups.value.find((group) => group.key === 'nfs'));
const nfsInvalid = computed(() => {
  const group = nfsGroup.value;
  if (!group?.enabled) return false;
  const config = group.config || {};
  return invalidNfsConfig(config)
    || (config.exports_mode === 'managed' && (nodesLoading.value || Boolean(nodesError.value)
      || !selectableNodes.value.some(node => node.ip === config.server_address)));
});
const minioGroup = computed(() => groups.value.find((group) => group.key === 'storage_observability'));
const minioErrors = computed(() => minioGroup.value?.enabled
  ? minioConfigErrors(minioGroup.value.config) : {});
const minioInvalid = computed(() => Object.keys(minioErrors.value).length > 0);
const redisInvalid = computed(() => groups.value.some(group => group.key === 'redis_sentinel'
  && group.enabled && Boolean(redisPasswordError(group.config))));

onMounted(load);
watch(() => props.clusterId, load);

async function load() {
  const sequence = ++loadSequence;
  loading.value = true;
  errorMessage.value = '';
  const nodeLoad = loadNodes();
  try {
    const payload = await listComponents(props.clusterId);
    if (sequence === loadSequence) groups.value = (payload?.groups || []).map(normalizeGroup);
  } catch (error) {
    if (sequence === loadSequence) errorMessage.value = safeErrorMessage(error, '组件配置加载失败，请重新加载。');
  } finally {
    await nodeLoad;
    if (sequence === loadSequence) loading.value = false;
  }
}

async function loadNodes() {
  const sequence = ++nodesSequence;
  nodesLoading.value = true;
  nodesError.value = '';
  nodes.value = [];
  try {
    const payload = await listNodes(props.clusterId);
    if (sequence === nodesSequence) nodes.value = Array.isArray(payload) ? payload : payload?.items || [];
  } catch (error) {
    if (sequence === nodesSequence) nodesError.value = safeErrorMessage(error, '集群节点加载失败，请重试。');
  } finally {
    if (sequence === nodesSequence) nodesLoading.value = false;
  }
}

function initializeNfs(group, enabled) {
  if (group.key !== 'nfs' || !enabled) return;
  group.config = {
    server_address: '', share_path: defaultNfsRoot.value, worker_mount_path: defaultNfsRoot.value,
    storage_class: 'nfs-storage', exports_mode: 'managed', ...group.config
  };
}

async function save() {
  if (props.locked || saving.value || nfsInvalid.value || minioInvalid.value || redisInvalid.value) return;
  saving.value = true;
  errorMessage.value = '';
  try {
    const saved = await updateComponents(props.clusterId, {
      groups: groups.value.map((group) => ({
        key: group.key,
        enabled: group.enabled,
        config: configurationForSave(group)
      }))
    });
    groups.value = (saved?.groups || groups.value).map(normalizeGroup);
    emit('next');
  } catch (error) {
    errorMessage.value = safeErrorMessage(error, '组件配置保存失败，请检查输入后重试。');
  } finally {
    saving.value = false;
  }
}

function configurationForSave(group) {
  if (group.key === 'nfs' && !group.enabled && invalidNfsConfig(group.config)) return {};
  if (group.key === 'redis_sentinel' && !group.enabled && redisPasswordError(group.config)) {
    return { has_password: Boolean(group.config.has_password) };
  }
  return group.config;
}

function normalizeGroup(group) {
  const config = group.key === 'redis_sentinel'
    ? { has_password: Boolean(group.config?.has_password), password: '' }
    : group.key === 'storage_observability'
    ? normalizeMinioConfig(group.config) : { ...(group.config || {}) };
  const normalized = {
    ...group,
    enabled: Boolean(group.enabled),
    components: Array.isArray(group.components) ? group.components : [],
    config
  };
  initializeNfs(normalized, normalized.enabled);
  return normalized;
}

function groupReadOnly(group) {
  return props.locked || !group.available || ['installed', 'installing'].includes(group.status);
}

function invalidNfsConfig(config) {
  return !isIpv4(config.server_address) || !isSafePath(config.share_path)
    || !isSafePath(config.worker_mount_path) || !isKubernetesName(config.storage_class)
    || !['managed', 'external'].includes(config.exports_mode);
}

function statusLabel(status) {
  return {
    not_installed: '未安装', installing: '安装中', installed: '已安装', failed: '安装失败'
  }[status] || '未知状态';
}

function statusType(status) {
  return { installed: 'success', installing: 'warning', failed: 'danger' }[status] || 'info';
}

function componentLabel(component) {
  return {
    nfs_exports: 'NFS exports', nfs_provisioner: 'NFS Provisioner', worker_mount: 'Worker 挂载',
    kubemate_ui: 'Kubemate UI', metrics_server: 'Metrics Server', redis_sentinel: 'Redis Sentinel',
    openebs: 'OpenEBS', minio: 'MinIO', loki: 'Loki', alloy: 'Alloy', traefik: 'Traefik', prometheus: 'Prometheus'
  }[component] || component;
}

function isIpv4(value) {
  if (typeof value !== 'string') return false;
  const parts = value.split('.');
  return parts.length === 4 && parts.every((part) => /^\d{1,3}$/.test(part) && Number(part) <= 255);
}

function isSafePath(value) {
  return typeof value === 'string' && value.startsWith('/') && !value.includes('//')
    && !value.split('/').some((part) => part === '.' || part === '..');
}

function isKubernetesName(value) {
  return typeof value === 'string' && /^[a-z0-9](?:[-a-z0-9]*[a-z0-9])?$/.test(value) && value.length <= 63;
}
</script>
