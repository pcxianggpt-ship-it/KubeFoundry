<template>
  <section>
    <div class="section-heading">
      <div>
        <p class="section-kicker">03 / 安装配置</p>
        <h2>安装配置</h2>
      </div>
      <el-button
        data-testid="save-settings"
        type="primary"
        :loading="saving"
        :disabled="locked || loading || Boolean(errorMessage)"
        @click="save"
      >
        保存安装配置
      </el-button>
    </div>

    <el-skeleton v-if="loading" :rows="5" animated aria-label="正在加载安装配置" />
    <section v-else-if="errorMessage" class="inline-error" role="alert">
      <span>{{ errorMessage }}</span>
      <el-button data-testid="retry-settings" :icon="Refresh" @click="load">重试</el-button>
    </section>
    <template v-else>
      <el-alert v-if="saved" title="安装配置已保存" type="success" show-icon :closable="false" />
      <el-form label-position="top" class="stage-form">
        <div class="form-grid">
          <el-form-item label="Kubernetes 工作目录">
            <el-input data-testid="k8s-home" v-model="settings.paths.k8s_home" :disabled="locked" />
          </el-form-item>
          <el-form-item label="离线介质目录">
            <el-input data-testid="install-media" v-model="settings.paths.install_media" :disabled="locked" />
          </el-form-item>
          <el-form-item label="kubelet 数据目录">
            <el-input v-model="settings.env.kubelet_root" :disabled="locked" />
          </el-form-item>
          <el-form-item label="containerd 数据目录">
            <el-input v-model="settings.env.containerd_root" :disabled="locked" />
          </el-form-item>
          <el-form-item label="etcd 数据目录">
            <el-input v-model="settings.env.etcd_data_dir" :disabled="locked" />
          </el-form-item>
          <el-form-item label="仓库源目录">
            <el-input v-model="settings.paths.repo_source" :disabled="locked" />
          </el-form-item>
        </div>
        <el-form-item label="IPv4 / IPv6 双栈">
          <el-switch v-model="settings.advanced.enable_ipv6_dual_stack" :disabled="locked" />
        </el-form-item>
      </el-form>
    </template>
  </section>
</template>

<script setup>
import { onMounted, reactive, ref, watch } from 'vue';
import { Refresh } from '@element-plus/icons-vue';
import { getClusterSettings, updateClusterSettings } from '../../api/client';
import { safeErrorMessage } from '../../utils/redaction';

const props = defineProps({
  clusterId: { type: [String, Number], required: true },
  locked: { type: Boolean, default: false }
});
const loading = ref(true);
const saving = ref(false);
const saved = ref(false);
const errorMessage = ref('');
const settings = reactive(emptySettings());

onMounted(load);
watch(() => props.clusterId, (next, previous) => {
  if (next !== previous) load();
});

function emptySettings() {
  return {
    paths: { k8s_home: '', install_media: '', arch: '', repo_source: '' },
    env: { kubelet_root: '', containerd_root: '', etcd_data_dir: '' },
    advanced: { enable_ipv6_dual_stack: false }
  };
}

async function load() {
  loading.value = true;
  saved.value = false;
  errorMessage.value = '';
  try {
    const payload = await getClusterSettings(props.clusterId);
    const next = emptySettings();
    Object.assign(next.paths, payload?.paths || {});
    Object.assign(next.env, payload?.env || {});
    Object.assign(next.advanced, payload?.advanced || {});
    Object.assign(settings.paths, next.paths);
    Object.assign(settings.env, next.env);
    Object.assign(settings.advanced, next.advanced);
  } catch (error) {
    errorMessage.value = safeErrorMessage(error, '安装配置加载失败，请重试。');
  } finally {
    loading.value = false;
  }
}

async function save() {
  if (props.locked || loading.value || saving.value || errorMessage.value) return;
  saving.value = true;
  saved.value = false;
  try {
    await updateClusterSettings(props.clusterId, {
      paths: { ...settings.paths },
      env: { ...settings.env },
      advanced: { ...settings.advanced }
    });
    saved.value = true;
  } catch (error) {
    errorMessage.value = safeErrorMessage(error, '安装配置保存失败，请重试。');
  } finally {
    saving.value = false;
  }
}
</script>
