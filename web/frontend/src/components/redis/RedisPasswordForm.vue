<template>
  <el-form class="component-nfs-form" label-position="top" @submit.prevent>
    <div class="form-grid">
      <el-form-item label="Redis / Sentinel 密码" :required="!config.has_password">
        <el-input
          v-model="config.password"
          data-testid="redis-password"
          aria-label="Redis / Sentinel 密码"
          :aria-required="!config.has_password"
          :aria-describedby="redisPasswordError(config) ? 'redis-password-hint redis-password-error' : 'redis-password-hint'"
          :aria-invalid="Boolean(redisPasswordError(config))"
          :type="visible ? 'text' : 'password'"
          autocomplete="new-password"
          maxlength="256"
          :placeholder="config.has_password ? '已配置（不回显）' : '请输入 Redis / Sentinel 密码'"
          :disabled="disabled"
        >
          <template #suffix>
            <el-button
              link
              :icon="visible ? Hide : View"
              :aria-label="visible ? '隐藏 Redis 密码' : '显示 Redis 密码'"
              :aria-pressed="visible"
              :disabled="disabled"
              @click="visible = !visible"
            />
          </template>
        </el-input>
        <span id="redis-password-hint" class="field-hint">
          {{ config.has_password ? '密码已配置，无需重复填写。' : '启用 Redis 必须配置密码，不允许为空。' }}
          Redis 与 Sentinel 使用同一密码；已安装组件不支持在线改密。
        </span>
        <p v-if="redisPasswordError(config)" id="redis-password-error" class="form-error" role="alert">
          {{ redisPasswordError(config) }}
        </p>
      </el-form-item>
    </div>
  </el-form>
</template>

<script setup>
import { ref } from 'vue';
import { Hide, View } from '@element-plus/icons-vue';
import { redisPasswordError } from './redisConfig';

const visible = ref(false);

defineProps({
  config: { type: Object, required: true },
  disabled: Boolean
});
</script>
