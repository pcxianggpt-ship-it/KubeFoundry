<template><section><div class="section-heading"><div><p class="section-kicker">03 / Kubemate 组件</p><h2>Kubemate 组件配置</h2><p>本版本仅保存配置，不参与实际安装。</p></div><el-button type="primary" :disabled="locked" :loading="saving" @click="save">保存并下一步</el-button></div><el-card v-for="item in items" :key="item.key" class="component-card"><div class="component-row"><div><strong>{{ item.key }}</strong><p>实际安装将在 v0.3.0 提供。</p></div><el-switch v-model="item.enabled" :disabled="locked" /></div></el-card></section></template>
<script setup>
import { onMounted, ref } from 'vue';
import { listComponents, updateComponents } from '../api/client';
const props = defineProps({ clusterId: { type: [String, Number], required: true }, locked: Boolean }); const emit = defineEmits(['next']); const items = ref([]); const saving = ref(false);
async function load() { const payload = await listComponents(props.clusterId); items.value = payload.items || []; }
async function save() { if (props.locked) return; saving.value = true; try { await updateComponents(props.clusterId, items.value); emit('next'); } finally { saving.value = false; } }
onMounted(load);
</script>
