<template>
  <div class="node-table-wrap execution-node-table">
    <table class="node-table">
      <thead><tr><th>节点</th><th>状态</th><th>退出码</th><th>诊断</th><th><span class="visually-hidden">操作</span></th></tr></thead>
      <tbody>
        <tr v-for="node in nodes" :key="node.id" :data-testid="`job-node-${node.id}`" :class="{ 'is-selected': node.node_id === selectedNodeId }">
          <td><strong>{{ node.hostname }}</strong><small>节点编号 {{ node.node_id }}</small></td>
          <td><el-tag :type="jobStatusTone(node.status)" size="small">{{ jobStatusLabel(node.status) }}</el-tag></td>
          <td>{{ node.exit_code ?? '-' }}</td>
          <td class="node-diagnostic">{{ node.message || '-' }}</td>
          <td><el-button link type="primary" @click="$emit('select', node.node_id)">查看日志</el-button></td>
        </tr>
      </tbody>
    </table>
  </div>
</template>

<script setup>
import { jobStatusLabel, jobStatusTone } from './jobStatus';

defineProps({
  nodes: { type: Array, default: () => [] },
  selectedNodeId: { type: [String, Number], default: '' }
});
defineEmits(['select']);
</script>
