<template>
  <section>
    <div class="section-heading">
      <div>
        <p class="section-kicker">01 / 集群信息</p>
        <h2>集群信息</h2>
      </div>
      <el-button
        data-testid="save-cluster"
        type="primary"
        :loading="saving"
        :disabled="locked || !form.name.trim()"
        @click="submit"
      >
        保存集群信息
      </el-button>
    </div>

    <el-form label-position="top" class="stage-form" @submit.prevent="submit">
      <div class="form-grid">
        <el-form-item label="集群名称" required>
          <el-input data-testid="cluster-name" v-model="form.name" maxlength="100" :disabled="locked" />
        </el-form-item>
        <el-form-item label="Kubernetes 版本" required>
          <el-input v-model="form.k8s_version" placeholder="1.30.14" :disabled="locked" />
        </el-form-item>
        <el-form-item label="Pod 网段" required>
          <el-input v-model="form.pod_subnet" placeholder="10.244.0.0/16" :disabled="locked" />
        </el-form-item>
        <el-form-item label="Service 网段" required>
          <el-input v-model="form.service_subnet" placeholder="10.96.0.0/16" :disabled="locked" />
        </el-form-item>
        <el-form-item label="镜像仓库主机名">
          <el-input v-model="form.registry_hostname" placeholder="registry" :disabled="locked" />
        </el-form-item>
        <el-form-item label="镜像仓库 IP">
          <el-input v-model="form.registry_ip" placeholder="192.168.1.10" :disabled="locked" />
        </el-form-item>
        <el-form-item label="镜像仓库端口">
          <el-input-number v-model="form.registry_port" :min="1" :max="65535" controls-position="right" :disabled="locked" />
        </el-form-item>
      </div>
      <el-form-item label="说明">
        <el-input v-model="form.description" type="textarea" :rows="3" maxlength="500" show-word-limit :disabled="locked" />
      </el-form-item>
    </el-form>
  </section>
</template>

<script setup>
import { reactive, watch } from 'vue';

const props = defineProps({
  cluster: { type: Object, required: true },
  saving: { type: Boolean, default: false },
  locked: { type: Boolean, default: false }
});
const emit = defineEmits(['save']);

const defaults = {
  name: '',
  description: '',
  k8s_version: '1.30.14',
  pod_subnet: '10.244.0.0/16',
  service_subnet: '10.96.0.0/16',
  registry_hostname: 'registry',
  registry_ip: '',
  registry_port: 5000
};
const form = reactive({ ...defaults });

watch(() => props.cluster, (cluster) => {
  Object.assign(form, defaults, cluster || {});
}, { immediate: true, deep: true });

function submit() {
  if (props.locked || props.saving || !form.name.trim()) return;
  emit('save', {
    name: form.name.trim(),
    description: form.description,
    k8s_version: form.k8s_version.trim(),
    pod_subnet: form.pod_subnet.trim(),
    service_subnet: form.service_subnet.trim(),
    registry_hostname: form.registry_hostname.trim(),
    registry_ip: form.registry_ip.trim(),
    registry_port: form.registry_port
  });
}
</script>
