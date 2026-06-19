<template>
  <el-config-provider>
    <main class="app-shell">
      <aside class="sidebar">
        <div class="brand">
          <div class="brand-mark">KF</div>
          <div>
            <h1>KubeFoundry</h1>
            <p>Web Wizard v0.1.0</p>
          </div>
        </div>

        <el-steps :active="activeStep" direction="vertical" finish-status="success" class="wizard-steps">
          <el-step v-for="item in steps" :key="item.key" :title="item.title" />
        </el-steps>
      </aside>

      <section class="workspace">
        <header class="topbar">
          <div>
            <p class="eyebrow">当前集群</p>
            <h2>{{ clusterForm.name || '未命名集群' }}</h2>
          </div>
          <div class="topbar-actions">
            <el-select v-model="selectedClusterId" placeholder="选择已有集群" filterable clearable @change="handleClusterChange">
              <el-option v-for="cluster in clusters" :key="cluster.id" :label="cluster.name" :value="cluster.id" />
            </el-select>
            <el-button :icon="Refresh" @click="loadClusters">刷新</el-button>
          </div>
        </header>

        <el-alert v-if="apiError" :title="apiError" type="error" show-icon closable @close="apiError = ''" />

        <section class="content-grid">
          <div class="primary-pane">
            <section v-show="activeStep === 0" class="pane">
              <div class="pane-header">
                <h3>集群基础配置</h3>
                <el-tag :type="selectedClusterId ? 'success' : 'info'">{{ selectedClusterId ? '已保存' : '未保存' }}</el-tag>
              </div>
              <el-form ref="clusterFormRef" :model="clusterForm" :rules="clusterRules" label-position="top">
                <div class="form-grid">
                  <el-form-item label="集群名称" prop="name">
                    <el-input v-model="clusterForm.name" placeholder="k8s-cluster" />
                  </el-form-item>
                  <el-form-item label="Kubernetes 版本" prop="k8s_version">
                    <el-input v-model="clusterForm.k8s_version" placeholder="1.30.14" />
                  </el-form-item>
                  <el-form-item label="Pod 网段" prop="pod_subnet">
                    <el-input v-model="clusterForm.pod_subnet" placeholder="10.244.0.0/16" />
                  </el-form-item>
                  <el-form-item label="Service 网段" prop="service_subnet">
                    <el-input v-model="clusterForm.service_subnet" placeholder="10.96.0.0/16" />
                  </el-form-item>
                  <el-form-item label="API Server 端口" prop="api_server_port">
                    <el-input-number v-model="clusterForm.api_server_port" :min="1" :max="65535" controls-position="right" />
                  </el-form-item>
                  <el-form-item label="安装模式">
                    <el-segmented v-model="clusterForm.install_mode" :options="installModeOptions" />
                  </el-form-item>
                  <el-form-item label="镜像仓库主机名">
                    <el-input v-model="clusterForm.registry_hostname" placeholder="registry" />
                  </el-form-item>
                  <el-form-item label="镜像仓库 IP">
                    <el-input v-model="clusterForm.registry_ip" placeholder="192.168.123.130" />
                  </el-form-item>
                  <el-form-item label="镜像仓库端口">
                    <el-input-number v-model="clusterForm.registry_port" :min="1" :max="65535" controls-position="right" />
                  </el-form-item>
                </div>
                <el-form-item label="描述">
                  <el-input v-model="clusterForm.description" type="textarea" :rows="3" />
                </el-form-item>
              </el-form>
            </section>

            <section v-show="activeStep === 1" class="pane">
              <div class="pane-header">
                <h3>节点配置</h3>
                <el-button type="primary" :icon="Plus" @click="openNodeDialog()">添加节点</el-button>
              </div>
              <el-table :data="nodes" empty-text="暂无节点" border>
                <el-table-column prop="hostname" label="主机名" min-width="150" />
                <el-table-column prop="ip" label="IP" min-width="140" />
                <el-table-column label="角色" width="150">
                  <template #default="{ row }">
                    <el-tag :type="roleTagType(row.role)">{{ roleText(row.role) }}</el-tag>
                  </template>
                </el-table-column>
                <el-table-column prop="ssh_user" label="SSH 用户" width="120" />
                <el-table-column prop="ssh_port" label="端口" width="90" />
                <el-table-column prop="arch" label="架构" width="110" />
                <el-table-column label="操作" width="150" fixed="right">
                  <template #default="{ row }">
                    <el-button :icon="Edit" circle @click="openNodeDialog(row)" />
                    <el-button :icon="Delete" circle type="danger" @click="removeNode(row)" />
                  </template>
                </el-table-column>
              </el-table>
            </section>

            <section v-show="activeStep === 2" class="pane">
              <div class="pane-header">
                <h3>SSH 配置</h3>
                <el-tag type="warning">MVP</el-tag>
              </div>
              <el-form :model="sshForm" label-position="top">
                <div class="form-grid">
                  <el-form-item label="认证方式">
                    <el-segmented v-model="sshForm.auth_type" :options="authTypeOptions" />
                  </el-form-item>
                  <el-form-item label="默认用户">
                    <el-input v-model="sshForm.username" placeholder="root" />
                  </el-form-item>
                  <el-form-item label="私钥路径">
                    <el-input v-model="sshForm.private_key_path" placeholder="/root/.ssh/id_rsa" />
                  </el-form-item>
                </div>
              </el-form>
            </section>

            <section v-show="activeStep === 3" class="pane">
              <div class="pane-header">
                <h3>路径配置</h3>
              </div>
              <el-form :model="pathForm" label-position="top">
                <div class="form-grid">
                  <el-form-item label="K8S_HOME">
                    <el-input v-model="pathForm.k8s_home" />
                  </el-form-item>
                  <el-form-item label="安装介质路径">
                    <el-input v-model="pathForm.install_media" />
                  </el-form-item>
                  <el-form-item label="kubelet root">
                    <el-input v-model="pathForm.kubelet_root" />
                  </el-form-item>
                  <el-form-item label="etcd 数据目录">
                    <el-input v-model="pathForm.etcd_data_dir" />
                  </el-form-item>
                </div>
              </el-form>
            </section>

            <section v-show="activeStep === 4" class="pane">
              <div class="pane-header">
                <h3>生态组件选择</h3>
              </div>
              <div class="component-list">
                <label v-for="item in ecosystemOptions" :key="item.key" class="component-row">
                  <span>
                    <strong>{{ item.name }}</strong>
                    <small>{{ item.step }}</small>
                  </span>
                  <el-switch v-model="ecosystemForm[item.key]" />
                </label>
              </div>
            </section>

            <section v-show="activeStep === 5" class="pane">
              <div class="pane-header">
                <h3>预检查</h3>
                <el-button type="primary" :icon="CircleCheck" :loading="actionLoading" :disabled="!selectedClusterId" @click="runPrecheck">
                  开始预检查
                </el-button>
              </div>
              <job-status-panel :job="currentJob" :steps="jobSteps" />
            </section>

            <section v-show="activeStep === 6" class="pane">
              <div class="pane-header">
                <h3>配置确认</h3>
                <el-button :icon="Document" :disabled="!currentJobId" @click="loadConfigYaml">读取 YAML</el-button>
              </div>
              <pre class="yaml-preview">{{ yamlPreview }}</pre>
            </section>

            <section v-show="activeStep === 7" class="pane">
              <div class="pane-header">
                <h3>安装执行</h3>
                <el-button type="danger" :icon="VideoPlay" :loading="actionLoading" :disabled="!selectedClusterId" @click="runInstall">
                  创建安装任务
                </el-button>
              </div>
              <job-status-panel :job="currentJob" :steps="jobSteps" />
            </section>

            <section v-show="activeStep === 8" class="pane">
              <div class="pane-header">
                <h3>安装结果</h3>
                <el-button :icon="Refresh" :disabled="!currentJobId" @click="refreshJob">刷新任务</el-button>
              </div>
              <job-status-panel :job="currentJob" :steps="jobSteps" />
            </section>
          </div>

          <aside class="right-pane">
            <section class="status-panel">
              <div class="pane-header compact">
                <h3>任务与日志</h3>
                <el-tag :type="jobStatusType(currentJob?.status)">{{ currentJob?.status || 'idle' }}</el-tag>
              </div>
              <el-input v-model="manualJobId" placeholder="输入 job_id" class="job-input">
                <template #append>
                  <el-button @click="bindManualJob">绑定</el-button>
                </template>
              </el-input>
              <div class="log-toolbar">
                <el-button :icon="Connection" :disabled="!currentJobId || eventConnected" @click="connectEvents">连接 SSE</el-button>
                <el-button :icon="Close" :disabled="!eventSource" @click="disconnectEvents">断开</el-button>
              </div>
              <pre class="log-view">{{ logLines.join('\n') }}</pre>
            </section>
          </aside>
        </section>

        <footer class="footer-actions">
          <el-button :disabled="activeStep === 0" @click="activeStep -= 1">上一步</el-button>
          <el-button v-if="activeStep === 0" type="primary" :loading="actionLoading" @click="saveCluster">保存集群</el-button>
          <el-button v-else-if="activeStep === 1" type="primary" :disabled="!selectedClusterId" @click="activeStep += 1">确认节点</el-button>
          <el-button v-else-if="activeStep < steps.length - 1" type="primary" @click="activeStep += 1">下一步</el-button>
        </footer>
      </section>

      <el-dialog v-model="nodeDialogVisible" :title="editingNodeId ? '编辑节点' : '添加节点'" width="640px">
        <el-form ref="nodeFormRef" :model="nodeForm" :rules="nodeRules" label-position="top">
          <div class="form-grid">
            <el-form-item label="主机名" prop="hostname">
              <el-input v-model="nodeForm.hostname" />
            </el-form-item>
            <el-form-item label="IP 地址" prop="ip">
              <el-input v-model="nodeForm.ip" />
            </el-form-item>
            <el-form-item label="IPv6">
              <el-input v-model="nodeForm.ipv6" />
            </el-form-item>
            <el-form-item label="角色" prop="role">
              <el-select v-model="nodeForm.role">
                <el-option label="控制节点" value="control_plane" />
                <el-option label="工作节点" value="worker" />
                <el-option label="镜像仓库" value="registry" />
              </el-select>
            </el-form-item>
            <el-form-item label="SSH 用户" prop="ssh_user">
              <el-input v-model="nodeForm.ssh_user" />
            </el-form-item>
            <el-form-item label="SSH 端口" prop="ssh_port">
              <el-input-number v-model="nodeForm.ssh_port" :min="1" :max="65535" controls-position="right" />
            </el-form-item>
            <el-form-item label="操作系统">
              <el-input v-model="nodeForm.os_type" placeholder="openEuler / CentOS / Kylin" />
            </el-form-item>
            <el-form-item label="架构">
              <el-select v-model="nodeForm.arch">
                <el-option label="amd64" value="amd64" />
                <el-option label="arm64" value="arm64" />
              </el-select>
            </el-form-item>
          </div>
        </el-form>
        <template #footer>
          <el-button @click="nodeDialogVisible = false">取消</el-button>
          <el-button type="primary" :loading="actionLoading" @click="saveNode">保存</el-button>
        </template>
      </el-dialog>
    </main>
  </el-config-provider>
