<template>
  <section>
    <div class="section-heading"><div><p class="section-kicker">01 / 集群信息</p><h2>集群信息</h2></div>
      <el-button data-testid="save-cluster" type="primary" :loading="saving" :disabled="locked || !form.name.trim()" @click="submit">保存并下一步</el-button>
    </div>
    <el-form label-position="top" class="stage-form" @submit.prevent="submit"><div class="form-grid">
      <el-form-item label="集群名称" required><el-input data-testid="cluster-name" v-model="form.name" maxlength="100" :disabled="locked" /></el-form-item>
      <el-form-item label="Kubernetes 版本" required><el-select v-model="form.k8s_version" :disabled="locked"><el-option label="1.30.14" value="1.30.14" /></el-select></el-form-item>
      <el-form-item label="Kubernetes 工作目录" required><el-input v-model="form.kubernetes_work_dir" placeholder="/data/k8s_install" :disabled="locked" /></el-form-item>
      <el-form-item label="镜像仓库"><el-select v-model="form.image_registry_type" :disabled="locked"><el-option label="Registry" value="REGISTRY" /></el-select></el-form-item>
    </div><el-form-item label="说明"><el-input v-model="form.description" type="textarea" :rows="3" maxlength="500" show-word-limit :disabled="locked" /></el-form-item></el-form>
  </section>
</template>
<script setup>
import { reactive, watch } from 'vue';
const props = defineProps({ cluster: { type: Object, required: true }, saving: Boolean, locked: Boolean });
const emit = defineEmits(['save']);
const defaults = { name: '', description: '', k8s_version: '1.30.14', kubernetes_work_dir: '/data/k8s_install', image_registry_type: 'REGISTRY' };
const form = reactive({ ...defaults });
watch(() => props.cluster, value => Object.assign(form, defaults, value || {}), { immediate: true, deep: true });
function submit() { if (!props.locked && !props.saving && form.name.trim()) emit('save', { name: form.name.trim(), description: form.description, k8s_version: form.k8s_version, kubernetes_work_dir: form.kubernetes_work_dir.trim(), image_registry_type: form.image_registry_type }); }
</script>
