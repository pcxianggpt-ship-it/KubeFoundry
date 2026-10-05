<template>
  <span class="node-role-card" :class="`node-role-card--${role}`">
    <component v-if="presentation[role]?.icon" :is="presentation[role].icon" aria-hidden="true" />
    {{ label || presentation[role]?.label || role }}
  </span>
</template>

<script setup>
import { Box, Connection, Cpu, FolderOpened } from '@element-plus/icons-vue';

defineProps({ role: { type: String, required: true }, label: { type: String, default: '' } });

const presentation = {
  control_plane: { label: '控制平面', icon: Connection },
  worker: { label: '工作节点', icon: Cpu },
  registry: { label: '镜像仓库', icon: Box },
  nfs_server: { label: 'NFS 服务器', icon: FolderOpened }
};
</script>
