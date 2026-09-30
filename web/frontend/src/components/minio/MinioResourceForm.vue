<template>
  <el-form class="component-resource-form" label-position="top" @submit.prevent>
    <div class="form-grid">
      <el-form-item label="PVC 容量" required :error="errors.minio_pvc_size">
        <el-input v-model="config.minio_pvc_size" data-testid="minio-pvc-size" placeholder="例如 10Gi" :disabled="disabled" />
      </el-form-item>
      <el-form-item label="CPU request" required :error="errors.minio_cpu_request">
        <el-input v-model="config.minio_cpu_request" data-testid="minio-cpu-request" placeholder="例如 250m" :disabled="disabled" />
      </el-form-item>
      <el-form-item label="CPU limit" required :error="errors.minio_cpu_limit">
        <el-input v-model="config.minio_cpu_limit" data-testid="minio-cpu-limit" placeholder="例如 2" :disabled="disabled" />
      </el-form-item>
      <el-form-item label="内存 request" required :error="errors.minio_memory_request">
        <el-input v-model="config.minio_memory_request" data-testid="minio-memory-request" placeholder="例如 512Mi" :disabled="disabled" />
      </el-form-item>
      <el-form-item label="内存 limit" required :error="errors.minio_memory_limit">
        <el-input v-model="config.minio_memory_limit" data-testid="minio-memory-limit" placeholder="例如 4Gi" :disabled="disabled" />
      </el-form-item>
    </div>
    <p class="field-hint">支持 Kubernetes Quantity，例如 CPU 使用 250m、2，容量使用 512Mi、10Gi。</p>
  </el-form>
</template>

<script setup>
defineProps({
  config: { type: Object, required: true },
  errors: { type: Object, default: () => ({}) },
  disabled: Boolean
});
</script>
