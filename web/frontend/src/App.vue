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
            <el-button :icon="Clock" :disabled="!selectedClusterId" @click="openJobHistory">任务历史</el-button>
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
                <el-alert title="当前版本仅支持离线安装。" type="info" show-icon :closable="false" />
              </el-form>
            </section>

            <section v-show="activeStep === 1" class="pane">
              <div class="pane-header">
                <h3>节点配置</h3>
                <div class="pane-actions">
                  <el-button :disabled="!selectedNodeIds.length" @click="copySelectedNodes">复制所选</el-button>
                  <el-button type="success" :disabled="!selectedClusterId" :loading="actionLoading" @click="runNodeTest">测试全部节点</el-button>
                  <el-button type="primary" :icon="Plus" @click="openNodeDialog()">添加节点</el-button>
                </div>
              </div>
              <el-alert v-if="nodeConfigProblems.length" :title="nodeConfigProblems.join('；')" type="warning" show-icon :closable="false" class="node-warning" />
              <el-table :data="nodes" empty-text="暂无节点" border @selection-change="handleNodeSelectionChange">
                <el-table-column type="selection" width="48" />
                <el-table-column prop="hostname" label="主机名" min-width="150" />
                <el-table-column prop="ip" label="IP" min-width="140" />
                <el-table-column prop="ssh_user" label="SSH 用户" width="120" />
                <el-table-column prop="ssh_port" label="SSH 端口" width="110" />
                <el-table-column prop="ipv6" label="IPv6" min-width="120" />
                <el-table-column label="角色" width="150">
                  <template #default="{ row }">
                    <el-tag :type="roleTagType(row.role)">{{ roleText(row.role) }}</el-tag>
                  </template>
                </el-table-column>
                <el-table-column label="密码" width="100">
                  <template #default="{ row }">
                    <el-tag :type="row.has_password ? 'success' : 'danger'">{{ row.has_password ? '已配置' : '未配置' }}</el-tag>
                  </template>
                </el-table-column>
                <el-table-column label="草稿" width="90">
                  <template #default="{ row }">
                    <el-tag :type="row.is_draft ? 'warning' : 'info'">{{ row.is_draft ? '草稿' : '正式' }}</el-tag>
                  </template>
                </el-table-column>
                <el-table-column prop="os_type" label="操作系统" width="120" />
                <el-table-column prop="os_version" label="系统版本" width="120" />
                <el-table-column prop="arch" label="架构" width="110" />
                <el-table-column prop="node_test_status" label="测试状态" width="120" />
                <el-table-column prop="node_tested_at" label="测试时间" min-width="160" />
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

            <section v-show="activeStep === 3" class="pane">
              <div class="pane-header">
                <h3>生态组件选择</h3>
                <el-tag type="info">v0.2.0</el-tag>
              </div>
              <el-alert
                title="v0.1.0 安装任务仅执行 Kubernetes 底座、Flannel 和最终健康检查；生态组件将在 v0.2.0 接入。"
                type="info"
                show-icon
                :closable="false"
              />
              <div class="component-list">
                <label v-for="item in ecosystemOptions" :key="item.key" class="component-row">
                  <span>
                    <strong>{{ item.name }}</strong>
                    <small>{{ item.step }}</small>
                  </span>
                  <el-switch v-model="ecosystemForm[item.key]" disabled />
                </label>
              </div>
            </section>

            <section v-show="activeStep === 4" class="pane">
              <div class="pane-header">
                <h3>预检查</h3>
                <el-button type="primary" :icon="CircleCheck" :loading="actionLoading" :disabled="!selectedClusterId || nodeConfigProblems.length > 0" @click="runPrecheck">
                  开始预检查
                </el-button>
              </div>
              <job-status-panel :job="currentJob" :steps="jobSteps" @open-node-log="loadNodeLog" />
              <el-table v-if="precheckResults.length" :data="precheckResults" class="precheck-table" border>
                <el-table-column prop="hostname" label="节点" min-width="120" />
                <el-table-column prop="check_name" label="检查项" min-width="130" />
                <el-table-column label="结果" width="100">
                  <template #default="{ row }">
                    <el-tag :type="precheckStatusType(row.status)">{{ row.status }}</el-tag>
                  </template>
                </el-table-column>
                <el-table-column prop="message" label="说明" min-width="220" />
              </el-table>
            </section>

            <section v-show="activeStep === 5" class="pane">
              <div class="pane-header">
                <h3>配置确认</h3>
                <div class="pane-actions">
                  <el-button :icon="Upload" :disabled="!selectedClusterId" @click="openYamlImport">导入 YAML</el-button>
                  <el-button :icon="Document" :disabled="!selectedClusterId" @click="loadConfigYaml">刷新预览</el-button>
                </div>
              </div>
              <pre class="yaml-preview">{{ yamlPreview }}</pre>
            </section>

            <section v-show="activeStep === 6" class="pane">
              <div class="pane-header">
                <h3>安装执行</h3>
                <el-button type="danger" :icon="VideoPlay" :loading="actionLoading" :disabled="!selectedClusterId || nodeConfigProblems.length > 0" @click="runInstall">
                  执行底座安装
                </el-button>
              </div>
              <el-table :data="installPlan" class="install-plan-table" border>
                <el-table-column prop="order" label="#" width="56" />
                <el-table-column prop="name" label="步骤" min-width="190" />
                <el-table-column label="目标" min-width="180">
                  <template #default="{ row }">
                    {{ installTargetText(row.target_scope) }}
                  </template>
                </el-table-column>
                <el-table-column label="执行方式" width="110">
                  <template #default="{ row }">
                    <el-tag :type="row.mode === 'parallel' ? 'success' : 'info'">{{ installModeText(row.mode) }}</el-tag>
                  </template>
                </el-table-column>
              </el-table>
              <job-status-panel :job="currentJob" :steps="jobSteps" @open-node-log="loadNodeLog" />
            </section>

            <section v-show="activeStep === 7" class="pane">
              <div class="pane-header">
                <h3>安装结果</h3>
                <el-button :icon="Refresh" :disabled="!currentJobId" @click="refreshJob">刷新任务</el-button>
              </div>
              <job-status-panel :job="currentJob" :steps="jobSteps" @open-node-log="loadNodeLog" />
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
            <el-form-item label="登录密码" prop="password">
              <el-input v-model="nodeForm.password" type="password" show-password :placeholder="nodePasswordPlaceholder" />
            </el-form-item>
          </div>
        </el-form>
        <template #footer>
          <el-button @click="nodeDialogVisible = false">取消</el-button>
          <el-button type="primary" :loading="actionLoading" @click="saveNode">保存</el-button>
        </template>
      </el-dialog>

      <el-dialog v-model="nodeLogDialogVisible" :title="nodeLogTitle" width="min(900px, 92vw)">
        <pre class="node-log-view">{{ nodeLogContent }}</pre>
      </el-dialog>

      <el-dialog v-model="yamlImportDialogVisible" title="导入 cluster.yaml" width="min(820px, 92vw)">
        <el-input v-model="yamlImportContent" type="textarea" :rows="22" placeholder="粘贴 YAML 配置内容" />
        <template #footer>
          <el-button @click="yamlImportDialogVisible = false">取消</el-button>
          <el-button type="primary" :loading="actionLoading" @click="submitYamlImport">导入并覆盖当前配置</el-button>
        </template>
      </el-dialog>

      <el-dialog v-model="jobHistoryDialogVisible" title="任务历史" width="min(960px, 94vw)">
        <el-table :data="jobs" border empty-text="暂无任务">
          <el-table-column prop="id" label="ID" width="72" />
          <el-table-column prop="job_type" label="类型" width="110" />
          <el-table-column label="状态" width="110">
            <template #default="{ row }">
              <el-tag :type="jobStatusType(row.status)">{{ row.status }}</el-tag>
            </template>
          </el-table-column>
          <el-table-column prop="current_step_key" label="当前/最后步骤" min-width="190" />
          <el-table-column prop="created_at" label="创建时间" min-width="170" />
          <el-table-column label="操作" width="100">
            <template #default="{ row }">
              <el-button link type="primary" @click="bindHistoryJob(row)">查看</el-button>
            </template>
          </el-table-column>
        </el-table>
      </el-dialog>
    </main>
  </el-config-provider>
