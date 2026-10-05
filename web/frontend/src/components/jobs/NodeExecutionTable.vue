<template>
  <div class="node-table-wrap execution-node-table" tabindex="0" role="region" aria-label="节点执行记录，窄屏可横向滚动">
    <table class="node-table" aria-label="节点执行状态">
      <thead><tr><th scope="col">节点名称</th><th scope="col">IP 地址</th><th scope="col">角色</th><th scope="col">状态</th><th scope="col"><span class="visually-hidden">操作</span></th></tr></thead>
      <tbody>
        <tr v-if="!nodes.length"><td colspan="5" class="execution-empty" role="status">当前步骤暂无节点执行记录。</td></tr>
        <tr v-for="node in nodes" :key="node.id" :data-testid="`job-node-${node.id}`" :class="{ 'is-selected': node.node_id === selectedNodeId }">
          <td><strong>{{ node.hostname }}</strong></td>
          <td class="node-address">{{ detail(node).ip || '-' }}</td>
          <td>
            <div v-if="detail(node).roles?.length" class="node-role-badges">
              <NodeRoleBadge v-for="role in detail(node).roles" :key="role" :role="role" />
            </div>
            <span v-else class="node-role-empty">-</span>
          </td>
          <td><span class="node-execution-status" :class="`execution-tone--${executionStatusTone(node.status, node.message)}`"><span class="node-status-dot" aria-hidden="true"></span>{{ nodeLabel(node) }}</span></td>
          <td><el-button link type="primary" :aria-label="`查看 ${node.hostname} 日志`" @click="$emit('select', node.node_id)">查看日志</el-button></td>
        </tr>
      </tbody>
    </table>
    <div v-if="nodes.some(node => node.exit_code != null || node.message)" class="node-diagnostics" aria-label="节点诊断">
      <details v-for="node in nodes.filter(node => node.exit_code != null || node.message)" :key="node.id" :class="`execution-tone--${executionStatusTone(node.status, node.message)}`">
        <summary>{{ node.hostname }}<span>退出码 {{ node.exit_code ?? '-' }}</span></summary>
        <p>{{ verificationMessage(node.message) || '暂无诊断信息' }}</p>
      </details>
    </div>
  </div>
</template>

<script setup>
import NodeRoleBadge from '../nodes/NodeRoleBadge.vue';
import { executionStatusTone, stepStatusLabel, verificationMessage } from './jobStatus';

const props = defineProps({
  nodes: { type: Array, default: () => [] },
  nodeDetails: { type: Array, default: () => [] },
  selectedNodeId: { type: [String, Number], default: '' }
});
defineEmits(['select']);

function detail(node) { return props.nodeDetails.find(item => item.id === node.node_id) || node; }
function nodeLabel(node) {
  return ({ success: '已完成', running: '运行中' })[node.status] || stepStatusLabel(node.status, node.message);
}
</script>