</template>

<script setup>
import { computed, defineComponent, h, onBeforeUnmount, onMounted, reactive, ref } from 'vue';
import { ElMessage, ElMessageBox, ElTag } from 'element-plus';
import {
  CircleCheck,
  Close,
  Connection,
  Delete,
  Document,
  Edit,
  Plus,
  Refresh,
  VideoPlay
} from '@element-plus/icons-vue';
import {
  createCluster,
  createNode,
  deleteNode,
  getCluster,
  getClusterSettings,
  getSettings,
  getJob,
  getJobConfigYaml,
  getJobSteps,
  listClusters,
  listNodes,
  startInstall,
  startPrecheck,
  updateCluster,
  updateNode,
  updateClusterSettings,
  upsertSshCredentials
} from './api/client';

const JobStatusPanel = defineComponent({
  props: {
    job: {
      type: Object,
      default: null
    },
    steps: {
      type: Array,
      default: () => []
    }
  },
  setup(props) {
    return () =>
      h('div', { class: 'job-panel' }, [
        h('div', { class: 'job-meta' }, [
          h('span', `任务：${props.job?.id || '-'}`),
          h('span', `类型：${props.job?.job_type || '-'}`),
          h('span', `当前步骤：${props.job?.current_step_key || '-'}`)
        ]),
        h(
          'div',
          { class: 'step-list' },
          props.steps.length
            ? props.steps.map((step) =>
                h('div', { class: 'step-row', key: step.id || step.step_key }, [
                  h('span', { class: 'step-key' }, step.step_key),
                  h('span', step.step_name || step.phase || '-'),
                  h(ElTag, { type: statusType(step.status), size: 'small' }, () => step.status || 'pending'),
                  h('small', step.message || '')
                ])
              )
            : h('p', { class: 'muted' }, '暂无步骤数据')
        )
      ]);
  }
});