</template>

<script setup>
import { computed, defineComponent, h, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue';
import { ElMessage, ElMessageBox, ElTag } from 'element-plus';
import {
  CircleCheck,
  Clock,
  Close,
  Connection,
  Delete,
  Document,
  Edit,
  Plus,
  Refresh,
  Upload,
  VideoPlay
} from '@element-plus/icons-vue';
import {
  copyNodes,
  createCluster,
  createNode,
  deleteNode,
  getCluster,
  getClusterConfigYaml,
  getClusterSettings,
  getInstallPlan,
  getSettings,
  getJob,
  getJobStepNodeLog,
  getJobSteps,
  getPrecheckResults,
  importClusterYaml,
  listClusters,
  listJobs,
  listNodes,
  startInstall,
  startNodeTest,
  startPrecheck,
  updateCluster,
  updateNode,
  updateClusterSettings
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
  emits: ['open-node-log'],
  setup(props, { emit }) {
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
                h('div', { class: 'step-block', key: step.id || step.step_key }, [
                  h('div', { class: 'step-row' }, [
                    h('span', { class: 'step-key' }, step.step_key),
                    h('span', step.step_name || step.phase || '-'),
                    h(ElTag, { type: statusType(step.status), size: 'small' }, () => step.status || 'pending'),
                    h('small', step.message || '')
                  ]),
                  h(
                    'div',
                    { class: 'step-node-list' },
                    (step.nodes || []).map((node) =>
                      h(
                        'button',
                        {
                          type: 'button',
                          class: 'step-node',
                          onClick: () => emit('open-node-log', node)
                        },
                        [
                          h('span', node.hostname),
                          h(ElTag, { type: statusType(node.status), size: 'small' }, () => node.status)
                        ]
                      )
                    )
                  )
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
  { key: 'paths', title: '路径配置' },
  { key: 'ecosystem', title: '生态组件选择' },
  { key: 'precheck', title: '预检查' },
  { key: 'confirm', title: '配置确认' },
  { key: 'install', title: '安装执行' },
  { key: 'result', title: '安装结果' }
];

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
const precheckResults = ref([]);
const jobs = ref([]);
const installPlan = ref([]);
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
const nodeLogDialogVisible = ref(false);
const nodeLogTitle = ref('节点日志');
const nodeLogContent = ref('');
const yamlImportDialogVisible = ref(false);
const yamlImportContent = ref('');
const jobHistoryDialogVisible = ref(false);
const editingNodeId = ref(null);
const selectedNodeIds = ref([]);

const clusterForm = reactive({
  name: 'k8s-cluster',
  description: '',
  k8s_version: '1.30.14',
  pod_subnet: '10.244.0.0/16',
  service_subnet: '10.96.0.0/16',
  registry_hostname: 'registry',
  registry_ip: '',
  registry_port: 5000
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
  ssh_user: 'root',
  ssh_port: 22,
  password: '',
  has_password: false,
  is_draft: false
});

const nodeForm = reactive(emptyNodeForm());

const clusterRules = {
  name: [{ required: true, message: '请输入集群名称', trigger: 'blur' }],
  k8s_version: [{ required: true, message: '请输入 Kubernetes 版本', trigger: 'blur' }],
  pod_subnet: [{ required: true, message: '请输入 Pod 网段', trigger: 'blur' }],
  service_subnet: [{ required: true, message: '请输入 Service 网段', trigger: 'blur' }]
};

const nodeRules = {
  hostname: [{ required: true, message: '请输入主机名', trigger: 'blur' }],
  ip: [{ required: true, message: '请输入 IP 地址', trigger: 'blur' }],
  role: [{ required: true, message: '请选择节点角色', trigger: 'change' }],
  ssh_user: [{ required: true, message: '请输入 SSH 用户', trigger: 'blur' }],
  ssh_port: [{ required: true, message: '请输入 SSH 端口', trigger: 'change' }],
  password: [{
    validator: (rule, value, callback) => {
      if (!editingNodeId.value && !value) {
        callback(new Error('请输入登录密码'));
        return;
      }
      callback();
    },
    trigger: 'blur'
  }]
};

const nodeConfigProblems = computed(() => {
  const problems = [];
  const hostnameMap = new Map();
  const ipMap = new Map();
  nodes.value.forEach((node) => {
    const label = node.hostname || `节点 ${node.id}`;
    if (node.is_draft) problems.push(`${label} 是草稿节点`);
    if (!node.hostname) problems.push(`${label} 缺少主机名`);
    if (!node.ip) problems.push(`${label} 缺少 IP`);
    if (!node.has_password) problems.push(`${label} 缺少登录密码`);
    if (node.hostname) {
      if (hostnameMap.has(node.hostname)) problems.push(`${label} 主机名重复`);
      hostnameMap.set(node.hostname, node.id);
    }
    if (node.ip) {
      if (ipMap.has(node.ip)) problems.push(`${label} IP 重复`);
      ipMap.set(node.ip, node.id);
    }
  });
  if (clusterForm.node_test_status && clusterForm.node_test_status !== 'success') {
    problems.push('节点配置已修改或节点测试未成功，请重新执行“测试全部节点”');
  }
  return problems;
});

const nodePasswordPlaceholder = computed(() => {
  if (!editingNodeId.value) return '请输入登录密码';
  return nodeForm.has_password ? '密码已保存，留空表示保留原密码' : '请输入登录密码';
});

onMounted(async () => {
  await loadSettings();
  await loadClusters();
  await loadInstallPlan();
});
onBeforeUnmount(disconnectEvents);
watch(activeStep, (step) => {
  if (step === 5 && selectedClusterId.value) {
    loadConfigYaml();
  }
});

function normalizeList(payload) {
  if (Array.isArray(payload)) return payload;
  if (payload && Array.isArray(payload.items)) return payload.items;
  if (payload && Array.isArray(payload.data)) return payload.data;
  return [];
}

function normalizeItem(payload) {
  return payload && payload.data ? payload.data : payload;
}

function normalizeClusterName(name) {
  return String(name || '').trim();
}

function findExistingClusterByName(name) {
  const targetName = normalizeClusterName(name);
  if (!targetName) return null;
  return clusters.value.find((cluster) => normalizeClusterName(cluster.name) === targetName) || null;
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
    const clusterData = { ...cluster };
    delete clusterData.api_server_port;
    delete clusterData.install_mode;
    delete clusterForm.api_server_port;
    delete clusterForm.install_mode;
    Object.assign(clusterForm, clusterData);
    await loadClusterNodes();
    await loadClusterSettings(clusterId);
    await loadConfigYaml();
  } else {
    nodes.value = [];
    yamlPreview.value = '';
  }
}

async function loadInstallPlan() {
  try {
    installPlan.value = normalizeList(await getInstallPlan());
  } catch (error) {
    apiError.value = error.message || String(error);
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
    let targetClusterId = selectedClusterId.value;
    if (!targetClusterId) {
      await loadClusters();
      targetClusterId = findExistingClusterByName(clusterForm.name)?.id || null;
    }
    const saved = normalizeItem(
      targetClusterId ? await updateCluster(targetClusterId, clusterForm) : await createCluster(clusterForm)
    );
    selectedClusterId.value = saved.id || selectedClusterId.value;
    await updateClusterSettings(selectedClusterId.value, {
      paths: { ...pathForm },
      ecosystem: { ...ecosystemForm }
    });
    await loadClusters();
    await loadClusterNodes();
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
  nodeForm.password = '';
  nodeDialogVisible.value = true;
}

async function saveNode() {
  await nodeFormRef.value.validate();
  await withAction(async () => {
    const payload = buildNodePayload();
    if (editingNodeId.value) {
      await updateNode(editingNodeId.value, payload);
    } else {
      await createNode(selectedClusterId.value, payload);
    }
    await loadClusterNodes();
    nodeDialogVisible.value = false;
    ElMessage.success('节点已保存');
  });
}

function buildNodePayload() {
  const payload = {
    hostname: nodeForm.hostname,
    ip: nodeForm.ip,
    ipv6: nodeForm.ipv6,
    role: nodeForm.role,
    ssh_user: nodeForm.ssh_user || 'root',
    ssh_port: nodeForm.ssh_port || 22
  };
  if (editingNodeId.value) {
    payload.is_draft = false;
  }
  if (nodeForm.password) {
    payload.password = nodeForm.password;
  }
  return payload;
}

function handleNodeSelectionChange(selection) {
  selectedNodeIds.value = selection.map((item) => item.id);
}

async function copySelectedNodes() {
  if (!selectedClusterId.value || !selectedNodeIds.value.length) return;
  await withAction(async () => {
    await copyNodes(selectedClusterId.value, selectedNodeIds.value);
    await loadClusterNodes();
    selectedNodeIds.value = [];
    ElMessage.success('已复制为草稿节点');
  });
}

async function runNodeTest() {
  if (!selectedClusterId.value) return;
  await withAction(async () => {
    const payload = normalizeItem(await startNodeTest(selectedClusterId.value));
    currentJob.value = {
      id: payload.job_id,
      job_type: 'node_test',
      status: payload.status
    };
    manualJobId.value = payload.job_id;
    await refreshJob();
    connectEvents();
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
    activeStep.value = 4;
    await refreshJob();
    connectEvents();
  });
}

async function runInstall() {
  await saveCluster();
  const confirmed = await ElMessageBox.confirm(
    `将按顺序执行 ${installPlan.value.length} 个 Kubernetes 底座步骤，安装过程会修改所有目标节点。`,
    '确认开始安装',
    {
      type: 'warning',
      confirmButtonText: '开始安装',
      cancelButtonText: '取消'
    }
  ).then(() => true, () => false);
  if (!confirmed) return;
  try {
    await withAction(async () => {
      const job = normalizeItem(await startInstall(selectedClusterId.value));
      currentJob.value = job;
      manualJobId.value = job.id;
      activeStep.value = 6;
      await refreshJob();
      connectEvents();
    });
  } catch (error) {
    if (error.status === 409 && error.jobId) {
      apiError.value = '';
      manualJobId.value = error.jobId;
      activeStep.value = 7;
      await refreshJob();
      connectEvents();
      ElMessage.warning('该集群已有安装任务，已切换到现有任务');
      return;
    }
    throw error;
  }
}

async function refreshJob() {
  if (!currentJobId.value) return;
  try {
    currentJob.value = normalizeItem(await getJob(currentJobId.value));
    jobSteps.value = normalizeList(await getJobSteps(currentJobId.value));
    if (currentJob.value?.job_type === 'precheck') {
      precheckResults.value = normalizeList(await getPrecheckResults(currentJobId.value));
    } else {
      precheckResults.value = [];
    }
    if (['success', 'failed', 'canceled'].includes(currentJob.value?.status) && selectedClusterId.value) {
      await handleClusterChange(selectedClusterId.value);
    }
  } catch (error) {
    apiError.value = error.message || String(error);
  }
}

async function loadNodeLog(node) {
  try {
    const payload = await getJobStepNodeLog(node.id);
    nodeLogTitle.value = `${payload.item?.step_key || '步骤'} / ${payload.item?.hostname || node.hostname}`;
    nodeLogContent.value = payload.content || '暂无日志';
    nodeLogDialogVisible.value = true;
  } catch (error) {
    apiError.value = error.message || String(error);
  }
}

async function bindManualJob() {
  if (!manualJobId.value) return;
  await refreshJob();
}

async function loadConfigYaml() {
  if (!selectedClusterId.value) return;
  try {
    const payload = await getClusterConfigYaml(selectedClusterId.value);
    yamlPreview.value = typeof payload === 'string' ? payload : payload?.yaml || JSON.stringify(payload, null, 2);
  } catch (error) {
    apiError.value = error.message || String(error);
  }
}

function openYamlImport() {
  yamlImportContent.value = yamlPreview.value || '';
  yamlImportDialogVisible.value = true;
}

async function submitYamlImport() {
  if (!yamlImportContent.value.trim()) {
    ElMessage.warning('请输入 YAML 配置内容');
    return;
  }
  await withAction(async () => {
    await importClusterYaml(selectedClusterId.value, yamlImportContent.value);
    yamlImportDialogVisible.value = false;
    await handleClusterChange(selectedClusterId.value);
    await loadClusters();
    ElMessage.success('YAML 配置已导入');
  });
}

async function openJobHistory() {
  await loadJobHistory();
  jobHistoryDialogVisible.value = true;
}

async function loadJobHistory() {
  if (!selectedClusterId.value) return;
  try {
    jobs.value = normalizeList(await listJobs(selectedClusterId.value));
  } catch (error) {
    apiError.value = error.message || String(error);
  }
}

async function bindHistoryJob(job) {
  disconnectEvents();
  currentJob.value = job;
  manualJobId.value = job.id;
  jobHistoryDialogVisible.value = false;
  activeStep.value = job.job_type === 'precheck' ? 4 : 7;
  await refreshJob();
  if (!['success', 'failed', 'canceled'].includes(job.status)) {
    connectEvents();
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
      if (eventName === 'job.status') {
        try {
          const payload = JSON.parse(event.data);
          const status = payload.payload?.status || payload.status;
          if (['success', 'failed', 'canceled'].includes(status)) {
            window.setTimeout(disconnectEvents, 800);
          }
        } catch (error) {
          // Ignore malformed event payloads; the next refresh still updates task state.
        }
      }
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

function installTargetText(targetScope) {
  return {
    primary_control_plane: '主控制节点',
    all_nodes: '所有节点',
    all_k8s_nodes: '所有 Kubernetes 节点',
    control_plane: '控制节点',
    non_primary_k8s_nodes: '非主控 Kubernetes 节点',
    registry: '镜像仓库节点',
    other_control_planes: '其他控制节点',
    workers: '工作节点'
  }[targetScope] || targetScope;
}

function installModeText(mode) {
  return {
    serial: '串行',
    parallel: '并行'
  }[mode] || mode;
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

function precheckStatusType(status) {
  return {
    pass: 'success',
    warning: 'warning',
    fail: 'danger'
  }[status] || 'info';
}
</script>
