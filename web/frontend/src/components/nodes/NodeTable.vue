<template>
  <div class="node-table-wrap">
    <table class="node-table">
      <thead>
        <tr>
          <th scope="col"><span class="visually-hidden">选择</span></th>
          <th scope="col">节点</th>
          <th scope="col">连接</th>
          <th scope="col">角色</th>
          <th scope="col">密码</th>
          <th scope="col">免密状态</th>
          <th scope="col">诊断</th>
          <th scope="col"><span class="visually-hidden">操作</span></th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="node in nodes" :key="node.id">
          <td>
            <el-checkbox
              :data-testid="`select-node-${node.id}`"
              :model-value="selectedIds.includes(node.id)"
              :aria-label="`选择 ${node.hostname || '草稿节点'}`"
              :disabled="locked"
              @change="$emit('toggle', node.id, $event)"
            />
          </td>
          <td><strong>{{ node.hostname || '未命名草稿' }}</strong><small>{{ node.ip || '待填写 IP' }}</small></td>
          <td>{{ node.ssh_user }}@{{ node.ip || '-' }}:{{ node.ssh_port }}</td>
          <td>
            <div class="node-role-cards" :aria-label="`节点角色：${roleLabel(node.roles)}`">
              <span
                v-for="role in resolvedRoles(node.roles)"
                :key="role"
                class="node-role-card"
                :class="`node-role-card--${role}`"
              >
                {{ roleMeta(role).label }}
              </span>
            </div>
          </td>
          <td><span>{{ node.has_password ? '密码已保存' : '未保存密码' }}</span></td>
          <td>
            <el-tag :type="nodeStatusTone(node.node_test_status)" size="small">
              {{ nodeStatusLabel(node.node_test_status) }}
            </el-tag>
          </td>
          <td class="node-diagnostic">{{ node.node_test_message || '-' }}</td>
          <td class="node-actions">
            <el-tooltip content="编辑节点">
              <el-button
                :data-testid="`edit-node-${node.id}`"
                :icon="Edit"
                circle
                aria-label="编辑节点"
                :disabled="locked"
                @click="$emit('edit', node)"
              />
            </el-tooltip>
            <el-tooltip content="删除节点">
              <el-button
                :data-testid="`delete-node-${node.id}`"
                :icon="Delete"
                circle
                type="danger"
                aria-label="删除节点"
                :disabled="locked"
                @click="$emit('delete', node)"
              />
            </el-tooltip>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>

<script setup>
import { Delete, Edit } from '@element-plus/icons-vue';
import { nodeStatusLabel, nodeStatusTone } from './nodeStatus';

defineProps({
  nodes: { type: Array, default: () => [] },
  selectedIds: { type: Array, default: () => [] },
  locked: { type: Boolean, default: false }
});
defineEmits(['toggle', 'edit', 'delete']);

function roleLabel(roles) {
  return resolvedRoles(roles).map((role) => roleMeta(role).label).join('、') || '-';
}

function resolvedRoles(roles) {
  return Array.isArray(roles) ? roles.filter(Boolean) : [];
}

function roleMeta(role) {
  return {
    control_plane: { label: '控制节点' },
    worker: { label: '工作节点' },
    registry: { label: '镜像仓库' }
  }[role] || { label: role };
}
</script>
