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
        :disabled="locked || loading || saving || nfsInvalid"
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

      <section class="component-master-switch" aria-labelledby="component-master-title">
        <div>
          <h3 id="component-master-title">启用 Kubemate 组件安装</h3>
          <p>关闭后保留各组件组选择，但本次安装计划不会包含组件步骤。</p>
        </div>
        <el-switch
          v-model="enabled"
          data-testid="kubemate-enabled"
          aria-label="启用 Kubemate 组件安装"
          :disabled="locked"
        />
      </section>

      <el-alert
        v-if="!enabled"
        class="component-plan-alert"
        title="组件安装已关闭"
        type="info"
        show-icon
        :closable="false"
      >已保存的组件选择会保留，重新开启后可继续使用。</el-alert>

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
            />
          </div>

          <el-form
            v-if="group.key === 'nfs' && group.enabled"
            class="component-nfs-form"
            label-position="top"
            @submit.prevent
          >
            <div class="form-grid">
              <el-form-item label="NFS 服务器地址" required>
                <el-input v-model="group.config.server_address" placeholder="例如 10.0.0.10" :disabled="groupReadOnly(group)" />
              </el-form-item>
              <el-form-item label="共享目录" required>
                <el-input v-model="group.config.share_path" placeholder="例如 /exports/k8s" :disabled="groupReadOnly(group)" />
              </el-form-item>
              <el-form-item label="Worker 挂载目录" required>
                <el-input v-model="group.config.worker_mount_path" placeholder="例如 /data/k8s_install/nfs_root" :disabled="groupReadOnly(group)" />
              </el-form-item>
              <el-form-item label="StorageClass 名称" required>
                <el-input v-model="group.config.storage_class" placeholder="nfs-storage" :disabled="groupReadOnly(group)" />
              </el-form-item>
              <el-form-item label="exports 管理模式" required>
                <el-radio-group v-model="group.config.exports_mode" :disabled="groupReadOnly(group)">
                  <el-radio-button value="managed">受管</el-radio-button>
                  <el-radio-button value="external">外部</el-radio-button>
                </el-radio-group>
              </el-form-item>
            </div>
            <p v-if="nfsInvalid" class="form-error">启用 NFS 前，请填写完整且有效的 NFS 配置。</p>
          </el-form>
        </li>
      </ul>
    </template>
  </section>
</template>

<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { Check, Refresh } from '@element-plus/icons-vue';
import { listComponents, updateComponents } from '../api/client';
import { safeErrorMessage } from '../utils/redaction';

const props = defineProps({ clusterId: { type: [String, Number], required: true }, locked: Boolean });
const emit = defineEmits(['next']);
const enabled = ref(false);
const groups = ref([]);
const loading = ref(true);
const saving = ref(false);
const errorMessage = ref('');

const nfsGroup = computed(() => groups.value.find((group) => group.key === 'nfs'));
const nfsInvalid = computed(() => {
  const group = nfsGroup.value;
  if (!group?.enabled) return false;
  const config = group.config || {};
  return !isIpv4(config.server_address)
    || !isSafePath(config.share_path)
    || !isSafePath(config.worker_mount_path)
    || !isKubernetesName(config.storage_class)
    || !['managed', 'external'].includes(config.exports_mode);
});

onMounted(load);
watch(() => props.clusterId, load);

async function load() {
  loading.value = true;
  errorMessage.value = '';
  try {
    const payload = await listComponents(props.clusterId);
    enabled.value = Boolean(payload?.enabled);
    groups.value = (payload?.groups || []).map(normalizeGroup);
  } catch (error) {
    errorMessage.value = safeErrorMessage(error, '组件配置加载失败，请重新加载。');
  } finally {
    loading.value = false;
  }
}

async function save() {
  if (props.locked || saving.value || nfsInvalid.value) return;
  saving.value = true;
  errorMessage.value = '';
  try {
    const saved = await updateComponents(props.clusterId, {
      enabled: enabled.value,
      groups: groups.value.map((group) => ({
        key: group.key,
        enabled: group.enabled,
        config: group.config
      }))
    });
    enabled.value = Boolean(saved?.enabled);
    groups.value = (saved?.groups || groups.value).map(normalizeGroup);
    emit('next');
  } catch (error) {
    errorMessage.value = safeErrorMessage(error, '组件配置保存失败，请检查输入后重试。');
  } finally {
    saving.value = false;
  }
}

function normalizeGroup(group) {
  return {
    ...group,
    enabled: Boolean(group.enabled),
    components: Array.isArray(group.components) ? group.components : [],
    config: { ...(group.config || {}) }
  };
}

function groupReadOnly(group) {
  return props.locked || !group.available || group.status === 'installed';
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
