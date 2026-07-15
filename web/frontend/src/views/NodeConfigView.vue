<template>
  <section class="node-config-view">
    <div class="section-heading">
      <div>
        <p class="section-kicker">02 / 服务器节点</p>
        <h2>服务器节点</h2>
      </div>
      <div class="section-actions">
        <el-button data-testid="add-node" :icon="Plus" @click="openEditor()">添加节点</el-button>
        <el-button
          data-testid="copy-selected-nodes"
          :icon="CopyDocument"
          :disabled="!selectedIds.length || running"
          @click="copySelected"
        >
          复制所选
        </el-button>
        <el-button
          data-testid="test-all-nodes"
          type="primary"
          :icon="Connection"
          :loading="running"
          :disabled="!canTest"
          @click="runTest"
        >
          测试全部节点
        </el-button>
      </div>
    </div>

    <el-skeleton v-if="loading" :rows="5" animated aria-label="正在加载节点" />
    <section v-else-if="errorMessage" class="inline-error" role="alert">
      <span>{{ errorMessage }}</span>
      <el-button :icon="Refresh" @click="loadNodes">重试</el-button>
    </section>
    <section v-else-if="!nodes.length" class="inline-state" role="status">
      <Monitor aria-hidden="true" />
      <div><strong>还没有服务器节点</strong><p>添加控制节点和工作节点后再配置免密登录。</p></div>
    </section>
    <template v-else>
      <el-alert
        v-if="failedNodes.length"
        type="error"
        show-icon
        :closable="false"
        title="部分节点测试失败"
      >
        <template #default>
          <span>{{ failedSummary }}</span>
          <el-button data-testid="retry-failed-nodes" link type="primary" :disabled="!canTest" @click="runTest">重新测试全部节点</el-button>
        </template>
      </el-alert>
      <NodeTable
        :nodes="nodes"
        :selected-ids="selectedIds"
        @toggle="toggleNode"
        @edit="openEditor"
        @delete="removeNode"
      />
      <NodeTestActivity :items="activities" :connected="connected" />
    </template>

    <NodeEditor v-model="editorOpen" :node="editingNode" @save="saveNode" />
  </section>
</template>

<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { Connection, CopyDocument, Monitor, Plus, Refresh } from '@element-plus/icons-vue';
import { ElMessage, ElMessageBox } from 'element-plus';
import NodeEditor from '../components/nodes/NodeEditor.vue';
import NodeTable from '../components/nodes/NodeTable.vue';
import NodeTestActivity from '../components/nodes/NodeTestActivity.vue';
import { nodeStatusLabel } from '../components/nodes/nodeStatus';
import { copyNodes, createNode, deleteNode, listNodes, startNodeTest, updateNode } from '../api/client';
import { safeErrorMessage } from '../utils/redaction';

const props = defineProps({ clusterId: { type: [String, Number], required: true } });
const emit = defineEmits(['cluster-updated']);
const nodes = ref([]);
const selectedIds = ref([]);
const activities = ref([]);
const loading = ref(true);
const running = ref(false);
const connected = ref(false);
const errorMessage = ref('');
const editorOpen = ref(false);
const editingNode = ref(null);
let eventSource;
let activityId = 0;

const failedNodes = computed(() => nodes.value.filter((node) => node.node_test_status === 'failed'));
const failedSummary = computed(() => failedNodes.value
  .map((node) => `${node.hostname || '草稿节点'}：${node.node_test_message || '请查看活动日志'}`)
  .join('；'));
const canTest = computed(() => !running.value && nodes.value.length > 0 && nodes.value.every((node) =>
  !node.is_draft && node.hostname && node.ip && node.has_password));

onMounted(loadNodes);
onBeforeUnmount(disconnect);
watch(() => props.clusterId, loadNodes);

function normalizeList(payload) {
  if (Array.isArray(payload)) return payload;
  if (Array.isArray(payload?.items)) return payload.items;
  return [];
}