const steps = [
  { key: 'cluster', title: '集群基础配置' },
  { key: 'nodes', title: '节点配置' },
  { key: 'ssh', title: 'SSH 配置' },
  { key: 'paths', title: '路径配置' },
  { key: 'ecosystem', title: '生态组件选择' },
  { key: 'precheck', title: '预检查' },
  { key: 'confirm', title: '配置确认' },
  { key: 'install', title: '安装执行' },
  { key: 'result', title: '安装结果' }
];

const installModeOptions = ['online', 'offline'];
const authTypeOptions = ['key'];
const ecosystemOptions = [
  { key: 'kubemate_ui', name: 'Kubemate UI', step: '31-install-kubemate-ui' },
  { key: 'nfs', name: 'NFS', step: '32-install-nfs' },
  { key: 'traefik', name: 'Traefik', step: '36-install-traefik' },
  { key: 'prometheus', name: 'Prometheus', step: '38-install-prometheus' },
  { key: 'metrics_server', name: 'Metrics Server', step: '40-install-metrics-server' }
];

const activeStep = ref(0);
const clusters = ref([]);
const selectedClusterId = ref(null);
const nodes = ref([]);
const currentJob = ref(null);
const jobSteps = ref([]);
const currentJobId = computed(() => currentJob.value?.id || manualJobId.value || '');
const manualJobId = ref('');
const yamlPreview = ref('');
const logLines = ref([]);
const eventSource = ref(null);
const eventConnected = ref(false);
const actionLoading = ref(false);
const apiError = ref('');
const clusterFormRef = ref(null);
const nodeFormRef = ref(null);
const nodeDialogVisible = ref(false);
const editingNodeId = ref(null);

