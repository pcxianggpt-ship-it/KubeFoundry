<template>
  <el-dialog
    :model-value="modelValue"
    :title="form.id ? '编辑节点' : '添加节点'"
    width="min(620px, calc(100vw - 32px))"
    :teleported="false"
    @close="close"
  >
    <el-form label-position="top" class="node-editor-form">
      <div class="form-grid">
        <el-form-item label="主机名" required>
          <el-input data-testid="node-hostname" v-model="form.hostname" />
        </el-form-item>
        <el-form-item label="IPv4" required>
          <el-input data-testid="node-ip" v-model="form.ip" placeholder="192.168.1.10" />
        </el-form-item>
        <el-form-item label="IPv6">
          <el-input v-model="form.ipv6" />
        </el-form-item>
        <el-form-item label="角色" required>
          <el-select v-model="form.role">
            <el-option label="控制节点" value="control_plane" />
            <el-option label="工作节点" value="worker" />
            <el-option label="镜像仓库" value="registry" />
          </el-select>
        </el-form-item>
        <el-form-item label="SSH 用户" required>
          <el-input v-model="form.ssh_user" />
        </el-form-item>
        <el-form-item label="SSH 端口" required>
          <el-input-number v-model="form.ssh_port" :min="1" :max="65535" />
        </el-form-item>
      </div>
      <el-form-item label="登录密码" :required="!form.id">
        <el-input
          data-testid="node-password"
          v-model="form.password"
          type="password"
          show-password
          autocomplete="new-password"
          :placeholder="passwordPlaceholder"
        />
        <span v-if="form.has_password" class="field-hint">密码已保存，留空表示保留原密码</span>
      </el-form-item>
    </el-form>
    <template #footer>
      <el-button @click="close">取消</el-button>
      <el-button
        data-testid="save-node"
        type="primary"
        :disabled="!canSave"
        @click="save"
      >
        保存节点
      </el-button>
    </template>
  </el-dialog>
</template>

<script setup>
import { computed, reactive, watch } from 'vue';

const props = defineProps({
  modelValue: { type: Boolean, default: false },
  node: { type: Object, default: null }
});
const emit = defineEmits(['update:modelValue', 'save']);
const form = reactive(emptyNode());

watch(() => [props.modelValue, props.node], () => {
  Object.assign(form, emptyNode(), props.node || {});
  form.password = '';
}, { immediate: true, deep: true });

const canSave = computed(() => Boolean(
  form.hostname.trim() && form.ip.trim() && form.role && form.ssh_user.trim()
  && form.ssh_port && (form.id || form.password)
));
const passwordPlaceholder = computed(() => form.has_password
  ? '密码已保存，留空表示保留原密码'
  : '请输入节点登录密码');

function emptyNode() {
  return {
    id: null,
    hostname: '',
    ip: '',
    ipv6: '',
    role: 'worker',
    ssh_user: 'root',
    ssh_port: 22,
    password: '',
    has_password: false
  };
}

function close() {
  emit('update:modelValue', false);
}

function save() {
  if (!canSave.value) return;
  const payload = {
    hostname: form.hostname.trim(),
    ip: form.ip.trim(),
    ipv6: form.ipv6.trim(),
    role: form.role,
    ssh_user: form.ssh_user.trim(),
    ssh_port: form.ssh_port
  };
  if (form.password) payload.password = form.password;
  emit('save', payload, form.id);
}
</script>
