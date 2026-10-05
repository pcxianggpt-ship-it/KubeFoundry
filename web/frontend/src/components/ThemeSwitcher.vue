<template>
  <label class="theme-switcher" :data-theme-location="location">
    <span>外观</span>
    <select aria-label="界面风格" :value="theme" @change="setTheme($event.target.value)">
      <option v-for="option in THEME_OPTIONS" :key="option.value" :value="option.value">{{ option.label }}</option>
    </select>
  </label>
</template>

<script setup>
import { setTheme, theme, THEME_OPTIONS } from '../themes/theme';

defineProps({ location: { type: String, required: true } });
</script>