const clusterForm = reactive({
  name: 'k8s-cluster',
  description: '',
  k8s_version: '1.30.14',
  pod_subnet: '10.244.0.0/16',
  service_subnet: '10.96.0.0/16',
  api_server_port: 6443,
  registry_hostname: 'registry',
  registry_ip: '',
  registry_port: 5000,
  install_mode: 'offline'
});

const sshForm = reactive({
  auth_type: 'key',
  username: 'root',
  private_key_path: '/root/.ssh/id_rsa'
});

const pathForm = reactive({
  k8s_home: '/data/k8s_install',
  install_media: '/root/kube-media',
  kubelet_root: '/data/k8s_install/kubelet_root',
  etcd_data_dir: '/data/k8s_install/etcd_backup'
});

const ecosystemForm = reactive({
  kubemate_ui: true,
  nfs: false,
  traefik: true,
  prometheus: false,
  metrics_server: true
});

const emptyNodeForm = () => ({
  hostname: '',
  ip: '',
  ipv6: '',
  role: 'worker',
  ssh_port: 22,
  ssh_user: 'root',
  os_type: '',
  arch: 'amd64'
});

const nodeForm = reactive(emptyNodeForm());

const clusterRules = {
  name: [{ required: true, message: '请输入集群名称', trigger: 'blur' }],
  k8s_version: [{ required: true, message: '请输入 Kubernetes 版本', trigger: 'blur' }],
  pod_subnet: [{ required: true, message: '请输入 Pod 网段', trigger: 'blur' }],
  service_subnet: [{ required: true, message: '请输入 Service 网段', trigger: 'blur' }],
  api_server_port: [{ required: true, message: '请输入 API Server 端口', trigger: 'blur' }]
};