async function loadNodes() {
  loading.value = true;
  errorMessage.value = '';
  try {
    nodes.value = normalizeList(await listNodes(props.clusterId));
    selectedIds.value = selectedIds.value.filter((id) => nodes.value.some((node) => node.id === id));
  } catch (error) {
    errorMessage.value = safeErrorMessage(error, '节点加载失败，请重试。');
  } finally {
    loading.value = false;
  }
}

function openEditor(node = null) {
  editingNode.value = node;
  editorOpen.value = true;
}

async function saveNode(payload, nodeId) {
  try {
    if (nodeId) await updateNode(nodeId, payload);
    else await createNode(props.clusterId, payload);
    editorOpen.value = false;
    await loadNodes();
    emit('cluster-updated');
    ElMessage.success('节点已保存');
  } catch (error) {
    errorMessage.value = safeErrorMessage(error, '节点保存失败。');
  }
}

function toggleNode(nodeId, checked) {
  selectedIds.value = checked
    ? [...new Set([...selectedIds.value, nodeId])]
    : selectedIds.value.filter((id) => id !== nodeId);
}

async function copySelected() {
  try {
    await copyNodes(props.clusterId, selectedIds.value);
    selectedIds.value = [];
    await loadNodes();
    emit('cluster-updated');
    ElMessage.success('节点已复制，密码已保存；请编辑主机名和 IP 后再测试');
  } catch (error) {
    errorMessage.value = safeErrorMessage(error, '节点复制失败。');
  }
}

async function removeNode(node) {
  try {
    await ElMessageBox.confirm(`确认删除节点 ${node.hostname || '草稿节点'}？`, '删除节点', { type: 'warning' });
    await deleteNode(node.id);
    await loadNodes();
    emit('cluster-updated');
  } catch (error) {
    if (error === 'cancel' || error === 'close') return;
    errorMessage.value = safeErrorMessage(error, '节点删除失败。');
  }
}

async function runTest() {
  if (running.value || !nodes.value.length) return;
  running.value = true;
  activities.value = [];
  errorMessage.value = '';
  try {
    const accepted = await startNodeTest(props.clusterId);
    connect(accepted.job_id || accepted.id);
  } catch (error) {
    running.value = false;
    errorMessage.value = safeErrorMessage(error, '节点测试启动失败。');
  }
}

function connect(jobId) {
  disconnect();
  eventSource = new EventSource(`/api/jobs/${jobId}/events`);
  connected.value = true;
  addActivity('节点测试任务已启动');
  eventSource.addEventListener('node.status', (event) => handleNodeEvent(event));
  eventSource.addEventListener('job.status', (event) => handleJobEvent(event));
  eventSource.onerror = () => {
    connected.value = false;
    addActivity('实时连接中断，可刷新页面查看最终状态');
  };
}

function eventPayload(event) {
  try {
    const parsed = JSON.parse(event.data);
    return parsed.payload || parsed;
  } catch (error) {
    return {};
  }
}

function handleNodeEvent(event) {
  const payload = eventPayload(event);
  const node = nodes.value.find((item) => item.id === Number(payload.node_id));
  if (node) {
    node.node_test_status = payload.status;
    node.node_test_message = payload.message || node.node_test_message;
  }
  addActivity(`${payload.hostname || '节点'}：${nodeStatusLabel(payload.status)}${payload.message ? `，${safeErrorMessage({ message: payload.message })}` : ''}`);
}

async function handleJobEvent(event) {
  const payload = eventPayload(event);
  addActivity(`任务状态：${payload.status === 'success' ? '测试成功' : payload.status === 'failed' ? '测试失败' : '执行中'}`);
  if (['success', 'failed', 'interrupted', 'canceled'].includes(payload.status)) {
    running.value = false;
    disconnect();
    await loadNodes();
    emit('cluster-updated');
  }
}

function addActivity(message) {
  activities.value.push({
    id: ++activityId,
    time: new Date().toLocaleTimeString('zh-CN', { hour12: false }),
    message
  });
  if (activities.value.length > 100) activities.value = activities.value.slice(-100);
}

function disconnect() {
  eventSource?.close();
  eventSource = null;
  connected.value = false;
}
</script>