const nodeRules = {
  hostname: [{ required: true, message: '请输入主机名', trigger: 'blur' }],
  ip: [{ required: true, message: '请输入 IP 地址', trigger: 'blur' }],
  role: [{ required: true, message: '请选择节点角色', trigger: 'change' }],
  ssh_user: [{ required: true, message: '请输入 SSH 用户', trigger: 'blur' }],
  ssh_port: [{ required: true, message: '请输入 SSH 端口', trigger: 'blur' }]
};

onMounted(async () => {
  await loadSettings();
  await loadClusters();
});
onBeforeUnmount(disconnectEvents);

function normalizeList(payload) {
  if (Array.isArray(payload)) return payload;
  if (payload && Array.isArray(payload.items)) return payload.items;
  if (payload && Array.isArray(payload.data)) return payload.data;
  return [];
}

function normalizeItem(payload) {
  return payload && payload.data ? payload.data : payload;
}

async function withAction(fn) {
  actionLoading.value = true;
  apiError.value = '';
  try {
    return await fn();
  } catch (error) {
    apiError.value = error.message || String(error);
    throw error;
  } finally {
    actionLoading.value = false;
  }
}

async function loadClusters() {
  try {
    clusters.value = normalizeList(await listClusters());
  } catch (error) {
    apiError.value = error.message || String(error);
  }
}

async function handleClusterChange(clusterId) {
  const cluster = clusterId ? normalizeItem(await getCluster(clusterId)) : null;
  if (cluster) {
    Object.assign(clusterForm, cluster);
    if (cluster.ssh_credentials) {
      Object.assign(sshForm, {
        auth_type: cluster.ssh_credentials.auth_type || 'key',
        username: cluster.ssh_credentials.username || 'root',
        private_key_path: cluster.ssh_credentials.private_key_path || '/root/.ssh/id_rsa'
      });
    }
    await loadClusterNodes();
    await loadClusterSettings(clusterId);
  } else {
    nodes.value = [];
  }
}

async function loadSettings() {
  try {
    const settings = await getSettings();
    if (settings.paths) {
      Object.assign(pathForm, settings.paths);
    }
    if (settings.ecosystem) {
      Object.assign(ecosystemForm, settings.ecosystem);
    }
  } catch (error) {
    apiError.value = error.message || String(error);
  }
}

async function loadClusterSettings(clusterId) {
  try {
    const settings = await getClusterSettings(clusterId);
    if (settings.paths) {
      Object.assign(pathForm, settings.paths);
    }
    if (settings.ecosystem) {
      Object.assign(ecosystemForm, settings.ecosystem);
    }
  } catch (error) {
    apiError.value = error.message || String(error);
  }
}

async function saveCluster() {
  await clusterFormRef.value.validate();
  await withAction(async () => {
    const saved = normalizeItem(
      selectedClusterId.value ? await updateCluster(selectedClusterId.value, clusterForm) : await createCluster(clusterForm)
    );
    selectedClusterId.value = saved.id || selectedClusterId.value;
    await upsertSshCredentials(selectedClusterId.value, {
      auth_type: sshForm.auth_type,
      username: sshForm.username,
      private_key_path: sshForm.private_key_path
    });
    await updateClusterSettings(selectedClusterId.value, {
      paths: { ...pathForm },
      ecosystem: { ...ecosystemForm }
    });
    await loadClusters();
    ElMessage.success('集群配置已保存');
    activeStep.value = Math.max(activeStep.value, 1);
  });
}

async function loadClusterNodes() {
  if (!selectedClusterId.value) return;
  nodes.value = normalizeList(await listNodes(selectedClusterId.value));
}

function openNodeDialog(row) {
  if (!selectedClusterId.value) {
    ElMessage.warning('请先保存集群配置');
    return;
  }
  editingNodeId.value = row?.id || null;
  Object.assign(nodeForm, emptyNodeForm(), row || {});
  nodeDialogVisible.value = true;
}

async function saveNode() {
  await nodeFormRef.value.validate();
  await withAction(async () => {
    if (editingNodeId.value) {
      await updateNode(editingNodeId.value, { ...nodeForm });
    } else {
      await createNode(selectedClusterId.value, { ...nodeForm });
    }
    await loadClusterNodes();
    nodeDialogVisible.value = false;
    ElMessage.success('节点已保存');
  });
}

async function removeNode(row) {
  await ElMessageBox.confirm(`删除节点 ${row.hostname}？`, '确认删除', { type: 'warning' });
  await withAction(async () => {
    await deleteNode(row.id);
    await loadClusterNodes();
    ElMessage.success('节点已删除');
  });
}

async function runPrecheck() {
  await saveCluster();
  await withAction(async () => {
    const job = normalizeItem(await startPrecheck(selectedClusterId.value));
    currentJob.value = job;
    manualJobId.value = job.id;
    activeStep.value = 5;
    await refreshJob();
    connectEvents();
  });
}

async function runInstall() {
  await saveCluster();
  await withAction(async () => {
    const job = normalizeItem(await startInstall(selectedClusterId.value));
    currentJob.value = job;
    manualJobId.value = job.id;
    activeStep.value = 7;
    await refreshJob();
    connectEvents();
  });
}

async function refreshJob() {
  if (!currentJobId.value) return;
  try {
    currentJob.value = normalizeItem(await getJob(currentJobId.value));
    jobSteps.value = normalizeList(await getJobSteps(currentJobId.value));
  } catch (error) {
    apiError.value = error.message || String(error);
  }
}

async function bindManualJob() {
  if (!manualJobId.value) return;
  await refreshJob();
}

async function loadConfigYaml() {
  if (!currentJobId.value) return;
  try {
    const payload = await getJobConfigYaml(currentJobId.value);
    yamlPreview.value = typeof payload === 'string' ? payload : payload?.yaml || JSON.stringify(payload, null, 2);
  } catch (error) {
    apiError.value = error.message || String(error);
  }
}

function connectEvents() {
  if (!currentJobId.value || eventSource.value) return;
  const source = new EventSource(`/api/jobs/${currentJobId.value}/events`);
  eventSource.value = source;

  source.onopen = () => {
    eventConnected.value = true;
    appendLog('SSE 已连接');
  };
  source.onerror = () => {
    eventConnected.value = false;
    appendLog('SSE 连接中断');
  };
  source.onmessage = (event) => {
    appendLog(event.data);
    tryRefreshFromEvent(event.data);
  };

  ['job.status', 'step.status', 'node.status', 'log.line', 'precheck.result'].forEach((eventName) => {
    source.addEventListener(eventName, (event) => {
      appendLog(`[${eventName}] ${event.data}`);
      tryRefreshFromEvent(event.data);
    });
  });
}

function disconnectEvents() {
  if (eventSource.value) {
    eventSource.value.close();
  }
  eventSource.value = null;
  eventConnected.value = false;
}

function appendLog(line) {
  logLines.value.push(`${new Date().toLocaleTimeString()} ${line}`);
  if (logLines.value.length > 600) {
    logLines.value = logLines.value.slice(-600);
  }
}

function tryRefreshFromEvent(raw) {
  if (!raw || !currentJobId.value) return;
  window.clearTimeout(tryRefreshFromEvent.timer);
  tryRefreshFromEvent.timer = window.setTimeout(refreshJob, 500);
}

function roleText(role) {
  return {
    control_plane: '控制节点',
    worker: '工作节点',
    registry: '镜像仓库'
  }[role] || role;
}

function roleTagType(role) {
  return {
    control_plane: 'success',
    worker: 'primary',
    registry: 'warning'
  }[role] || 'info';
}

function statusType(status) {
  return {
    pending: 'info',
    running: 'warning',
    success: 'success',
    failed: 'danger',
    canceled: 'info'
  }[status] || 'info';
}

function jobStatusType(status) {
  return statusType(status);
}
</script>
